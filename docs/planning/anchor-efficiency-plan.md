# Anchor efficiency — three legs off the 2026-08-02 bench audit

Non-canonical planning (see AGENTS.md § Docs). Evidence-first plan for three PR-sized changes to the catalogue anchor pipeline, each independently shippable. All numbers below were measured against prod on 2026-08-02; the full forensic narrative lives in the operator's session memory and the run ledger — this doc carries what a builder needs.

## The measured problems

1. **Anchoring is ~100% ISRC-gated in practice.** Across 3,250 rows attempted on 2026-08-02: 0 of 1,701 ISRC-less rows anchored; all 1,302 anchors carried an ISRC. Yet `ANCHOR_ORDER` (`apps/web/src/lib/server/track-work.ts`, the anchor worklist's ordering) sorts by `has_embedding desc, nearest_finding_score desc, track_id desc` — sunk cost, no anchorability term — and **56% of the ~15,400 currently-eligible rows are ISRC-less** dead weight, each still costing a billed Apify search per 14-day re-ask cycle.
2. **Bulk re-arm paths can poison the queue head.** Twice on 2026-08-02, bulk stamp-clears (an operator repair, and #1071's label-scope re-arm, which released ~1,518 embedded+scored rows of which 706 were on their SECOND attempt) put walls of structurally-unanchorable rows at the head of the sunk-cost order, causing a 5-tick total anchor drought (~1,250 rows burned for 1 anchor).
3. **The search gate (`verifySearchCandidate`, the ISRC-free triple gate) silently produces zero for long windows** — zero anchors and zero `anchor_review_json` near-miss reviews for ~10h daily on 07-31/08-01, and continuously past the usual resume hour on 08-02. Leading hypothesis, untested: the gate hard-requires `typeof candidate.durationMs === "number"` (`apps/web/src/lib/server/anchor.ts` near line 242, and `detectVersionMismatch` likewise) while `pickIsrcCandidate` (near line 381) tolerates a missing duration via `?? 0` — so Apify actor payloads that omit `durationMs` (possibly time-of-day-dependent) would zero the search gate and review minting while the ISRC gate runs at full strength. **Instrument before concluding anything.**

## Leg 1 — the `durationMs`-dropped counter (observability only)

In the box sweep (`docs/agents/hermes/scripts/anchor-sweep.ts`) and/or the Worker resolve path — wherever candidates are normalized for the gates — count candidates that arrive without a numeric `durationMs` and surface the count in the tick summary (style precedent: `apifyTargetOmitted`, added the same way). NO behavior change: the gate keeps rejecting them; the counter makes the rejection visible in the run ledger. Name it in the sweep's summary merge (field-wise across pages, like its siblings).

## Leg 2 — ISRC-first `ANCHOR_ORDER`

Lead the anchor worklist's order with `(t.isrc is not null and trim(t.isrc) <> '') desc`, keeping the existing keys behind it. The covering index for the anchor worklist must be widened accordingly (find the index the worklist's EXPLAIN actually uses and extend it — the funnel's `tracks_funnel_scan_idx` was widened the same way in migration 0148). Migration via `bun run --cwd apps/web db:generate`, NEVER handwritten. **Deploy trap, learned twice (migrations 0144 and 0148): a multi-column index rebuild over the populated `tracks` table can exceed the Cloudflare build's patience under live sweep writes.** Note in the PR body that the operator may need to apply the index out-of-band (manual DDL + drizzle bookkeeping row + empty-commit re-trigger) if the Workers Build fails on the migrate step — do not fight it in CI.

## Leg 3 — anchorability filters on every bulk re-arm path

Every path that bulk-clears `spotify_anchor_attempted_at` must exclude rows that cannot benefit: add `and t.isrc is not null and trim(t.isrc) <> ''` (or an equivalent no-prior-attempt guard where re-offering a first look is the intent) to: the label-scope re-arm shipped in #1071 (find its clear statement), `requeueAnchorStamps` / the `requeue_anchor` op (`apps/web/src/lib/server/anchor.ts` near line 1248), and the `set_anchor_apify` flip-ON requeue (#851's machinery). Each gains a test pinning that an ISRC-less row's stamp survives the re-arm. Rationale: with Leg 2 the head no longer inverts, but re-arming dead weight still re-bills Apify for asks that cannot conclude.

## Shared rails

- Full verification battery: `bun run --cwd apps/web test` (vitest — never bare `bun test`), typecheck, build; root `bun run check`; the box sweep tests (`bun run test:scripts`) where the sweep changes; integration tests execute real SQL via the `createIntegrationDb` pattern for worklist/order changes.
- No public copy changes expected anywhere; `/admin` strings are operator-tier.
- Hosted-Turso laws apply to any new query shape (see AGENTS.md § Database); the uncorrelated-`not in` precedent for label subqueries is in `ANCHOR_RULED_OUT_LABEL_CLAUSE` (#1080).
- Box-side sweep changes ride the pin-watch rebake automatically (it rebuilds on baked-content drift).
