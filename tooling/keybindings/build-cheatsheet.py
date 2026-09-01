#!/usr/bin/env python3
"""Generate the DMS keybinds cheatsheet shown by Mod+Slash.

niri's built-in hotkey overlay orders itself, cannot be searched, and only ever
knows about niri. DMS ships a searchable modal that renders any JSON cheatsheet
found in ~/.config/DankMaterialShell/cheatsheets/, so Mod+Slash opens ours.

The sheet is in two halves.

The DIGEST is the first screen: the three `###` blocks of the "Every Day"
section of docs/keybindings.md become the three columns, and their `####`
headings become the groups inside each. It is capped at what actually fits
above the fold, measured rather than guessed -- 25 rows plus 3 group headings
per column at the overlay's 900px.

The REFERENCE is everything below it: the rest of docs/keybindings.md for the
in-app layers, and binds.kdl plus the local.kdl seed for the desktop, which is
rebuilt from the KDL rather than the doc so it is complete rather than curated.
tooling/data/cheatsheet-layout groups it into topic-sized categories.

WHY THE CAP MATTERS. DMS ignores the order categories appear in the JSON;
Modals/KeybindsContent.qml sorts by estimated height, descending, and
greedy-packs each into the shortest column. With three empty columns the three
tallest categories land at the top of the three columns, which is the only
lever over what sits above the fold. The digest wins it by being taller than
every reference category, and check_layout() asserts exactly that -- so a
category that grows too large fails the build instead of silently pushing the
digest out of view.

Descriptions for the desktop come from each bind's hotkey-overlay-title, and
group headings from the `// -- Section --` comments binds.kdl is already
organised by, so that curation stays load-bearing. A bind carrying no title
must be named in tooling/data/niri-bind-descriptions, asserted in both
directions. `hotkey-overlay-title=null` still means hidden.

With --check it regenerates and diffs against the committed seed instead of
writing, so validate can assert the seed is in sync.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]

DOC = REPO / "docs/keybindings.md"
SYSTEM_BINDS = REPO / "system_files/usr/share/workstation-os-image/niri/includes/binds.kdl"
LOCAL_SEED = REPO / "system_files/usr/share/workstation-os-image/dotfiles/dot_config/niri/create_local.kdl.tmpl"
LEXICON = REPO / "tooling/data/niri-bind-descriptions"
LAYOUT = REPO / "tooling/data/cheatsheet-layout"
SEED = REPO / "system_files/usr/share/workstation-os-image/dotfiles/dot_config/DankMaterialShell/cheatsheets/workstation.json"

TITLE = "Workstation Keys"
PROVIDER = "workstation"

# The doc section whose `###` blocks become the digest columns.
DIGEST_SECTION = "Every Day"

# Measured, not derived. A calibration sheet of numbered rows rendered in the
# overlay at 900px shows 25 rows plus 3 group headings per column before the
# fold. DMS costs a category at 40px and everything inside it at 28px
# (KeybindsContent.qml estimateCategoryHeight), so one column is 28 units and a
# unit is a row or a group heading.
FOLD_UNITS = 28

# The key gets its own narrow column, and DMS renders it as `Mod + Shift + H`
# with spaces around every plus, so it runs out of room well before the
# description does. Measured at the overlay's width: `Mod+Ctrl+Up/Down` (16)
# renders on one line and `Mod+Shift+H/J/K/L` (17) wraps onto two, which costs
# a row the fold arithmetic has not budgeted for.
DIGEST_KEY_CHARS = 16

# Every `##` in the doc is either a category in the sheet or listed here. A new
# section can then never be added to the doc and silently miss the modal.
# Sections whose rows are reference. Their `###` headings are the source groups
# that tooling/data/cheatsheet-layout assigns to categories.
DOC_REFERENCE = {"Session", "Editor", "Terminal and Apps", "When You Are Lost"}
DOC_IGNORED = {
    # Rebuilt from binds.kdl instead, so it is complete rather than curated.
    "Desktop",
    # Prose, no table.
    "Where to go next",
}


def fail(message: str) -> None:
    print(f"{Path(__file__).name}: {message}", file=sys.stderr)
    sys.exit(1)


# --- key normalisation ---------------------------------------------------
# The modal lays out at 1000px across three columns and gives the key its own
# narrow column, so a long key wraps onto three lines and overlaps its
# neighbour. These collapse the doc's prose-friendly forms into short ones
# without losing which keys are meant.

WHEEL = {
    "WheelScrollDown": "Wheel↓",
    "WheelScrollUp": "Wheel↑",
    "WheelScrollLeft": "Wheel←",
    "WheelScrollRight": "Wheel→",
}


def shorten(key: str) -> str:
    """Shorten a raw niri key for display. `Mod+Ctrl+Shift+WheelScrollDown` is
    30 characters and wraps onto three lines in the modal's key column."""
    for raw, short in WHEEL.items():
        key = key.replace(raw, short)
    return key


