#!/usr/bin/env bash
# agent-env.sh — strip the box's credential set from an agentic `claude -p` child.
#
# THE PROBLEM THIS EXISTS FOR
# Every sweep loads the shared 0600 secrets file with `set -a` … `. "${SECRETS_FILE}"` … `set +a`.
# `set -a` marks each key it defines for EXPORT, so a `claude -p` launched from that same shell
# inherits the entire box credential set — the Sentry token, the read-only prod Turso pair, the R2
# access keys, the Gemini/Apify keys, the agent-scoped Fluncle API token — none of which any
# agentic sweep needs. Three drivers claimed in comments that a given token "never enters the claude
# process"; that was true of the ARGUMENTS and false of the ENVIRONMENT, and `printenv` does not
# care about the distinction. The audit's own prompt made the same false promise about Turso
# ("Turso Cloud credentials are not on this box" — prompts/db-query-shape.md), while the shared file
# carried the read-only pair for backup-sweep. This helper is what makes those claims true.
#
# It is a latent problem for a sweep whose input is the repo, and a live one for `sentry-triage`,
# whose input is an ATTACKER-WRITABLE Sentry event body: anyone holding the public ingest DSN can
# write the text that lands in that prompt (docs/error-tracking.md → "Nightly triage").
#
# WHY THE ALLOWLIST IS PER-CALLER, NOT GLOBAL
# The first version of this file hardcoded one allowlist for every sweep. That is a footgun: the day
# one sweep legitimately needs a credential — say a db-query-shape night that finally gets a hosted
# scratch DB — the natural fix is to widen the list here, which silently hands that same credential
# to `sentry-triage`, the one sweep reading attacker-written text. Capability must grow for ONE
# caller without growing for its neighbours, so each driver DECLARES what its agent may keep:
#
#   agent_env_scrub_args --secrets "${SECRETS_FILE}" --allow GH_TOKEN
#
# Anything not declared is scrubbed. The default is deny; the declaration is the audit trail.
#
# The one implicit survivor is CLAUDE_CODE_OAUTH_TOKEN — the auth the `claude` binary itself runs
# on, not a service credential. A sweep that scrubbed it could not start, so varying it per caller
# buys no safety and only invites a 03:30 breakage. Every genuine CAPABILITY is declared.
#
# WHY IT ANNOUNCES ITSELF
# A scrubbed credential fails at 03:30 inside steps that swallow errors (`|| log …`), where "denied
# a credential" and "the API was down" look identical in the journal. So this logs the names it
# stripped and the ones it kept — NAMES ONLY, never values — so the line sits directly above
# whatever failed and the operator can tell the two apart at a glance.
#
# KNOWN RESIDUALS, stated rather than implied:
#   • GH_TOKEN's capability is inherent — the agent opens its own PRs. Scrubbing the PAT's other
#     name (FLUNCLE_AUDIT_GITHUB_PAT) removes the duplicate, not the power. Narrowing that is a
#     GitHub-side change: branch protection plus a finer-grained PAT.
#   • A credential that lives in a FILE is untouched by `env -u`. `GOOGLE_APPLICATION_CREDENTIALS`
#     is the live example: scrubbing the variable hides the pointer, but `~/.fluncle-gsc.json` is
#     still readable by anything running as this user. Pass such names via `--scrub` anyway
#     (defence in depth); the durable fix is not to leave the file where an agentic sweep runs.
#
# USAGE
#   . "${SCRIPT_DIR}/agent-env.sh"
#   agent_env_scrub_args --secrets "${SECRETS_FILE}" [--allow NAME]… [--scrub NAME]…
#   env ${AGENT_ENV_SCRUB[@]+"${AGENT_ENV_SCRUB[@]}"} "$(command -v claude)" -p "${prompt}" …
#
# The `${arr[@]+"${arr[@]}"}` form is required: these drivers run under `set -u`, where a bare
# `"${arr[@]}"` on an EMPTY array is an unbound-variable error on older bash.

# The auth the `claude` binary runs on. Not a service credential, and not per-caller — see above.
AGENT_ENV_ALWAYS_ALLOW="CLAUDE_CODE_OAUTH_TOKEN"

# Populates the global array AGENT_ENV_SCRUB with `-u NAME` pairs. Bash cannot return an array, so
# the global is the interface; it is reset on every call, never appended across calls.
agent_env_scrub_args() {
  local secrets_file=""
  local allow=" ${AGENT_ENV_ALWAYS_ALLOW} "
  local extra=""
  local key kept=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --secrets)
        secrets_file="${2:-}"
        shift 2
        ;;
      --allow)
        allow="${allow}${2:-} "
        shift 2
        ;;
      --scrub)
        extra="${extra}${2:-} "
        shift 2
        ;;
      *)
        echo "[agent-env] ignoring unknown argument: $1" >&2
        shift
        ;;
    esac
  done

  AGENT_ENV_SCRUB=()
  local scrubbed=""

  # Names the caller flagged as sensitive that the secrets file does not itself define.
  for key in ${extra}; do
    AGENT_ENV_SCRUB+=(-u "${key}")
    scrubbed="${scrubbed}${key} "
  done

  if [ -n "${secrets_file}" ] && [ -r "${secrets_file}" ]; then
    # Match `KEY=…` and `export KEY=…`, ignoring comments and blank lines. Only the NAME is read;
    # no value is ever expanded, printed, or logged.
    while IFS= read -r key; do
      case "${allow}" in
        *" ${key} "*)
          kept="${kept}${key} "
          continue
          ;;
      esac
      AGENT_ENV_SCRUB+=(-u "${key}")
      scrubbed="${scrubbed}${key} "
    done < <(sed -n 's/^[[:space:]]*\(export[[:space:]]\{1,\}\)\{0,1\}\([A-Za-z_][A-Za-z0-9_]*\)=.*/\2/p' "${secrets_file}")
  fi

  # NAMES ONLY. This line is the difference between a diagnosable 03:30 failure and a mystery.
  echo "[agent-env] kept: ${kept:-<none>}| scrubbed: ${scrubbed:-<none>}" >&2
}
