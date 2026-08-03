# Internal search learns the Spotify-URL tier, and the read path gets locked

One PR. Two halves that belong together: internal search gains a deterministic Spotify-URL/URI resolution tier (the prerequisite for any future submit-fallback posture), and a regression test locks the already-true fact that every browse surface searches internally.

## Context a worker needs

- The archive search resolver is `apps/web/src/lib/server/search.ts` — a tiered resolver: coordinate → exact entity → FTS token → LLM filters (see `docs/search.md`). It is served by the `searchArchive` op (`GET /search/archive`, `packages/contracts/src/orpc/search.ts`).
- The Spotify-backed op (`searchTracks`, `GET /search`) exists ONLY for the submit funnel. Every browse surface (web ⌘K `apps/web/src/components/search/search-command.tsx`, CLI `apps/cli/src/commands/search.ts`, mobile archive `apps/mobile/app/(tabs)/archive.tsx`, MCP/ChatDnB `search_archive`, recommendations panel, mix builder) already calls the internal op.
- Today a pasted Spotify URL falls through to FTS in the internal resolver and misses; the Spotify op short-circuits URLs to a by-id fetch (`apps/web/src/lib/server/spotify.ts` ~line 348) — that convenience is what this tier brings home.
- `tracks` carries `spotify_uri` and `spotify_url` (`apps/web/src/db/schema.ts` ~line 764, both nullable — the crawler deliberately never writes them; anchoring fills them asynchronously, so NULL is a standing population). An index on `spotify_uri` exists (search schema.ts for `spotify_uri` index definitions before assuming the name).

## Build

1. **The URL tier.** In `search.ts`, before the existing deterministic tiers run their text matching: detect a query that parses as a Spotify track reference — `https://open.spotify.com/track/<22-char-id>` (tolerate `intl-*/` path segments and query strings) or `spotify:track:<id>`. Extract the id, resolve against `tracks` by `spotify_uri = 'spotify:track:' || <id>` (confirm the stored format by reading the anchor write sites in `apps/web/src/lib/server/anchor.ts` before writing the predicate). A hit returns that single row as the result set through the same projection the other tiers use (the row's `certified` tag, cover, etc. — no new projection). A miss falls through to the normal tiers (the query text will FTS-miss harmlessly). No network call is ever made — this tier is a local column seek.
2. **Contract header truthing.** The header comment of `packages/contracts/src/orpc/search.ts` still narrates the SPOTIFY/FLUNCLE split as if a read migration were pending. Rewrite it to the standing state: `searchTracks` is the submit-funnel candidate search; `searchArchive` is the archive/browse search and resolves Spotify URLs locally.
3. **The read-path lock.** New test `apps/web/src/lib/server/search-consumers.test.ts`: walk the repo sources (`apps/web/src`, `apps/cli/src`, `apps/mobile/app` + `apps/mobile/src`) for literal references to the Spotify op's path (`/api/v1/search` exact, not `/search/archive`) and its client helpers, and assert the caller set equals a named allowlist of the seven submit-flow files. Follow the shape of the existing cross-cutting guards (`apps/web/src/lib/mcp-webmcp-parity.test.ts` reads files with `node:fs`). A new browse consumer of the Spotify op should fail this test with a message explaining the read path is internal-only.
4. **Docs.** `docs/search.md` gains the URL rung in its tier description (one short paragraph, same register as the existing tier prose).

## Constraints

- No changes to the Spotify op, the submit flow, or any consumer — this PR adds capability and locks state; the fallback posture is a separate, operator-gated decision.
- No new dependencies. No TypeScript non-null assertions (oxlint error). Match `search.ts`'s existing comment idiom (constraints, never change history).
- Integration tests live beside the existing ones in `apps/web/src/lib/server/search.integration.test.ts` — follow its fixture style.

## Acceptance

- `bun run --cwd apps/web typecheck` passes.
- `cd apps/web && bunx vitest run src/lib/server/search.integration.test.ts src/lib/server/search-consumers.test.ts` passes, including new cases: URL form resolves to the seeded track; `spotify:track:` form resolves; an unknown id falls through without error; an `intl-de` URL form resolves.
- `bun run check` passes from the repo root.