def _collapse(alternatives: list[str]) -> str:
    """Mod+H / Mod+L -> Mod+H/L. Repeating the modifier costs the width that
    makes the row wrap, and every alternative here shares it."""
    joined = "/".join(alternatives)
    if len(alternatives) > 1 and all("+" in a for a in alternatives):
        prefixes = [a.rsplit("+", 1)[0] for a in alternatives]
        if len(set(prefixes)) == 1:
            tails = [a.rsplit("+", 1)[1] for a in alternatives[1:]]
            joined = alternatives[0] + "/" + "/".join(tails)
    return joined


def normalise_key(cell: str) -> str:
    """Render a doc key cell for the modal.

    The doc distinguishes a sequence from an alternation by where it puts the
    backticks: ``Space`` ``/`` is press Space then slash, while ``Mod+H`` /
    ``Mod+L`` is one key or the other. Strip the backticks first and the two
    become indistinguishable, so the separators are read before that.
    """
    parts = re.split(r"`([^`]*)`", cell.strip())
    if len(parts) == 1:  # no backticks: prose, e.g. `pro` written plainly
        return re.sub(r"\s+", " ", cell.replace("`", "")).strip()

    tokens = [parts[i] for i in range(1, len(parts), 2)]
    separators = [parts[i].strip() for i in range(2, len(parts) - 1, 2)]

    runs: list[list[str]] = [[tokens[0]]]
    joins: list[str] = []
    for token, separator in zip(tokens[1:], separators):
        if separator in {"", "then"}:
            runs.append([token])
            joins.append(" ")
        elif separator in {"…", "...", ".."}:
            runs.append([token])
            joins.append("..")
        else:  # "/", ",", "or", ", " -- alternation
            runs[-1].append(token)

    rendered = _collapse(runs[0])
    for join, run in zip(joins, runs[1:]):
        part = _collapse(run)
        # Mod+1 .. Mod+9 -> Mod+1..9, for the same width reason as _collapse.
        if join == ".." and "+" in rendered and "+" in part:
            if rendered.rsplit("+", 1)[0] == part.rsplit("+", 1)[0]:
                part = part.rsplit("+", 1)[1]
        rendered += join + part
    return shorten(re.sub(r"\s+", " ", rendered).strip())


def normalise_desc(cell: str) -> str:
    text = cell.replace("`", "")
    text = re.sub(r"\*\*(.+?)\*\*", r"\1", text)
    text = re.sub(r"\*(.+?)\*", r"\1", text)
    return re.sub(r"\s+", " ", text).strip()


# --- docs/keybindings.md -------------------------------------------------

