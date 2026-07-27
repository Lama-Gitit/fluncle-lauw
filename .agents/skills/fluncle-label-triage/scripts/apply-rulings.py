#!/usr/bin/env python3
"""Apply a label-triage round's operator-RATIFIED rulings (fluncle-label-triage skill, step 4).

Reads the staged verdicts (label-triage.json in CWD: the triage workflow's result object) and
applies `dnb` -> enabled, `not_dnb` -> disabled through the operator-tier `update_label` op.
`unclear` rows are NEVER touched -- they stay undecided for the operator's own ear.

    apply-rulings.py pilot     # ONE write, verify the round-trip, exit
    apply-rulings.py apply     # the rest

Safety shape, learned over four live rounds (2026-07-26/27):
  - Only rows the server STILL lists as `undecided` are written (other sessions and the operator
    rule labels too; a slug that moved since the triage is skipped and reported, never clobbered).
  - Idempotent: a second `apply` finds nothing left in-plan and writes zero rows.
  - The API sits behind Cloudflare, which 1010-rejects the default Python-urllib signature --
    every request carries a real User-Agent.
Needs FLUNCLE_API_TOKEN (operator) + FLUNCLE_API_BASE_URL in the env (`set -a; source ...`).
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

MODE = sys.argv[1] if len(sys.argv) > 1 else "pilot"
BASE = os.environ["FLUNCLE_API_BASE_URL"].rstrip("/")
TOK = os.environ["FLUNCLE_API_TOKEN"]


def call(method: str, path: str, body=None):
    req = urllib.request.Request(
        BASE + path,
        method=method,
        data=json.dumps(body).encode() if body else None,
        headers={
            "Authorization": f"Bearer {TOK}",
            "Content-Type": "application/json",
            # Cloudflare 1010s the default Python-urllib signature -- send a real UA.
            "User-Agent": "fluncle-label-triage/1.0 (operator)",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=45) as r:
            return r.status, json.load(r)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:200]


# slug -> id and CURRENT state, straight from the server (never a stale local list).
status, live = call("GET", "/api/v1/admin/labels?seedState=undecided")
assert status == 200, f"list failed: {status} {live}"
rows = live["labels"] if isinstance(live, dict) else live
undecided = {r["slug"]: r["id"] for r in rows}
print(f"server says undecided: {len(undecided)}")

triage = json.load(open("label-triage.json"))
plan = [
    (r["slug"], r["name"], state)
    for bucket, state in (("dnb", "enabled"), ("not_dnb", "disabled"))
    for r in triage[bucket]
]

missing = [s for s, _, _ in plan if s not in undecided]
if missing:
    print(f"SKIPPING {len(missing)} no longer undecided: {missing[:5]}")
plan = [(s, n, st) for s, n, st in plan if s in undecided]

unclear = {r["slug"] for r in triage["unclear"]}
assert not (unclear & {s for s, _, _ in plan}), "unclear leaked into the plan"
print(
    f"plan: {sum(1 for p in plan if p[2] == 'enabled')} enable, "
    f"{sum(1 for p in plan if p[2] == 'disabled')} disable, "
    f"{len(unclear)} left undecided"
)

if not plan:
    print("nothing to apply")
    sys.exit(0)

if MODE == "pilot":
    slug, name, state = plan[0]
    print(f"\nPILOT -> {name} ({slug}) => {state}")
    code, res = call("PATCH", f"/api/v1/admin/labels/{undecided[slug]}", {"seedState": state})
    print("  status:", code)
    got = (res.get("label") or {}).get("seedState") if isinstance(res, dict) else res
    print("  seedState now:", got)
    sys.exit(0 if got == state else 1)

ok = fail = 0
failures = []
for i, (slug, name, state) in enumerate(plan, 1):
    code, res = call("PATCH", f"/api/v1/admin/labels/{undecided[slug]}", {"seedState": state})
    got = (res.get("label") or {}).get("seedState") if isinstance(res, dict) else None
    if code == 200 and got == state:
        ok += 1
    else:
        fail += 1
        failures.append((slug, code, str(res)[:90]))
    if i % 25 == 0 or i == len(plan):
        print(f"  {i}/{len(plan)}  ok={ok} fail={fail}")
    time.sleep(0.12)

print(f"\nDONE ok={ok} fail={fail}")
for f in failures[:10]:
    print("  FAILED", f)
sys.exit(1 if fail else 0)
