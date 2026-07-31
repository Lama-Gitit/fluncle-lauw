#!/usr/bin/env bash
# PostToolUse(Edit|Write): format the file Claude just touched, in Fluncle's house style.
# oxfmt owns JS/TS formatting (never prettier — see AGENTS.md); gofmt owns apps/ssh Go.
# Always exits 0: formatting is best-effort and must never block or redact an edit.
#
# Unlike its guard sibling this one SHOULD fail open — a formatter that refuses an edit because it
# could not parse a payload would be worse than a file that stays unformatted. It shares the
# jq-free reader only so a container without jq stops silently skipping every format (which is what
# was happening on the box; the guard's version of that bug was the dangerous one).
set -uo pipefail

HOOK_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_hook-json.sh
. "${HOOK_DIR}/_hook-json.sh"

fields="$(hook_read_fields)" || exit 0
file="$(printf '%s' "$fields" | sed -n '2p')"
[ -z "$file" ] && exit 0
[ -f "$file" ] || exit 0

case "$file" in
  *.ts | *.tsx | *.js | *.jsx | *.mjs | *.cjs)
    bunx oxfmt --write "$file" >/dev/null 2>&1 || true
    bunx oxlint --fix "$file" >/dev/null 2>&1 || true
    ;;
  *.go)
    gofmt -w "$file" >/dev/null 2>&1 || true
    ;;
esac

exit 0
