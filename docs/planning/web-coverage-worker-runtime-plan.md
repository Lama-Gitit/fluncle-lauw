# Plan: make the web coverage gate runnable in worker shells

`apps/web`'s `test` script is `vitest run --coverage`, and `@vitest/coverage-v8` imports Node-only inspector/module-hook APIs. In a bun-first headless worker shell the coverage provider aborts and thresholds read as zero, so local evidence and CI evidence (Node runner, green) disagree about the same command. The fix is one canonical invocation that works identically in both places.

## The change

1. Make the documented `apps/web` test/coverage invocation run under Node explicitly wherever coverage is collected — e.g. the package script invokes the vitest binary through Node rather than relying on the ambient shell runtime, or a dedicated `test:coverage` script does so with plain `test` staying runtime-agnostic. Investigate which shape the repo's script conventions and turbo pipeline prefer before choosing; the constraint is that the SAME command a CI step runs is the one a worker shell runs, with the coverage ratchet floors in `vitest.config.ts` actually measured.
2. Verify the ratchet floors still gate: a run must report real coverage numbers (non-zero) and fail if a floor is violated.
3. If any turbo task or CI step names the old invocation, update it in the same change so there is exactly one canonical spelling.

## Acceptance

- The documented coverage command completes under a bun-only login shell (no ambient Node assumption) and reports measured, non-zero coverage with the thresholds enforced.
- `turbo run test` (the root gate) and the `quality-checks` CI workflow remain green with no coverage regression.
- The chosen invocation is the single spelling used by package script, turbo, and CI alike.
