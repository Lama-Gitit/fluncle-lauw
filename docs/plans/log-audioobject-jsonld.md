# AudioObject markup: the spoken observation becomes a first-class schema object on /log/<id>

One S-sized PR. The observation audio already renders and streams on the finding page; this gives it the JSON-LD identity the video already has.

## Context a worker needs

- All JSON-LD builders live in `apps/web/src/lib/log-schema.ts`. The pattern to copy is `videoObjectJsonLd` (~lines 274–302): a pure function over `(track: LogSchemaInput, extras)` returning a flat record with `@context`/`@type`, `creator`/`publisher` both `{ "@id": fluncleEntityId }`, `description: definitionalProse(track)`, `name: artistTitleLine(track)`, `url: logPageUrl(track.logId)`.
- Emission site: `apps/web/src/routes/log.$logId.tsx` → `logHead()`, finding branch — `videoSchema` is built conditionally (~line 245) and pushed through `jsonLdScript` (which HTML-escapes; mandatory, it is the stored-XSS rail).
- The observation audio URL is the DTO field `track.observationAudioUrl` — already version-busted server-side (`versionedObservationAudioUrl` in `apps/web/src/lib/server/tracks.ts` ~line 512). Duration is `observationDurationMs`; the generated-at timestamp is `observationGeneratedAt`. All three are in the detail DTO already — no new query.
- Date fields must go through the existing `uploadDateIso()` normalizer (date-only values trip GSC — a past validator failure this repo already fixed once).
- `musicRecordingJsonLd` already contains a ms→ISO-8601 duration conversion — reuse its helper/shape for `duration`.

## Build

1. Add `observationAudioObjectJsonLd(track)` to `log-schema.ts`: `@type: "AudioObject"`, `contentUrl` = the versioned observation URL, `duration` (ISO-8601 from `observationDurationMs`), `uploadDate` via `uploadDateIso(observationGeneratedAt)`, `encodingFormat: "audio/mpeg"`, `name`/`description`/`url`/`creator`/`publisher` per the video builder's pattern. Extend `LogSchemaInput` with the observation fields it needs.
2. **Deliberately NO `transcript` field.** The observation script is internal authoring fuel (admin-only); publishing it is an unruled canon question. Do not surface it in any form, including via the alignment JSON.
3. Emit in `logHead()`'s finding branch, conditional on `track.observationAudioUrl`, exactly parallel to the `videoSchema` conditional.
4. Tests: per-builder assertions in `apps/web/src/lib/log-schema.test.ts` (match its exhaustive house style — every field asserted). **Mandatory:** add the new builder to the import list of `apps/web/src/lib/log-schema-hop-carveout.test.ts` — that guard asserts no `/out/` hop URL ever reaches emitted schema, and it only covers builders it imports. If `apps/web/src/routes/-jsonld-xss.test.ts` enumerates emission sites, extend it too.

## Constraints

- The mixtape branch of `logHead` is OUT of scope (its audio is a different object; a parallel AudioObject there is a future call).
- No new public copy — `description` reuses `definitionalProse`, `name` reuses `artistTitleLine`.
- No non-null assertions; comment idiom per AGENTS.md (constraints, never history).

## Acceptance

- `bun run --cwd apps/web typecheck` passes.
- `cd apps/web && bunx vitest run src/lib/log-schema.test.ts src/lib/log-schema-hop-carveout.test.ts src/routes/-jsonld-xss.test.ts` passes, with new assertions covering: all fields present on a full fixture; the builder omitted when `observationAudioUrl` is null; the hop-carveout walk covering the new builder.
- `rg -n "transcript" apps/web/src/lib/log-schema.ts` returns nothing.
- `bun run check` passes from the repo root.
