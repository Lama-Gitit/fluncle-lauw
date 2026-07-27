---
name: session-reflection
description: >-
  Mine a working session for durable improvements to how AI agents work in this
  repo, and route each lesson to its RIGHT home (a test/hook, a code fix, a
  skill, a memory, or — rarely — a standing instruction), never just appending
  prose. Use this at the END of any substantial session, or whenever the
  operator says "reflect on this session", "what did we learn", "any takeaways",
  "should we update the docs/skills/memory after this", "self-improve", "run a
  retro", or asks how to keep the codebase's agent guidance sharp. Also reach for
  it when a session hit repeated friction, a stale instruction, or a correction
  the operator had to repeat — those are exactly the lessons this captures. Do
  NOT use it for writing product features or copy; this is about improving the
  agent harness itself.
---

# Session reflection — route the lessons, guard the constitution

You are closing out a working session on this codebase. Mine what actually happened for durable improvements to how AI agents work here — and route each lesson to the right home, which is usually NOT another sentence of instructions.

The deep reason this skill exists as a _router_ rather than a "CLAUDE.md appender": every added rule dilutes every existing rule (model adherence measurably degrades as instruction files grow — the "context rot" effect, and Anthropic's own guidance names bloat as why Claude ignores instructions). A reflection habit whose only move is "write it down" makes the guidance worse over time. The valuable question is always _where does this lesson belong_, and prose is the answer of last resort.

## Ground rules (they bind everything below)

1. **Prose is the last resort.** The routing ladder runs strongest home → weakest; a lesson lands at the FIRST rung that can hold it, and reaches "standing instruction" only when nothing above it can.
2. **No receipt, no proposal.** Every finding cites the concrete session moment that earned it: the failed tool call, the operator's correction, the wrong deploy, the turns it cost. A lesson you cannot point at did not happen — this is the antidote to overfitting a one-session idiosyncrasy into a permanent rule.
3. **One occurrence is an episode, not a rule.** A standing-instruction proposal needs the pattern to have bitten at least twice (in this session, or once here plus a prior memory/doc scar). Single occurrences route to memory at most — or to nothing.
4. **Never regenerate a file.** Propose minimal diffs against curated files (exact old text → new text). Full-file rewrites are how curated playbooks collapse — a single bad rewrite can silently gut hard-won specifics.
5. **Hard cap: at most 5 proposals**, ranked by expected cost-of-recurrence. If you found more, the overflow dies in one line, no detail. A long session yields dozens of plausible tweaks; most are noise.
6. **Pruning counts as improvement.** Actively hunt deletions: rules now enforced by CI/tests/hooks, stale paths, contradictions, shipped-work references, memories this session proved wrong. The instruction budget should trend flat or down; propose an eviction alongside any addition to an already-long file.
7. **Never propose weakening safety rails, autonomy boundaries, or operator gates — including for yourself.**

## The routing ladder

For each candidate lesson, take the FIRST rung that fits:

| Rung                     | When                                                                                            | Home                                                                                                               |
| ------------------------ | ----------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| **Code fix**             | The lesson papers over a real defect                                                            | Fix the code (or file the fix as the proposal)                                                                     |
| **Executable guardrail** | Recurring AND mechanically checkable                                                            | A test, lint rule, hook, coverage gate, or CI step — agents can ignore prose, not a red check                      |
| **Skill / scoped rule**  | A procedure or gotcha tied to one workflow or one part of the tree                              | The relevant skill in `packages/skills/**` (then `bun run skills:install`), or a path-scoped `.claude/rules/` file |
| **Memory**               | Narrow, situational, or single-occurrence but worth recall                                      | The persistent memory system (one fact per file, indexed in `MEMORY.md`)                                           |
| **Standing instruction** | Broad, durable, un-checkable, ≥2 occurrences, and a new teammate would need it in every session | `AGENTS.md` (or the relevant canon doc) — the rarest outcome                                                       |

The spine, from Anthropic's own guidance: _if Claude already does the thing right without the rule, delete it or convert it to a hook._ Default to the lowest-commitment destination; promotion up the ladder requires a reason.

## What to hold the session against

Skim (you know most of it): `CLAUDE.md` → `AGENTS.md`; the skills that were loaded or SHOULD have been loaded this session (`packages/skills/**`); `.claude/agents/*`, `.claude/rules/*`, hooks and settings under `.claude/`; the memory index (`MEMORY.md`) and any recalled memory files; and the CI enforcement points (the deploy gate, the coverage/naming/guardrail tests). "Could this be a test?" is the question that beats "where do I write this down?".

## Signal sources, in priority order

1. **Explicit operator corrections** — every time they said "no", "please don't", "why did you…", or fixed your output. The highest-grade ore.
2. **Failed tool calls and their recovery cost** — errors that took multiple turns to route around, especially ones a doc/skill claimed wouldn't happen.
3. **Stale guidance hit live** — any instruction, skill line, or memory that was WRONG when followed. These become deletions/corrections, the best kind of finding.
4. **Repeated friction** — anything done 3+ times by hand that a script/hook/flag should own.
5. **Surprises** — things that worked only because of undocumented knowledge you happened to have.

## Output

First, an **"Already routed in-session"** line: lessons handled live during the session (a rule already added, a fix already shipped), listed one-line each so they are not re-proposed. This is not filler — a well-run session routes most lessons as it goes, and naming them proves the process worked and keeps the table below to the genuinely-open items.

Then present ONE ranked table and stop for ratification:

| # | Lesson (one line) | Receipt (the session moment) | Rung | Proposed change (diff or new-file summary) |

Below the table: the overflow line (what the cap cut), any proposed **deletions** listed separately, and any proposed **memory deletions** flagged for the operator (never auto-delete a memory).

The operator replies with numbers to approve (e.g. "1, 3, 4"). Then implement exactly those: minimal edits, house verification for whatever you touch (skills need `bun run skills:install`; public copy needs the copy gates + `canon-reviewer`; code needs its tests and the deploy watched to green), one commit, and a one-line-per-change report. Auto-apply WITHOUT waiting is permitted only for the mechanically-safe class: typo fixes, dead paths, and factually-stale lines in non-canon files.

## Before you trust anything you added

If a proposal was itself a _detector_ — a new test, guard, hook, or alert meant to catch a failure — prove it fires before trusting it: feed it one synthetic instance of the failure it guards and watch it trip (a known-red input for a CI watcher, a thrown error for an error path). An armed-but-blind detector is indistinguishable from a working one until the day it should have fired and didn't.
