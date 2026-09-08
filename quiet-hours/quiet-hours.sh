#!/bin/bash
# quiet-hours.sh — Project TV quiet-hours state machine
#
# Suspends the configured scheduled HDD I/O sources (k8s CronJobs and
# systemd units) during the quiet window and restores them outside it.
# Run by project-tv-quiet-hours.timer every 15 minutes and once at boot.
#
# Fail-soft contract: this script always exits 0. On any error it logs to
# the journal and leaves the system in its current (loud or partially
# quiet) state. The applied state is written only after every step of a
# transition succeeds, so a partial transition is retried on the next tick
# and never strands the media stack in a broken state.
#
# The streaming path (Jellyfin playback) is never touched: only the
# scheduled background sources named in the config are managed.
#
# Environment overrides (used by the test suite, defaults for production):
#   QUIET_HOURS_CONF      config file    (default /etc/project-tv/quiet-hours.conf)
#   QUIET_HOURS_STATE     state file     (default /var/lib/project-tv/quiet-hours/state)
#   QUIET_HOURS_NAMESPACE k8s namespace  (wins over the config key; default
#                                          project-tv)
#   QUIET_HOURS_TZ        IANA timezone for window math (default: system local time)
#
# The QUIET_K8S_NAMESPACE config key names the namespace installer module 21
# detected the targets in (from $K8S_NAMESPACE), so detection and runtime
# read the same value.

set -uo pipefail

# --- Paths and namespace (env-overridable for tests) ---
QUIET_HOURS_CONF="${QUIET_HOURS_CONF:-/etc/project-tv/quiet-hours.conf}"
QUIET_HOURS_STATE="${QUIET_HOURS_STATE:-/var/lib/project-tv/quiet-hours/state}"
# Namespace resolution order: the QUIET_HOURS_NAMESPACE environment
# variable (test-suite override, wins), then the QUIET_K8S_NAMESPACE key
# from the config (load_config applies it when the env var is unset), then
# the default. The provenance marker remembers whether the env var supplied
# the namespace, so the config key never clobbers a test override.
QUIET_HOURS_NAMESPACE_ENV="${QUIET_HOURS_NAMESPACE:-}"
QUIET_HOURS_NAMESPACE="${QUIET_HOURS_NAMESPACE:-project-tv}"

# --- Config values (populated by load_config; sane defaults) ---
QUIET_START_HOUR=20
QUIET_END_HOUR=7
QUIET_ENABLED=1
QUIET_OVERRIDE=0
QUIET_K8S_CRONJOBS=""
QUIET_SYSTEMD_UNITS=""

# Log to stderr; under systemd this lands in the journal.
log() {
    echo "[quiet-hours] $*" >&2
}

