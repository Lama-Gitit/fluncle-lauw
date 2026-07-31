#!/usr/bin/env bash
# PreToolUse(Edit|Write|Bash): refuse the changes the repo rules forbid by hand.
#
# TWO TIERS, because the same repo is worked by two very different callers.
#
#   ALWAYS — every session, including the operator's own:
#     • Drizzle migrations under apps/web/drizzle/ are GENERATED, never hand-written.
#       Change apps/web/src/db/schema.ts, then `bun run --cwd apps/web db:generate`.
#     • .env / .dev.vars secret files are never edited by an agent (secrets live in 1Password and
#       Cloudflare Worker secrets, not the repo).
#
#   UNATTENDED (FLUNCLE_UNATTENDED=1, exported by the agentic box sweeps) — additionally:
#     • .github/workflows/** and CI config. A workflow edit is a direct route to running arbitrary
#       code with repository secrets, which is why every sweep prompt lists it as a hard rail.
#     • .claude/** — the sweeps' own settings and hooks, so a compromised run cannot disarm the
#       guard it is running under. Interactive sessions are exempt: the operator must be able to
#       edit these files, and if the operator is compromised this hook was never the defence.
#     • apps/web/src/lib/server/orpc-auth.ts — the auth-tier guards the prompts also name.
#
#   Those unattended rails were previously prose in three prompt files and nothing else. The nightly
#   sentry-triage sweep reads ATTACKER-WRITABLE Sentry event bodies (docs/error-tracking.md), and a
#   rail that lives only in a prompt is exactly what a prompt injection is built to talk past. This
#   turns three of them into refusals.
#
# BASH IS MATCHED TOO. The previous version matched only Edit|Write, so `bash -c 'cat > .env'`
# walked straight past it. Under `--dangerously-skip-permissions` (how the sweeps run) the
# settings.json allowlist has no effect, so this hook is the only code left in the path.
#
# Exit 2 blocks the call and feeds stderr back to Claude as the reason.
set -uo pipefail

HOOK_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_hook-json.sh
. "${HOOK_DIR}/_hook-json.sh"

# FAIL CLOSED. An unparseable payload, or a box with no bun/node/jq, must not read as "allow" —
# that is the precise failure this hook shipped with (see _hook-json.sh).
if ! fields="$(hook_read_fields)"; then
  echo "guard-protected-files: cannot read the hook payload (no bun, node, or jq on PATH, or malformed JSON). Refusing the call rather than allowing it unchecked. Install bun in this environment." >&2
  exit 2
fi

tool="$(printf '%s' "$fields" | sed -n '1p')"
file="$(printf '%s' "$fields" | sed -n '2p')"
cmd="$(printf '%s' "$fields" | sed -n '3p')"

unattended=0
[ "${FLUNCLE_UNATTENDED:-}" = "1" ] && unattended=1

deny() {
  echo "$1" >&2
  exit 2
}

MSG_DRIZZLE="Refusing to hand-edit a Drizzle migration. Migrations are generated: edit apps/web/src/db/schema.ts, then run \`bun run --cwd apps/web db:generate\` (AGENTS.md: NEVER write SQL migrations by hand)."
MSG_ENV="Refusing to touch an env/secret file. Fluncle secrets live in 1Password and Cloudflare Worker secrets, not in the repo."
MSG_CI="Refusing to touch CI/workflow config in an unattended run. Every sweep prompt lists .github/workflows/* as a hard rail; a workflow edit runs arbitrary code with repo secrets. File it instead."
MSG_SELF="Refusing to touch .claude/** in an unattended run. That is the guard this run is executing under; a sweep does not get to edit its own rails. File it instead."
MSG_AUTH="Refusing to touch the auth-tier guards in an unattended run. Every sweep prompt lists adminAuth/operatorGuard and the publish boundary as a hard rail. File it instead."

check_path() {
  local p="$1"
  case "$p" in
    */apps/web/drizzle/*.sql | apps/web/drizzle/*.sql | */apps/web/drizzle/meta/* | apps/web/drizzle/meta/*)
      deny "${MSG_DRIZZLE} ($p)"
      ;;
    */.env | */.env.* | .env | .env.* | */.dev.vars | */.dev.vars.* | .dev.vars | .dev.vars.*)
      deny "${MSG_ENV} ($p)"
      ;;
  esac
  [ "$unattended" = "1" ] || return 0
  case "$p" in
    */.github/workflows/* | .github/workflows/*) deny "${MSG_CI} ($p)" ;;
    */.claude/* | .claude/*) deny "${MSG_SELF} ($p)" ;;
    */lib/server/orpc-auth.ts) deny "${MSG_AUTH} ($p)" ;;
  esac
}

case "$tool" in
  Edit | Write | NotebookEdit)
    [ -n "$file" ] && check_path "$file"
    ;;
  Bash)
    [ -n "$cmd" ] || exit 0
    # Bash reaches these paths through a command string, not a file_path field, so match the string.
    # `[[ =~ ]]` is bash-native: no grep, no second dependency that can be missing from a container.
    # The leading class must ALLOW `/` and `.` — a real target is `/ws/.env`, and excluding the
    # slash meant the pattern matched a bare `.env` but not any actual path (caught by the test
    # "a shell redirection into a protected path is refused"). It still excludes alphanumerics and
    # `-` so `--env-file` and `myfile.env` do not trip it; the trailing class is what keeps
    # `.environment` out.
    protected_re='(^|[^[:alnum:]_-])(\.env|\.dev\.vars)([^[:alnum:]_.-]|$)|apps/web/drizzle/'
    # Interactively only a WRITE is refused — reading a local .env while debugging is the operator's
    # business. Unattended, ANY reference is refused: a sweep has no reason to read a secrets file,
    # and reading it is the first half of exfiltrating it.
    # Spelled with explicit boundaries rather than `\b`, which is a GNU extension to POSIX ERE and
    # not dependable across the bash builds this repo runs on (macOS 3.2 through the container's 5.x).
    write_re='(>)|(^|[^[:alnum:]_-])(tee|cp|mv|install|dd|truncate|rm)([^[:alnum:]_-]|$)|(^|[^[:alnum:]_-])sed([^|]*)-i'
    if [[ $cmd =~ $protected_re ]]; then
      if [ "$unattended" = "1" ]; then
        deny "${MSG_ENV} / ${MSG_DRIZZLE} — refused via Bash in an unattended run."
      elif [[ $cmd =~ $write_re ]]; then
        deny "${MSG_ENV} / ${MSG_DRIZZLE} — refused: this Bash command writes to a protected path."
      fi
    fi
    if [ "$unattended" = "1" ]; then
      [[ $cmd =~ \.github/workflows/ ]] && deny "${MSG_CI}"
      [[ $cmd =~ (^|[^[:alnum:]_-])\.claude/ ]] && deny "${MSG_SELF}"
      [[ $cmd =~ orpc-auth\.ts ]] && deny "${MSG_AUTH}"
    fi
    ;;
esac

exit 0
