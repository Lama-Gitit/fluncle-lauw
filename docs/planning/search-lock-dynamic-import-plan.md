# Plan: the read-path lock learns dynamic track-search imports

The Spotify read-path lock (`apps/web/src/lib/server/search-consumers.test.ts`) holds five `SPOTIFY_OP_MARKERS`; the fifth (added for the server-side import shape) is deliberately `from`-shaped — `/from ["'][^"']*\/track-search["']/` — so a dynamic `import("…/track-search")` inside a server handler contains no `from` and evades the lock entirely. This matters because the dynamic-import-inside-`createServerFn().handler()` body is the repository's _documented_ client-bundle pattern (docs/client-bundle.md), so the evasion sits on a path the codebase actively encourages.

## The change

Add a sixth, dynamic-import-shaped marker to `SPOTIFY_OP_MARKERS`: it must match `import(` followed by a string literal resolving to `lib/server/track-search` in any of the same spellings the static marker accepts (relative at any depth, or the `@/` alias), tolerating whitespace between `import` and the parenthesis and inside the call. It must NOT match prose (a comment mentioning track-search), non-import parentheses, or dynamic imports of unrelated modules. Mirror the existing marker's comment discipline: state what the marker covers and why it is shaped the way it is.

The allowlist semantics are unchanged: the same `SUBMIT_FLOW_ALLOWLIST` files remain the only legitimate holders; a dynamic import from any other file under the four `SOURCE_ROOTS` fails the lock.

## Acceptance

- The focused test file passes: `cd apps/web && bunx vitest run src/lib/server/search-consumers.test.ts`.
- A demonstration: a temporary mock route/server file using `await import("@/lib/server/track-search")` (and one using a relative spelling) trips the lock; the test's own fixture-style verification or an in-test string probe of the marker regexes is acceptable in place of committing a mock file.
- No false positive on the existing tree (the marker added must not flag any currently-allowlisted or unrelated file).
- `bun run check` stays green from the repo root.
