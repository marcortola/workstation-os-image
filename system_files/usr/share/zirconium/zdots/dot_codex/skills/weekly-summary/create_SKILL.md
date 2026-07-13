---
name: weekly-summary
description: Generate a concise Spanish weekly stakeholder summary from the last 7 days of git commits across the active repositories in the user's projects folder. Use when the user asks for a weekly summary, stakeholder update, team-meeting update, WhatsApp-ready product update, or invokes $weekly-summary. Optionally scope to a single project group or repository (e.g. "weekly summary for growwer").
---

# Weekly Summary

Generate a concise weekly update in Spanish for non-technical stakeholders, built
from recent git activity across the user's projects. This skill is project-agnostic:
it discovers repositories at runtime and never assumes a fixed set of clients.

## Scope

Projects live under `$HOME/projects/`, organized as `<group>/<repo>` (for example
`growwer/growwer`, `mencoro/mencoro-app-backend`), where `<group>` is a product,
client, or area. Some repositories sit directly under `$HOME/projects/`.

- Default: analyze every git repository under `$HOME/projects/` that has commits in
  the last 7 days.
- If the user names a group or repository (for example "weekly summary for growwer"),
  restrict the analysis to that group or repository only.

## Discover repositories

Never hardcode repository paths. Discover them at runtime:

```bash
find "$HOME/projects" -mindepth 1 -maxdepth 4 -type d -name .git 2>/dev/null \
  | xargs -r -n1 dirname | sort
```

When the user scopes to a group, restrict the search to `$HOME/projects/<group>`.

## Workflow

1. Discover repositories as above. For each one, inspect the last 7 days of history:
   `git -C <repo> log --since="7 days ago" --no-merges --pretty=format:'%s'`.
   Skip repositories with no commits in the window.
2. Derive each repository's group from its path: the first path segment under
   `$HOME/projects/`, or the repository name itself if it sits directly under it.
3. Discard non-important or micro-commits unless they combine into a meaningful user
   or business outcome. Ignore noise such as typos, formatting, cleanup, internal
   refactors, test-only adjustments, renames, minor dependency bumps, internal
   configuration, trivial fixes, and WIP commits.
4. Group related changes by business impact or user-facing feature, not by repository
   or individual commit. If several repositories in the same group support one feature
   (for example a backend, a frontend, and a service), present them as a single entry.
5. Write in Spanish with simple, user-friendly, stakeholder-oriented language. Avoid
   technical terms, branch names, class names, commit hashes, PR numbers, and
   implementation details unless essential.
6. Keep the output brief enough for WhatsApp or an executive update. Prefer short
   sentences and a small number of high-signal bullets.
7. Structure the document by group/product, using these sections within each group and
   omitting empty sections:
   - `Nuevas funcionalidades`
   - `Mejoras de experiencia de usuario`
   - `Rendimiento e infraestructura` only for changes that materially affect stability,
     speed, operations, or user experience.
8. If few changes are truly relevant, produce a short summary instead of padding the
   report.
9. Save the final result to `$HOME/projects/weekly-YYYY-MM-DD.md` using today's date.
   When the run is scoped to a single group, save to
   `$HOME/projects/weekly-<group>-YYYY-MM-DD.md` instead.

## Output Standard

The summary should read like an update for stakeholders, not a changelog. Favor
outcomes and value:

- Good: "Se ha simplificado el flujo de invitaciones para que los equipos puedan
  incorporar usuarios con menos pasos."
- Avoid: "Refactorizado InvitationController y ajustados tests de backend."