# Validate a space-separated list of CronJob names against the k8s
# DNS-1123 label allowlist [a-z0-9]([a-z0-9-]*[a-z0-9])?; an empty list
# (no targets) is valid. The tokens are passed to kubectl by the root
# service, so they are checked before they can reach a command line. The
# label form (alphanumeric first and last) also rejects option tokens
# such as "--foo", which a bare [a-z0-9-]+ class would accept.
valid_cronjob_list() {
    local value="$1"
    [[ -z "$value" || "$value" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?([[:space:]]+[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$ ]]
}

# Validate a space-separated list of systemd unit names: first character
# from [A-Za-z0-9._:@], the rest from [A-Za-z0-9._:@-]. Same allowlist
# rationale as valid_cronjob_list: the tokens go to systemctl verbatim,
# and the no-leading-dash rule rejects option tokens such as "--foo".
valid_unit_list() {
    local value="$1"
    [[ -z "$value" || "$value" =~ ^[A-Za-z0-9._:@][A-Za-z0-9._:@-]*([[:space:]]+[A-Za-z0-9._:@][A-Za-z0-9._:@-]*)*$ ]]
}

# Parse the config file into the QUIET_* globals.
# Returns 0 on success, 1 if the file is missing or a known value is invalid.
# Unknown keys and malformed lines are logged and skipped (forward
# compatibility); an invalid value for a known key fails the whole load,
# because a garbage hour would silently corrupt the window math.
load_config() {
    local file="${1:-$QUIET_HOURS_CONF}"
    local line key value

    if [[ ! -f "$file" ]]; then
        log "config file not found: $file"
        return 1
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip blank lines and comments
        [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
        if [[ ! "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            log "skipping malformed config line: $line"
            continue
        fi
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        # Trim leading/trailing whitespace, keep interior spaces (lists)
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"
        # Strip one pair of surrounding quotes if present
        if [[ "$value" =~ ^\"(.*)\"$ ]] || [[ "$value" =~ ^\'(.*)\'$ ]]; then
            value="${BASH_REMATCH[1]}"
        fi

        case "$key" in
            QUIET_START_HOUR|QUIET_END_HOUR)
                if ! [[ "$value" =~ ^[0-9]+$ ]] || (( 10#$value > 23 )); then
                    log "invalid $key: '$value' (must be an integer 0-23)"
                    return 1
                fi
                if [[ "$key" == "QUIET_START_HOUR" ]]; then
                    QUIET_START_HOUR=$((10#$value))
                else
                    QUIET_END_HOUR=$((10#$value))
                fi
                ;;
            QUIET_ENABLED|QUIET_OVERRIDE)
                if [[ "$value" != "0" && "$value" != "1" ]]; then
                    log "invalid $key: '$value' (must be 0 or 1)"
                    return 1
                fi
                if [[ "$key" == "QUIET_ENABLED" ]]; then
                    QUIET_ENABLED="$value"
                else
                    QUIET_OVERRIDE="$value"
                fi
                ;;
            QUIET_K8S_CRONJOBS)
                if ! valid_cronjob_list "$value"; then
                    log "invalid $key: '$value' (CronJob names must be k8s DNS-1123 labels, e.g. jellyfin-library-refresh)"
                    return 1
                fi
                QUIET_K8S_CRONJOBS="$value"
                ;;
            QUIET_SYSTEMD_UNITS)
                if ! valid_unit_list "$value"; then
                    log "invalid $key: '$value' (unit names must match [A-Za-z0-9._:@][A-Za-z0-9._:@-]*, e.g. sanoid.timer)"
                    return 1
                fi
                QUIET_SYSTEMD_UNITS="$value"
                ;;
            QUIET_K8S_NAMESPACE)
                # k8s DNS-1123 label: [a-z0-9]([-a-z0-9]*[a-z0-9])?
                if [[ -z "$value" || ! "$value" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]]; then
                    log "invalid $key: '$value' (must be a k8s DNS-1123 label, e.g. project-tv)"
                    return 1
                fi
                if [[ -z "$QUIET_HOURS_NAMESPACE_ENV" ]]; then
                    QUIET_HOURS_NAMESPACE="$value"
                fi
                ;;
            *)
                log "ignoring unknown config key: $key"
                ;;
        esac
    done < "$file"
    return 0
}

# Set-membership test: is hour (0-23) inside the quiet window?
# Start inclusive, end exclusive. start == end is the degenerate config and
# is treated as a full 24-hour window, defensively. Pure set semantics with
# no arithmetic across the wrap, which is what makes the window correct
# across DST transitions (a repeated wall-clock hour is simply quiet twice,
# a skipped hour simply never occurs).
# Returns 0 (true) when inside the window.
hour_in_window() {
    local hour="$1"
    local start="$QUIET_START_HOUR"
    local end="$QUIET_END_HOUR"

    if (( start == end )); then
        return 0
    fi
    if (( start < end )); then
        # No wrap: [start, end)
        (( hour >= start && hour < end ))
    else
        # Wrap across midnight: [start, 24) union [0, end)
        (( hour >= start || hour < end ))
    fi
}

# Run date(1) under the effective timezone, resolved per call:
# QUIET_HOURS_TZ when set, else the environment's TZ, else the system local
# time. Per-call resolution keeps the functions correct for tests and for
# long-lived environments. glibc gotcha handled here: an EMPTY TZ must not
# be passed to date(1) — TZ="" is interpreted as UTC, not as the system
# timezone. Only a non-empty value is exported; otherwise date(1) uses
# /etc/localtime as usual.
run_date() {
    local tz="${QUIET_HOURS_TZ:-${TZ:-}}"

    if [[ -n "$tz" ]]; then
        TZ="$tz" date "$@"
    else
        date "$@"
    fi
}

# Echo the local wall-clock hour (00-23) for an epoch timestamp.
local_tz_hour() {
    run_date -d "@$1" +%H 2>/dev/null
}

# Echo an epoch timestamp formatted in the effective timezone.
local_tz_date() {
    run_date -d "@$1" "$2" 2>/dev/null
}

# Echo "quiet" or "loud": the desired state at the given epoch timestamp.
# Quiet when the feature is enabled and either the override flag is set or
# the local wall-clock hour at <epoch> is inside the window.
# The state word goes to stdout; diagnostics to stderr; always returns 0
# (an unresolvable clock fails soft to loud rather than erroring out).
desired_state_at() {
    local epoch="$1"
    local hour

    if (( QUIET_ENABLED != 1 )); then
        echo "loud"
        return 0
    fi
    if (( QUIET_OVERRIDE == 1 )); then
        echo "quiet"
        return 0
    fi
    if ! hour=$(local_tz_hour "$epoch"); then
        log "could not resolve local hour for epoch $epoch; failing soft to loud"
        echo "loud"
        return 0
    fi
    if hour_in_window "$((10#$hour))"; then
        echo "quiet"
    else
        echo "loud"
    fi
    return 0
}

# Echo the desired state at the current time.
desired_state() {
    desired_state_at "$(date +%s)"
}

# Echo the applied state from the state file: "loud", "quiet", or
# "unknown" when the file is missing, unreadable, or holds garbage.
read_state() {
    local state=""

    if [[ -f "$QUIET_HOURS_STATE" ]]; then
        state=$(head -n1 "$QUIET_HOURS_STATE" 2>/dev/null)
    fi
    case "$state" in
        loud|quiet)
            echo "$state"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Atomically write the applied state. Called only after every step of a
# transition succeeded, so the file never claims a state that was not fully
# applied. Returns 1 (and logs) on write failure; the next tick retries.
write_state() {
    local new_state="$1"
    local tmp

    if ! mkdir -p "$(dirname "$QUIET_HOURS_STATE")" 2>/dev/null; then
        log "cannot create directory for state file $QUIET_HOURS_STATE"
        return 1
    fi
    tmp="${QUIET_HOURS_STATE}.tmp.$$"
    if ! printf '%s\n' "$new_state" > "$tmp" 2>/dev/null; then
        rm -f "$tmp" 2>/dev/null
        log "cannot write state file $QUIET_HOURS_STATE"
        return 1
    fi
    if ! mv -f "$tmp" "$QUIET_HOURS_STATE" 2>/dev/null; then
        rm -f "$tmp" 2>/dev/null
        log "cannot move state file into place at $QUIET_HOURS_STATE"
        return 1
    fi
    return 0
}

# Suspend or resume a CronJob in the configured namespace.
# The kubectl error output is captured and logged (journal), stdout stays
# clean. Returns kubectl's exit status.
cronjob_set_suspend() {
    local name="$1"
    local suspend="$2"
    local err

    if ! command -v kubectl >/dev/null 2>&1; then
        log "kubectl not available; cannot set suspend=$suspend on CronJob $name"
        return 1
    fi
    if ! err=$(kubectl -n "$QUIET_HOURS_NAMESPACE" patch cronjob "$name" --type merge \
            -p "{\"spec\":{\"suspend\":$suspend}}" 2>&1 >/dev/null); then
        log "failed to set suspend=$suspend on CronJob $name (namespace $QUIET_HOURS_NAMESPACE): $err"
        return 1
    fi
    return 0
}

# Delete in-flight jobs of a CronJob. Kubernetes names CronJob jobs
# <cronjob>-<timestamp>-<hash>, so a pure bash prefix match selects them;
# no `| grep` pipelines (SIGPIPE/pipefail trap, CLAUDE.md). Jobs that
# complete between list and delete are tolerated via --ignore-not-found,
# keeping the step idempotent for the next tick's retry.
# Returns 0 only if every listed in-flight job was deleted.
cronjob_delete_inflight_jobs() {
    local name="$1"
    local line job err
    local rc=0
    local jobs

    if ! command -v kubectl >/dev/null 2>&1; then
        log "kubectl not available; cannot list in-flight jobs of CronJob $name"
        return 1
    fi
    if ! jobs=$(kubectl -n "$QUIET_HOURS_NAMESPACE" get jobs -o name 2>&1 >/dev/null); then
        log "failed to list jobs in namespace $QUIET_HOURS_NAMESPACE: $jobs"
        return 1
    fi
    for line in $jobs; do
        job="${line##*/}"
        if [[ "$job" == "${name}-"* ]]; then
            if ! err=$(kubectl -n "$QUIET_HOURS_NAMESPACE" delete job "$job" --ignore-not-found 2>&1 >/dev/null); then
                log "failed to delete in-flight job $job: $err"
                rc=1
            fi
        fi
    done
    return "$rc"
}

# Stop or start a systemd unit (the configured timers). Returns 0 on
# success; logs the systemctl error otherwise.
unit_set() {
    local unit="$1"
    local action="$2"
    local err

    if ! err=$(systemctl "$action" "$unit" 2>&1); then
        log "failed to $action unit $unit: $err"
        return 1
    fi
    return 0
}

# Transition loud -> quiet. Every step is independent: a failing step is
# logged and the remaining steps still run (partial quiet is acceptable,
# broken is not). Returns 0 only when every step succeeded, which is the
# only case in which the state file may advance.
apply_quiet() {
    local rc=0
    local cronjob unit

    for cronjob in $QUIET_K8S_CRONJOBS; do
        cronjob_set_suspend "$cronjob" "true" || rc=1
        cronjob_delete_inflight_jobs "$cronjob" || rc=1
    done
    for unit in $QUIET_SYSTEMD_UNITS; do
        unit_set "$unit" "stop" || rc=1
    done

    if (( rc == 0 )); then
        log "quiet applied: CronJob(s) [${QUIET_K8S_CRONJOBS:-none}] suspended, unit(s) [${QUIET_SYSTEMD_UNITS:-none}] stopped"
    else
        log "quiet transition incomplete; state file unchanged, retrying next tick"
    fi
    return "$rc"
}

# Transition quiet -> loud: resume every CronJob and start every unit.
# Same per-step error isolation as apply_quiet.
release_quiet() {
    local rc=0
    local cronjob unit

    for cronjob in $QUIET_K8S_CRONJOBS; do
        cronjob_set_suspend "$cronjob" "false" || rc=1
    done
    for unit in $QUIET_SYSTEMD_UNITS; do
        unit_set "$unit" "start" || rc=1
    done

    if (( rc == 0 )); then
        log "quiet released: CronJob(s) [${QUIET_K8S_CRONJOBS:-none}] resumed, unit(s) [${QUIET_SYSTEMD_UNITS:-none}] started"
    else
        log "loud transition incomplete; state file unchanged, retrying next tick"
    fi
    return "$rc"
}

# One state-machine tick. Always exits 0 (fail-soft contract).
main() {
    local desired applied

    if ! load_config; then
        log "config load failed; leaving the system in its current state"
        exit 0
    fi

    desired=$(desired_state)
    applied=$(read_state)

    log "tick: start=${QUIET_START_HOUR} end=${QUIET_END_HOUR} enabled=${QUIET_ENABLED} override=${QUIET_OVERRIDE} desired=${desired} applied=${applied}"

    if [[ "$desired" == "quiet" && "$applied" != "quiet" ]]; then
        if apply_quiet; then
            write_state "quiet"
        fi
    elif [[ "$desired" == "loud" && "$applied" != "loud" ]]; then
        if release_quiet; then
            write_state "loud"
        fi
    fi
    exit 0
}

# Run main only when executed directly. The test suite sources this file
# for the functions, and sourcing must have no side effects.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
