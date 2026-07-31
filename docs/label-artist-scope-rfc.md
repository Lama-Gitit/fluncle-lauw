# RFC: Label artist scope — per-label artist rules on the catalogue crawler's storage gate

**Status:** Final (4 research threads → taste pass → 4-role adversarial panel — staff engineer, data correctness, MusicBrainz domain, product/operator — synthesized 2026-07-31) — completeness standard applied.
**For:** a build session (or small team of agents) executing against this repo.
**Canon/authority:** docs/catalogue-crawler.md, docs/label-entity.md, docs/artist-relationship.md, docs/the-ear.md, docs/admin-shell.md, docs/naming-conventions.md, and the codebase. This document is planning, not spec; where it deviates from canon, canon wins.

> Process note: every load-bearing claim below was either verified live against MusicBrainz (census payloads preserved; appendix) or read from source by at least two independent reviewers. The panel falsified several claims in the draft; the corrections are baked in, and the appendix lists what was overturned so the reasoning is auditable.

## The standard (definition of done)

Nothing here is optional. The delivery is: the re-arm unit, the schema + migration, the crawler gate + counters, the contracts + CLI, the admin dialog + board surfacing, the triage-skill upgrade, the doc/canon fan-out (six surfaces, §11), and the tests named in §12 — shipped in the §10 order, each PR complete with its tests and docs, with the Gutterfunk pilot applied end-to-end as the acceptance proof. The staged items in §9 are gated on named dependencies (a customer census, a persisted-credit enabler), not on convenience.

## 0. Summary / the reframe

- **The scope is an in-memory filter on data the crawler already holds and discards.** `expandRelease` builds per-track MB artist MBIDs (`creditMbids`, crawl.ts:1283–1288) from its one existing MusicBrainz request and throws them away after edge-linking. The overlay consumes them at the existing storage gate (crawl.ts:1312). Zero new HTTP, zero hot-path SQL — the rule set rides the same per-tick memo as `enabledLabelFolds`.
- **v1 ships blocklist mode only.** Measured on the pilot: blocklisting one act keeps 124/130 recordings _including future signings_. Blocklist fails open (an error over-stores; prune fixes it); allowlist fails closed (an error silently loses music — the triage skill's own named worst case) and has **no proven customer yet**: every allowlist argument in the draft derived from the single label that wants blocklist, and the census shows a real allowlist needs collaboration-entity expansion (DJ Die's catalogue is 44/130 alone, 57/130 with DieMantle — the "dominant few artists" are many MBIDs). Allowlist is a staged v2 unit with named gates (§9).
- **Quantifier, measured:** a blocklist **drops a track iff its FIRST credited MBID is blocked** — zero collateral on guest features (`Nuff Pedals feat. Maddslinky` ×2 kept), zero leak on off-lane records (all `Jus Now` tracks dropped). Block-ANY drops 9 (collateral); block-ALL drops 3 (leaks 4 of 6 Jus Now tracks). Credit order is preserved end-to-end today; a test pins it.
- **Match on the MusicBrainz artist MBID, never on names or `artists.id`** — one act is credited under two names on one label (`DJ Die` ×31 / `Die` ×15, same MBID); two different acts share the name "Sure Thing" on the same label. And **identify labels by `mb_label_id`, never by name-fold**: two enabled labels can fold identically (the namesake class the merge/alias machinery exists for), and a fold-keyed rules map is last-write-wins — one operator's scope silently governing a label he never ruled.
- **Forward-only, and now atomic.** Scope changes what the next crawl writes; it never deletes, hides, or filters stored rows. Mode + rules are one transactional write on `update_label` — the invalid states (allowlist with zero rules; a mode switch racing its rule set) are unrepresentable, not policed by call-ordering conventions.
- **The re-arm is a watermark, not a browse.** A scope/enable write stamps `labels.scope_changed_at` and nothing else. The crawl tick — the only process allowed to spend the shared 1 req/s MusicBrainz budget — revives the label's already-walked release nodes through the browse it performs anyway. Termination is by watermark comparison; there is no second HTTP path and no operator-request-deadline hazard.
- **Check MusicBrainz for an existing sub-imprint before scoping — and the check is automatable.** Med School is its own MB Imprint entity (168 releases) with a machine-readable `label ownership` edge to Hospital; 3 Beat Breaks likewise. The triage pass queries `?inc=label-rels` and refuses to propose a scope when an imprint child already covers the boundary. The overlay is for Gutterfunk-shaped labels: one logo, one Discogs entry, one catalogue, genuinely mixed output — where an MB split would be a wrong edit.

