# Plan: tighten the tracks-hub payload validator's edge values

`parseTracksHubPayload` (`apps/web/src/lib/tracks-search.ts`, the `/tracks` serverFn boundary validator) passed its adversarial security review; three harmless strictness residuals remain and this plan closes them so the boundary is in exact lockstep with `parseTracksSearch`.

## The residuals

1. **Array-shaped `filters` acts as an empty object.** `typeof [] === "object"` and `[] !== null`, so a crafted `filters: []` passes the object check and every field lookup returns `undefined`. Reject arrays explicitly (`Array.isArray`) with the existing `TracksHubPayloadError("filters", "an object")` shape.
2. **Padded strings pass untrimmed.** `strictFilterString` checks `value.trim().length === 0` but returns the untrimmed value, while the loader contract says already-trimmed values arrive. Decide with `parseTracksSearch` as the reference: normalize (trim) or reject untrimmed input — whichever keeps the two parsers behaviorally identical for the same axis; state the choice in the function comment.
3. **Unbounded magnitudes.** `strictPositiveInt` accepts any positive safe-or-unsafe integer and `page` any integer ≥ 1. Add deliberate upper bounds consistent with what `parseTracksSearch` accepts from the URL for the same axes (bpm/year plausibility bounds, and a page ceiling consistent with the hub's real pagination); reject beyond-bounds values rather than clamping, matching the validator's reject-don't-coerce doctrine.

## Acceptance

- Focused adversarial tests in `apps/web/src/lib/tracks-search.test.ts` cover: array filters, nested-array field values, padded strings, extreme/unsafe integers, and page bounds — all rejected; every legitimate loader-shaped payload still parses (the existing round-trip tests stay green).
- The loader's URL → filters → serverFn round-trip acceptance stated in the file's own comments is preserved.
- `cd apps/web && bunx vitest run src/lib/tracks-search.test.ts` passes; `bun run --cwd apps/web typecheck` and root `bun run check` pass.
