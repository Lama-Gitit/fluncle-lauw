#!/usr/bin/env bash
# fluncle-timer-watchdog — the rave-02 host guard against a systemd timer that reports
# `active` but will never fire again.
#
# ── THE FAILURE IT CATCHES (observed 2026-07-28: seven sweeps dead 13h, zero alerts) ──
# Every sweep timer on this box fires ONCE on `OnBootSec` and then rides
# `OnUnitActiveSec=<period>`, which systemd measures from the SERVICE's last activation.
# Stop such a timer before its one-shot boot fire and start it again afterwards and it can
# be left with no reference point at all: `NextElapse` becomes `infinity` and the sweep
# never runs again.
#
# `Persistent=true` is what makes it permanent, opposite to the intuition: it writes a
# stamp file, and on a fresh start systemd reads that stamp as the last trigger and so
# treats the one-shot `OnBootSec` as already satisfied, declining to re-fire it.
# `OnUnitActiveSec` then waits on a service activation that only the timer could produce.
# Reproduced all three ways on the box 2026-07-29 — see the README table.
#
# It happened when an unattended kernel-upgrade reboot (12:19 UTC) landed inside the
# pin-watch rebake quiesce window (timers stopped 12:29, restored 12:35): every timer
# whose boot fire was due in that gap came back active-but-dead. `systemctl is-active`
# said active, the last service result said success, and all 43 timers looked healthy —
# the damage was visible ONLY in `NextElapse`, which nothing read. rebuild-hermes.sh now
# re-arms on the restore path (prevention); this is the independent net (detection), and
# it catches the same stranding from ANY cause — an installer re-run shortly after boot,
# a manual `systemctl stop`, a crash mid-quiesce.
#
# Runs on `OnCalendar`, deliberately: a calendar timer always carries a realtime next
# elapse, so the watchdog cannot itself fall into the hole it is watching for.
set -uo pipefail

SELF_TIMER="fluncle-timer-watchdog.timer"
CONTAINER="${HERMES_CONTAINER:-hermes}"
# Seconds between the first sighting and the confirming re-check. A timer parks at
# `infinity` for the instant its service is being reaped, so acting on a single sample
# would occasionally kick a perfectly healthy sweep.
RECHECK_DELAY="${TIMER_WATCHDOG_RECHECK_DELAY:-5}"

log() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*"; }

# No armed trigger: monotonic elapse `infinity` AND no realtime elapse at all. A calendar
# timer always reports a realtime elapse, so this stays false for a healthy one.
has_no_next_elapse() {
  local mono real
  mono="$(systemctl show "$1" -p NextElapseUSecMonotonic --value 2>/dev/null)"
  real="$(systemctl show "$1" -p NextElapseUSecRealtime --value 2>/dev/null)"
  [ "$mono" = "infinity" ] && [ -z "$real" ]
}

# A oneshot service mid-tick legitimately parks its own timer at `infinity` until it
# finishes. That is a BUSY timer, not a stranded one — never kick it.
service_busy() {
  case "$(systemctl show "$1" -p ActiveState --value 2>/dev/null)" in
    active | activating | reloading | deactivating) return 0 ;;
  esac
  return 1
}

# Every fluncle sweep timer, PLUS pin-watch (outside the fluncle-* glob and the one whose
# stranding would silently stop the box self-deploying). Exclude ourselves.
list_timers() {
  {
    systemctl list-units --type=timer --state=active --no-legend --plain 'fluncle-*.timer' 2>/dev/null | awk '{print $1}'
    systemctl list-units --type=timer --state=active --no-legend --plain 'pin-watch.timer' 2>/dev/null | awk '{print $1}'
  } | grep -vxF "$SELF_TIMER" | sort -u
}

suspects=()
while IFS= read -r timer; do
  [ -n "$timer" ] || continue
  service="${timer%.timer}.service"
  has_no_next_elapse "$timer" || continue
  service_busy "$service" && continue
  suspects+=("$timer")
done < <(list_timers)

if [ "${#suspects[@]}" -eq 0 ]; then
  log "ok — every active timer has a next elapse"
  exit 0
fi

# Confirm before acting: re-sample after a beat and drop anything that has since re-armed
# or started running on its own.
sleep "$RECHECK_DELAY"

stranded=()
for timer in "${suspects[@]}"; do
  service="${timer%.timer}.service"
  has_no_next_elapse "$timer" || continue
  service_busy "$service" && continue
  stranded+=("$timer")
done

if [ "${#stranded[@]}" -eq 0 ]; then
  log "ok — ${#suspects[@]} timer(s) re-armed on their own during the re-check"
  exit 0
fi

# Re-arm by activating the service ONCE: that gives `OnUnitActiveSec` the reference point
# it is missing, and the normal cadence resumes from this moment. `--no-block` so a long
# sweep (anchor runs ~15 min) does not hold the watchdog open.
healed=()
for timer in "${stranded[@]}"; do
  service="${timer%.timer}.service"
  if systemctl start --no-block "$service" >/dev/null 2>&1; then
    healed+=("${timer%.timer}")
    log "re-armed ${timer} (no next elapse; kicked ${service} once)"
  else
    log "FAILED to re-arm ${timer} — could not start ${service}"
  fi
done

[ "${#healed[@]}" -gt 0 ] || exit 1

# Alert regardless of the self-heal: a stranded timer means something stopped it outside
# the paths that know to restore it, and that cause deserves eyes even once the sweep is
# running again. The webhook is read off the live container's env — never stored here.
webhook="$(docker inspect "$CONTAINER" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | sed -n 's/^DISCORD_ALERT_WEBHOOK=//p' | head -1 || true)"
if [ -n "$webhook" ]; then
  names="$(
    IFS=', '
    echo "${healed[*]}"
  )"
  payload="$(printf '{"content": "\\u23f0 timer-watchdog: re-armed %d stranded sweep(s) — %s. They were `active` with no next elapse, so they would never have fired again."}' "${#healed[@]}" "$names")"
  curl -sS --max-time 20 -H "Content-Type: application/json" -d "$payload" "$webhook" >/dev/null 2>&1 || true
fi

log "re-armed ${#healed[@]} stranded timer(s)"