## 1. Context & goals

The storage gate is label-level: one `seed_state` stores or skips a label's whole catalogue. Triage rounds keep stranding mixed-genre labels in `unclear` — Gutterfunk (DJ Die's imprint: mostly DnB, some dub/soul/soca), YUKU, Crucast, Echowide, Sneaker Social Club, Candy Mountain, Nice Up Records. The operator ruled (2026-07-31): per-label artist scoping, Gutterfunk pilot.

Honest calibration:

- **In reach:** exact track-level scoped storage; triage proposing scoped enables with per-rule evidence; an admin surface; the pilot.
- **In reach with stated limits:** back-catalogue capture after a scoped enable. The constraint is **not** the MusicBrainz request rate (900 fetches ≈ 17 min of wall clock at the 1.1 s floor) — it is the crawl tick's release half-batch × cadence: `FLUNCLE_CRAWL_NODES=30` deployed, `pickNodes` reserves `ceil(limit/2)` = 15 release slots/tick, ~5.6 ticks/h → **≈84 release expansions/h upper bound**, in contention with the pending frontier. Hospital-scale (1,019 releases) ⇒ ≥12 h. Stated on the board (§7), not hidden.
- **Sparse upstream, not absent:** MB _does_ carry recording-level remixer relations, free in the crawler's existing request by extending its `inc` string (+2.8 % payload, zero extra HTTP) — but coverage on the pilot label is ~4.5 % of track rows. v1 does not scope on remixers; §9 stages the remixer-override refinement with the data path already named.

## 2. Data model

### 2.1 `labels` columns

- **`scope_mode`** — nullable text, app-level enum (`blocklist` in v1; the column accepts `allowlist` for v2 without migration). **NULL = open** (today's behaviour). No DDL default (avoids the populated-table rebuild hazard; verified: generates a bare `ALTER TABLE labels ADD scope_mode text;`).
- **`scope_changed_at`** — nullable text. The re-arm watermark **and** the scope ruling's own clock. Stamped on every scope write. `ruled_at` is **never** touched by a scope-only write — it is the seed-ruling's provenance, load-bearing in `mergeLabel` precedence and the D7 bootstrap exemption; one column cannot arbitrate two independent rulings.

Scoped ⇔ `seed_state = 'enabled' AND scope_mode IS NOT NULL`. **No fourth seed_state** — every reader keyed on the literal `'enabled'` (gate memo, seed re-arm crawl.ts:591, capture ladder, tap worklist, the one partial index `labels_label_releases_queue_idx`) stays untouched. A `disabled`/`undecided` label may carry a mode+rules harmlessly (seed gate runs first), which lets triage stage a scope alongside an enable in one ratification.

### 2.2 `label_artist_rules`

| column                                           | type          | notes                                                                                    |
| ------------------------------------------------ | ------------- | ---------------------------------------------------------------------------------------- |
| `id`                                             | text PK       | `lar_…`                                                                                  |
| `label_id`                                       | text notNull  | no FK/cascade (matches `tracks.label_id`)                                                |
| `artist_mbid`                                    | text notNull  | **the match key**, from the MB payload                                                   |
| `artist_name`                                    | text notNull  | credited spelling at ruling time (display; never matched)                                |
| `resolved_mbid` / `resolved_name` / `checked_at` | text nullable | drift audit, written by the triage re-audit sweep (§8), never by a dialog-render MB call |
| `source`                                         | text notNull  | `operator \| triage`                                                                     |
| `created_at`, `updated_at`                       | text notNull  |                                                                                          |

One index: `uniqueIndex("label_artist_rules_label_mbid_idx").on(labelId, artistMbid)` — it also serves the `label_id` prefix seek, so no second index. Plain ASC. Migration `0145_*` via `db:generate`; `oxfmt` the whole output incl. `meta/*.json`; the diff must contain only the two ALTERs + CREATE TABLE + its index (any index churn = snapshot drift, a separate fix).

Rejected (recorded so they are not relitigated): artist-level seed state (global; can't express per-label; row may not exist; collides with the capture ladder's `qualifiedArtists` _spend_ set); JSON column (the label entity's own no-denormalization precedent, schema.ts:3671); keying on `artists.id` (inherits conflated/duplicate rows; hot-path translation join; chicken-and-egg).

### 2.3 Merge behaviour (specified, not sketched)

- **409 `merge_scope_conflict` whenever both `scope_mode` are non-null and differ** — regardless of `ruled_at` (which stamps seed rulings, not scopes). `LabelScopeConflictError` clones the existing 409 plumbing (orpc/admin-labels.ts:108).
- **Rule sets never union across a merge.** A naive repoint collides on the unique index; `update or ignore` + delete (the alias recipe) silently _unions_, and a union across modes inverts meaning ("only these" becomes "ban these"). Instead: the survivor keeps its own set; the loser's rows are dropped in the batch (`delete from label_artist_rules where label_id = <loser>`), reported as `droppedRules: N` on `MergeLabelResult` so the operator re-authors deliberately.
- Mechanics the builder needs: `LabelMergeRow` + `getLabelMergeRow`'s select list gain `scope_mode`/`scope_changed_at`; the reconcile UPDATE (statement 5) carries them; the rules delete joins the existing `db.batch(_, "write")`. Orphan rule: the only production `delete from labels` is mergeLabel's statement 0 (verified), so the batch's delete is the complete story; the prune skill's label deletes gain the same companion delete.

## 3. The crawler

### 3.1 The gate (per-track filter, MBID-first identity)

The memo becomes two maps, built once per pass alongside `listLabels("enabled")` (which picks up `scope_mode` for free once `LABEL_COLUMNS`/`LabelRow`/`toLabelItem` gain it) plus one bounded read of `label_artist_rules` for enabled labels:

```ts
scopeByMbid: Map<mbLabelId, ScopeEntry>; // exact — labels.mb_label_id is UNIQUE
scopeByFold: Map<labelFold, ScopeEntry | "ambiguous">; // fallback for MBID-less labels
```

Lookup order mirrors `linkTracksToLabel`: the release's `mbLabelId` (in hand at crawl.ts:1220) first, fold fallback second. **Fold-collision rule:** if all colliders are unscoped → `{ mode: null }` (today's behaviour, zero regression); if any collider is scoped → treat as unscoped-open for storage **but** log `crawl.scope-ambiguous` — never apply a scope the operator didn't attribute to that entity. (The draft's claim that fold-keying "agrees on aliased spellings" was false — the gate has a known alias blind spot today, out of scope here but noted in §13.)

