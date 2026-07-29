# RFC: The DnB identity graph — the honest identity surface (decided, ready to build)

**Status:** Final — all decisions RESOLVED with the operator, 2026-07-29 (research → /taste → 4-role adversarial panel → operator interview). Completeness standard applied.
**For:** a build session. Nothing below is open; § Rulings is the contract.
**Canon/authority:** the codebase, `LORE.md` / `PRODUCT.md` / `DESIGN.md` / `VOICE.md`, `docs/album-entity.md`, `docs/catalogue-crawler.md`, `docs/naming-conventions.md`. Planning, not spec. Evidence: [docs/planning/identity-graph-research.md](./planning/identity-graph-research.md) — including the Unit 0 prod measurements, run 2026-07-29.

> Process note: four research threads + two sub-verifications, a /taste pass, a four-role adversarial panel, then a decision-by-decision operator interview (2026-07-29) that ruled every open item. The panel's corrections are baked in; the interview's rulings supersede the earlier § Decisions.

## The standard (definition of done)

The build ships complete — implementation, tests, docs, copy gates, registry fan-out. The sanctioned "not now"s, honestly scoped: the nightly dump (ruled out for now — no consumer yet; the envelope serializer it would reuse ships anyway, so building it later is ~a day); the key layer (Unit 3b, trigger-gated); third-party Apple links (blocked on reading ADPLA §3.3.6(D) verbatim — attempt the read during the build; until read, Apple is `unsupported` in machine-served answers while first-party page rendering continues as today); Tidal (no integration exists — `unsupported`, honest). Dangling threads tied off: the ISRC attempt stamp + backfill, Discogs catalogue-row bookkeeping, and **the Apple catalogue backfill cron leg** (machinery shipped end-to-end, never scheduled — 65,260 rows never attempted, measured).

## 0. What this builds, in plain words

Fluncle knows, for tens of thousands of recordings, that _this recording_ = _this Spotify link_ = _this Apple link_ = _this MusicBrainz ID_ = _this ISRC_. This build lets anyone look that up — and, uniquely, hear the honest negative: per platform, one of **"found and verified (here's how and when)"**, **"looked N times over M months, not there — stop asking"**, **"never looked yet"**, or **"we don't cover that platform"**. No incumbent says the middle two out loud; Fluncle can because the anchor machinery already counts its attempts. That honesty is the product, and it is a _selector's_ claim (a human gate exists), never a data-provider claim — no surface built here may advertise coverage, compare breadth, or read like a database speaking.

Three faces were considered; **two were ruled in**: a public reader page, and an identity upgrade to the existing track API. The standalone keyed endpoint was dropped; the downloadable nightly file was ruled _not for now_.

## § Rulings (operator, 2026-07-29 — the build's contract)

