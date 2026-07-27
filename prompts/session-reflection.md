# Session reflection — route the lessons, guard the constitution

You are closing out a working session on this codebase. Your job is to mine what actually happened for durable improvements to how AI agents work here — and to route each lesson to the right home, which is usually NOT another sentence of instructions.

## Ground rules (read first, they bind everything below)

1. **Prose is the last resort.** Every added rule dilutes every existing rule (adherence measurably degrades as instruction files grow). The routing ladder below runs from strongest home to weakest; a lesson lands at the FIRST rung that can hold it, and reaches "standing instruction" only when nothing above it can.
2. **No receipt, no proposal.** Every finding must cite the concrete session moment that earned it: the failed tool call, the user's correction, the wrong deploy, the turns it cost. A lesson you cannot point at did not happen.
3. **One occurrence is an episode, not a rule.** A standing-instruction proposal needs the pattern to have bitten at least twice (in this session, or once here plus a prior memory/doc scar). Single occurrences route to memory at most — or to nothing.
4. **Never regenerate a file.** Propose minimal diffs against curated files (exact old text → new text). Full-file rewrites are how playbooks collapse.
5. **Hard cap: at most 5 proposals**, ranked by expected cost-of-recurrence. If you found more, the overflow dies — mention it in one line, no detail.
6. **Pruning counts as improvement.** Actively hunt deletions: rules now enforced by CI/tests/hooks, stale paths, contradictions, shipped-work references, memories this session proved wrong. The instruction budget should trend flat or down; propose an eviction alongside any addition to an already-long file.
7. **Never propose weakening safety rails, autonomy boundaries, or operator gates** — including for yourself.

## The routing ladder

For each candidate lesson, take the FIRST rung that fits:

| Rung                     | When                                                                                            | Home                                                                                              |
| ------------------------ | ----------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| **Code fix**             | The lesson papers over a real defect                                                            | Fix the code (or file the fix as the proposal)                                                    |
| **Executable guardrail** | Recurring AND mechanically checkable                                                            | A test, lint rule, hook, coverage gate, or CI step — agents can ignore prose, not a red check     |
| **Skill / scoped rule**  | A procedure or gotcha tied to one workflow or one part of the tree                              | The relevant skill in `packages/skills/**` (then `bun run skills:install`), or a path-scoped rule |
| **Memory**               | Narrow, situational, or single-occurrence but worth recall                                      | The persistent memory system (one fact per file, indexed)                                         |
| **Standing instruction** | Broad, durable, un-checkable, ≥2 occurrences, and a new teammate would need it in every session | `AGENTS.md` (or the relevant canon doc) — the rarest outcome                                      |

## What to hold the session against

Read (skim; you know most of it): `CLAUDE.md` → `AGENTS.md`; the skills that were loaded or SHOULD have been loaded this session (`packages/skills/**`); `.claude/agents/*`, `.claude/rules/*`, hooks and settings under `.claude/`; the memory index (`MEMORY.md`); and the CI enforcement points (the deploy gate, the coverage/naming/guardrail tests) — because "could this be a test?" is the question that beats "where do I write this down?".

## Signal sources, in priority order

1. **Explicit user corrections** — every time the operator said "no", "please don't", "why did you…", or fixed your output. These are the highest-grade ore.
2. **Failed tool calls and their recovery cost** — errors that took multiple turns to route around, especially ones a doc/skill claimed wouldn't happen.
3. **Stale guidance hit live** — any instruction, skill line, or memory that was WRONG when followed (these become deletions/corrections, the best kind of finding).
4. **Repeated friction** — anything you did 3+ times by hand that a script/hook/flag should own.
5. **Surprises** — things that worked but only because of undocumented knowledge you happened to have.

## Output

Present ONE ranked table, then stop and wait for ratification:

| # | Lesson (one line) | Receipt (the session moment) | Rung | Proposed change (diff or new-file summary) |

Below the table: the overflow line (what got cut by the cap), any proposed **deletions** listed separately, and any proposed **memory deletions** flagged for the operator (never auto-delete a memory).

The operator replies with numbers to approve (e.g. "1, 3, 4"). Then implement exactly those: minimal edits, house verification for whatever you touch (skills need `skills:install`; public copy needs the copy gates; code needs its tests), one commit, and a one-line-per-change report. Auto-apply WITHOUT waiting is permitted only for the mechanically-safe class: typo fixes, dead paths, and factually-stale lines in non-canon files.
