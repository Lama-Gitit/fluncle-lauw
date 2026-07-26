# RFC: Global sub-100ms vector serving — the in-memory SIMD sidecar (Option D → C)

**Status:** Draft — **the one-region pilot has SHIPPED; what remains is the growth path and two surfaces** (updated 2026-07-26). Synthesized from a 4-thread deep-research pass + the Vectorize spike + the Slice A hosted proof. **Supersedes** `docs/rfcs/vectorize-similarity-rfc.md` (Cloudflare Vectorize — rejected). Two candidate fixes were **built and rejected on measured evidence**: Cloudflare Vectorize (spike) and hardening the Turso scan in place (Slice A, PR #842 — closed).
**For:** a fresh build session or a small team of agents. Next concrete step: the remaining surfaces (§Sequencing 3).

**What already shipped (the codebase is the record, not this RFC):** `apps/sonar` — the Rust in-memory exact-SIMD sidecar — runs in one EU region and serves **sonic search, `/artists?like=`, and `/log` neighbours** in production, each behind its own `settings` dark flag with the Turso exact scan as the fallback. The sonic scan that was failing at 7–19s with intermittent 500s is now a flat in-memory scan that does not grow with the catalogue. Measured on the pilot box: single-probe **~36ms p50 at 150k**, 100% recall. Details live in the code and in `apps/sonar/README.md`; this RFC keeps only what is still unbuilt.
**Canon/authority:** the codebase arbitrates (`apps/web/src/lib/server/{embedding,search,recommendations,tracks,catalogue,artist-dossier,track-update}.ts`, `apps/web/src/db/schema.ts`), plus `docs/the-ear.md`, `docs/search.md`, `docs/local-database.md`, `AGENTS.md`. Planning under `docs/rfcs/`, not spec. PRUNE on ship.

> Process note: this RFC rests on evidence gathered over this session — the Vectorize de-risk spike (real Cloudflare infra, measured), four parallel research threads (compute/hosting, database/storage, vector engines, reference architectures, dated 2025-2026), and the Slice A hosted-scale proof (real hosted Turso, measured). The decision below is the synthesis, not a proposal to research.

---

## The standard (definition of done)

The destination is a global architecture where **every surface — web, mobile, and the JSON API (CLI/MCP) — answers the dynamic/search slice in sub-100ms worldwide**, and the whole thing is delivered in complete, shippable phases (not a menu to cut from). Each phase ships whole: implementation + the hosted-scale proof + tests + docs + a rollback. The only sanctioned "not now" is genuine demand-gating — you do not pay for a second/third region's replica until far-region _dynamic_ traffic is measured as a real fraction, which the reference research is emphatic about. That is honest scoping (you cannot place a replica correctly without knowing where the audience is), not deferral of a reachable solve.

---

## 0. Summary / the reframe

**The unifying finding: this was never a "which vector database" problem. At Fluncle's scale the vector corpus is tiny (~600MB at 150k, ~2-4GB at 1M — ~128MB binary-quantized), so the real question is "where does a small in-memory index live, and how is it replicated globally." Once framed that way, exact in-memory search beats every remote ANN service on every axis Fluncle cares about.**

Five load-bearing conclusions from the evidence:

1. **Exact beats approximate here.** Independent SIMD-kernel numbers (~95 ns/vector bulk-scoring) put a single-probe "sounds like" scan at **~2ms @150k / ~12ms @1M** and the 24-probe recommendations fold at **~5ms / ~30ms**, across 8 cores, at **100% recall**. The multi-probe max-similarity fold is a native inner loop with **no topK cap** — the exact thing that made Cloudflare Vectorize impossible for `/recommendations` (topK≤100, 115-row pool). ([Elastic simdvec, 2025](https://www.elastic.co/search-labs/blog/elasticsearch-vector-search-simdvec-engine))
2. **The only hard problem is network geography, and it's cheap to solve.** A single-region box is ~2-30ms of compute + up to ~250ms of trans-oceanic RTT. Because the index is small, replicating it to a few regions removes the RTT. The blocker: the index cannot live in a Cloudflare Worker (128MB isolate cap, hard) — it needs a container/VPS with real RAM. ([Cloudflare limits, 2026](https://developers.cloudflare.com/durable-objects/platform/limits))
3. **Caching already handles ~90%+ of traffic.** Fluncle's anonymous reads are textbook 95-99% cache-hit; the edge already serves those sub-100ms globally for free. The _only_ thing this architecture must fix is the small, high-cardinality search/dynamic slice.
4. **There is no cheap in-place fix — hardening the Turso scan was tested and rejected (§2).** A hosted-scale proof (real Turso) showed the int8 coarse scan is still a _full SQL scan_, and hosted `vector_distance_cos` is seconds even at 20k — because the cost is per-row SQL cosine × N rows + network RTT to aws-eu-west-1, **not** blob I/O, so 4×-smaller vectors don't move the needle. The SQL-scan model is the ceiling. That leaves the in-memory sidecar as the _near-term_ answer, not a deferred one.
5. **Vectorize is rejected on measured evidence** (appendix): ~150ms floor, 74% recall@10 approximate, 290-806ms for high-precision, and structurally can't do the multi-probe fold.

**The plan: the vector sidecar (Stack D) is the immediate build.** A long-lived box holds the in-memory exact index (and a Turso embedded replica) and the Workers call it for the dynamic slice — **starting in one region and adding regions on measured demand**, growing naturally into the full regional-replica architecture (Stack C). The two other candidate fixes are spent: Vectorize (spike) and the in-place Turso hardening (Slice A / PR #842) were both built and measured to miss the bar. The sidecar is the one path the evidence leaves standing, and the corpus being small (~600MB) is exactly why it's cheap.

---

## 1. Context & goals

**Why now.** The DB-scale audit found Turso/relational fine to 150k; the misfit is vector latency for a global audience as the catalogue triples. The Vectorize spike killed the "managed edge ANN" premise (sub-100ms + exact is not on offer there). The research reframed the problem: at this corpus size, own the index in memory near compute.

**Goals, honestly calibrated.**

1. **The dynamic discovery surfaces** (sonic search, `/recommendations`, `/artists?like=`) answer in **sub-100ms**, at **100% recall**, scaling to 1M — served from an in-memory SIMD index on a sidecar box the Workers call, **starting in one region** and adding regions on measured demand.
2. Keep the edge/cache model for the cacheable 90%; keep monthly cost proportional to a solo-operator budget; **do not lock in a box provider** — the sidecar runtime is a swappable target (Fly / Koyeb / commodity VPS / Cloudflare Containers all fit the contract).
3. Prove the in-memory compute numbers on real hardware (the one-box spike) before committing the full build.

**What this explicitly does not do:** it does not re-platform the Cloudflare Workers web tier up front (the sidecar keeps Workers for the cacheable majority and adds a backend the Workers call); it does not chase global-sub-100ms for the _dynamic_ slice before the audience data justifies a second region; and it does not pursue any in-Turso hardening — that was measured to not clear the bar (§2).

---

## 2. Rejected: hardening the Turso scan in place (the proof)

This was the presumed near-term win — make the existing Turso exact scan cheap enough that 150k stays sub-100ms without moving any infrastructure. It was **built (Slice A, PR #842) and rejected on a hosted-scale proof.** Recording it so the decision isn't re-litigated.

**The technique tested: quantized coarse scan + exact float32 rescore.** Store an int8 (`FLOAT8`, ~4× smaller — `FLOAT1BIT` was verified to only rank with jaccard/hamming, not cosine, so it was out) code alongside the float32 `embedding_blob`; scan the compact codes, take the top-N, exact-rescore those N with the full vectors. Recall is preserved and the multi-probe min-fold is intact.

**What the proof showed (real hosted Turso, 2026-07-23):**

- **Recall: solved** — 100% top-K across all shapes (int8 coarse + 8× overfetch + exact rescore is a correct design; carry this learning to §3's quantization decision).
- **Latency: NOT solved.** The int8 coarse pass is still a _full SQL scan_, and a hosted `vector_distance_cos` scan is seconds even at 20k (broad "sounds like" shape: OLD exact ~2.5s p50, NEW coarse+rescore ~1.9s p50 — int8 bought only ~25%, nowhere near sub-100ms, and it grows with the corpus). On narrow pre-filtered scans the two-round-trip coarse+rescore is actually _slower_ than the plain exact scan.

**Why it can't be rescued:** the bottleneck is not blob I/O (which int8 shrinks) — it is the **per-row SQL cosine × N rows in Turso's engine + the network RTT** to the single-region primary. Shrinking the vector 4× can't change that order of magnitude, and no btree pre-filter narrows the _broad_ "sounds like X" case (it filters little beyond `anchored`). The SQL-scan model is the ceiling. So there is no cheap in-place fix, and the sidecar (§3) is not a "later" phase — it is the answer.

---

## 3. The vector sidecar (Stack D), growing into regional replicas (Stack C) — THE BUILD

This is the immediate track. Stand up **one** sidecar now; grow to more regions on measured demand (§3.6). It is the one architecture the evidence leaves standing, and the small corpus is what makes it cheap.

### 3.1 What the sidecar is

A long-lived box (RAM: ~1-4GB float32, or ~128MB-1GB quantized) running a thin service that holds:

- **The in-memory exact vector index** (raw float32 vectors in a `Float32Array`, scanned with SIMD via `usearch(exact=True)`/SimSIMD or a small custom kernel). Single-probe ~2-12ms, 24-probe fold ~5-30ms, 100% recall, native multi-probe, pre-filters shrink the scan.
- **A Turso embedded replica** (local SQLite file synced from the primary — the box has a filesystem, so this works where a Worker can't). This lets the sidecar do the _whole_ dynamic query locally — vector scan **and** the relational post-filter/hydration (certified/dismissed, the DTO) — and return finished results, so a search is a single Worker→sidecar hop with no second trip back to Turso.

### 3.2 The index is a derived, distributed artifact

The index is rebuilt from the embeddings (Turso is source of truth) into a versioned artifact, pushed to R2, and pulled by each sidecar on a schedule — the same "derived artifact, not a migration" pattern Fluncle already uses for FTS5 and cover masters. Adding a region is: spin up a box, pull the artifact from R2, register it with the router. Freshness is periodic (minutes), which fits Fluncle's already-async enrichment; the embedded replica covers relational read-your-writes within its lag.

### 3.3 The Worker routes to the nearest sidecar

The Worker knows the user's geography (`request.cf`), so it calls the nearest sidecar directly by region, or hits a geo-steered endpoint (an anycast hostname, or a Cloudflare Load Balancer with geo-steering fronting the boxes). The hop must be **same-continent** — an EU user's Worker calling an EU sidecar is ~10-40ms; a cross-ocean hop would defeat the purpose, which is exactly why far regions get their own sidecar rather than being served from the first one.

### 3.4 Provider stays flexible (do not lock in)

The sidecar is defined by a **runtime contract** (a container/VM with N GB RAM, an HTTP endpoint, R2 access to pull the artifact, and a Turso embedded replica), so the host is a swappable implementation detail. Candidates carried forward, **none chosen yet**:

- **Regional VMs/containers you place explicitly** — e.g. Fly.io Machines (best multi-region ergonomics + anycast, ~$15-50/region), Koyeb (10+ regions), or **commodity VPS** (cheapest, operator already runs this class; needs a geo-router in front, fewer locations).
- **On-Cloudflare** — Cloudflare Containers (stays on-network, Worker→Container never leaves Cloudflare) — integrated, but placement co-location isn't guaranteed and it's the newest option.
  Selection criteria to decide later: RAM/$ at the needed index size, how many regions/where, built-in vs DIY geo-routing, ops burden, and how cleanly it holds an embedded replica. Keep the deployment scripted against the contract so switching providers is a config change, not a rewrite.

### 3.5 Sidecar (D) → regional replica (C)

Stack D and Stack C are the same architecture at two maturities. As the sidecar accretes responsibility (vector + embedded replica + post-filter + hydration), it is already doing most of what the app does for the dynamic slice; moving the rest of the app onto the regional boxes (Stack C — the app _is_ the replica) becomes a small, optional step rather than a re-platform. Start as a sidecar behind the Workers; let it grow only as far as demand requires.

### 3.6 Growth trigger (demand-gated, one region at a time)

1. Instrument far-region _dynamic_ (uncached search/recs) latency + traffic share by continent.
2. Pilot **one** sidecar in the region nearest the core audience; route only same-continent dynamic traffic to it; measure.
3. Add a second/third region **only when** its far-region dynamic traffic is a measured, meaningful slice. Each addition is cheap (spin box, pull artifact, register).

---

## Sequencing & ownership

0. **DONE:** two candidate fixes built and rejected — Vectorize (spike) and the in-place Turso hardening (Slice A / PR #842, closed). See §2 and the appendix.
1. **DONE — the de-risk spike.** The in-memory SIMD scan was measured on real hardware: single-probe **7–8ms @150k / 44ms @1M** on a dev machine, and **36ms p50 @150k** on the (2-vCPU) pilot box — sub-100ms at both scales, 100% recall. Multi-probe is compute-bound and lives only in latency-tolerant paths, which is why the current box suffices.
2. **DONE — pilot, one region.** `apps/sonar` (in-memory index + the `POST /search` contract, refreshed hourly from Turso), the Worker client, and three surfaces behind per-surface dark flags, with the Turso scan as the flag-flip fallback. Self-deploy (CI-built artifact → box pull + verify + swap + rollback) is the last piece landing.
3. **REMAINING — the last two surfaces.** `/recommendations` (draft/setup phase only — the committed phase reads a frozen edition and never runs the engine) and `/mix` **single-probe-on-last** (transition mixing is adjacency to the last track, not a whole-set taste fold; the already-picked set is the exclude list). Both are multi-probe-shaped today; moving them is what retires the last slow vector path.
4. **REMAINING — growth, demand-gated.** Add regions per §3.6 only on measured far-region dynamic demand. Untriggered so far.

Deploy discipline: the sidecar introduces a new runtime — keep the current Workers→Turso path as the fallback (flag per surface) until the sidecar is proven in prod. The Turso exact scan stays the fallback even though it's slow at scale; it is correct, and it is what the flag flips back to.

## Decisions — resolved by the pilot

1. ~~First region~~ — **RESOLVED: one EU region**, co-located with the existing box fleet. Revisit only on the §3.6 growth trigger.
2. ~~Provider shortlist~~ — **RESOLVED:** the pilot runs on the existing EU box rather than a new vendor, which kept the pilot free. §3.4's flexibility still holds — the service is a plain static binary behind an HTTP contract, so it moves.
3. ~~Quantization~~ — **RESOLVED: full float32 in RAM**, as recommended. At the current corpus the index is small and the scan is already well under budget; int8 stays in the back pocket for the 1M-per-region case, and Slice A proved the recall-preserving recipe if it is ever needed.
4. **Freshness SLA** — **RESOLVED in practice: ~1 hour** (the sidecar re-reads Turso hourly). No surface has needed read-your-write on a fresh embedding, since enrichment is already async. Revisit if one ever does.
5. **Routing mechanism** — still open, but **not yet load-bearing** at one region (the Worker calls the sidecar directly). **Recommend a geo-steered LB** if a second region is ever added.

**Still genuinely open:** whether `/recommendations` and `/mix` move to the sidecar as-is or the multi-probe fold gets the single-pass min-fold kernel first (§Sequencing 3).

## Acceptance criteria

- ~~**Spike**~~ — **MET.** Single-probe measured at 150k and 1M on real hardware, within the modeled range; footprint confirmed; go recorded.
- ~~**Pilot**~~ — **MET.** Three surfaces serve through the sidecar with the per-surface flag restoring the Turso path with no deploy; the hourly index refresh runs on schedule.
- **Remaining surfaces:** `/recommendations` (draft/setup) and `/mix` single-probe-on-last serve through the sidecar, each behind its own flag with the Turso fallback intact, and no surface regresses on ranking (the-ear.md's nearest-probe rule holds — **never a centroid**).
- **Docs:** a `docs/vector-serving.md` describing the sidecar contract, the flag map, and the refresh/self-deploy loop — **and it must carry the appendix's measured rejections forward**, since that evidence exists nowhere else. **PRUNE this RFC** once that doc lands and the two surfaces ship.

## Risks & open questions

- **Turso platform pivot** (discontinuing edge replicas for new users, Rust engine rewrite, unclear parity/timeline) — a standing risk on the incumbent. Mitigation: the sidecar uses _embedded_ replicas (local file sync, the durable feature) and the index is a self-owned artifact; if Turso's sync story degrades, Litestream v0.5 live read replicas on R2 (fixed in 0.5.2) or a plain periodic SQLite artifact are drop-in substitutes. Monitor. ([Turso roadmap, 2025](https://turso.tech/blog/upcoming-changes-to-the-turso-platform-and-roadmap); [Litestream v0.5, 2025](https://fly.io/blog/litestream-v050-is-here/))
- **Ops burden of a stateful box** — patching, failover, replication lag, index-rebuild correctness. Real, but bounded (read-only replicas, single-writer primary, rebuild is idempotent from R2). Start with one box.
- **Worker→sidecar hop** adds latency to the dynamic slice vs a pure in-process app (Stack C) — acceptable same-continent; the D→C step removes it if it ever matters.
- **Index freshness vs staleness** — periodic rebuild means a new embedding is searchable minutes late; argued invisible (enrichment already async), but confirm per surface.
- **Cost creep with regions** — each region is a box + its artifact pull; demand-gating keeps this proportional.

## Appendix — the two rejected candidates (measured) + sources

**Candidate 1 — Cloudflare Vectorize (real Cloudflare infra, 2026-07-23, torn down):** latency ~150-180ms p50 / ~170-225ms p95 approximate at 150k, hard floor 147ms even warm; high-precision 287ms p50 / **806ms p95**; none sub-100ms. Recall (13.4k real embeddings, overlap@K vs exact): approximate @10 74-80%, high-precision @10 99% but @50 ~79-86%. Structurally cannot serve the 115-row / 24-probe multi-probe fold (topK≤100). Wrong tool for exact, multi-probe, sub-100ms at this scale.

**Candidate 2 — hardening the Turso scan in place / Slice A (real hosted Turso, 2026-07-23, 20k smoke over a flaky link — directional; PR #842 closed):** recall **100%** top-12 across all shapes (int8 coarse + 8× overfetch + exact rescore is correct). Latency, per-shape p50 (absolutes inflated by the flaky connection; the _relative_ story is structural): SONIC broad (anchored-only ~70%) OLD 2543ms / NEW 1902ms — int8 bought ~25%, not sub-100ms; SONIC narrow (key+anchored ~3%) OLD 112ms / NEW 196ms — NEW _slower_ (double round-trip on a small scan); RECOMMENDATIONS (12-probe ~70%) OLD 720ms / NEW 689ms — ~equal. The int8 coarse pass is still a full SQL scan; the cost is per-row SQL cosine × N + network RTT, not blob I/O, so vector-width reduction can't reach sub-100ms. Rejected as a latency fix; its recall-preserving quantization is the surviving learning.

**Both rejections point the same way:** a remote/SQL scan can't hit the bar at this scale; the answer is the in-memory index near compute (§3).

**Research sources (dated 2025-2026):** [Elastic simdvec kernel timings](https://www.elastic.co/search-labs/blog/elasticsearch-vector-search-simdvec-engine); [usearch/SimSIMD exact search](https://github.com/unum-cloud/usearch); [Cloudflare Workers/DO limits](https://developers.cloudflare.com/durable-objects/platform/limits) + [Containers](https://blog.cloudflare.com/cloudflare-containers-coming-2025/); [Cloudflare D1 read replication + lag numbers](https://blog.cloudflare.com/d1-read-replication-beta/); [Turso embedded replicas](https://docs.turso.tech/features/embedded-replicas/introduction) + [platform pivot](https://turso.tech/blog/upcoming-changes-to-the-turso-platform-and-roadmap); [Fly multi-region blueprint](https://fly.io/docs/blueprints/multi-region-fly-replay/) + [LiteFS](https://fly.io/docs/litefs/how-it-works/); [Litestream v0.5](https://fly.io/blog/litestream-v050-is-here/); [sqlite-vec scale numbers](https://alexgarcia.xyz/blog/2024/sqlite-vec-stable-release/index.html); [Turbopuffer pricing/benchmark](https://turbopuffer.com/pricing); [Qdrant/Milvus/Weaviate/pgvector independent benchmark, Q1 2026](https://effoma.com/blog/vector-database-performance-benchmark-comparison-2026/); [Pagefind client search](https://pagefind.app/); [SQLite-at-the-edge 2026](https://www.sitepoint.com/sqlite-edge-production-readiness-2026/).