Filter, inside the existing enabled-label block:

- `mode === null` → keep all.
- `mode === "blocklist"` → drop a candidate iff its **first non-null** `creditMbids` entry is in the set; keep otherwise — including candidates with no usable credit identity (blocklist is conservative about dropping, so the dead-in-practice degraded path fails **open**; verified: 0 of 133 pilot rows lack recording credits).

Exact `ensureAlbum` form (one resolve, never two — the resolved id is also the layer-2 dedupe key):

```ts
const kept = applyScope(candidates, scope);
const albumId = kept.length > 0 ? ((await ensureAlbum(...)) ?? null) : null;
```

`writeCatalogueTracks(kept, albumId)`; the artist-entity link map is rebuilt **from `kept`** (it is built from `candidates` today — the one downstream line that does not follow automatically); `linkTracksToLabel` / `linkTracksToAlbumId` / `stampRemixerRoles` (lives in artists.ts:1011) key off `writtenIds` and follow.

**Unfiltered on purpose (stated so nobody "tightens" them):** the artist-hop discovery leg (crawl.ts:1372–1390) walks every credit — scope bounds storage, never discovery; `rearmSeedLabels`' `seed_state='enabled'` guard keeps scoped labels re-arming.

Dedupe caveat, pinned in a test: layer 2 (`existingAlbumTitleFolds`) is an album-scoped title fold, so a widening re-walk stores "the newly permitted rows _except_ same-album title-fold twins" — correct Apple-twin behaviour, now stated.

### 3.2 Pass outcome recording

`expandRelease` writes a compact debug string into `crawl_frontier.note` at settle (`stored=N skipped_held=N skipped_scope=N`) — **a human forensic aid, not a queryable index** (the column is unindexed over a ~90k-row table; nothing may build behavior on scanning it). The re-arm needs no refused-set query — termination is the watermark (§3.3).

### 3.3 The re-arm (watermark + existing walk; no second HTTP path)

