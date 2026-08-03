# Per-hub OG cards: the four entity hubs stop sharing the generic cover

One S-sized PR. `/artists`, `/albums`, `/labels`, and `/tracks` each get a Satori-rendered link-preview card carrying the hub's live counts.

## Context a worker needs

- All four hubs currently point `og:image` at the generic `${siteUrl}/fluncle-cover.png`: `apps/web/src/routes/artists.index.tsx` (~line 133, inside a `metaTagsFor` helper), `albums.index.tsx` (~line 96), `labels.index.tsx` (~line 101), and `apps/web/src/lib/tracks-search.ts` (~line 180, `tracksHead()` — the `/tracks` head lives in the lib, not the route file). The hubs also omit `og:image:width/height` and `twitter:image` entirely — `/log/<id>`'s head is the complete shape to match.
- **The template to copy wholesale is `apps/web/src/routes/api/og.set.ts`** (~100 lines): a Satori `ImageResponse` route with no params and no `/api/v1` twin, mounted bare — its header comment explains why `aliasHandlers` is deliberately not used; keep that comment's rationale intact in the copy.
- The shared kit is `apps/web/src/lib/server/satori-render.ts`: `cardFonts()`, `OG_CACHE_CONTROL`, `fetchImageDataUri()` (Satori cannot fetch remote `<img>` — inline the cover as a data URI), and the `BRAND`/`BODY` faces. Colors come from `@fluncle/tokens`, never hand-copied hex. DESIGN.md §3's type split binds: Oxanium for brand marks and numerals/coordinates, Space Grotesk for reading text.
- Counts: the hubs read stored per-entity counters (the `renderable_track_count`/`certified_finding_count` keystone). Find the cheapest existing server read that yields "N artists / N albums / N labels / N tracks" (the hub page loaders and `countIndexableHubEntities` in the funnel are the places to look) — do not write a new aggregate over raw tracks. The render hits Turso, so `OG_CACHE_CONTROL` on the response is load-bearing, not decorative.

## Build

1. New route `apps/web/src/routes/api/og.hub.ts`: one endpoint taking `?hub=artists|albums|labels|tracks` (validated; unknown → 404). 1200×630. Layout: the hub's name, its live count, the site identity — quiet, cover-led, dark; follow `og.set.ts`'s composition idiom rather than inventing a new one.
2. **Copy rule — no new public strings.** Every word on the card must be a string that already ships on that hub's page or head (the existing meta title/description, the hub's own heading). If a layout genuinely needs a word that does not exist yet, use fewer words instead. This keeps the slice outside the copywriting gate by construction; state this in the PR description.
3. Swap the `og:image` line in the four heads to the new route (with a `?hub=` param), and add `og:image:width`, `og:image:height`, `og:image:type`, `twitter:image` + `twitter:card` matching `/log`'s head shape.
4. Extend `apps/web/src/routes/-cache-headers.test.ts` — it locks the exact `Cache-Control` literal per crawler-facing surface and already covers the existing OG card (~line 92); the new route joins that list.
5. This is NOT a registry surface (no `/api/og` entries exist in `packages/registry`), so no surface fan-out is owed — do not add one.

## Constraints

- No new dependencies; `workers-og` and the font assets are already in place.
- Rendering must not run for invalid `hub` values (validate before any DB read).
- No non-null assertions; comment idiom per AGENTS.md.

## Acceptance

- `bun run --cwd apps/web typecheck` and `bun run --cwd apps/web build` pass.
- `cd apps/web && bunx vitest run src/routes/-cache-headers.test.ts` passes with the new route asserted.
- A new route test (beside the existing OG route tests if any exist; else a focused unit test of the hub-param validation and count read) passes under `bunx vitest run`.
- `rg -n "fluncle-cover.png" apps/web/src/routes/artists.index.tsx apps/web/src/routes/albums.index.tsx apps/web/src/routes/labels.index.tsx apps/web/src/lib/tracks-search.ts` returns nothing.
- `bun run check` passes from the repo root.
