---
name: fluncle-label-triage
description: Run a label triage pass — research Fluncle's undecided crawl-seed labels into DnB / not-DnB / unclear buckets with per-label evidence, present them for the operator's ruling, and apply the ratified enables/disables. Use whenever undecided labels have piled up on /admin/labels, the operator says "triage the labels", "rule on the new labels", "run a label pass/round", "sort the undecided pile", or a funnel/crawl check shows the storage gate skipping most finds because too many labels are unruled. The crawler mints new undecided labels every time a round OPENS new neighbourhoods, so this is a recurring pass, not a one-off. NOT for ruling a single label the operator already named (that is one `fluncle admin labels update`), and NOT for removing already-stored off-genre content (that is fluncle-catalogue-prune).
---

# Fluncle label triage — rule the undecided crawl seeds

The catalogue crawler stores a track only when its release's label is `enabled` (the STORAGE GATE, docs/catalogue-crawler.md); a newly discovered label lands `undecided` and its releases are walked but written as nothing. So the undecided pile is the throttle on catalogue growth — and it refills itself: **every batch of enables opens new walks that mint the next batch of discoveries within hours**. This skill is the repeatable pass: pull the pile, research every label with real evidence, present three buckets, apply what the operator ratifies.

The ruling itself is an OPERATOR act (`update_label` is operator-tier — crawl scope is editorial control). The skill's job is to make each ruling a one-glance decision, never to make it.

## The pass, end to end

### 0 · Preconditions

- Operator env: `set -a; source <operator env file>; set +a` (the `set -a` matters — a plain source doesn't export to child processes). The file's location is operator topology (private companion runbook).
- Prod DB read creds resolve through `op` via the indirection var `FLUNCLE_TURSO_OP_ITEM` (the open-source posture: scripts never hardcode `op://` paths). One biometric approval covers the session. NEVER run `op signin`/`op whoami` first — in a non-TTY shell they always claim you're signed out; just run the real `op read`.

### 1 · Pull the pile

```bash
bash <skill>/scripts/pull-undecided.sh [--exclude held-slugs.txt] > undecided.json
```

Emits every `undecided` label with its **`mb_label_id`** (load-bearing: agents research the EXACT MusicBrainz entity, never a same-named label — "Absolute" the Swedish pop-comp brand is not "Absolute 2 Records" the UK jungle label) plus its stored-track count, and refreshes `calib-enabled.txt` / `calib-disabled.txt` from the LIVE rulings. The DB read is required — the admin labels API does not carry `mb_label_id` on the wire.

`--exclude` skips slugs the operator is holding for their own ear (prior rounds' `unclear`). Skipping the flag is safe — a re-triaged held label just comes back `unclear` again — it only spends tokens.

### 2 · Fan out the research

Launch the Workflow with `<skill>/scripts/triage-workflow.js` (batch ≈ 10 labels per agent):

```
Workflow({ scriptPath: "<skill>/scripts/triage-workflow.js",
           args: { file: ".../undecided.json", enabled: ".../calib-enabled.txt",
                   disabled: ".../calib-disabled.txt", total: <n>, batch: 10 } })
```

The script already guards the harness's stringified-`args` delivery (a workflow that returns instantly with zero agents IS that trap) and embeds the full research brief. The method the brief enforces, and why:

- **Calibrate to the operator's live rulings, not a genre notion.** Agents read both calibration lists first. The boundary has a specific learned shape: majors, subsidiaries, distributors and aggregators are OUT even when they carry DnB; **DnB-specific media brands are IN** (Drum&BassArena, UKF enabled; DJ Magazine disabled); genre-adjacent scenes (dubstep, grime, UKG, jungle-adjacent electronica) are OUT.
- **MusicBrainz artists are the genre signal; MB `tags`/`genres` are usually EMPTY** — don't rely on them. Release credits (25 releases with artist-credits) decide most labels; the Discogs url-rel from the MB label settles the rest; firecrawl/web search only for what's still open. MB pacing: 1 req/s with a real User-Agent, or 403s.
- Return `unclear` for mixed-genre labels, minority-DnB catalogues, or evidence too sparse to support a ruling; the operator reviews these manually.
- Return `unclear` and name the conflation when one MBID contains releases from distinct labels; enabling crawls by MBID, so split the upstream entity before enabling.
- On a partial failure (an agent dies mid-run), **resume with `resumeFromRunId`** — completed batches replay from cache, only the dead slice re-runs.

### 3 · Present for ratification

Three buckets with per-label evidence (what was actually SEEN: artists, Discogs styles, release titles — never a restated guess). Lead with the judgment calls: every `unclear` and every non-`high` confidence verdict. A rendered review page (the artifact pattern) is a nice-to-have for big rounds; the chat table is fine for small ones. **Do not apply anything the operator has not ratified.**

### 4 · Apply

```bash
python3 <skill>/scripts/apply-rulings.py pilot     # ONE write, verify the round-trip
python3 <skill>/scripts/apply-rulings.py apply     # the rest
```

Reads the staged verdicts (`label-triage.json`: `dnb` → enabled, `not_dnb` → disabled, `unclear` untouched), re-checks each row is STILL `undecided` server-side before writing (other sessions rule labels too), and reports per-row. Single labels also work through the first-class CLI: `fluncle admin labels update <slug> --seed-state enabled|disabled`. The API sits behind Cloudflare — every request needs a real `User-Agent` (the default `Python-urllib` signature gets a 1010).

### 5 · Close the loop

Re-count after applying and report newly minted undecided labels; offer another pass when the queue has refilled.

## Verification quality bar (the pass earns trust once, keeps it always)

- A wrong "enable" stores off-genre catalogue and mints public pages; a wrong "disable" silently loses good music. When a verdict matters and is checkable — an ISRC in hand, a duration — spot-check via free oracles (Deezer's no-auth API) before presenting it as fact.
- Agents may challenge the brief with evidence. Live calibration lists override category rules.

## Where the concrete detail lives

- The storage gate + widening loop: docs/catalogue-crawler.md; the label entity + seed states: docs/label-entity.md.
- The CLI carrier: `fluncle admin labels update` (docs/naming-conventions.md, `update_label`).
- Secrets/topology (operator env file, Turso op item): the private companion runbook. This skill holds procedure + placeholders only.
- The removal counterpart (already-stored off-genre content): the fluncle-catalogue-prune skill.
