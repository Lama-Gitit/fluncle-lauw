# RFC: Artist rules — allow/block exceptions to the label gate, global and per-label

**Status:** Final v2 (4 research threads → taste pass → 4-role adversarial panel → operator interview, 2026-08-02). Every open decision is resolved below; the build is deliberately **not started** — the operator triggers it.
**For:** a build session (or small team of agents) executing against this repo.
**Canon/authority:** docs/catalogue-crawler.md, docs/label-entity.md, docs/artist-relationship.md, docs/the-ear.md, docs/admin-shell.md, docs/naming-conventions.md, and the codebase. Planning, not spec; canon wins on conflict.

> v2 note: the operator interview reshaped v1's design. The label `scope_mode` (allowlist/blocklist modes) is **gone**; in its place is a strictly simpler exception model that also dissolves several of the panel's hazards (the mode-switch inversion, the store-nothing window, the 409 machinery). v1's verified research and panel corrections all still hold and are cited throughout; the appendix records both review rounds.

## The standard (definition of done)

Nothing here is optional. The delivery: the re-arm unit (labels **and** artists), the schema + migration, the crawler gate + counters, the scope-aware freshness tap, the contracts + CLI, the admin surfaces, the triage-skill upgrade, the doc/canon fan-out (§11), and the tests in §12 — shipped in the §10 order, each PR complete with tests and docs, with the pilot (§10.7) and the enabled-label backfill (§10.8) as acceptance proof. §9's staged items are gated on named dependencies, not convenience.

## 0. The model (the reframe)

**`seed_state` is the label-level default. Artist rules are exceptions to it.**

|                                        | label **enabled**                                            | label **disabled / undecided**                              |
| -------------------------------------- | ------------------------------------------------------------ | ----------------------------------------------------------- |
| no matching rule                       | store                                                        | skip                                                        |
| artist **block** (per-label or global) | **skip their records** (Gutterfunk enabled, Jus Now blocked) | — (redundant; inert)                                        |
| artist **allow** (per-label or global) | — (redundant; inert)                                         | **store their records** (Virgin disabled, Dillinja allowed) |

- **One quantifier everywhere: FIRST credit.** A rule fires on a track iff the track's first credited MB artist MBID matches. Measured (Gutterfunk census, 130 recordings): block-FIRST has zero collateral on guest features and zero leak on off-lane records; block-ANY kills genuine label tracks where a blocked act guests; block-ALL leaks off-lane records rescued by one unblocked guest. Allow-FIRST is the mirror: Dillinja _allowed_ imports records **he is billed on**, not every pop record he guests on.
- **Two scopes:** global ("never/always their records, anywhere" — Jus Now / Dillinja) and per-label ("their records on _this_ label" — a genre-crosser's off-genre works on an enabled label). **Precedence: per-label beats global** (the operator's specific act wins); within a scope an artist carries at most one verdict (unique key).
- **Fail-safe by construction, both directions.** A credit with no usable MBID (bare-name, `["Unknown"]`, Various Artists) matches no rule, so the track falls to the label default — never a silent loss, never a silent import. The invalid states v1 policed (empty allowlist storing nothing; mode-switch races) are **unrepresentable**: there are no modes.
- **Match on MB artist MBIDs, never names or `artists.id`** (one act credited two ways ×46 rows; two acts sharing one name on one label; `artists.mbid` nullable/non-unique/occasionally wrong). **Identify labels by `mb_label_id`, never name-fold alone** (namesake folds are last-write-wins in a map — the Radar Records class).
- **Forward-only.** Rules change what the next crawl (and tap) _takes_; nothing already stored is touched. Removal stays with fluncle-catalogue-prune.
- **The gate is still free.** All identities the rules need (`creditMbids` per track, `mbLabelId` per release) are already in memory at the storage gate (crawl.ts:1283–1288, :1220) — zero new HTTP, zero hot-path SQL; rules ride the per-tick memo like `enabledLabelFolds`.
- **Check MB for an existing sub-imprint before ruling artists** — automatable via `?inc=label-rels` (Med School: own Imprint entity, `label ownership` edge to Hospital; 3 Beat Breaks). Artist rules are for boundaries MB cannot model (Gutterfunk: one imprint, mixed output).

### What today's system does (verified, the gap this fills)

