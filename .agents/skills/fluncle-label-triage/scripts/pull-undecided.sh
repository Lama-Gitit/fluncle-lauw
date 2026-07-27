#!/usr/bin/env bash
# pull-undecided.sh — the label-triage pass's data pull (fluncle-label-triage skill, step 1).
#
# Emits (to stdout) a JSON array of every `undecided` label with its mb_label_id + stored-track
# count, and refreshes calib-enabled.txt / calib-disabled.txt (in CWD) from the LIVE rulings.
# The DB read is REQUIRED — the admin labels API does not carry mb_label_id on the wire, and the
# MBID is what lets a research agent hit the EXACT MusicBrainz entity instead of a same-named label.
#
#   pull-undecided.sh [--exclude held-slugs.txt] > undecided.json
#
# --exclude: one slug per line — labels the operator is holding for their own ear (prior rounds'
# `unclear`). Optional; re-triaging a held label is harmless (it comes back unclear again).
#
# SECRETS: prod Turso creds resolve through `op` via the FLUNCLE_TURSO_OP_ITEM indirection var
# (the open-source posture — no concrete op:// path in this public script). Read-only by
# construction: this script only ever SELECTs.
set -euo pipefail

EXCLUDE=""
if [ "${1:-}" = "--exclude" ]; then
  EXCLUDE="${2:?--exclude needs a file}"
fi

: "${FLUNCLE_TURSO_OP_ITEM:?set FLUNCLE_TURSO_OP_ITEM (see the private ops runbook)}"
URL="$(op read "${FLUNCLE_TURSO_OP_ITEM}/TURSO_DATABASE_URL")"
TOK="$(op read "${FLUNCLE_TURSO_OP_ITEM}/TURSO_AUTH_TOKEN")"
HTTP="https://${URL#libsql://}"

query() {
  python3 - "$HTTP" "$TOK" "$1" <<'PY'
import json, sys, urllib.request
http, tok, sql = sys.argv[1], sys.argv[2], sys.argv[3]
body = {"requests": [{"type": "execute", "stmt": {"sql": sql}}, {"type": "close"}]}
req = urllib.request.Request(http.rstrip('/') + "/v2/pipeline", data=json.dumps(body).encode(),
    method="POST", headers={"Authorization": f"Bearer {tok}", "Content-Type": "application/json"})
r0 = json.load(urllib.request.urlopen(req, timeout=90))["results"][0]
if r0.get("type") != "ok":
    print("QUERY ERROR:", json.dumps(r0)[:300], file=sys.stderr); raise SystemExit(1)
rs = r0["response"]["result"]
cols = [c["name"] for c in rs["cols"]]
rows = [{c: (None if v.get("type") == "null" else v.get("value")) for c, v in zip(cols, row)}
        for row in rs["rows"]]
print(json.dumps(rows))
PY
}

# The pile, with the load-bearing MBID + how many rows already point at each label.
UNDECIDED="$(query "select l.name, l.slug, l.mb_label_id, count(t.track_id) as track_rows
from labels l left join tracks t on t.label_id = l.id
where l.seed_state = 'undecided'
group by l.id order by l.name")"

# The calibration — the operator's LIVE boundary, refreshed every pass (it moves every round).
query "select seed_state, name from labels where seed_state in ('enabled','disabled') order by seed_state, name" \
  | python3 -c "
import json, sys
d = json.load(sys.stdin)
en = [r['name'] for r in d if r['seed_state'] == 'enabled']
di = [r['name'] for r in d if r['seed_state'] == 'disabled']
open('calib-enabled.txt', 'w').write('\n'.join(en))
open('calib-disabled.txt', 'w').write('\n'.join(di))
print(f'calibration: {len(en)} enabled / {len(di)} disabled', file=sys.stderr)
"

printf '%s' "$UNDECIDED" | python3 -c "
import json, sys
rows = json.load(sys.stdin)
exclude = set()
path = '''$EXCLUDE'''
if path:
    exclude = {l.strip() for l in open(path) if l.strip()}
fresh = [r for r in rows if r['slug'] not in exclude]
print(f'undecided: {len(rows)} | excluded (held): {len(rows)-len(fresh)} | to triage: {len(fresh)}', file=sys.stderr)
json.dump(fresh, sys.stdout, indent=0)
"