**Why:** nothing re-expands a `done` release node — `enqueue` is `on conflict (id) do nothing`, the forward browse has no early-stop but cannot revive nodes, and the tail re-arm early-stops on zero-new (pinned at crawl.integration.test.ts:1369). So enabling a label whose releases were already visited under other seeds' subtrees silently loses them **today, overlay or not**. There is no test for enable-after-walk; that absence is why the gap survived. This unit ships first and fixes it for plain enables and scoped enables alike.

**Design:**

1. Any write that enables a label or changes its scope stamps `labels.scope_changed_at` (the enable path stamps it too). **The write does nothing else** — no browse in the Worker request path (the MB client's rate gate is per-isolate; browsing from a PATCH handler doubles the real request rate against a service that 503-throttled Fluncle's IP once already, and a 5,000-release browse blows the request deadline).
2. In the crawl tick, `rearmScopedLabelReleases(): Promise<number>` runs as a sibling of `rearmSeedLabels()` (called from `crawlCatalogue` next to crawl.ts:1450, reported as `CrawlPass.releasesRearmed`): select enabled labels `where scope_changed_at is not null` whose MB **label node** is `done` with `done_at < scope_changed_at`, flip those label nodes to `pending, cursor=0` (bounded like `REARM_BATCH`).
3. `enqueueReleaseNodes` gains a re-arm mode, active only while expanding such a label node:

```sql
on conflict (id) do update
  set state = 'pending', cursor = 0, hop = 0, label_slug = excluded.label_slug, updated_at = excluded.updated_at
  where crawl_frontier.state = 'done' and crawl_frontier.done_at < :scopeChangedAt
```

