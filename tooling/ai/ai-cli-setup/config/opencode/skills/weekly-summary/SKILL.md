---
name: weekly-summary
description: Generate or audit a concise Spanish weekly stakeholder summary from the last 7 days of git activity across active repositories. Use for weekly summaries, stakeholder or team-meeting updates, WhatsApp-ready product updates, draft curation, or invocation of weekly-summary. Optionally scope to one or more project groups or repositories.
---

# Weekly Summary

Generate a concise weekly update in Spanish for non-technical stakeholders, built
from recent git activity across the user's projects. Also audit a user-provided
draft for omissions, overclaims, vague entries, and incorrect business framing.
This skill is project-agnostic: discover repositories at runtime and never assume
a fixed set of clients.

## Scope

Projects live under `$HOME/projects/`, organized as `<group>/<repo>` (for example
`acme/acme-web`, `globex/globex-app-backend`), where `<group>` is a product,
client, or area. Some repositories sit directly under `$HOME/projects/`.

- Default: analyze every git repository under `$HOME/projects/` that has commits in
  the last 7 days.
- If the user names a group or repository (for example "weekly summary for acme"),
  restrict the analysis to that group or repository only.

## Discover repositories

Never hardcode repository paths. Discover them at runtime:

```bash
find "$HOME/projects" -mindepth 1 -maxdepth 4 -type d -name .git 2>/dev/null \
  | xargs -r -n1 dirname | sort
```

When the user scopes to a group, restrict the search to `$HOME/projects/<group>`.

## Inspect history

For each discovered repository:

1. Resolve its mainline from `refs/remotes/origin/HEAD`, then local `main` or
   `master`, then `HEAD`. Do not assume the checked-out branch is the mainline.
2. Inspect non-merge commits from the last 7 days on that ref, including date,
   short hash, and subject:
   `git -C <repo> log <mainline> --since="7 days ago" --no-merges --date=short --pretty=format:'%ad%x09%h%x09%s'`.
3. Compare against `git -C <repo> log --all --not <mainline> --since="7 days ago"
   --no-merges` so meaningful work on other local refs is not silently missed.
   Treat work found only outside mainline as in progress unless stronger evidence
   proves otherwise.
4. For every potentially important or ambiguous change, inspect its body and scope
   with `git -C <repo> show --stat --format='%s%n%b' <commit>`. Read a directly
   referenced design record when delivery status or business impact remains unclear.
   Do this selectively; dependency and formatting noise does not need deep inspection.
5. Derive the group from the first path segment under `$HOME/projects/`, or use the
   repository name when it sits directly under that directory. Skip repositories
   with no relevant activity in the window.

Use existing local refs. Do not fetch or mutate repositories unless the user asks.

## Curate by outcome

- Discard micro-commits unless they combine into a meaningful user or business
  outcome. Ignore typos, formatting, cleanup, internal refactors, test-only changes,
  renames, minor dependency bumps, internal configuration, trivial fixes, and WIP.
- Group related changes by business outcome, not repository or individual commit.
  Combine backend, frontend, service, and infrastructure work supporting one feature.
- Include a fix only when its outcome matters to users, revenue, operations,
  reliability, cost, or risk. State that outcome; never write `Fixes varios` or an
  equivalent filler entry.
- Do not broaden what was built. A saved card can speed up later top-ups; it does not
  imply recurring billing. A merged feature is not necessarily deployed, enabled, or
  used in production.
- Distinguish `en desarrollo`, `preparado`, `fusionado`, `desplegado`, and `activado`
  only when evidence supports the status. When evidence is incomplete, use neutral
  wording such as `Se ha desarrollado` and name any known activation gate.
- When auditing a supplied draft, lead with concrete corrections and missing outcomes,
  then provide a clean replacement version. Preserve useful human context that Git
  cannot prove, but flag any conflict with repository evidence.

## Write the update

- Write simple, stakeholder-oriented Spanish. Avoid branch names, classes, hashes,
  PR numbers, and implementation detail in the final artifact.
- Structure by product or group with `## <Producto>` headings.
- Under each product, use high-signal bullets prefixed by a short business area, for
  example `- Pagos: ...`, `- Soporte: ...`, `- Web comercial: ...`,
  `- Organizaciones: ...`, or `- Infraestructura: ...`.
- Do not force generic subsections such as new features, UX, or infrastructure. Area
  labels should reflect the actual work and make the update easy to scan.
- Keep it short enough for WhatsApp or an executive update. If little matters, return
  less rather than padding.
- Save a generated summary to `$HOME/projects/weekly-YYYY-MM-DD.md`. For one scoped
  group, use `$HOME/projects/weekly-<group>-YYYY-MM-DD.md`. When auditing text without
  a request to update a file, return the corrected text without overwriting anything.

## Output Standard

The summary should read like an update for stakeholders, not a changelog. Favor
specific outcomes and value:

- Good: `- Pagos: Las recargas interrumpidas se recuperan automáticamente, evitando
  cargos duplicados o saldo sin acreditar.`
- Good: `- Prospección: Se ha desarrollado el sistema automático; la activación de
  envíos reales sigue pendiente de aprobación operativa.`
- Avoid: `- Pagos: Añadido SavedCardController y sus tests.`
- Avoid: `- Otros: Fixes varios por aquí y por allá.`
