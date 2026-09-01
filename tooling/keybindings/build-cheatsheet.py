#!/usr/bin/env python3
"""Generate the DMS keybinds cheatsheet shown by Mod+Slash.

niri's built-in hotkey overlay orders itself, cannot be searched, and only ever
knows about niri. DMS ships a searchable modal that renders any JSON cheatsheet
found in ~/.config/DankMaterialShell/cheatsheets/, so Mod+Slash opens ours
instead. This builds that JSON from the two sources that already exist:

  docs/keybindings.md  the curated study sheet -- every layer except the
                       desktop, in the wording a human already reviewed.
  binds.kdl + the      the desktop layer, complete. Descriptions come from each
  local.kdl seed       bind's hotkey-overlay-title, and subcategories from the
                       `// -- Section --` comments the file is already grouped
                       by, so the curation in that file stays load-bearing.

A bind carrying no title has no label to borrow, so it must be named in
tooling/data/niri-bind-descriptions. That file is asserted in BOTH directions:
a new bind with no title and no entry fails the build rather than silently
vanishing from the sheet, and an entry naming a bind that no longer exists
fails too. `hotkey-overlay-title=null` still means hidden, as it did for niri.

With --check it regenerates into a temp file and diffs against the committed
seed instead of writing, so validate can assert the seed is in sync.
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
SEED = REPO / "system_files/usr/share/workstation-os-image/dotfiles/dot_config/DankMaterialShell/cheatsheets/workstation.json"

TITLE = "Workstation Keys"
PROVIDER = "workstation"
DESKTOP_CATEGORY = "Desktop"

# Every `##` in the doc is either a category in the sheet or listed here. A new
# section can then never be added to the doc and silently miss the modal.
DOC_CATEGORIES = {
    "Every Day": "Every Day",
    "Session": "Session (Ctrl+G)",
    "Editor": "Editor (Space)",
    "Terminal and Apps": "Terminal & Apps",
    "When You Are Lost": "When You Are Lost",
}
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

def parse_doc() -> dict[str, list[dict[str, str]]]:
    category: str | None = None
    subcat = ""
    out: dict[str, list[dict[str, str]]] = {}
    seen_sections: set[str] = set()

    for raw in DOC.read_text().splitlines():
        line = raw.rstrip()
        if line.startswith("## "):
            section = line[3:].strip()
            seen_sections.add(section)
            category = DOC_CATEGORIES.get(section)
            subcat = ""
            continue
        if line.startswith("### "):
            subcat = line[4:].strip()
            continue
        if category is None or not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) != 2:
            continue
        if set(cells[0]) <= set("-: ") or cells[0] == "Key":
            continue
        entry = {"key": normalise_key(cells[0]), "desc": normalise_desc(cells[1])}
        if subcat:
            entry["subcat"] = subcat
        out.setdefault(category, []).append(entry)

    unknown = seen_sections - set(DOC_CATEGORIES) - DOC_IGNORED
    if unknown:
        fail(
            f"{DOC.relative_to(REPO)} has sections this generator does not place: "
            f"{sorted(unknown)}. Add them to DOC_CATEGORIES or DOC_IGNORED."
        )
    missing = set(DOC_CATEGORIES) - seen_sections
    if missing:
        fail(f"{DOC.relative_to(REPO)} no longer has these sections: {sorted(missing)}.")
    return out


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
) -> list[dict[str, str]]:
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

    rows: list[dict[str, str]] = []
    for bind in visible:
        key = str(bind["key"])
        subcat, desc = lexicon.get(key, ("", ""))
        row = {
            "key": shorten(key),
            "desc": desc or str(bind["title"]),
            "subcat": subcat or str(bind["section"]),
        }
        rows.append(row)
    for key, (subcat, desc) in additions.items():
        rows.append({"key": shorten(key), "desc": desc, "subcat": subcat})
    return rows


def main() -> None:
    check = "--check" in sys.argv[1:]

    categories = parse_doc()
    binds = parse_binds(SYSTEM_BINDS, "Desktop")
    binds += parse_binds(LOCAL_SEED, "Reclaimed from DMS")
    lexicon, additions = parse_lexicon()
    categories[DESKTOP_CATEGORY] = build_desktop(binds, lexicon, additions)

    order = ["Every Day", DESKTOP_CATEGORY, "Session (Ctrl+G)", "Editor (Space)",
             "Terminal & Apps", "When You Are Lost"]
    missing = [c for c in order if c not in categories]
    if missing:
        fail(f"no rows produced for {missing}.")

    sheet = {
        "title": TITLE,
        "provider": PROVIDER,
        "binds": {name: categories[name] for name in order},
    }
    rendered = json.dumps(sheet, indent=2, ensure_ascii=False) + "\n"

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
        total = sum(len(v) for v in sheet["binds"].values())
        print(f"Keybindings cheatsheet is in sync ({total} binds).")
        return

    SEED.parent.mkdir(parents=True, exist_ok=True)
    SEED.write_text(rendered)
    total = sum(len(v) for v in sheet["binds"].values())
    print(f"Wrote {SEED.relative_to(REPO)} ({total} binds across {len(sheet['binds'])} categories).")


if __name__ == "__main__":
    main()