An artist's releases on a non-enabled label are _walked_ (the discovery leg runs regardless — crawl.ts:1365) and **permanently refused** at the storage gate; the only bypass is operator certification via publish.ts. The capture ladder's "qualified artist" tier prioritizes buying for _already-stored_ rows and never overrides storage; `record_demand` re-orders the walk, never the gate. Every non-test `tracks` writer enumerated: crawl.ts (gate), label-releases.ts (tap, enabled labels only), publish.ts. So a Dillinja record on Virgin is fetched, inspected, discarded — that is the missing cell the **allow** fills, and Jus Now on Gutterfunk is the cell the **block** fills.

## 1. Context & goals

Triage keeps stranding mixed-genre labels in `unclear`, and the label-level gate cannot express either "this act never" or "this act always". Operator rulings (2026-07-31 → 08-02, interview-ratified): the exception model above; pilot = global-block Jus Now + plain-enable Gutterfunk.

Calibration:

- **In reach:** exact FIRST-credit exception storage both directions; triage proposing per-label rules with evidence; admin + CLI surfaces; the pilot; the enabled-label backfill.
- **In reach with stated limits:** back-catalogue arrival after a rule/enable. The constraint is the crawl tick's release half-batch × cadence (deployed `FLUNCLE_CRAWL_NODES=30`, 15 release slots/tick, ~5.6 ticks/h → ≈84 release expansions/h ceiling), not the MB request rate. Hospital-scale ≥12 h; stated on the board.
- **Sparse upstream, not absent:** MB remixer relations exist in the crawler's request for +2.8 % payload but cover ~4.5 % of pilot rows; v1 does not scope on remixers (§9.3).

## 2. Data model

### 2.1 `artist_rules` (one table, both scopes)

| column                                           | type          | notes                                                                                                                                                                                                                                 |
| ------------------------------------------------ | ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `id`                                             | text PK       | `arl_…`                                                                                                                                                                                                                               |
| `artist_mbid`                                    | text notNull  | **the match key**, from the MB payload                                                                                                                                                                                                |
| `artist_name`                                    | text notNull  | credited spelling at ruling time (display; never matched)                                                                                                                                                                             |
| `artist_spotify_id`                              | text nullable | **the tap bridge** (§3.5): resolved server-side at rule-write from the MB artist's own Spotify url-rel (verified present for Jus Now), falling back to an `artists` row carrying both ids; null = tap-blind rule, surfaced not hidden |
| `verdict`                                        | text notNull  | `allow \| block`                                                                                                                                                                                                                      |
| `label_id`                                       | text nullable | **NULL = global**; else the label the exception is scoped to. No FK/cascade (matches `tracks.label_id`)                                                                                                                               |
| `resolved_mbid` / `resolved_name` / `checked_at` | text nullable | drift audit, written by the triage re-audit sweep (§8) — never by a dialog-render MB call                                                                                                                                             |
| `source`                                         | text notNull  | `operator \| triage`                                                                                                                                                                                                                  |
| `created_at`, `updated_at`                       | text notNull  |                                                                                                                                                                                                                                       |

Indexes (plain ASC; partial-unique because SQLite treats NULLs as distinct):

- `uniqueIndex("artist_rules_label_artist_idx").on(labelId, artistMbid).where(label_id is not null)`
- `uniqueIndex("artist_rules_global_artist_idx").on(artistMbid).where(label_id is null)`
- `index("artist_rules_label_id_idx").on(labelId)` (board reads)

### 2.2 `labels` columns

