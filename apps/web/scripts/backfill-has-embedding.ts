#!/usr/bin/env bun
/**
 * The `has_embedding` backfill — an idempotent, deploy-time pass that seeds the maintained
 * embedding-presence mirror (docs/db-scale-backlog Wave 2 #4) onto history.
 *
 * WHY IT EXISTS, AND WHY IT IS NOT FREE LIKE `is_catalogue`'s. The migration adds `has_embedding`
 * with `DEFAULT 0`, so every EXISTING row lands un-embedded — correct for the rows with no vector
 * and WRONG for every row that already carries one (21,088 of 54,860 on prod at the time of
 * writing). Keystone 1 got its history for free because "born catalogue" happened to be the DDL
 * default; this mirror has no such luck, so the flip has to be done here. Until it runs,
 * `/admin/funnel` would report `embedded` and `rec_eligible` as 0 — an under-report, never an
 * over-report, and never a wrong RANKING (the recommendation reads still gate on the blob itself).
 *
 * DEPLOY ORDER IS WHAT MAKES THAT SAFE. `deploy:cf` is `db:migrate && db:backfill && wrangler
 * deploy` (package.json), so the column is added and flipped BEFORE the Worker that reads it ships.
 * The old Worker in front of a migrated database reads a column it never mentions; the new Worker
 * never sees an unflipped one.
 *
 * THE SHAPE, AND WHY IT CORRECTS BOTH DIRECTIONS. `set has_embedding = (embedding_blob is not null)
 * where has_embedding <> (embedding_blob is not null)` — not the narrower "flip the un-flagged
 * embedded rows". Seeding history only ever needs 0 → 1, but the failure mode a maintained mirror
 * actually has is drift either way: a hand-run `UPDATE … SET embedding_blob = NULL` in a console,
 * or a restored backup, leaves a row FLAGGED with no vector, and that direction makes the funnel
 * OVER-report. Reconciling against the blob itself is the same cost as the one-way form and turns
 * this from a one-shot seed into a standing backstop — the same posture as the hub-counts
 * reconciliation sweep (Wave 2 #2 slice C).
 *
 * It is a full scan of `tracks` either way (there is no index that answers "which vectors exist"),
 * and it REWRITES each matching row, so the first run is the expensive one: 108 s over 21,088
 * embedded rows on a hosted prod-scale clone (measured 2026-07-26), alongside a 63 s build of
 * `tracks_funnel_scan_idx` in the migration ahead of it — call it three minutes added to the ONE
 * deploy that lands them, and nothing on the deploys after. Testing `embedding_blob IS NOT NULL` is itself
 * cheap — null-ness reads the record header, not the overflow pages. The `where` residual is what
 * makes the SECOND run cheap: on a correct database it matches nothing, so there is no write
 * amplification on later deploys.
 *
 * IDEMPOTENT + SELF-HEALING. Wired into `db:backfill`, so it runs on every deploy after
 * `db:migrate`: the first deploy seeds history, every deploy after finds nothing to correct (the
 * four write sites keep the mirror moving in lockstep — schema.ts § `has_embedding`, and
 * `embedding-mirror.test.ts` fails the build if a fifth writer forgets) and changes nothing. Reads
 * `TURSO_DATABASE_URL`/`TURSO_AUTH_TOKEN` from the environment (locally from apps/web/.dev.vars),
 * exactly like `db:migrate` and its sibling backfills.
 */
import { type Client, createClient } from "@libsql/client";
import { config } from "dotenv";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

export type HasEmbeddingBackfillResult = {
  /** How many rows this run reconciled against their vector, in either direction. */
  flipped: number;
};

/**
 * The idempotent core, taking any libSQL client so a test can drive it against an in-memory DB with
 * the real migrations applied (the `backfillIsCatalogue` precedent).
 */
export async function backfillHasEmbedding(client: Client): Promise<HasEmbeddingBackfillResult> {
  const result = await client.execute({
    sql: `update tracks set has_embedding = (embedding_blob is not null)
          where has_embedding <> (embedding_blob is not null)`,
  });

  return { flipped: result.rowsAffected };
}

async function main(): Promise<void> {
  if (!process.env.TURSO_DATABASE_URL) {
    config({ path: join(dirname(fileURLToPath(import.meta.url)), "..", ".dev.vars") });
  }

  const url = process.env.TURSO_DATABASE_URL;

  if (!url) {
    throw new Error("TURSO_DATABASE_URL is required (set it in apps/web/.dev.vars)");
  }

  const authToken = process.env.TURSO_AUTH_TOKEN;
  const client = createClient(authToken ? { authToken, url } : { url });
  const result = await backfillHasEmbedding(client);

  console.log(`has_embedding backfill: ${result.flipped} row(s) reconciled against their vector.`);
}

if (import.meta.main) {
  await main();
}