def parse_doc() -> tuple[dict[str, list[dict[str, str]]], dict[str, list[dict[str, str]]]]:
    """Returns (digest categories, reference groups).

    Inside the digest section a `###` opens a column and a `####` a group
    within it. Everywhere else `###` is itself a group, and which category it
    lands in is tooling/data/cheatsheet-layout's business, not this function's.
    """
    digest: dict[str, list[dict[str, str]]] = {}
    reference: dict[str, list[dict[str, str]]] = {}

    section = ""
    digest_column = ""
    group = ""
    seen_sections: set[str] = set()

    for raw in DOC.read_text().splitlines():
        line = raw.rstrip()
        if line.startswith("## ") and not line.startswith("### "):
            section = line[3:].strip()
            seen_sections.add(section)
            digest_column = group = ""
            continue
        if line.startswith("#### "):
            group = line[5:].strip()
            continue
        if line.startswith("### "):
            if section == DIGEST_SECTION:
                digest_column = line[4:].strip()
                group = ""
            else:
                group = line[4:].strip()
            continue
        if not line.startswith("|"):
            continue

        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) != 2 or cells[0] == "Key" or set(cells[0]) <= set("-: "):
            continue
        row = {"key": normalise_key(cells[0]), "desc": normalise_desc(cells[1])}

        if section == DIGEST_SECTION:
            if not digest_column or not group:
                fail(f"{DOC.relative_to(REPO)}: a row in {DIGEST_SECTION} sits outside a ### column and #### group.")
            row["subcat"] = group
            digest.setdefault(digest_column, []).append(row)
        elif section in DOC_REFERENCE:
            if not group:
                fail(f"{DOC.relative_to(REPO)}: a row in '{section}' sits outside a ### group.")
            reference.setdefault(group, []).append(row)

    unknown = seen_sections - {DIGEST_SECTION} - DOC_REFERENCE - DOC_IGNORED
    if unknown:
        fail(
            f"{DOC.relative_to(REPO)} has sections this generator does not place: "
            f"{sorted(unknown)}. Add them to DOC_REFERENCE or DOC_IGNORED."
        )
    missing = ({DIGEST_SECTION} | DOC_REFERENCE) - seen_sections
    if missing:
        fail(f"{DOC.relative_to(REPO)} no longer has these sections: {sorted(missing)}.")
    if len(digest) != 3:
        fail(
            f"the digest must be exactly 3 columns, one per column DMS renders, but "
            f"{DOC.relative_to(REPO)}'s {DIGEST_SECTION} section has {len(digest)}: {sorted(digest)}."
        )
    return digest, reference


# --- niri binds ----------------------------------------------------------

def strip_comments(text: str) -> str:
    """Drop // comments without touching a // inside a quoted string."""
    out = []
    for line in text.splitlines():
        quoted = False
        cut = len(line)
        i = 0
        while i < len(line):
            char = line[i]
            if char == '"':
                quoted = not quoted
            elif char == "/" and not quoted and line[i : i + 2] == "//":
                cut = i
                break
            i += 1
        out.append(line[:cut].rstrip())
    return "\n".join(out)


SECTION_RE = re.compile(r"//\s*[─-]{2,}\s*(.+?)\s*[─-]{2,}\s*$")
KEY_RE = re.compile(r"^\s*((?:[A-Z][A-Za-z0-9_]*|XF86[A-Za-z0-9_]+)(?:\+[A-Za-z0-9_]+)*)\s")
TITLE_RE = re.compile(r'hotkey-overlay-title=(?:"((?:[^"\\]|\\.)*)"|(null))')


def parse_binds(path: Path, default_section: str) -> list[dict[str, object]]:
    """Extract binds with their section heading, title and hidden state."""
    raw_lines = path.read_text().splitlines()
    clean_lines = strip_comments(path.read_text()).splitlines()

    binds: list[dict[str, object]] = []
    section = default_section
    depth = 0
    in_binds = False
    pending: list[str] | None = None
    pending_section = section

    for raw, line in zip(raw_lines, clean_lines):
        heading = SECTION_RE.search(raw)
        if heading:
            # The file's own headings become the subcategories. Their trailing
            # asides ("Overview (bridges into apps)") are notes to whoever edits
            # the KDL, not labels for the modal.
            section = re.sub(r"\s*\(.*\)$", "", heading.group(1).strip())
            continue

        if not in_binds:
            if re.match(r"^\s*binds\s*\{", line):
                in_binds = True
                depth = line.count("{") - line.count("}")
            continue

        if pending is None:
            match = KEY_RE.match(line)
            if match and "{" in line:
                pending = [line]
                pending_section = section
            else:
                depth += line.count("{") - line.count("}")
                if depth <= 0:
                    in_binds = False
                continue
        else:
            pending.append(line)

        block = "\n".join(pending)
        if block.count("{") <= block.count("}"):
            binds.append(_bind(block, pending_section, path))
            pending = None

    if pending is not None:
        fail(f"{path.relative_to(REPO)} has an unterminated bind block.")
    if not binds:
        fail(f"{path.relative_to(REPO)} yielded no binds; the parser is not reading it.")
    return binds


