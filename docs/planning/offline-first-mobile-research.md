# Offline-first mobile — research notes (2026-07-29)

Non-canonical planning input for the offline-first mobile RFC (ROADMAP § _Offline-first mobile_). Agent-researched 2026-07-29 against Expo SDK 56 / the app as shipped at 1.0 approval; verify versions before building. The RFC session consumes this; it decides nothing by itself.

## The runtime path — the answer is `expo-sqlite`

- **`expo-sqlite` (SDK 56, `~56.0.5`) ships libSQL support natively**: `useLibSQL` ("Use libSQL rather than the default SQLite") and `syncLibSQL()` ("Synchronize the local database with the remote libSQL server"), documented in the SDK-56-versioned docs, present in `expo@56.0.17`'s `bundledNativeModules.json`. Also in SDK 56: `expo-sqlite/kv-store` (a SQLite-backed drop-in AsyncStorage replacement with sync variants + a `localStorage` polyfill), `addDatabaseChangeListener()` behind `enableChangeListener: true`, `backupDatabaseAsync()`. NOT present: `sqlite3_rsync`, custom VFS, CR-SQLite.
- **libSQL's status makes this safe, not stale**: the `tursodatabase/libsql` README states "Turso database and libSQL are two different projects from the same team… libSQL is actively maintained, but new features are being developed in Turso." Feature-frozen in direction, maintained — the branch you want under a shipping app.
- **`@libsql/client` cannot run on React Native.** Its exports map has no `react-native` condition; Metro resolves to the Node build, which pulls a native N-API addon Hermes cannot load. `@libsql/client/web` is hrana-over-network only (throws `URL_SCHEME_NOT_SUPPORTED` for `file:`) — no local DB, no replica, no offline.
- **Turso's own RN bindings are undocumented**: the full `turso-docs` tree (451 files) has no `sdk/react-native/` and `docs.turso.tech/sdk/react-native` 404s; the 2026-01-29 announcement lists the Expo plugin as a ROADMAP item, beside Partial Sync and Real-time Subscriptions. Do not assume an RN capability from a Turso docs page; check the RN binding's README for that version.
- **op-sqlite** (the fallback): libSQL/Turso are BUILD-TIME flags in the root `package.json` (`"op-sqlite": { "libsql": true }` — the sync param is `url`, not `syncUrl`), and enabling them COSTS features: multiple statements per string, update/commit/rollback hooks, **reactive queries**, extension loading, local disk-encryption, custom tokenizers; SQLCipher is mutually exclusive. A one-way door — decide before, not after. UNVERIFIED: SDK 56 compatibility (peers are `react: *`), bundle size, New-Arch support as a stated claim.
- **The alternatives are out**: CR-SQLite (0 commits in 365 days; op-sqlite's `crsqlite` flag points at a corpse), WatermelonDB (New-Arch/SDK-54+ status issue open since 2026-06-05, zero comments), Legend-State (v3 beta 22 months, peers `expo-sqlite ^15` — five SDK generations behind), Zero (peers `react ^19.2.6`; the app is on 19.2.3), Electric (now read-path-for-Postgres only), PowerSync (Postgres/Mongo/MySQL sources only), TanStack DB (RN adapters peer stale majors; `localStorageCollectionOptions` silently degrades to in-memory on RN; no durable offline mutation queue — watch, don't build on). Also: there is no TanStack Query v6 for React — `@tanstack/react-query` latest is 5.x; the v6 packument is the Svelte adapter.

## Turso sync mechanics (as of mid-2026)

- Conflict posture on `pull()` with unpushed local changes is a **rebase**: roll local back to last synced state, apply remote, atomically replay local on top. Not per-field merge — the user-data union-merge law still needs app-level merge logic on top.
- `bootstrapIfEmpty` / partial sync / checkpoints exist in the TS/Go/Python docs; their availability IN THE RN BINDING specifically is UNVERIFIED.
- **The RFC's first de-risking spike, named:** `syncLibSQL()` against a live Turso database on a real device. Nobody has verified it; the whole architecture leans on it.

## The offline write path (TanStack Query persist) — the spec

All four persist packages ship in lockstep at 5.101.4 (2026-07-21); `react-query-persist-client` peers `react ^18 || ^19` (19.2.3 in range). The trap that bites first: **`onlineManager` starts `online: true` and only flips on events** — without a seed the app believes it is online forever. `expo-network` is already pinned (`apps/mobile/package.json:41`) and unimported; seed via `Network.getNetworkStateAsync()` + `addNetworkStateListener`, pair `focusManager` with `AppState` (guard `Platform.OS !== "web"`).

Queue-and-replay shape: `PersistQueryClientProvider` with `maxAge` ≤ query `gcTime`, `buster: BUILD_SHA`, `onSuccess: () => queryClient.resumePausedMutations()`, and `setMutationDefaults` per mutation key. The ten doc-backed gotchas:

1. `mutationFn` must be re-registered via `setMutationDefaults` before restore ("No mutationFn found" after hydration is a documented limitation).
2. Mutation `variables` must be JSON-serializable (no `Date`/`File`/`FormData`).
3. `shouldDehydrateMutation` already defaults to paused-mutations-only.
4. Errors are redacted by default on dehydrate.
5. The provider's `onSuccess` is the only documented "restore finished" hook — resuming earlier races the restore.
6. Callbacks passed to `mutate(vars, {…})` never fire on replay; replay-critical effects go in `setMutationDefaults`.
7. Replays preserve order but run in parallel — `scope: { id }` serializes.
8. `maxAge` discards silently — a stale queue vanishes with no error.
9. `status: 'pending'` + `fetchStatus: 'paused'` is a real state — a spinner keyed only on `isPending` spins forever offline (named regression risk against `apps/mobile`'s `archive-state.ts` four-view branch).
10. `useIsRestoring` is exported from `@tanstack/react-query`, not the persist package.

Storage: the persister's storage interface is structural, so `expo-sqlite/kv-store` fits — but the docs name only `@react-native-async-storage/async-storage` (SDK 56 pins 2.2.0, which the app has).

## Slices (recommendation shape, not a decision)

- **Slice 0 — offline resilience, no DB**: onlineManager/focusManager seeding + persisted query cache + paused-mutation replay. Cheapest, ships value alone.
- **Slice 1 — device stores onto SQLite**: `saved.ts` / `mix.ts` move from AsyncStorage to `expo-sqlite/kv-store` — close to an import swap given the existing pure/wiring split.
- **Slice 2 — the synced replica**: `useLibSQL` + `syncLibSQL()` against a public-catalogue slice (server-authoritative), user data union-merged at app level. GATED on the device spike, on the RN-binding capability verification, and on a sizing pass (the MuQ embedding blobs must never ship to devices).

## Open decisions for the operator

- One shared read replica vs per-user DBs (Turso multi-DB cost at 2026 pricing — unresearched).
- The op-sqlite one-way door (reactive queries / SQLCipher lost with libSQL) if ever preferred over expo-sqlite.
- Whether slice 0+1 ship inside the 1.1 arc or after it.

## Carried-forward UNVERIFIED list

op-sqlite SDK-56 compat + bundle size + New-Arch statement; `useLibSQL` in Expo Go; RN-binding availability of `bootstrapIfEmpty`/partial sync/checkpoints; TanStack DB RN adapters against current majors; Legend-State v3 on modern expo-sqlite; and the device `syncLibSQL()` spike itself.