- **Terminates by construction:** re-expansion settles `done_at` past the watermark.
- **`hop = 0` and `label_slug` repoint are required:** a release previously reached at hop 2 under another seed would otherwise queue behind every pending hop-0/1 node indefinitely (`pickNodes` orders `hop asc …`). `created_at` is deliberately untouched (old nodes sort early within the hop).
- **Status filter, client-side:** drop `Bootleg` and `Pseudo-Release`, keep `Official`/`Promotion`/**status-absent** (7 of Gutterfunk's 37 lack status and are real records; `&status=official` on the browse would wrongly drop them).
- **Gating:** the `do update` arm is active only in re-arm mode, so `enqueue`'s `rowsAffected` semantics — and the tail-early-stop test — are unchanged on every other path. Both get pinned tests (§12).
- Co-released edge (first `label-info` entry belongs to another label): the walk's gate refuses it and it counts into `skipped_label` — noted, harmless.
- `skipped`/`failed`/abandoned nodes are **not** touched: `skipped` = no MB release; `failed` is owned by its own exponential backoff (the `rearmSeedLabels` doctrine, crawl.ts:559); abandoned stays abandoned.

Narrowing fires nothing (a narrowing re-walk is a guaranteed no-op — nothing deletes); the server stamps the watermark **only on enable or widening** (mode set, rule removed from a blocklist), computable from the write's diff.

### 3.4 Counters (wire-compatible)

`tracksSkipped` **stays, as the sum** — it is on the wire in the contract, the pinned box CLI, and the baked crawl-sweep script; silently repurposing it makes the box report garbage until the pin moves. Three **additive** fields: `tracksSkippedHeld` / `tracksSkippedLabelGate` / `tracksSkippedArtistScope`, through the pass summary, cron JSON, and ledger.

### 3.5 The freshness tap

Scoped labels are excluded from the tap worklist: `where seed_state = 'enabled' and scope_mode is null` — **in the SQL**, not the TS refine (or `WORKLIST_OVERSCAN` is consumed by scoped labels and unscoped ones starve). The predicate implies the existing partial index's condition, so `labels_label_releases_queue_idx` still serves it with a residual filter — **no new index** (a builder adding one has misread this). Verified single entry point (`listProbeLabels` → `probeLabelReleases` → `backfill_label_releases`; no per-label targeting). Priced honestly: a scoped label's new releases arrive only via the MB re-walk — scoping a Spotify-forward label makes it the least fresh label in the archive, and a release Spotify has but MB lacks never lands. That cost lands on exactly the mixed modern labels this feature serves; the operator accepts it per scoped label knowingly (it is in the dialog copy, §7).

## 4. Matching semantics — the measured ground (corrected numbers)

Census: Gutterfunk `c7a4f6d6-af59-4376-9d77-722c14e392fb` — 37 releases, 133 track rows, 130 recordings, **50 distinct credited artist MBIDs** (51 name strings). Corrections from the panel's re-measurement: block-ANY drops 9 (collateral incl. **two** Nuff Pedals × Maddslinky tracks); block-ALL drops 3 and leaks **4 of 6** Jus Now tracks (two are solo-credited); block-FIRST drops 7 with zero collateral/zero leak. `Maddslinky` never appears as a first credit — a blocklist rule on it is **inert**, which is why per-rule census counts are mandatory at ratification (§8).

**Pilot ruling, corrected by its own census:** blocklist **{ Jus Now }** — keeps 124/130, drops all six soca tracks. Crystal Waters is deliberately **not** blocked: both "Gypsy Woman" pressings are the _DieMantle RaveYard mix_ — a genuine label-boss DnB record credited solely to Crystal Waters (the remixer exists only as a recording-level `remixer` relation). Blocking her would drop it — the original-of-remix class inverted. The remixer-override refinement that would make blocking her safe is staged (§9.3) with its data path verified.

The MB-alternative decision rule (goes into docs/label-entity.md): prefer an existing MB entity when the boundary is a **product line** — a sub-imprint with its own identity that MB models (`3 Beat Breaks`; **Med School**: own Imprint entity, 168 releases, machine-readable `label ownership` edge to Hospital — and Fluncle already carries both as separate enabled rows). The triage pass automates the check (§8). Use the overlay when the label is one imprint with mixed output (Gutterfunk: no type, no label-rels, one Discogs entry). Never reach for a ℗-holder entity as a _mechanism_ — ownership ≠ genre; use it when it happens to coincide (the shipped `3Beat Productions Limited` precedent).

## 5. Contracts & API

- **`update_label`** (PATCH `/admin/labels/{id}`, operator — already `.use(adminAuth).use(operatorGuard)`): input becomes

  ```ts
  { id, seedState?: LabelSeedState, scope?: { mode: "blocklist", rules: Array<{ artistMbid, artistName }> } | null }
  ```

  with an at-least-one refine. **Mode + rules write atomically in one `db.batch(_, "write")`** — the store-nothing window, the ordering ritual, and the mode/rules race are unrepresentable. Validation: `scope.rules` non-empty when `scope` is non-null (`409 scope_without_rules`); `scope: null` clears the mode and **retains rule rows inert** (cheap undo; a later re-scope reuses them). Semantics per field: `seed_state = coalesce(:seedState, seed_state)`; `ruled_at` stamped **only** when `seedState` present; `scope_changed_at` stamped only on enable/widening (§3.3). `LabelAdminItemSchema` gains `scopeMode` + `scopeRuleCount` additive-optional (the ratified compatibility pattern) — required for the triage pilot's round-trip check.

- **`list_label_artist_rules`** (GET `/admin/labels/{id}/artists`, admin tier) — the read for board, dialog, and scripts. Same `{id}` key space as `update_label` (one flow, one key; the slug-keyed newer ops are a separate lineage).
- Both ops: entries in `ADMIN_ROUTE_OPS` + `EXPECTED_TIERS`; `verb_noun` passes with no verb-set edit (`list` approved; no `rearm` op exists — the re-arm has **no HTTP surface**, it's the watermark + crawl tick).
- The dialog's artist typeahead is a **`createServerFn`**, not an oRPC op (page-local admin read behind `isAdminRequest()`, the artists.tsx debounced-search precedent), returning `{ id, name, mbid, trackCount }` limit 20 — stated here so PR 4 doesn't discover the coverage gate late.
- No MCP entry, no `PUBLIC_OPERATION_IDS`, no registry change.

## 6. CLI

- `fluncle admin labels update <slug> [--seed-state <state>] [--scope open|blocklist] [--artists-file <json>] [--rewalk]` — one command, one op. `--scope blocklist` requires `--artists-file`; `open` clears mode (rules retained); `--rewalk` stamps the watermark without changing the scope (the operator's manual re-walk lever). All value-taking flags join `stringOptions` (build-gated; the cli.test.ts:991 invariant fails otherwise). The `--artists a,b,c` inline form is cut — 36-char UUIDs by hand serve nobody.
- `fluncle admin labels artists <slug>` — read the rule set (drift columns included).
- Success copy gains a scoped arm in the operator register ("Takes everything except N artists from it." — see §7 copy).

## 7. Admin surface (`/admin/labels`)

- **Entry:** "Scope it…" in the row `⋮` (scoping never competes with the two ruling buttons — the placement contract). Dialog copied from the `ManageLinksDialog` **pattern** (route-local in artists.tsx, not a shared component).
- **Dialog:** the rule chips (name + MBID + drift marker when `resolved_mbid` differs); the typeahead + paste-an-MBID field; **one plain sentence** rendered from the live rule — copy per the panel's Flat-Copy correction: **"Take everything except these 2 artists from it."** (never "seed only…" — _seed_ is this page's label-level verb); one clause on the boundary: _"A scope narrows which artists the next crawl takes from it. Everything already here stays."_; one clause on the tap trade-off (§3.5). **No live MB call and no match count in the dialog** — the DB cannot answer "what would this rule admit" (credit MBIDs aren't persisted; most crawled rows have no artist edges), and a near-zero count at ruling time is worse than none. The census lives at ratification (§8), where the MB payload is present.
- **Board:** a quiet mode-distinct chip — `Except 3 artists` — beside `SeedStateChip` (never one label for two modes' opposite meanings; no loud states — the empty-scope state is a 409, unreachable). While a re-walk is in flight, the row's identity line carries a transient `· N releases queued` from **one grouped bounded read** of `crawl_frontier` (`label_slug` now repointed by the re-arm, so the group-by is honest) for the visible page's scoped rows — the operator's answer to "is it working?" on the page where he acted. The scoped-section intro carries the one-line count of scoped labels (the "which of my labels are scoped" view).
- Route gains `validateSearch` for `?label=<slug>`; the producer of that link is the triage ratification page (each scoped proposal deep-links its label).
- Mutations invalidate `LABELS_KEY`; inline `role="alert"` errors; no toasts; the react-query/loader conventions of the exemplar hold.
- **Smokes:** shell-smoke stays green (dialog queries must not throw on mount); add `/admin/labels` to `admin-touch-smoke` `SURFACES` (verified absent today); fixture updates ship in the same PR as the UI change.
- **No new attention source** (the label-alias precedent: crawl-volume review is a page section, not a queue row). Scoped-label maintenance is the triage re-audit (§8) — which now actually exists in the apply script.

## 8. The triage skill

- **Verdict schema:** `dnb` rows gain optional `scope: { mode: "blocklist", artists: [{ name, mbid, evidence, firstCreditCount }] }`. Hard rules in the brief: MB entity **conflation stays `unclear`** (a scope is never the dumping ground for an entity problem); an **imprint-child check** runs first (`/label/<mbid>?inc=label-rels` — an existing imprint/`label ownership` child covering the boundary means "enable the child", not a scope; the Med School shape, automated); a blocklist entry with **zero first-credits on the census is rejected as inert** (the Maddslinky lesson). The share test replaces the draft's arbitrary ~8-artist cap: propose blocklist when the excluded artists' first-credit share is ≤ Y% (default 15) of recordings; otherwise `unclear` (allowlist proposals return in v2 with their own share test).
- **The census is costed and gated:** phase 1 stays the cheap 25-release release-credit classify; only mixed-verdict labels get a phase-2 census (`?inc=artist-credits+recordings`, ≤100/page, capped pages with the sampling caveat stated in evidence). Census-bearing rounds drop the batch to 5 labels/agent — the budget is stated, not discovered.
- **`pull-undecided.sh`** emits existing scope state; writes `calib-scoped.txt` for the brief.
- **`apply-rulings.py`:** scoped rows write **one** `PATCH` (atomic scope+enable); pilot mode pilots a scoped label and verifies `scopeMode` + `scopeRuleCount` round-trip. A new **`rescope` mode** reads `?seedState=enabled` scoped labels and PATCHes rules-only — the maintenance loop the no-attention-source argument depends on (it did not exist in the draft's pointer). The re-audit also refreshes `checked_at`/`resolved_*` per rule (the drift sweep — catches MB merges by comparing the response `id`; splits are surfaced by first-credit counts going stale).
- **Ratification** leads with scoped proposals: label → mode + N artists, per-artist evidence **and per-rule first-credit count**, would-drop/would-keep census, already-stored rows per scoped-out artist (so ratification and any prune decision are one look). Local HTML with a path, per standing preference.

## 9. Staged (gated, not deferred)

1. **Allowlist mode** — gates: a census of ≥2 real allowlist customers from the waiting list; the would-store preview it structurally requires (see 2); collaboration-entity expansion in the census (DieMantle-class entities). The schema, gate plumbing, counters, and dialog all carry it with one enum value's work.
2. **Persisted credit MBIDs** (`track_artist_mbids (track_id, position, artist_mbid)`) — the single enabler that makes three things exact at once: a truthful dialog match count, capture-ladder integration (Decision 2), and precise historical audits. Written by `expandRelease` from data already in hand.
3. **Remixer-override on blocklist** — data path verified (`inc=…+recording-level-rels+artist-rels`, +2.8 % payload, zero HTTP): a first-credit-blocked track carrying a `remixer` rel to a non-blocked artist is kept. Unblocks blocking Crystal Waters without losing the DieMantle mix. Gate: decide the exact predicate after v1 ships and the counters show how often the class occurs.

## 10. Sequencing

1. **PR 1 — the re-arm unit:** `scope_changed_at` (columns only), the enable-path stamp, `rearmScopedLabelReleases` in the crawl tick, the `enqueueReleaseNodes` re-arm mode, `--rewalk`, and the enable-after-walk test that does not exist today. Standalone value; live from day one; the riskiest component shipped smallest.
2. **PR 2 — schema + gate:** `scope_mode`, `label_artist_rules`, the memo maps, the filter, counters (§3.4), gate-outcome note, tap exclusion. Inert until a mode exists (tests seed modes by direct insert; the write path is PR 3).
3. **PR 3 — contracts + CLI:** the atomic `update_label`, `list_label_artist_rules`, merge behaviour, CLI flags.
4. **PR 4 — admin:** dialog, chips, queued-count read, validateSearch, smokes.
5. **PR 5 — triage skill** (repo-only; `skills:install`).
6. **PR 6 — the pilot (operator-gated production act):** scope Gutterfunk `blocklist { Jus Now }` + enable; the re-walk fires (~10–12 h at the measured ceiling); verify 124/130 recordings, counters, board. Note: Gutterfunk has **no `labels` row in the seeded dev DB** — the pilot runs against prod after a crawl mints it, or the row is seeded. Abort path: `--scope open` + let the frontier drain. Pre-existing off-lane rows on the label are checked and, if present, pruned via fluncle-catalogue-prune as part of pilot acceptance (scope is forward-only; the pilot must not leave the operator asking "why is the soca still here").

## 11. Doc/canon fan-out (six surfaces, one restatement)

The doctrine drift is real (schema.ts:3428 "never storage" vs crawl.ts:1150 "gates STORAGE") and the draft's fix was wrong — `seed_state` also drives capture spend and the tap, so "governs what the next crawl writes" would create fresh drift with the-ear.md's ratified acquisition framing. The restatement, everywhere it lands:

> _A ruling and a scope govern what Fluncle **acquires** next — what the crawler seeds from, what it stores, and what audio gets bought. Neither ever changes what is already stored._

Surfaces: docs/label-entity.md (scope section + MB-alternative rule + restatement) · docs/catalogue-crawler.md (gate, counters, re-arm; also fix its "two layers" — the code implements three) · docs/the-ear.md (per Decision 2) · docs/admin-shell.md (the verbatim "crawl scope, never storage" line + the Labels placement row) · labels.tsx's header comment + on-page paragraph · fluncle-catalogue-prune's SKILL.md (named as the retroactive remedy).

## 12. Acceptance criteria

Named tests (the load-bearing set):

- `crawl.integration.test.ts` @ the :620 describe — `"stores a previously gate-refused release once its label is ENABLED — the back-catalogue re-arm"` (drain → enable → re-arm → drain; **not** a fresh-DB cold walk, which is why the gap has no test today); `"a second re-arm pass is a no-op — the watermark terminates it"`; `"the re-arm resets hop and label_slug so revived nodes are picked"`; `"a re-arm skips Bootleg and keeps status-absent releases"`; `"the tail re-arm still stops in one tick when nothing is new"` (guards the enqueue-mode gating); `"two enabled labels that fold together never share a scope"`; `"a blocklist drops on the FIRST credit and keeps the guest feature"`; `"a blocklist keeps a candidate whose credits carry no MBID"`; `"a fully-filtered release mints no albums row"`; `"the artist-hop leg still enqueues from filtered-out credits"`; `"a widening re-walk stores only newly permitted rows (album-title twins excepted)"`; credit-order stability.
- `labels.test.ts`: merge 409 on differing modes; loser rules dropped + `droppedRules` reported; scope-only write leaves `ruled_at` untouched; restale fires only with `seedState` present.
- Contract gates: orpc-naming / orpc-admin-coverage / orpc-auth-coverage; `cli.test.ts` stringOptions; full `apps/cli` run.
- Board/dialog: shell + touch + queue smokes green via `smoke:routine`.
- Docs: all six §11 surfaces; `skills:install` run.
- Pilot: §10.6 verified end-to-end, counters visible, no soca stored post-re-walk, pre-existing off-lane rows pruned.

## Decisions needed BEFORE handoff

1. **Blocklist-only v1** — confirm (the panel's case: no proven allowlist customer; fail-open safety; Gutterfunk needs exactly this). Rejecting it reopens §9.1's gates now.
2. **Scope × capture spend.** Enabling scoped Gutterfunk makes its stored rows capture-authorized at the seed-label tier — including any already-stored off-scope rows — and the capture ladder keys on `artists.id`/label, so an exact scope veto is structurally unreachable until credit MBIDs are persisted (§9.2). Recommended v1 ruling: **scope is storage-only; capture untouched; the pilot prunes pre-existing off-scope rows so there is nothing mis-authorized to buy** — stated in the-ear.md; revisit as a veto when §9.2 lands. The alternative (best-effort `artists.mbid` join veto now) buys partial coverage at the cost of a false sense of exactness.
3. **Re-arm trigger** — automatic in the crawl tick on enable/widening + `--rewalk` manual (recommended); or manual-only.
4. **Blocklist share threshold Y** for triage proposals (default 15 % of recordings by first credit).
5. **The global artist verdict** (off-lane-everywhere acts) — park until Decision 2's revisit, since it is the same question as capture authorization wearing a different hat; the park is safe once 2 is ruled.

## Risks & open questions

- Frontier contention: a big re-walk competes for the 15 release slots/tick; visible via `releasesRearmed` + the ledger; bounded by the watermark batches.
- MB entity drift (merges silent-but-benign via response-id comparison; **splits** silently stop matching — surfaced only by the re-audit's first-credit counts; stated, accepted for v1).
- Operator model: one mode in v1 keeps the mental object simple; the chip + sentence carry the meaning; the dialog states the two boundaries (forward-only; tap trade-off).
- The alias blind spot on the gate (a confirmed alias spelled differently by MB is gate-refused today) predates this RFC — noted in §3.1, not widened by it, and worth its own small fix later.

## Appendix — verifications & sources

**Panel-verified live (2026-07-31):** Gutterfunk census 37/133/130/50 (payloads in the session scratchpad: `gf_browse_rec.json`, `gf_rels.json`, `census.tsv`); VA-comp credits (`729b130c`); block-quantifier tables re-measured (ANY 9 / ALL 3-with-4-leaks / FIRST 7); Maddslinky first-credit count = 0; `Gypsy Woman (DieMantle RaveYard mix)` credited solely to Crystal Waters with a recording-level `remixer` rel to DieMantle (falsifying the draft's "no remixer data upstream" and its pilot list); remixer-rels payload cost +2.8 %; browse status behaviour (`&status=official` drops status-absent releases); Med School = MB Imprint `a44a51ea` with a `label ownership` edge to Hospital, both already enabled Fluncle rows; Hospital = 1,019 MB releases; 70-MBID drift probe (0 merges observed); deployed crawl budget `FLUNCLE_CRAWL_NODES=30`, release half-batch 15, cadence ~10.75 min.
**Panel-verified in source:** every crawl.ts/labels.ts/schema.ts line cited above re-checked by two reviewers; mergeLabel's 8-statement batch; `settle`'s unconditional `done_at`; the per-isolate MB rate gate and its 2026-07-19 incident note; `LabelMergeRow`; the one partial `'enabled'` index; `orpc-naming`'s verb list (`replace` in, `rearm` absent — moot, no such op ships); `/admin/labels` absent from touch-smoke `SURFACES`; migration shape vs `0141`/`0144` precedents.
**Overturned from the draft by the panel (kept for the record):** remixer data "structurally out of reach" (false — sparse); the Crystal Waters pilot entry (inverted a genuine record); the fold-keyed memo (namesake-unsound); the browse-in-the-write re-arm (rate-gate violation, no termination); the "~15 h from MB budget" arithmetic (wrong constraint, wrong node budget); "two partial indexes" (one); the split write ordering (superseded by atomicity); the DB-side dialog count (structurally near-empty); 52 artists (50); the doctrine restatement's axis (writes → acquisition).
**External:** MusicBrainz Style/Artist_Credits · How_to_Identify_Labels · Label/Type · label-label relationship types (all July 2026).
