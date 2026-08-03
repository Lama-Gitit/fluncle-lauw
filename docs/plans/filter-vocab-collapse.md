# Collapse the two search-filter vocabularies into one type

One small PR, types only, zero behavior change.

## Context a worker needs

- `TracksHubFilters` (`apps/web/src/lib/server/tracks-hub.ts` ~line 98, re-exported by `apps/web/src/lib/tracks-search.ts`) mirrors `SearchFilters` (`packages/contracts/src/orpc/search.ts` ~line 52) verbatim for the six shared fields: `bpmMin`, `bpmMax`, `yearMin`, `yearMax`, `key`, `label` — same names, same semantics, compiled by the same `compileFilters`.
- The genuine deltas: the hub adds `galaxy` (findings-only structurally) and `certified` (API-only tri-state); the search schema has five fields the hub does not take (`album`, `artist`, `soundsLike`, `soundsLikeArtists`, `text`).
- `sharedFilters()` in `tracks-hub.ts` (~line 177, ~12 lines) is a hand-written bridge copying the shared six between the two shapes.

## Build

Retype `TracksHubFilters` as an intersection over the contract type — `Pick<SearchFilters, the six shared keys> & { certified?: ...; galaxy?: ... }` (or the equivalent shape that typechecks cleanly against every existing consumer) — and delete `sharedFilters()`, updating its call sites to pass the fields directly. The contract package is the single source for the shared field types afterward; the hub file keeps only its two additions.

## Constraints

- ZERO runtime behavior change: `compileFilters` and every query untouched. This is a type-level dedup.
- If the intersection route fights the existing Zod-derived types, an acceptable alternative is deriving the hub type from the contract Zod schema (`z.infer` + extension) — pick whichever leaves the smallest diff. Do not restructure either module.
- No non-null assertions; match existing comment idiom.

## Acceptance

- `bun run --cwd apps/web typecheck` passes.
- `cd apps/web && bunx vitest run src/lib/server/tracks-hub.test.ts src/lib/funnel-view.test.ts src/lib/server/search.integration.test.ts` passes with no test-expectation edits (behavior is unchanged).
- `rg -n "sharedFilters" apps/web/src` returns nothing.
- `bun run check` passes from the repo root.
