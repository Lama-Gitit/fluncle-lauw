# Plan: runtime validation for the /tracks serverFn filter boundary

Payload for Hyperspeed envelope `tracks-serverfn-runtime-validation` (residual surfaced by hs-2026-08-03-003's adversarial reviewer, verdict pass — bounded hardening, not a regression).

## The gap

`fetchTracksHubPage` (`apps/web/src/routes/tracks.tsx`, the `createServerFn` at ~line 125) validates with an identity cast: `.validator((data: { filters: TracksHubFilters; page: number }) => data)`. Before the search-filter vocabulary collapse (#1091), `sharedFilters()` was incidentally a RUNTIME whitelist; the collapse removed it, so a directly-crafted RPC payload carrying `artist`/`album`/`text` — `SearchFilters`-only fields the old bridge deliberately did not copy — now flows into `compileFilters`/`resolveFilterEntities` and compiles extra clauses.

Impact is bounded (all binds parameterized, every in-app caller runtime-whitelists via `parseTracksSearch`'s exactly-seven fields, the same filter vocabulary is already public on `/search`, and the boundary accepted injected `certified`/`galaxy` pre-collapse) — but the boundary should parse, not cast.

## The change

- Replace the identity cast with a real runtime validator on the serverFn: parse the payload against the `TracksHubFilters` shape (`apps/web/src/lib/server/tracks-hub.ts:99` — the six `SearchFilters`-picked axes plus `certified`/`galaxy`) and `page`. Zod is fine (the contracts package already carries it) — or a hand parser in lockstep with `parseTracksSearch` (`apps/web/src/lib/tracks-search.ts:98`) if that matches the route-file idiom better; survey how sibling serverFn validators in `apps/web/src/routes/` do it and match the strongest existing pattern. Unknown fields are stripped or rejected — never forwarded.
- Field-level types must match what the compile path expects (numbers for the bpm/year bounds, string key/label/galaxy, boolean certified, integer page ≥ 1); a value of the wrong type is rejected, not coerced into a clause.
- Note: the web page itself never sets `certified` (API-only, per the type's comment) — decide deliberately whether the serverFn accepts it or strips it, and say which in a comment at the validator.

## Acceptance

- The serverFn runtime-validates its payload; a crafted payload carrying `artist`/`album`/`text` is rejected or stripped rather than compiled into hub clauses — proven by a test (vitest, colocated with the route's existing tests or in the tracks-hub suite; assert at the compile boundary, not just the parser).
- `bun run --cwd apps/web typecheck` and the tracks-hub/funnel-view test files pass; full `bun run --cwd apps/web test` green.
- No behavior change for legitimate callers: the loader/`parseTracksSearch` path serializes exactly the whitelisted axes and must round-trip untouched (the existing hub tests pin this — zero expectation edits expected outside the new test).