1. **Uncertified tracks are served.** Confirmed (a formality — six shipped public ops already do this): identifiers and links are data; `logId`, notes, and every Fluncle-authored word stay absent on uncertified rows; the `certified` boolean is the only tier carrier; no field name, enum value, or reason string ever contains a noun for the tier.
2. **The artifact: the reader page + the `get_track` extension, one slice.** A public page rendering the honest-state answer for a recording (reachable by ISRC / MBID / Log ID), crawlable and citable; and the existing `get_track` op learning `?isrc=` / `?mbid=` keys plus an optional identity projection carrying the same envelope. **No new standalone endpoint. No nightly dump for now** (revisit when a consumer appears — label outreach is the likely trigger; the serializer ships regardless).
3. **Posture A — free.** No key requirement, no money machinery. The standing commitment is scoped precisely: **the platform-link map is free for as long as Fluncle holds a Spotify developer app** (selling it trips Developer Terms V.5 + the standalone-service clause — this is contract, not choice). Fluncle's **own** analysis (BPM/key from captured audio, embeddings, sonic neighbours, certification) explicitly remains monetizable later; a posture-B rung (money buys bulk/convenience, links never degraded) stays open and nothing in this build forecloses it.
4. **Timing: pre-overhaul, build now.** The operator's freeze ruling. Unit 0 already ran (2026-07-29, GO at 4× the threshold); Unit 1a + the Apple cron leg + the artifact slice all proceed.
5. **No retirement trigger needed.** With the dump out, nothing in the build carries a standing cost — the page and the projection are archive surfaces the overhaul re-judges like everything else.
6. **Wrong-answer channel: `hey@fluncle.com`** — the existing public fix-it address on `/terms`. Carried on the page, the docs section, and the response `meta.contact`. No new machinery.
7. **The Spotify hop, served everywhere.** Raw links stay _stored_; every _served-for-following_ Spotify link — page buttons, API responses, existing DTOs — becomes `https://www.fluncle.com/out/spotify/<fluncleTrackId>`, a 302. The key is **Fluncle's track id, never the Spotify id** (an id in the path would BE the mapping). Two ruled carve-outs: **(a)** JSON-LD / `sameAs` / schema markup keeps RAW links — those are machine identity _assertions_, not link serving, and hop URLs would poison the knowledge-graph anchoring; **(b)** the Fluncle iOS app preserves today's instant app-open by resolving the hop itself (one manual-redirect fetch, open the `Location` natively) while still consuming hop-only data. Known UX truth, accepted: OS-level link recognition does not survive a redirect, so third-party taps open Spotify via Spotify's own web-to-app bounce (the smart-link industry's standard path) — a brief browser flash.
8. **The dials: 30 req/min/IP burst + 1,000 req/day/IP ceiling** on the identity lookups (the keyed reads + the page's server fn), on the existing atomic limiter (`search_archive` precedent). Ships with a `rate_limit_counters` prune and the tested abuse alert (a detector is unproven until a synthetic failure fires it).

## Unit 0 — DONE (measured against hosted prod, 2026-07-29)

Full tables in the companion file. The load-bearing numbers: **GO at 4× threshold** (8,341 rows with ≥2 platform links: 8,256 catalogue + 85 certified). Certified (85): 100% ISRC, 100% Spotify, 99% Apple, 62% MBID. Catalogue (65,249): 52% ISRC, 31% Spotify (+8,778 honest tried-and-missed — the negative corpus already has volume), **Apple 0% / all never-attempted** (the sweep leg was never scheduled), 58% Discogs, ~100% MBID (crawler PK). ISRC collisions: 468 of 33,472 ISRCs (~1.4%) — arrays required, rarer than the external ~8% estimate. The keys are complementary: ISRC serves certified rows perfectly, MBID serves the catalogue perfectly; spotify-born MBID (59%) is the one soft spot. Q2 (uncovered scan) completed in ~4.8s wall including network — tolerable as a one-off, never as a live op (the coverage read stays snapshot-based).

## Unit 1 — the ledger trues-ups + the acquisition leg

All columns nullable, no `.default()` (the ~125-index rebuild trap).

1. **`tracks.isrc_attempted_at`** — an "attempt" is any ISRC fill path concluding (publish's Spotify/Deezer lookups, the crawl's MB read, the Deezer-recovery rung). Backfill: stamp rows whose ISRC is non-null; ISRC-less legacy rows honestly read `unattempted` and drain as sweeps revisit. Rows under the worklist's permanent exclusions read `refused` (Unit 2's shared predicate), never `unattempted`.
2. **Discogs catalogue-row bookkeeping** — mirror the Apple four-column reliability set onto `tracks`; without it catalogue rows cannot distinguish `absent` from `unattempted` for Discogs.
3. **The Apple catalogue cron leg** (interview addition): add the `admin backfills apple-catalogue` call to the existing box `backfill-sweep.ts` tick, right after the findings leg — the op, worklist (capture-priority-ordered, breaker/meter-gated), and CLI command all exist (`cli.ts:2601`); nothing schedules it. One cron does all tracks; the two server ops stay split on purpose (different worklists, certified-first drain, the certification rail). 33,853 ISRC-bearing catalogue rows to try — the single biggest coverage lever available, feeding first-party surfaces regardless of this build.
4. **Contract-serving columns**: the persisted provenance pair on the five-member `AnchorReviewSource` enum ("apify" included — that rung bypasses `resolveAnchorFree`) + `verifiedBy` extended with `"search-subset"` and `"operator"` (the review-accepted anchors are the best-provenance rows in the corpus and must not read `unknown-legacy`); `spotify_anchored_at` (the hit time — the attempted stamp is NULL on publish-born findings); the Deezer pair (`deezer_track_id` + attempt bookkeeping) **or** Deezer ships `unsupported` — builder's call once in the code, honesty non-negotiable either way.

