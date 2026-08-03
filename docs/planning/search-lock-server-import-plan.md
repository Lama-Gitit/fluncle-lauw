# Plan: the read-path lock learns the server-side import shape

Payload for Hyperspeed envelope `search-lock-server-import-marker` (discovered by hs-2026-08-03-002's adversarial review, verdict pass — this is the non-blocking coverage hole it filed, not a regression).

## The gap

The read-path lock (`apps/web/src/lib/server/search-consumers.test.ts`) walks every app source for references to the Spotify op and asserts the caller set equals `SUBMIT_FLOW_ALLOWLIST`. Its four `SPOTIFY_OP_MARKERS` cover the op's literal path, the oRPC client op, and the two client helpers — but a SERVER file importing the capability module `lib/server/track-search` directly evades all four. That shape is real and legitimate today in exactly two places: `apps/web/src/lib/server/mcp.ts:7` (`import { searchTracks } from "./track-search"`) and `apps/web/src/lib/server/orpc/search.ts:9` (`from "../track-search"`). A future browse-surface server route could import the same module and the lock would never see it.

## The change

One more marker + two allowlist entries, nothing else:

- Add a marker to `SPOTIFY_OP_MARKERS` matching a module import of `track-search` in any of its reachable spellings — relative (`./track-search`, `../track-search`) and aliased (`@/lib/server/track-search`). Keep the regex import-shaped (match `from "<...>track-search"`), not a bare substring: the walk reads full file contents, and prose mentions of the words must not trip it.
- Add `apps/web/src/lib/server/mcp.ts` and `apps/web/src/lib/server/orpc/search.ts` to `SUBMIT_FLOW_ALLOWLIST`, each with the one-line comment the list's convention requires (which leg of the funnel / why the reference is the implementation side, in the style of the existing `track-search.ts` entry).
- The companion test ("keeps the allowlist itself honest") already requires every allowlist entry to match a marker — the two new entries satisfy it via the new marker; verify, don't disable.

Recorded in the same review, deliberately NOT in scope (no envelope owed): the URL-tier regex tolerance gaps (uppercase host, uppercase intl segment, trailing slash fall through to the FTS fail-safe — Spotify's share sheet never emits those shapes).

## Acceptance

- `search-consumers.test.ts` gains the direct-import marker; `mcp.ts` and the oRPC search router are allowlisted.
- `cd apps/web && bunx vitest run src/lib/server/search-consumers.test.ts` passes, and a mock browse-route file importing `track-search` would trip the lock (prove it in-run: create the temp file, watch the test fail, delete it — do not commit the mock).
- Verification battery: `bun run --cwd apps/web test`, root typecheck + check (the Go-less substitution where the box lacks a toolchain, recorded as such).
