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
# care about the distinction.
#
# It is a latent problem for a sweep whose input is the repo, and a live one for `sentry-triage`,
# whose input is an ATTACKER-WRITABLE Sentry event body: anyone holding the public ingest DSN can
# write the text that lands in that prompt (docs/error-tracking.md → "Nightly triage"). This helper
# is the code that makes the claim true, so the rails stop being only prose.
#
# HOW
# Read the KEY NAMES out of the secrets file itself and turn each into an `env -u NAME` argument.
# Deriving the list from the file — rather than hardcoding today's keys — is the point: a key added
# to the file next month is scrubbed automatically, with no second list to keep in sync. Only the
# short allowlist below survives.
#
# THE SURVIVORS, and why each must be one:
#   CLAUDE_CODE_OAUTH_TOKEN — the subscription auth the `claude` binary itself runs on.
#   GH_TOKEN                — the agent opens its own PRs, so it needs this capability by design.
#                             Note honestly: the drivers export GH_TOKEN from FLUNCLE_AUDIT_GITHUB_PAT,
#                             so scrubbing the PAT's own name removes the DUPLICATE, not the value.
#                             Narrowing what that token can do is a GitHub-side change (branch
#                             protection + a finer-grained PAT), not something this file can reach.
#
# KNOWN RESIDUAL: a credential that lives in a FILE rather than an env var is untouched by `env -u`.
# `GOOGLE_APPLICATION_CREDENTIALS` is the live example — scrubbing the variable hides the pointer,
# but `~/.fluncle-gsc.json` is still readable on disk by anything running as this user. Pass such
# names as extra arguments anyway (defence in depth); the durable fix is not to leave the file
# mounted where an agentic sweep runs.
#
# USAGE
#   . "${SCRIPT_DIR}/agent-env.sh"
#   agent_env_scrub_args "${SECRETS_FILE}" [EXTRA_NAME …]
#   env ${AGENT_ENV_SCRUB[@]+"${AGENT_ENV_SCRUB[@]}"} "$(command -v claude)" -p "${prompt}" …
#
# The `${arr[@]+"${arr[@]}"}` form is required: these drivers run under `set -u`, where a bare
# `"${arr[@]}"` on an EMPTY array is an unbound-variable error on older bash.

# Populates the global array AGENT_ENV_SCRUB with `-u NAME` pairs. Bash cannot return an array, so
# the global is the interface; it is reset on every call, never appended across calls.
agent_env_scrub_args() {
  local secrets_file="${1:-}"
  shift || true
  local key
  AGENT_ENV_SCRUB=()

  # Extra names the caller knows are sensitive but that the secrets file does not define.
  for key in "$@"; do
    AGENT_ENV_SCRUB+=(-u "${key}")
  done

  [ -n "${secrets_file}" ] && [ -r "${secrets_file}" ] || return 0

  # Match `KEY=…` and `export KEY=…`, ignoring comments and blank lines. Only the NAME is read;
  # no value is ever expanded, printed, or logged.
  while IFS= read -r key; do
    case "${key}" in
      # The allowlist. Keep it this short.
      CLAUDE_CODE_OAUTH_TOKEN | GH_TOKEN) continue ;;
    esac
    AGENT_ENV_SCRUB+=(-u "${key}")
  done < <(sed -n 's/^[[:space:]]*\(export[[:space:]]\{1,\}\)\{0,1\}\([A-Za-z_][A-Za-z0-9_]*\)=.*/\2/p' "${secrets_file}")
}
