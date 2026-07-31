#!/usr/bin/env bash
# _hook-json.sh — read a hook payload's fields WITHOUT depending on jq.
#
# Why this exists: both hooks used to parse stdin with `jq -r`, and `jq` is not installed in the
# Hermes container the nightly sweeps run in. Neither script used `set -e`, so the failed command
# substitution yielded an empty `$file`, the next line read that as "no file to check" and exited 0
# — and the guard silently allowed every edit on the box for as long as it had been deployed. The
# hook was not bypassed; it answered "allow" to every question it was asked. A control that fails
# open is indistinguishable from a control that passed, which is exactly why it went unnoticed.
#
# So: prefer `bun` (the repo's mandated runtime, present everywhere Fluncle runs), fall back to
# `node`, fall back to `jq`, and if none is available say so via exit 3 rather than printing
# nothing. Callers decide what an unparseable payload means — the GUARD must treat it as a refusal,
# a FORMATTER may treat it as a no-op.
#
# Emits exactly three lines on success: tool_name, tool_input.file_path, tool_input.command.
# Embedded newlines are folded to spaces so the line structure survives a multi-line command.

hook_read_fields() {
  local prog='try{const d=JSON.parse(require("fs").readFileSync(0,"utf8"));const t=d.tool_input||{};const s=v=>typeof v==="string"?v.replace(/[\r\n]+/g," "):"";process.stdout.write([s(d.tool_name),s(t.file_path),s(t.command)].join("\n"))}catch(e){process.exit(3)}'
  if command -v bun >/dev/null 2>&1; then
    bun -e "${prog}"
  elif command -v node >/dev/null 2>&1; then
    node -e "${prog}"
  elif command -v jq >/dev/null 2>&1; then
    jq -j '[(.tool_name // ""), (.tool_input.file_path // ""), (.tool_input.command // "")] | map(gsub("[\r\n]+"; " ")) | join("\n")'
  else
    return 3
  fi
}