## Unit 2 — the envelope (one answer, two carriers)

**Naming:** `get_track_identity` semantics ride the existing `get_track` — the op gains `?isrc=` / `?mbid=` keys and an identity projection; the reader page is a new web route (name it in the build past the naming linter; `resolve` is an Engine-Room verb — legal in an operationId or path segment, forbidden in any heading, title, or user-facing sentence). The MBID key needs the new `tracks(mb_recording_id)` value index, hosted-proven before shipping (24–36s-class build at this scale).

**The envelope, per recording** (always an array under a shared ISRC — with `relation: "canonical" | "duplicate-of:<trackId>" | "ambiguous"` per entry, honoring `duplicate_of_track_id` verdicts): `certified` + `logId` (both carried, never inferred from each other), identifiers with provenance, and per-platform link states:

- `verified` — with `verification: { method, at, atMeaning }` (`method` from the persisted rung incl. `search-subset` / `operator` / `pk-derived` / `unknown-legacy`; `atMeaning: "verified" | "attempted" | null` so an attempt stamp is never read as a verification time)
- `absent` — `{ attempts, lastAttemptedAt, retry: "capped" | "recheckable" | "single-shot", cap, terminal }`, `terminal: null` wherever no column backs it (Apple is `recheckable` forever by its own doctrine; MBID is `single-shot`); the served `attempts` is a monotone count, never the requeue-decremented budget counter
- `refused` — derived from **the same exported SQL fragment `kindClause("anchor")` uses** (all five exclusions), tested for row-for-row agreement with the worklist; `reason` a closed machine enum, no tier nouns
- `unattempted` / `unsupported` — as ruled; Tidal `unsupported`; Apple `unsupported` in machine-served answers until the ADPLA clause is read (page rendering unaffected)

Spotify links serve as the hop per Ruling 7, with both carve-outs. `meta` carries `asOf`, MusicBrainz attribution, and `contact: "hey@fluncle.com"`. Transport: `404` only for an unknown key (no submission affordance — machine callers must not pollute the crew triage queue), `422` for a malformed key thrown **in-handler** (oRPC schema rejection emits 400; tolerant input schema per the `search_tracks` precedent).

**The coverage read** (page footer + docs, not a standalone op unless the build finds it free): snapshot-based (the `catalogue_snapshots` precedent), never a live scan — the live aggregate is the measured 12–19s uncovered-walk shape. Denominator: the resolvable set (`dismissed_at is null and duplicate_of_track_id is null`), split by tier, with per-platform attempted sub-denominators, and a test that every denominator row resolves non-404.

## Unit 3 — the hop route + the dials

- **`/out/spotify/<trackId>`** — a 302 keyed on Fluncle's id; logs enough to see bulk harvesting; joins the DTO serving path so every served Spotify link is the hop (Ruling 7), with the JSON-LD carve-out enforced by a test (no `fluncle.com/out/` URL may ever appear in a `sameAs` array) and the app-side resolver helper landing in `apps/mobile` in the same wave.
- **The dials** per Ruling 8 on the identity lookups, on the existing limiter; hosted measurement of the 2-writes-per-read pair; the `rate_limit_counters` prune; the abuse alert with its synthetic-fire test.
- **Cache: uncached at launch** (decided — caching any oRPC op means opening the `server.ts` dispatch spine, a change touching every contract op; not this build).