- **`scope_changed_at`** — nullable text: the label re-arm watermark, stamped on enable and on any per-label rule change for the label. (`ruled_at` is never touched by rule writes — it is the seed-ruling's provenance, load-bearing in merge precedence and the D7 bootstrap.)

### 2.3 `artists` columns

- **`rearm_requested_at`** — nullable text on… **no**: allow re-arms key on the _rule_, not an `artists` row (the row may not exist). The artist re-arm watermark lives on the rule row: **`artist_rules.rearmed_at`** (nullable text; null = the crawl tick owes this allow a back-catalogue walk). Global and per-label allows both use it.

Migration `0146_*` (0145 was consumed by nothing — verify journal at build time) via `db:generate`; nullable columns, no DDL defaults (no populated-table rebuild); `oxfmt` whole output incl. `meta/*.json`; the diff must be exactly the ALTERs + CREATE TABLE + its indexes.

Rejected (recorded): label `scope_mode` (v1 — superseded by the exception model; its whole hazard class evaporates); artist-level seed_state on `artists` (row may not exist; collides with the capture ladder's _spend_ set); JSON columns (the label entity's ratified precedent, schema.ts:3671); keying rules on `artists.id` (conflated/duplicate rows; hot-path join; chicken-and-egg).

### 2.4 Merge behaviour

`mergeLabel`: per-label rules **never union** across a merge (a naive repoint collides on the partial-unique index; an `or ignore` union can invert operator intent). The survivor keeps its rules; the loser's per-label rules are deleted in the batch, reported `droppedRules: N` on `MergeLabelResult` for deliberate re-authoring. Global rules are untouched by label merges. `LabelMergeRow`/`getLabelMergeRow` + the reconcile UPDATE gain `scope_changed_at`. The prune skill's label deletes gain the companion rules delete.

## 3. The crawler

### 3.1 The gate

Per-tick memo (built with `listLabels("enabled")` + one bounded `artist_rules` read; cleared at crawl.ts:1417):

```ts
labelByMbid:  Map<mbLabelId, { labelId, enabled: boolean }>   // exact identity
labelByFold:  Map<labelFold, { labelId, enabled } | "ambiguous">  // fallback; ambiguous → label default only, log crawl.scope-ambiguous
globalAllow / globalBlock: Set<mbid>
labelAllow / labelBlock: Map<labelId, Set<mbid>>
```

Decision per candidate track (first non-null entry of `creditMbids` = `first`):

```
verdict(first, labelId):
  per-label rule for (labelId, first)  → its verdict        // specific wins
  global rule for first                → its verdict
  none                                 → label default (enabled ⇒ store, else skip)
```

- `first === null` (no usable identity) → label default. Fail-safe both directions.
- Exact `ensureAlbum` form (one resolve; the id is also the layer-2 dedupe key): `const kept = applyRules(candidates, …); const albumId = kept.length > 0 ? ((await ensureAlbum(...)) ?? null) : null;` — a fully-excluded release mints no album row. **New in v2:** the gate now runs for _non-enabled_ labels too when an allow could match — the enabled-only short-circuit at crawl.ts:1312 becomes the `verdict` call; a non-enabled release with no allow hits is the same no-op it is today.
- The artist-entity link map is rebuilt from `kept` (it is built from `candidates` today); `linkTracksToLabel` / `linkTracksToAlbumId` / `stampRemixerRoles` (artists.ts:1011) key off `writtenIds` and follow.
- **Unfiltered on purpose:** the artist-hop discovery leg walks every credit (rules bound storage, never discovery); `rearmSeedLabels`' enabled-guard is untouched.
- Album dedupe caveat pinned in a test: layer 2 is an album-scoped title fold, so a widening re-walk stores "newly permitted rows except same-album title-fold twins".
- Storing on a non-enabled label via an allow: `ensureLabel` already mints/links label rows independent of seed_state; hub counters and `/label/<slug>` render stored rows in the unnamed register exactly as for any catalogue row — no read-side change (crawl-scope-never-storage's read half is untouched).

### 3.2 Pass outcome note

`expandRelease` writes a compact debug string to `crawl_frontier.note` at settle (`stored=N skipped_held=N skipped_rule=N`) — forensic aid only, unindexed, nothing may query it.

### 3.3 Re-arms (watermarks; all work inside the crawl tick)

**Why (verified):** nothing re-expands a `done` release node — `enqueue` is `on conflict do nothing`, the forward browse cannot revive, the tail re-arm early-stops on zero-new (pinned, crawl.integration.test.ts:1369). Enabling a label whose releases were visited under other seeds silently loses them **today**; there is no enable-after-walk test. This unit ships first.

- **Label leg:** enable/rule writes stamp `labels.scope_changed_at` — nothing else in the request path (the MB client's rate gate is per-isolate; a browse in a PATCH handler doubles the real request rate — the 2026-07-19 throttling incident class — and big labels blow the request deadline). In the tick, `rearmScopedLabelReleases()` (sibling of `rearmSeedLabels`, reported as `CrawlPass.releasesRearmed`) flips label nodes `done` with `done_at < scope_changed_at` back to pending; `enqueueReleaseNodes` gains a re-arm mode: `on conflict (id) do update set state='pending', cursor=0, hop=0, label_slug=excluded.label_slug where crawl_frontier.state='done' and crawl_frontier.done_at < :watermark`. Hop reset + `label_slug` repoint are required (a hop-2 node otherwise queues behind the world); `created_at` untouched. Client-side status filter: drop `Bootleg`/`Pseudo-Release`, keep status-absent (7 of Gutterfunk's 37 are status-less and real; `&status=official` would wrongly drop them). The `do update` arm is active only in re-arm mode (the tail-early-stop semantics stay pinned).
- **Artist leg (allows):** an allow write leaves `rearmed_at` null; the tick's `rearmAllowedArtists()` mints-or-revives the artist's browse node (`musicbrainz:artist:<mbid>`, hop 0) for every allow rule with `rearmed_at is null`, stamps `rearmed_at`, and the normal walk does the rest (each release then passes the gate, where the allow admits the billed records). **Allowed artists also join the daily re-arm set** — their artist nodes re-browse tail-first like enabled labels' nodes, so future releases on non-enabled labels keep arriving.
- **Backfill (operator-ratified):** after PR 1 lands, stamp `scope_changed_at` on **all enabled labels** once — the tick drains the rounds-1/2 back-catalogue holes over days at the ~84/h ceiling, safe by idempotence.
- Untouched states: `skipped` (no MB release), `failed` (owned by its backoff — the crawl.ts:559 doctrine), abandoned.

### 3.4 Counters (wire-compatible)

`tracksSkipped` stays as the sum (pinned box CLI + baked sweep script read it); additive fields `tracksSkippedHeld` / `tracksSkippedLabelGate` / `tracksSkippedArtistRule` (+ `tracksAllowedIn` for allow-admitted rows) through pass summary, cron JSON, ledger.

### 3.5 The freshness tap — scope-aware via the Spotify bridge (operator's design)

The tap keeps serving scoped labels; **no exclusion**. `parseProbeTrack` keeps the per-track Spotify artist **ids** it already receives (today it discards them, label-releases.ts:334 — the album parse already keeps ids at :312). The tap's write leg drops a track whose FIRST Spotify artist id matches a blocked rule's `artist_spotify_id` (per-label for that label, or global) — same quantifier, fail-open (no id / unresolved bridge → keep, the tap's status quo). Resolution happens at rule-write time from MB url-rels (authoritative, no fuzzy matching); a rule with a null bridge is **tap-blind** and marked so in the dialog and triage report (the crawler still enforces it exactly). Allows don't apply to the tap (it probes enabled labels only; allowed artists on non-enabled labels are served by the artist re-arm leg). The tap worklist SQL is unchanged (no exclusion clause; no new index — a builder adding one has misread this).

## 4. Measured ground (corrected census)

Gutterfunk `c7a4f6d6`: 37 releases, 133 track rows, 130 recordings, 50 credited artist MBIDs. Block-FIRST on {Jus Now} drops 6; block-ANY 9 (collateral: two Nuff Pedals × Maddslinky tracks); block-ALL 3 (leaks 4 of 6 Jus Now tracks). Maddslinky first-credit count = 0 → an inert rule; per-rule census counts are mandatory at ratification. Crystal Waters is **not** blocked: both "Gypsy Woman" pressings are the DieMantle RaveYard DnB remix credited solely to her (remixer exists only as a sparse recording-level rel) — the record stays in. DJ Die credited as "DJ Die"×31 / "Die"×15 (one MBID); two "Sure Thing" entities on one label — the MBID-keying proofs. Allow-shape lesson: "one artist" is often several MBIDs (DJ Die alone 44/130; +DieMantle 57/130) — allow sets need collaboration-entity expansion in the census.

MB-alternative rule (goes to label-entity.md): prefer an existing MB entity when the boundary is a product line (Med School, 3 Beat Breaks — machine-checkable via `?inc=label-rels`; triage refuses to propose rules when an imprint child covers the boundary). Use artist rules when the label is one imprint with mixed output. Never use ℗-holder entities as a mechanism.

## 5. Contracts & API

- **`update_label`** (PATCH `/admin/labels/{id}`, operator): `{ id, seedState? }` with the coalesce semantics (`ruled_at` stamped only when `seedState` present; enable stamps `scope_changed_at`). Simpler than v1 — no scope payload here.
- **`list_label_artist_rules`** (GET `/admin/labels/{id}/artists`, admin) — per-label rules for board/dialog/scripts.
- **`replace_label_artist_rules`** (PUT `/admin/labels/{id}/artists`, operator): transactional whole-set swap `{ rules: [{ artistMbid, artistName, verdict }] }`; server resolves `artist_spotify_id` per rule at write; stamps `scope_changed_at`; rejects bare names. `replace` is the blessed whole-set verb.
- **Global rules:** `list_artist_rules` (GET `/admin/artist-rules`, admin), `add_artist_rule` (POST, operator, `{ artistMbid, artistName, verdict }`), `remove_artist_rule` (DELETE `/admin/artist-rules/{id}`, operator) — `add`/`remove`/`list` all approved verbs. An allow add leaves `rearmed_at` null (the tick picks it up).
- All ops: `ADMIN_ROUTE_OPS` + `EXPECTED_TIERS` entries; contract-only oRPC; no MCP/registry/public-ids changes. The dialog's artist typeahead is a `createServerFn` (page-local admin read; the artists.tsx precedent), not an op.

## 6. CLI

- `fluncle admin labels update <slug> [--seed-state <state>] [--rewalk]` — `--rewalk` stamps `scope_changed_at` bare.
- `fluncle admin labels artists <slug>` (list) / `--replace --rules-file <json>` (whole-set swap with verdicts).
- `fluncle admin artists rule <artist-mbid> --verdict allow|block [--name <n>]` / `fluncle admin artists rules` (global list) / `… unrule <id>`.
- All value-taking flags join `stringOptions` (build-gated). Success copy uses the ratified vocabulary (§7).

## 7. Admin surfaces

Ratified vocabulary: **take** is the acquisition verb. Label row `⋮`: "Block an artist on it…" (enabled rows) / "Allow an artist from it…" (disabled rows). Chips (quiet, mode-distinct): `Except 2 artists` (enabled + blocks) / `Only 3 artists` (disabled + allows). Artists-row global actions: "Never take their records" / "Always take their records" (+ a quiet badge on ruled artists). Boundary clause everywhere a rule is edited: _"Rules change what the next crawl takes. Everything already here stays."_

- Dialog on the `ManageLinksDialog` pattern (route-local, copy it): chips with per-rule drift + tap-blind markers; typeahead + paste-an-MBID; **no live MB calls, no match counts** (the census lives at ratification where the MB payload exists; a DB-side count is structurally near-empty — verified). Per-rule census counts render at triage ratification instead.
- Board: while a re-walk is in flight, the row's identity line carries `· N releases queued` from one grouped bounded `crawl_frontier` read for the visible page. Scoped-section intro carries the count of rule-carrying labels. `validateSearch` for `?label=<slug>` (producer: the triage ratification page's per-label links).
- `/admin/artists` gains the global-rule action in its row menu; the artists board shows the badge.
- Smokes: shell-smoke stays green; add `/admin/labels` to touch-smoke `SURFACES` (verified absent); fixtures ship with the UI change. No new attention source (the label-alias precedent; maintenance = the triage rescope round, which exists in the script per §8).

## 8. The triage skill

- **Verdicts:** `dnb` rows may carry `rules: [{ artistMbid, artistName, verdict: "block", evidence, firstCreditCount }]` (enabled-shape: propose enable + blocks when off-lane first-credit share ≤ **15 %** — operator-ratified Y); `unclear`-avoidance for the disabled-mixed class: a new `dnb_partial` verdict proposing **keep disabled + allow rules** (the YUKU/Crucast shape), with collaboration-entity expansion in the census and per-artist evidence. **Global rules are never machine-applied:** agents may _suggest_ a global in prose (`globalSuggestion` note field); the operator authors globals by hand. Inert-rule guard: any proposed rule with zero first-credits on the census is rejected. Conflation stays `unclear`; the imprint-child check (`?inc=label-rels`) runs before any rule proposal.
- **Census:** phase-2 (`?inc=artist-credits+recordings`, ≤100/page, capped + sampling caveat) only for mixed-verdict labels; census-bearing slices batch at 5 labels/agent.
- **`pull-undecided.sh`:** emits existing rules per label; writes `calib-rules.txt` for the brief.
- **`apply-rulings.py`:** enabled-shape rows = `PATCH {seedState:"enabled"}` + `PUT …/artists`; `dnb_partial` rows = `PUT …/artists` only (label stays as-is); pilot pilots a rule-carrying label and verifies the rule set + `scope_changed_at` round-trip; **`rescope` mode** reads enabled/ruled labels for maintenance rounds and refreshes `checked_at`/`resolved_*` (the drift sweep — MB merges caught by response-id comparison; splits surfaced by first-credit counts going stale).
- **Ratification** leads with rule proposals: per-artist evidence + first-credit count + tap-bridge status + would-take/would-drop census; local HTML with a path.

## 9. Staged (gated)

1. **Per-label allow-as-restriction previews** ("would-store" for big allow sets) — gated on real usage shapes from the first rescope rounds.
2. **Persisted credit MBIDs** (`track_artist_mbids`) — the enabler for capture-ladder integration (Decision record #2), truthful dialog counts, and exact retroactive audits.
3. **Remixer-override** — a first-credit-blocked track carrying a remixer rel to a non-blocked artist is kept (`inc` extension verified, +2.8 % payload); decide the predicate after v1 counters show the class frequency. Unblocks blocking Crystal Waters-class credits without losing label-boss remixes.
4. **Capture veto** — scope × spend, revisit when 9.2 lands (operator ruling: v1 is storage-only; with the pilot's clean slate there is nothing mis-authorized to buy).

## 10. Sequencing

1. **PR 1 — the re-arm unit:** `scope_changed_at` + `rearmed_at` columns, enable-path stamp, `rearmScopedLabelReleases` + `rearmAllowedArtists` in the tick, enqueue re-arm mode, `--rewalk`, and the enable-after-walk test that does not exist today.
2. **PR 2 — schema + gate:** `artist_rules`, the memo, the verdict filter (inert until rules exist; tests seed by direct insert), counters, pass note.
3. **PR 3 — contracts + CLI** (all ops above, merge behaviour, bridge resolution at write).
4. **PR 4 — tap awareness** (parseProbeTrack ids + the write-leg check + tap-blind accounting).
5. **PR 5 — admin surfaces** (labels dialog + chips + queued count; artists global actions; smokes).
6. **PR 6 — triage skill** (repo-only; `skills:install`).
7. **PR 7 — the pilot (operator-gated production act):** global-block **Jus Now** (`3ae210f7…`, bridge id `0iT2o4MNsBKSLy7bllgdo0`) + plain-enable **Gutterfunk**. Prod verified: the label row exists (undecided, correct MBID) with **zero stored tracks** — clean slate, empty prune leg, no capture exposure. Acceptance: back catalogue arrives via the re-walk; Jus Now first-credit records refused (`tracksSkippedArtistRule` visible); 124/130 recordings stored incl. both Gypsy Woman mixes.
8. **PR 8 — the backfill (operator-gated):** stamp `scope_changed_at` on all enabled labels; monitor the drain in the ledger.

## 11. Doc/canon fan-out

The acquisition-axis restatement (everywhere): _A ruling and its artist rules govern what Fluncle **acquires** next — what the crawler seeds from, what it takes, and what audio gets bought. Nothing ever changes what is already stored._ Surfaces: docs/label-entity.md (the exception model + MB-alternative rule + restatement) · docs/catalogue-crawler.md (gate, exceptions, re-arms, counters; fix its "two layers" → three) · docs/the-ear.md (capture untouched in v1, pointer to 9.4) · docs/admin-shell.md (the verbatim "crawl scope, never storage" line + Labels/Artists placement rows) · labels.tsx header + on-page paragraph · docs/artist-relationship.md (global rules live on the artist entity's surface) · fluncle-catalogue-prune SKILL.md (the retroactive remedy).

## 12. Acceptance criteria (named tests)

- crawl.integration.test.ts @ :620 describe — enable-after-walk re-arm stores previously refused releases; second re-arm pass is a no-op (watermark terminates); re-arm resets hop + label_slug; re-arm skips Bootleg, keeps status-absent; tail re-arm still one-ticks on nothing-new; fold-colliding enabled labels never share rules (default-only + logged); block-FIRST drops the act's record, keeps the guest feature; a no-identity credit falls to the label default (both directions); **an allow stores a billed record from a disabled label and skips the same artist's guest credit**; an allowed artist's node is minted/revived and daily-re-armed; a fully-excluded release mints no album row; the artist-hop leg still enqueues from excluded credits; widening re-walk stores only newly permitted rows (album-title twins excepted); credit-order stability.
- labels.test.ts — merge drops loser rules + reports `droppedRules`; rule writes leave `ruled_at` untouched; restale fires only with `seedState`.
- label-releases tests — tap drops a first-credit-blocked Spotify id; keeps on null bridge; allowed artists don't affect the tap.
- Contract gates (naming/admin-coverage/auth-coverage), `cli.test.ts` stringOptions, full apps/cli run; smokes via `smoke:routine`; all §11 docs; `skills:install`.
- Pilot + backfill per §10.7–10.8.

## Decision record (interview, 2026-08-01→02 — all resolved)

1. Exception model (2 scopes × 2 verdicts), no label modes — **ratified** (supersedes v1's blocklist-only Q1).
2. Capture untouched in v1; storage-only; pilot's clean slate removes exposure — **ratified**.
3. Re-arms automatic (label enable/rule change; allow-artist walks; daily allowed-artist freshness) + `--rewalk` — **ratified**.
4. Triage block-share threshold Y = 15 % — **ratified**.
5. Pilot = global-block Jus Now + plain-enable Gutterfunk — **ratified**.
6. Backfill all enabled labels post-PR 1 — **ratified**.
7. Scope-aware tap via the Spotify-id bridge (operator's design) — **ratified**.
8. Agents propose per-label rules (both verdicts) with evidence; operator ratifies; globals operator-authored (prose suggestions only) — **ratified**.
9. Vocabulary: take/Except/Only/Never/Always set — **ratified**.
10. Build starts on operator trigger — **not before**.

## Risks & open questions

- Frontier contention during the backfill drain (visible via `releasesRearmed` + ledger; bounded batches).
- MB entity drift (merges benign via response-id comparison; splits surfaced by the rescope sweep's counts).
- Allow-set completeness (collab entities) — census expansion + ratification counts mitigate; a missed alias under-imports, never mis-imports.
- The gate's pre-existing alias blind spot (confirmed alias spelled differently by MB is refused on an enabled label) — predates this RFC, unchanged by it, worth its own fix.

## Appendix — verifications & sources

**Interview round (2026-08-01→02):** prod Gutterfunk row `lbl_16f6f120…` undecided, mb `c7a4f6d6…`, 0 stored tracks, 0 raw-string matches; Jus Now MB artist `3ae210f7…` carries Spotify url-rel `0iT2o4MNsBKSLy7bllgdo0` (the bridge proof); tap album parse keeps Spotify artist ids (label-releases.ts:312) while `parseProbeTrack` discards per-track ids it receives (:334); artist-hop discovery leg runs regardless of storage (crawl.ts:1365); `record_demand` re-orders, never stores (demand.ts); qualified-artists SQL authorizes capture only (catalogue.ts:815–880); non-test `tracks` writers = crawl.ts, label-releases.ts, publish.ts.
**Panel round (2026-07-31):** census 37/133/130/50 with corrected quantifier tables; Maddslinky first-credit = 0; Gypsy Woman = DieMantle remix credited solely to Crystal Waters (remixer rel verified; +2.8 % inc cost); browse status behaviour; Med School Imprint + `label ownership` edge; Hospital = 1,019 releases; deployed crawl budget 30 / release half-batch 15 / cadence ~10.75 min; 70-MBID drift probe (0 merges); mergeLabel's 8-statement batch; per-isolate MB rate gate + 2026-07-19 incident; `settle`'s unconditional `done_at`; the one partial `'enabled'` index; migration shape precedents; `/admin/labels` absent from touch-smoke.
**Overturned in v1→v2:** label modes (superseded); tap exclusion (superseded by the bridge); "remixer data doesn't exist" (sparse, not absent); the browse-in-the-write re-arm; fold-keyed memo; the DB-side dialog count; the write-ordering ritual; the ~8-artist cap (share test); the doctrine axis (writes → acquisition).
**External:** MusicBrainz Style/Artist_Credits · How_to_Identify_Labels · Label/Type · label-label relationship types (July 2026).
