# Plan: wire the Go packages' vet and format checks into the root gate

Ruled (operator, this plan): WIRE the checks in — do not merely document the gap. Today the root `lint` script is bare oxlint (no turbo), so `bun run check` and `deploy:gate` never execute `apps/ssh` and `apps/dns`'s `lint` (`go vet ./...`) or any gofmt check, while their `test`/`typecheck` already ride `turbo run test`/`turbo run typecheck`. CI runs vet/gofmt as dedicated steps (`.github/workflows/quality-checks.yml` ~lines 122–140), and the deploy runner demonstrably has Go (go test rides `deploy:gate` via turbo), so the wiring is feasible on both gates.

## The change

1. Add a `format:check` script to both Go packages (`apps/ssh/package.json`, `apps/dns/package.json`) implementing the CI shape: fail when `gofmt -l .` lists anything (the existing `format` script stays the write-mode fixer).
2. Wire both packages' `lint` and the new `format:check` into the root contract so `bun run check` AND `deploy:gate` exercise them. Prefer the smallest structural change consistent with how the repo already runs turbo tasks (e.g. a turbo task the root scripts invoke); do not convert the root oxlint invocation itself into a turbo task unless that is genuinely the cleanest fit — the goal is additive coverage, not a lint-pipeline refactor.
3. Update the AGENTS.md "External Effects" paragraph that currently records the gap ("the Go apps' gofmt/go vet … the fmt/vet steps are CI-only") to state the new contract instead.
4. Prove the tripwire: temporarily introduce a gofmt violation and a vet violation in a scratch file, confirm the chosen root command fails on each, then remove the fixtures (do not commit them).

## Acceptance

- A failing `gofmt` fixture and a failing `go vet` fixture are each detected by the root-level command (demonstrated in the worker's report, fixtures not committed).
- `bun run check` and `bun run deploy:gate` pass from the repo root with both Go packages included.
- `.github/workflows/quality-checks.yml` is left unchanged (its dedicated steps remain the PR-time net; this change extends the root/deploy gate).
- AGENTS.md's description matches the shipped contract.