## Unit 3b — the key layer (unchanged: decoupled, trigger-gated)

Off the critical path. Triggers: the abuse alert firing, a real integrator asking for headroom, or wanting the MCP/`/chat` unblock. Mechanics as researched (an `api_keys` table, `bucket = keyId`, the auth-tier addition — a new middleware + `STATIC_MIDDLEWARE_TIERS` + `EXPECTED_TIERS` entries). Strictly before any money, which Ruling 3 declines to pursue.

## Unit 4 — terms, copy, and fan-out

**`/terms`: three edits, launch-blocking, shipped with the slice** — the fair-use number on "reasonable use"; the carve-out on the user-side licence grant (line 65 — as written it forbids every commercial integrator; the API becomes callable by commercial products while the archive's _content_ stays non-commercial); the consumer-side attribution + Spotify link-back duty. All through `copywriting-fluncle` + blocking `canon-reviewer`.

**Every public string is copy-gated** (both gates named, per string): the page's copy, the docs section, the op's OpenAPI summaries (they render in `/docs/api`), the 404/422 bodies, the closed enums, the llms.txt line, the registry entry for the new page. The Engine-Room constraint on "resolve" holds throughout. Registry fan-out via the fluncle-surfaces checklist for the page; the `get_track` change is not a new surface. `PUBLIC_UNAUTH_OPS` untouched (no new op) but the projection's schema widening runs the full gate set; any new op that does appear also lands in `PUBLIC_OPERATION_IDS` (deploy-build-only gate — the known trap).

## Sequencing

1. **Wave 1 (immediately):** Unit 1 items 1–3 (the trues-ups + the Apple cron leg) + the legacy backfills. Freeze-safe truth work; the Apple leg starts draining 33,853 rows at the sweep's pace.
2. **Wave 2:** the hosted proof pair (MBID index build; dial write load) on a scratch DB → then Unit 1 item 4 + Unit 2 + Unit 3 as one reviewed slice (page + projection + hop + dials + terms + copy), canon-reviewed, merged, watched to green.
3. **Unit 3b** waits on its tested trigger. The dump waits on a consumer. Apple's machine-served links wait on the clause read (attempted during Wave 2).
4. This RFC is deleted on ship; the evidence file stays.

## Acceptance criteria

- Unit 1's columns land with semantics in schema comments, backfills executed, integration tests through real migrations; the Apple cron leg observed completing one real paced batch on the box.
- The envelope's states exhaustively fixtured (every `method`, every `retry` class, `terminal: null` cases, `refused` row-for-row with the shared predicate, ambiguous-vs-duplicate relations, the certified straggler window); the hop 302s and logs; the sameAs test proves no hop URL in identity markup; the app helper preserves instant-open on a real device; dials + prune + tested alert land together; the hosted proofs recorded.
- All copy gates run with canon-reviewer blocking; `/terms`' three edits ship in the same wave as the page — never after.
- Docs: the `/docs` section, llms.txt, the registry entry + fan-out for the page; roadmap trued up; this RFC deleted on ship.

## Risks (unchanged in substance from the panel's rewrite)

- **Spotify remains the structural risk**: the standing bulk exposure is `list_tracks` (already public); this build's delta is the cross-identifier mapping, mitigated by the hop (now everywhere, keyed on Fluncle ids), the dials, the terms duty, and the evidence framing. There is no "legal firewall" in the provenance column — it is provenance, which is reason enough.
- **Deezer's terms bar any commercial benefit** — an exposure that already exists via the recovery rung, independent of this build; posture A keeps it theoretical.
- **Demand may be ~zero** — accepted; the build is small, the trues-ups are durable, and nothing accretes standing cost.

## Appendix

Measured numbers, queries, ToS clauses, and panel verifications: [docs/planning/identity-graph-research.md](./planning/identity-graph-research.md), including the Unit 0 results (2026-07-29). RollDaBeats lives on the roadmap's long tail, not here.