def _bind(block: str, section: str, path: Path) -> dict[str, object]:
    key = KEY_RE.match(block).group(1)
    head, _, rest = block.partition("{")
    action = rest.rsplit("}", 1)[0].strip()
    action = re.sub(r"\s+", " ", action).rstrip(";").strip()

    title_match = TITLE_RE.search(head)
    hidden = bool(title_match and title_match.group(2))
    title = title_match.group(1) if title_match and title_match.group(1) else None
    return {
        "key": key,
        "action": action,
        "title": title,
        "hidden": hidden,
        "section": section,
        "source": str(path.relative_to(REPO)),
    }


# --- the hand-written lexicon -------------------------------------------

def parse_lexicon() -> tuple[dict[str, tuple[str, str]], dict[str, tuple[str, str]]]:
    """Returns (descriptions, additions).

    A leading + marks an addition: a bind that exists only in the DMS-generated
    fragment, which is machine-generated and not in this repo, so no amount of
    parsing our own files will find it.
    """
    entries: dict[str, tuple[str, str]] = {}
    additions: dict[str, tuple[str, str]] = {}
    for number, raw in enumerate(LEXICON.read_text().splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split("|")
        if len(fields) != 3:
            fail(f"{LEXICON.relative_to(REPO)}:{number}: expected 'key|subcat|description'.")
        key, subcat, desc = (f.strip() for f in fields)
        target = entries
        if key.startswith("+"):
            key, target = key[1:], additions
            if not subcat or not desc:
                fail(f"{LEXICON.relative_to(REPO)}:{number}: an addition needs a subcat and a description.")
        if key in entries or key in additions:
            fail(f"{LEXICON.relative_to(REPO)}:{number}: duplicate entry for {key}.")
        target[key] = (subcat, desc)
    return entries, additions


def build_desktop(
    binds: list[dict[str, object]],
    lexicon: dict[str, tuple[str, str]],
    additions: dict[str, tuple[str, str]],
) -> dict[str, list[dict[str, str]]]:
    """The desktop layer as {section heading: rows}, ready for the layout file."""
    visible = [b for b in binds if not b["hidden"]]

    undescribed = sorted(
        str(b["key"]) for b in visible if not b["title"] and not lexicon.get(str(b["key"]), ("", ""))[1]
    )
    if undescribed:
        fail(
            "these binds have no hotkey-overlay-title and no entry in "
            f"{LEXICON.relative_to(REPO)}, so they would vanish from the cheatsheet:\n  "
            + "\n  ".join(undescribed)
        )

    known = {str(b["key"]) for b in binds}
    stale = sorted(set(lexicon) - known)
    if stale:
        fail(
            f"{LEXICON.relative_to(REPO)} describes binds that no longer exist:\n  "
            + "\n  ".join(stale)
        )
    clash = sorted(set(additions) & known)
    if clash:
        fail(
            f"{LEXICON.relative_to(REPO)} adds binds that this repo already defines, "
            f"so they would appear twice:\n  " + "\n  ".join(clash)
        )

    groups: dict[str, list[dict[str, str]]] = {}
    for bind in visible:
        key = str(bind["key"])
        subcat, desc = lexicon.get(key, ("", ""))
        section = subcat or str(bind["section"])
        groups.setdefault(section, []).append(
            {"key": shorten(key), "desc": desc or str(bind["title"])}
        )
    for key, (subcat, desc) in additions.items():
        groups.setdefault(subcat, []).append({"key": shorten(key), "desc": desc})
    return groups


def parse_layout() -> dict[str, str]:
    """source group -> the reference category it belongs to."""
    mapping: dict[str, str] = {}
    for number, raw in enumerate(LAYOUT.read_text().splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split("|")
        if len(fields) != 2:
            fail(f"{LAYOUT.relative_to(REPO)}:{number}: expected 'source group|category'.")
        group, category = (f.strip() for f in fields)
        if not group or not category:
            fail(f"{LAYOUT.relative_to(REPO)}:{number}: both fields are required.")
        if group in mapping:
            fail(f"{LAYOUT.relative_to(REPO)}:{number}: '{group}' is assigned twice.")
        mapping[group] = category
    return mapping


def units(rows: list[dict[str, str]]) -> int:
    """What DMS charges for a category, in rows. estimateCategoryHeight bills a
    named subcategory the same 28px as a bind, so a heading costs one row."""
    return len(rows) + len({r["subcat"] for r in rows if r.get("subcat")})


def build_reference(groups: dict[str, list[dict[str, str]]]) -> dict[str, list[dict[str, str]]]:
    layout = parse_layout()

    unassigned = sorted(set(groups) - set(layout))
    if unassigned:
        fail(
            f"{LAYOUT.relative_to(REPO)} does not say which category these belong to, "
            f"so they would not appear at all:\n  " + "\n  ".join(unassigned)
        )
    unknown = sorted(set(layout) - set(groups))
    if unknown:
        fail(
            f"{LAYOUT.relative_to(REPO)} names groups that do not exist:\n  "
            + "\n  ".join(unknown)
        )

    out: dict[str, list[dict[str, str]]] = {}
    for group in sorted(groups):
        for row in groups[group]:
            out.setdefault(layout[group], []).append({**row, "subcat": group})
    return out


def check_layout(digest: dict[str, list[dict[str, str]]],
                 reference: dict[str, list[dict[str, str]]]) -> None:
    """Assert the digest actually lands above the fold.

    DMS sorts categories by height and greedy-packs them, so the three tallest
    take the top of the three columns. The digest gets them by being taller
    than everything else and no taller than one column.
    """
    oversized = {c: units(r) for c, r in digest.items() if units(r) > FOLD_UNITS}
    if oversized:
        fail(
            f"a digest column may be at most {FOLD_UNITS} rows-plus-headings or it "
            f"scrolls; these are bigger: {oversized}. Trim "
            f"{DOC.relative_to(REPO)}'s {DIGEST_SECTION} section."
        )

    long_keys = sorted(
        {r["key"] for rows in digest.values() for r in rows if len(r["key"]) > DIGEST_KEY_CHARS}
    )
    if long_keys:
        fail(
            f"these digest keys are longer than {DIGEST_KEY_CHARS} characters, so they wrap "
            f"onto a second line and push the column past the fold:\n  " + "\n  ".join(long_keys)
        )

    smallest = min(units(r) for r in digest.values())
    too_tall = {c: units(r) for c, r in reference.items() if units(r) >= smallest}
    if too_tall:
        fail(
            f"these reference categories are at least as tall as the smallest digest "
            f"column ({smallest}), so DMS would pack them at the top of a column and "
            f"push the digest below the fold: {too_tall}. Split them in "
            f"{LAYOUT.relative_to(REPO)}."
        )


def main() -> None:
    check = "--check" in sys.argv[1:]

    digest, doc_groups = parse_doc()

    binds = parse_binds(SYSTEM_BINDS, "Desktop")
    binds += parse_binds(LOCAL_SEED, "Reclaimed from DMS")
    lexicon, additions = parse_lexicon()
    kdl_groups = build_desktop(binds, lexicon, additions)

    collision = sorted(set(doc_groups) & set(kdl_groups))
    if collision:
        fail(
            "these group headings exist in both docs/keybindings.md and the niri "
            f"binds, so the layout file cannot tell them apart:\n  " + "\n  ".join(collision)
        )

    reference = build_reference({**doc_groups, **kdl_groups})
    check_layout(digest, reference)

    # Digest first for a human reading the JSON. DMS repacks by height anyway;
    # check_layout is what actually guarantees the order on screen.
    sheet = {
        "title": TITLE,
        "provider": PROVIDER,
        "binds": {**digest, **{k: reference[k] for k in sorted(reference)}},
    }
    rendered = json.dumps(sheet, indent=2, ensure_ascii=False) + "\n"
    total = sum(len(v) for v in sheet["binds"].values())

    if check:
        if not SEED.exists():
            fail(f"{SEED.relative_to(REPO)} is missing: run 'just cheatsheet' and commit.")
        if SEED.read_text() != rendered:
            subprocess.run(
                ["diff", "-u", "--label", "committed", "--label", "regenerated",
                 str(SEED), "-"],
                input=rendered, text=True, check=False,
            )
            fail(f"{SEED.relative_to(REPO)} is stale: run 'just cheatsheet' and commit.")
        print(f"Keybindings cheatsheet is in sync ({total} binds).")
        return

    SEED.parent.mkdir(parents=True, exist_ok=True)
    SEED.write_text(rendered)
    widest = max(units(r) for r in digest.values())
    print(
        f"Wrote {SEED.relative_to(REPO)}: {total} binds, "
        f"{len(digest)} digest columns (tallest {widest}/{FOLD_UNITS}) "
        f"and {len(reference)} reference categories."
    )


if __name__ == "__main__":
    main()
