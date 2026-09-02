# Design Records

A **design record** is a snapshot of one durable decision and its rationale,
written while the work was being done. The rest of the handbook says how the
machine works now; a record says what was believed, and why one route beat the
alternatives, on the day it was written.

**Trust the current code over anything in this directory.**

---

## The Standing Rule

A record is never updated to match reality. When reality moves, the change lands
in the code and in the handbook page that owns the topic; the record stays as
written, wrong parts included — editing it to stay accurate destroys the one
thing it is for. `tooling/validate/sources` does read these records, along with
the rest of `docs/`, but it proves no more than that a cited recipe still exists,
that a cited path still resolves and that a link still lands — never that the
reasoning around them still holds. So a record goes stale in the way that
matters, silently and by design; see
[../validation-and-gates.md](../validation-and-gates.md) for what is asserted.

---

## When to Add One

Add a record when a decision is durable and its rationale would otherwise be
re-derived — the git log carries what changed, never why one route beat another:
the constraint that forced a mechanism's shape, the alternatives that lost, the
failure that motivated the work. Skip it for a routine change or a fix whose
reasoning fits in the commit body.

Records are written to be read at the start of the next long change, not found
after it. The shipped agent seeds say so directly:
`system_files/usr/share/workstation-os-image/dotfiles/dot_claude/create_CLAUDE.md`
and its codex and opencode twins tell every AI CLI on this machine to record
durable decisions here, and to read the relevant record plus the recent git log
before starting long work.

---

## The Records

| Record | What it covers |
|---|---|
| [docs-split.md](docs-split.md) | Why the 855-line root README became this handbook: the three audiences one file was failing, the sub-decisions whose cheaper alternative was rejected, and the twenty factual defects corrected while the text moved. |
| [agent-recency.md](agent-recency.md) | Why "when did this agent finish?" needed a clock of our own, where the stamp lives, and the four cheaper routes that lost — a seen-watermark, polling, a subscriber daemon, and expiring open spaces. |
| [herdr-layouts.md](herdr-layouts.md) | Why the dev workspace has two layouts rather than one, why neither is built with `layout.apply` — the call that replaces the tab and restarts the agent — and the four arrangements that lost, including the two-tab shape a pane's single-tab membership rules out. |
| [upgrade-download-size.md](upgrade-download-size.md) | Why every `bootc upgrade` re-downloaded 1.4 GB, the four changes that cut it to ~0.8 GB, and the five routes that were measured and lost — rechunking, splitting the packages `RUN`, chasing the layer cache, prefetching, and rescheduling `uupd`. |

---

## Where to go next

[../README.md](../README.md) is the handbook index and
[../conventions.md](../conventions.md) holds the mechanisms a record would
otherwise restate. [../working-with-agents.md](../working-with-agents.md)
covers landing a durable change — the point at which a record is written.
