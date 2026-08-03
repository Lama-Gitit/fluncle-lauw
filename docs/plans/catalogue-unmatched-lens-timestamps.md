# The unmatched lens shows when a row was last tried

One S-sized PR closing an observability gap: `fluncle admin catalogue list --lens unmatched` orders by `source_audio_attempted_at` but never returns it, and its plain-text renderer has no unmatched-specific branch — so the lens sold as the capture audit's observability window cannot show when a row was last attempted or even its capture status.

## Context a worker needs

- Server: `apps/web/src/lib/server/catalogue.ts` — the shared `CATALOGUE_SELECT` (~line 2401) omits `source_audio_attempted_at`; the unmatched lens query (~line 2467) is `where capture_status = 'unmatched'` ordered by `source_audio_attempted_at desc`. The lens's own doc comment in `packages/contracts/src/orpc/admin-catalogue.ts` (`CatalogueLensSchema`, ~line 66) names `requeue_unmatched_captures` as its rescue.
- Contract: the catalogue row schema in `packages/contracts/src/orpc/admin-catalogue.ts`. Additive-optional is the house pattern for extending admin rows (see the labels contract's identity-fields block for the precedent and its rationale comment: older clients and the CLI keep working).
- CLI: `fluncle admin catalogue list` is registered in `apps/cli/src/cli.ts` (~line 2371); the plain-text renderer falls through to the generic ranked-row line for the unmatched lens. The admin CLI is operator-tier register (terse is fine; em-dash clause joins and ALL-CAPS status words are the allowed carve-outs).

## Build

1. Add `source_audio_attempted_at` (and `capture_status` if the select omits it) to `CATALOGUE_SELECT` and thread them through the server mapping into the row DTO.
2. Extend the contract row schema with the new fields as `.nullable().optional()`, with a short constraint-style doc comment (additive so existing clients keep working).
3. Give the CLI renderer an `unmatched` branch: the row line shows identity, `captureStatus`, and the attempted-at timestamp (human-readable relative or ISO — match how other CLI timestamps in this file render). `--json` output picks the new fields up automatically once the DTO carries them; verify it does.
4. Tests: extend the relevant server/oRPC admin-catalogue tests for the enriched rows, and the CLI tests for the new renderer branch.

## Constraints

- No new CLI flags (nothing joins `stringOptions`); this is output-only.
- No changes to lens semantics, ordering, or the requeue op.
- No non-null assertions; comment idiom per AGENTS.md.

## Acceptance

- `bun run --cwd apps/web typecheck` and `bun run --cwd apps/cli typecheck` pass.
- The focused apps/web admin-catalogue tests pass under `bunx vitest run`.
- The FULL apps/cli test suite passes (`bun run --cwd apps/cli test`) — the whole suite, not a focused file.
- `bun run check` passes from the repo root.
