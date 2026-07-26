import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

// THE has_embedding MIRROR RAIL (schema.ts § `has_embedding`, docs/db-scale-backlog Wave 2 #4).
//
// `tracks.has_embedding` is a MAINTAINED mirror of `embedding_blob IS NOT NULL`, and the whole point
// of it is that `/admin/funnel`'s stage scan can read the flag out of a covering index instead of
// walking every 4 KB vector's overflow pages to reach the columns stored after it. A mirror is only
// worth having if it cannot drift, so the invariant is: EVERY statement that assigns
// `embedding_blob` assigns `has_embedding` in the same statement.
//
// That invariant lives in four writers, and a reviewer remembering it is not a guarantee. This is
// the net that makes it structural: it scans the server source for `embedding_blob =` assignments
// and fails on any that does not carry the mirror. A fifth writer added later has to satisfy it.
//
// The complement — that the mirror's VALUE is right, not merely present — is proven on live rows by
// the funnel fold-equivalence test, which runs the folded scan (reading `has_embedding`) against the
// standalone reference queries (still reading `embedding_blob IS NOT NULL`) and requires the two to
// agree. Together: this test proves the pair always moves, that test proves it moves correctly.

const SERVER = fileURLToPath(new URL("./", import.meta.url));

/** Every non-test `.ts` under `lib/server`, recursively, as paths relative to the server root. */
function serverSources(dir = SERVER, prefix = ""): string[] {
  const out: string[] = [];

  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const rel = prefix ? `${prefix}/${entry.name}` : entry.name;

    if (entry.isDirectory()) {
      out.push(...serverSources(join(dir, entry.name), rel));
    } else if (entry.name.endsWith(".ts") && !entry.name.includes(".test.")) {
      out.push(rel);
    }
  }

  return out;
}

/**
 * One `embedding_blob = …` assignment and the statement it sits in. The statement is approximated as
 * the enclosing `set …` run up to the next `where`/backtick — enough to see whether the mirror is
 * assigned alongside, and deliberately crude: a false ALARM is a reviewer reading one line, while a
 * false pass is a drifted mirror in production.
 */
type Assignment = { file: string; statement: string };

function assignments(): Assignment[] {
  const found: Assignment[] = [];

  for (const file of serverSources()) {
    const source = readFileSync(join(SERVER, file), "utf8");

    // Skip the shared fragment's own definition — it IS the mirror pairing, not a bare write.
    if (file === "embedding.ts") {
      continue;
    }

    for (const match of source.matchAll(/embedding_blob\s*=/g)) {
      const start = Math.max(0, match.index - 400);
      found.push({ file, statement: source.slice(start, match.index + 400) });
    }
  }

  return found;
}

/** Statements that clear the vector through the shared fragment rather than spelling it out. */
function sharedClears(): string[] {
  return serverSources().filter(
    (file) =>
      file !== "embedding.ts" &&
      readFileSync(join(SERVER, file), "utf8").includes("${CLEAR_EMBEDDING_SQL}"),
  );
}

describe("the has_embedding mirror cannot drift", () => {
  it("finds the embedding_blob writers at all (the scanner still works)", () => {
    // A guard on the guard: if a refactor moves these writes somewhere this test cannot see, the
    // suite must fail loudly rather than pass by finding nothing to check. Both spellings count —
    // the two `update_track` arms that SET a vector, and the quarantine paths that clear it through
    // the shared fragment (which is why the raw-assignment count alone is not the floor).
    expect(assignments().length + sharedClears().length).toBeGreaterThanOrEqual(3);
  });

  it("pairs every embedding_blob assignment with its has_embedding mirror", () => {
    const unpaired = assignments()
      .filter(
        ({ statement }) =>
          !statement.includes("has_embedding") && !statement.includes("CLEAR_EMBEDDING_SQL"),
      )
      .map(({ file }) => file);

    expect(unpaired).toEqual([]);
  });

  it("keeps the shared clearing fragment carrying both halves", () => {
    const embedding = readFileSync(join(SERVER, "embedding.ts"), "utf8");

    expect(embedding).toContain("embedding_blob = null");
    expect(embedding).toContain("has_embedding = 0");
  });
});
