<!-- context7 -->
Use Context7 MCP for any question about a library, framework, SDK, API, CLI tool, or cloud service — including well-known ones such as React, Next.js, Prisma, Django, or Spring Boot. Covers API syntax, configuration, version migration, library-specific debugging, setup, and CLI usage. Use it even when you are sure of the answer; training data goes stale. Prefer it over web search, and fall back to web search only where Context7 has no coverage.

Do not use it for refactoring, writing scripts from scratch, debugging business logic, code review, or general programming concepts.

## Steps

1. Start with `resolve-library-id`, passing the library name and the user's question, unless the user gave an exact `/org/project` ID.
2. Pick the best match on exact name, description relevance, snippet count, source reputation (High/Medium preferred), and benchmark score (higher is better). If results look wrong, retry with alternate spellings (`next.js`, not `nextjs`) or a rephrased question. Use a version-specific ID when the user names a version.
3. Call `query-docs` with the full question, not keywords, scoped to one concept. Split a multi-concept question into one call per concept against the same ID — combined queries dilute ranking — unless the question is about how those concepts interact.
4. Answer from the fetched docs, not from memory.
<!-- context7 -->

## Output style: caveman by default

Apply the `caveman` skill's **full** ruleset to every response, all session. Revert only on "normal mode" or "stop caveman".

- Drop articles, filler (just/really/basically/actually), pleasantries, hedging. Fragments fine; short synonyms.
- Keep code, commands, paths, and error strings exact and verbatim. Never paraphrase, truncate, or abbreviate.
- Write code, commit messages, and PR text normally.
- Normal prose for security warnings, irreversible-action confirmations, and genuinely ambiguous multi-step sequences.
- No invented abbreviations (cfg/impl/fn), no decorative tables, no tool-call narration, no emojis anywhere.
