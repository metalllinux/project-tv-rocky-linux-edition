#!/bin/bash
# test_quiet_hours.sh — quiet hours unit + structural tests (TAP format)
#
# Runs on the team host or in the VM, no root and no cluster required:
#   bash test/scripts/test_quiet_hours.sh [repo-dir]
#
# The unit tests source quiet-hours/quiet-hours.sh and exercise the window
# math, the timezone/DST behaviour, the config parser and the state
# machine with stubbed kubectl/systemctl and a fake clock. The structural
# tests validate the module 21 wiring in install.sh and the quiet-hours
# deliverables.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${1:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

echo "TAP version 13"
echo "1..118"

PASS=0
FAIL=0

pass() { PASS=$((PASS+1)); echo "ok $((PASS+FAIL)) - $1"; }
fail() { FAIL=$((FAIL+1)); echo "not ok $((PASS+FAIL)) - $1"; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

CORE="$REPO_DIR/quiet-hours/quiet-hours.sh"
CONF="$WORK/quiet-hours.conf"
STATE="$WORK/state"

# Point the core script at the scratch paths before sourcing it (it reads
# the env vars with :- defaults at source time).
export QUIET_HOURS_CONF="$CONF"
export QUIET_HOURS_STATE="$STATE"
export QUIET_HOURS_NAMESPACE="project-tv"

if [[ ! -f "$CORE" ]]; then
    fail "core script $CORE not found (repo dir: $REPO_DIR)"
    echo "# Results: $PASS passed, $FAIL failed out of $((PASS+FAIL))"
    exit 1
fi

# shellcheck source=/dev/null
source "$CORE"

# Silence the core's journal logger: TAP output must contain only ok/not
# ok lines and # diagnostics.
log() { :; }

# Stub the external commands the state machine drives. Every invocation is
# recorded so the tests can assert what would have been executed.
KUBECTL_LOG="$WORK/kubectl.log"
SYSTEMCTL_LOG="$WORK/systemctl.log"
STUB_FAIL_UNIT=""

kubectl() {
    echo "kubectl $*" >> "$KUBECTL_LOG"
}

systemctl() {
    echo "systemctl $*" >> "$SYSTEMCTL_LOG"
    if [[ -n "$STUB_FAIL_UNIT" && "${2:-}" == "$STUB_FAIL_UNIT" ]]; then
        return 1
    fi
}

# Fake clock: when FAKE_NOW is set, `date +%s` returns it. Everything else
# (fixed-epoch date -d calls) passes through to the real date, so the
# timezone math under test is the real glibc date.
FAKE_NOW=""
date() {
    if [[ -n "$FAKE_NOW" && "${*}" == "+%s" ]]; then
        echo "$FAKE_NOW"
        return 0
    fi
    command date "$@"
}

# ---------------------------------------------------------------------------
# A. Window matrix: start inclusive, end exclusive, wrap-aware
# ---------------------------------------------------------------------------
QUIET_START_HOUR=20
QUIET_END_HOUR=7

for h in 20 21 22 23 0 1 2 3 4 5 6; do
    if hour_in_window "$h"; then
        pass "A wrap 20-07: hour $h is inside the window"
    else
        fail "A wrap 20-07: hour $h is inside the window"
    fi
done

for h in 7 8 9 10 11 12 13 14 15 16 17 18 19; do
    if hour_in_window "$h"; then
        fail "A wrap 20-07: hour $h is outside the window"
    else
        pass "A wrap 20-07: hour $h is outside the window"
    fi
done

QUIET_START_HOUR=10
QUIET_END_HOUR=14

if hour_in_window 10; then pass "A no-wrap 10-14: start hour 10 is inside"; else fail "A no-wrap 10-14: start hour 10 is inside"; fi
if hour_in_window 13; then pass "A no-wrap 10-14: hour 13 is inside"; else fail "A no-wrap 10-14: hour 13 is inside"; fi
if hour_in_window 14; then fail "A no-wrap 10-14: end hour 14 is outside"; else pass "A no-wrap 10-14: end hour 14 is outside"; fi
if hour_in_window 9; then fail "A no-wrap 10-14: hour 9 is outside"; else pass "A no-wrap 10-14: hour 9 is outside"; fi

# start == end is the degenerate config: treated as a full 24h window
QUIET_START_HOUR=10
QUIET_END_HOUR=10

if hour_in_window 10; then pass "A degenerate 10-10: hour 10 is inside (full day)"; else fail "A degenerate 10-10: hour 10 is inside (full day)"; fi
if hour_in_window 5; then pass "A degenerate 10-10: hour 5 is inside (full day)"; else fail "A degenerate 10-10: hour 5 is inside (full day)"; fi

# ---------------------------------------------------------------------------
# B. Boundary inclusivity, named explicitly (wrap 20-07)
# ---------------------------------------------------------------------------
QUIET_START_HOUR=20
QUIET_END_HOUR=7

if hour_in_window 20; then pass "B boundary: start hour (20) is inclusive"; else fail "B boundary: start hour (20) is inclusive"; fi
if hour_in_window 7; then fail "B boundary: end hour (7) is exclusive"; else pass "B boundary: end hour (7) is exclusive"; fi

# ---------------------------------------------------------------------------
# C. DST and fixed-epoch timezone correctness (window 0-2 unless noted)
# ---------------------------------------------------------------------------
QUIET_ENABLED=1
QUIET_OVERRIDE=0
QUIET_START_HOUR=0
QUIET_END_HOUR=2

# America/New_York, 2026-03-08 spring forward: 02:00 EST -> 03:00 EDT (07:00 UTC)
export QUIET_HOURS_TZ="America/New_York"
E_EPOCH=$(command date -u -d "2026-03-08 06:30:00 UTC" +%s)  # 01:30 EST
E_SKIP=$(command date -u -d "2026-03-08 07:00:00 UTC" +%s)   # 02:00 EST, which does not exist

if [[ "$(desired_state_at "$E_EPOCH")" == "quiet" ]]; then pass "C NY spring 2026-03-08: 01:30 EST (hour 1) is quiet"; else fail "C NY spring 2026-03-08: 01:30 EST (hour 1) is quiet"; fi
E_EPOCH=$(command date -u -d "2026-03-08 07:30:00 UTC" +%s)
if [[ "$(desired_state_at "$E_EPOCH")" == "loud" ]]; then pass "C NY spring 2026-03-08: 03:30 EDT (hour 3) is loud"; else fail "C NY spring 2026-03-08: 03:30 EDT (hour 3) is loud"; fi
if [[ "$(local_tz_hour "$E_SKIP")" == "03" ]]; then pass "C NY spring 2026-03-08: skipped hour 02 never occurs (07:00 UTC reads as hour 3)"; else fail "C NY spring 2026-03-08: skipped hour 02 never occurs (07:00 UTC reads as hour 3)"; fi

# America/New_York, 2026-11-01 fall back: 02:00 EDT -> 01:00 EST (06:00 UTC)
E_EPOCH=$(command date -u -d "2026-11-01 05:30:00 UTC" +%s)  # 01:30 EDT
if [[ "$(desired_state_at "$E_EPOCH")" == "quiet" ]]; then pass "C NY fall 2026-11-01: 01:30 EDT (first pass, hour 1) is quiet"; else fail "C NY fall 2026-11-01: 01:30 EDT (first pass, hour 1) is quiet"; fi
E_EPOCH=$(command date -u -d "2026-11-01 06:30:00 UTC" +%s)  # 01:30 EST
if [[ "$(desired_state_at "$E_EPOCH")" == "quiet" ]]; then pass "C NY fall 2026-11-01: 01:30 EST (second pass, hour 1) is quiet too"; else fail "C NY fall 2026-11-01: 01:30 EST (second pass, hour 1) is quiet too"; fi
E_EPOCH=$(command date -u -d "2026-11-01 12:30:00 UTC" +%s)  # 07:30 EST
if [[ "$(desired_state_at "$E_EPOCH")" == "loud" ]]; then pass "C NY fall 2026-11-01: 07:30 EST (hour 7) is loud"; else fail "C NY fall 2026-11-01: 07:30 EST (hour 7) is loud"; fi

# Europe/Berlin, 2026-03-29 spring forward: 02:00 CET -> 03:00 CEST (01:00 UTC), window 2-4
QUIET_START_HOUR=2
QUIET_END_HOUR=4
export QUIET_HOURS_TZ="Europe/Berlin"
E_EPOCH=$(command date -u -d "2026-03-29 00:30:00 UTC" +%s)  # 01:30 CET
if [[ "$(desired_state_at "$E_EPOCH")" == "loud" ]]; then pass "C Berlin spring 2026-03-29: 01:30 CET (hour 1) is loud"; else fail "C Berlin spring 2026-03-29: 01:30 CET (hour 1) is loud"; fi
E_EPOCH=$(command date -u -d "2026-03-29 01:30:00 UTC" +%s)  # 02:30 CET
if [[ "$(desired_state_at "$E_EPOCH")" == "quiet" ]]; then pass "C Berlin spring 2026-03-29: 02:30 CET (hour 2) is quiet"; else fail "C Berlin spring 2026-03-29: 02:30 CET (hour 2) is quiet"; fi
E_EPOCH=$(command date -u -d "2026-03-29 02:30:00 UTC" +%s)  # 04:30 CEST
if [[ "$(desired_state_at "$E_EPOCH")" == "loud" ]]; then pass "C Berlin spring 2026-03-29: 04:30 CEST (hour 4) is loud (end exclusive)"; else fail "C Berlin spring 2026-03-29: 04:30 CEST (hour 4) is loud (end exclusive)"; fi

# Europe/Berlin, 2026-10-25 fall back: 03:00 CEST -> 02:00 CET (01:00 UTC), window 2-3
QUIET_START_HOUR=2
QUIET_END_HOUR=3
E_EPOCH=$(command date -u -d "2026-10-25 00:30:00 UTC" +%s)  # 02:30 CEST
if [[ "$(desired_state_at "$E_EPOCH")" == "quiet" ]]; then pass "C Berlin fall 2026-10-25: 02:30 CEST (first pass, hour 2) is quiet"; else fail "C Berlin fall 2026-10-25: 02:30 CEST (first pass, hour 2) is quiet"; fi
E_EPOCH=$(command date -u -d "2026-10-25 01:30:00 UTC" +%s)  # 02:30 CET
if [[ "$(desired_state_at "$E_EPOCH")" == "quiet" ]]; then pass "C Berlin fall 2026-10-25: 02:30 CET (second pass, hour 2) is quiet too"; else fail "C Berlin fall 2026-10-25: 02:30 CET (second pass, hour 2) is quiet too"; fi

# Asia/Tokyo control: no DST, the same instants stay put
QUIET_START_HOUR=0
QUIET_END_HOUR=2
export QUIET_HOURS_TZ="Asia/Tokyo"
E_EPOCH=$(command date -u -d "2026-03-08 03:00:00 UTC" +%s)  # 12:00 JST
if [[ "$(desired_state_at "$E_EPOCH")" == "loud" ]]; then pass "C Tokyo control 2026-03-08: 12:00 JST (hour 12) is loud"; else fail "C Tokyo control 2026-03-08: 12:00 JST (hour 12) is loud"; fi
E_EPOCH=$(command date -u -d "2026-11-01 16:00:00 UTC" +%s)  # 01:00 JST next day
if [[ "$(desired_state_at "$E_EPOCH")" == "quiet" ]]; then pass "C Tokyo control 2026-11-01: 01:00 JST (hour 1) is quiet"; else fail "C Tokyo control 2026-11-01: 01:00 JST (hour 1) is quiet"; fi
if [[ "$(local_tz_hour "$E_EPOCH")" == "01" ]]; then pass "C Tokyo control: wall hour resolves to 01 with no DST shift"; else fail "C Tokyo control: wall hour resolves to 01 with no DST shift"; fi
unset QUIET_HOURS_TZ

# ---------------------------------------------------------------------------
# D. Config parsing
# ---------------------------------------------------------------------------
cat > "$CONF" << 'EOF'
# sample config
QUIET_START_HOUR=20
QUIET_END_HOUR=7
QUIET_ENABLED=1
QUIET_OVERRIDE=0
QUIET_K8S_CRONJOBS="jellyfin-library-refresh"
QUIET_SYSTEMD_UNITS="sanoid.timer plocate-updatedb.timer"
EOF

if load_config; then pass "D config parse: valid file loads (rc 0)"; else fail "D config parse: valid file loads (rc 0)"; fi
if [[ "$QUIET_START_HOUR" == "20" && "$QUIET_END_HOUR" == "7" && "$QUIET_ENABLED" == "1" && \
      "$QUIET_OVERRIDE" == "0" && "$QUIET_K8S_CRONJOBS" == "jellyfin-library-refresh" && \
      "$QUIET_SYSTEMD_UNITS" == "sanoid.timer plocate-updatedb.timer" ]]; then
    pass "D config parse: all six values parsed (interior spaces kept in lists)"
else
    fail "D config parse: all six values parsed (got start=$QUIET_START_HOUR end=$QUIET_END_HOUR enabled=$QUIET_ENABLED override=$QUIET_OVERRIDE k8s=$QUIET_K8S_CRONJOBS units=$QUIET_SYSTEMD_UNITS)"
fi

if load_config "$WORK/does-not-exist.conf"; then
    fail "D config parse: missing file returns rc 1"
else
    pass "D config parse: missing file returns rc 1"
fi

printf 'QUIET_END_HOUR=24\n' > "$CONF"
if load_config; then fail "D config parse: hour 24 rejected (rc 1)"; else pass "D config parse: hour 24 rejected (rc 1)"; fi

printf 'QUIET_START_HOUR=09\n' > "$CONF"
if load_config && [[ "$QUIET_START_HOUR" == "9" ]]; then
    pass "D config parse: 09 is decimal 9 (no octal trap)"
else
    fail "D config parse: 09 is decimal 9 (no octal trap)"
fi

printf 'QUIET_START_HOUR=20\nQUIET_END_HOUR=7\nSOME_FUTURE_KEY=whatever\n' > "$CONF"
if load_config; then pass "D config parse: unknown keys are skipped (rc 0)"; else fail "D config parse: unknown keys are skipped (rc 0)"; fi

printf 'QUIET_ENABLED=2\n' > "$CONF"
if load_config; then fail "D config parse: flag value 2 rejected (rc 1)"; else pass "D config parse: flag value 2 rejected (rc 1)"; fi

printf 'QUIET_SYSTEMD_UNITS="a.timer b.timer"\n' > "$CONF"
if load_config && [[ "$QUIET_SYSTEMD_UNITS" == "a.timer b.timer" ]]; then
    pass "D config parse: quoted list keeps interior spaces"
else
    fail "D config parse: quoted list keeps interior spaces"
fi

# ---------------------------------------------------------------------------
# E. State machine with stubbed kubectl/systemctl and a fake clock
# ---------------------------------------------------------------------------
export QUIET_HOURS_TZ="UTC"
IN_WINDOW_EPOCH=$(command date -u -d "2026-09-08 23:30:00 UTC" +%s)   # hour 23, inside 20-07
OUT_WINDOW_EPOCH=$(command date -u -d "2026-09-08 12:00:00 UTC" +%s)  # hour 12, outside

write_machine_conf() {
    cat > "$CONF" << EOF
QUIET_START_HOUR=20
QUIET_END_HOUR=7
QUIET_ENABLED=1
QUIET_OVERRIDE=$1
QUIET_K8S_CRONJOBS="jellyfin-library-refresh"
QUIET_SYSTEMD_UNITS="sanoid.timer plocate-updatedb.timer"
EOF
}

# E1: fresh install, in-window tick -> full quiet transition
: > "$KUBECTL_LOG"; : > "$SYSTEMCTL_LOG"
rm -f "$STATE"
write_machine_conf 0
FAKE_NOW="$IN_WINDOW_EPOCH"
( main ) 2>/dev/null
if [[ "$(cat "$STATE" 2>/dev/null)" == "quiet" ]]; then pass "E1 fresh in-window tick: state file advanced to quiet"; else fail "E1 fresh in-window tick: state file advanced to quiet"; fi
if grep -q 'patch cronjob jellyfin-library-refresh' "$KUBECTL_LOG" && grep -q 'suspend.:true' "$KUBECTL_LOG"; then
    pass "E1 CronJob suspended via kubectl patch"
else
    fail "E1 CronJob suspended via kubectl patch"
fi
if grep -q 'stop sanoid.timer' "$SYSTEMCTL_LOG" && grep -q 'stop plocate-updatedb.timer' "$SYSTEMCTL_LOG"; then
    pass "E1 both systemd units stopped"
else
    fail "E1 both systemd units stopped"
fi

# E2: already quiet -> no-op tick, no duplicate actions
K_BEFORE=$(wc -l < "$KUBECTL_LOG")
S_BEFORE=$(wc -l < "$SYSTEMCTL_LOG")
FAKE_NOW="$IN_WINDOW_EPOCH"
( main ) 2>/dev/null
K_AFTER=$(wc -l < "$KUBECTL_LOG")
S_AFTER=$(wc -l < "$SYSTEMCTL_LOG")
if [[ "$K_BEFORE" == "$K_AFTER" && "$S_BEFORE" == "$S_AFTER" ]]; then pass "E2 already-quiet tick issues no new actions"; else fail "E2 already-quiet tick issues no new actions"; fi
if [[ "$(cat "$STATE")" == "quiet" ]]; then pass "E2 state stays quiet"; else fail "E2 state stays quiet"; fi

# E3: outside-window tick -> full release
FAKE_NOW="$OUT_WINDOW_EPOCH"
( main ) 2>/dev/null
if grep -q 'suspend.:false' "$KUBECTL_LOG"; then pass "E3 CronJob resumed (suspend false)"; else fail "E3 CronJob resumed (suspend false)"; fi
if grep -q 'start sanoid.timer' "$SYSTEMCTL_LOG" && grep -q 'start plocate-updatedb.timer' "$SYSTEMCTL_LOG"; then
    pass "E3 both systemd units started"
else
    fail "E3 both systemd units started"
fi
if [[ "$(cat "$STATE")" == "loud" ]]; then pass "E3 state file advanced to loud"; else fail "E3 state file advanced to loud"; fi

# E4: one apply step fails -> exit 0, state file NOT written, retry next tick
rm -f "$STATE"
: > "$KUBECTL_LOG"; : > "$SYSTEMCTL_LOG"
write_machine_conf 0
STUB_FAIL_UNIT="plocate-updatedb.timer"
FAKE_NOW="$IN_WINDOW_EPOCH"
( main ) 2>/dev/null
RC_E4=$?
STUB_FAIL_UNIT=""
if [[ "$RC_E4" == "0" ]]; then pass "E4 failed apply step: main still exits 0 (fail-soft)"; else fail "E4 failed apply step: main still exits 0 (fail-soft)"; fi
if [[ ! -f "$STATE" ]]; then pass "E4 failed apply step: state file NOT written"; else fail "E4 failed apply step: state file NOT written"; fi
if grep -q 'stop plocate-updatedb.timer' "$SYSTEMCTL_LOG"; then pass "E4 failing step was attempted and logged"; else fail "E4 failing step was attempted and logged"; fi

# E5: reboot simulation with the override on -> quiet re-applied outside the window
rm -f "$STATE"
: > "$KUBECTL_LOG"; : > "$SYSTEMCTL_LOG"
write_machine_conf 1
FAKE_NOW="$OUT_WINDOW_EPOCH"
( main ) 2>/dev/null
if [[ "$(cat "$STATE" 2>/dev/null)" == "quiet" ]]; then pass "E5 reboot with override on re-applies quiet outside the window"; else fail "E5 reboot with override on re-applies quiet outside the window"; fi
if grep -q 'suspend.:true' "$KUBECTL_LOG"; then pass "E5 override-driven quiet suspends the CronJob"; else fail "E5 override-driven quiet suspends the CronJob"; fi

# E6: corrupt config -> no actions, state untouched, exit 0
: > "$KUBECTL_LOG"; : > "$SYSTEMCTL_LOG"
printf 'QUIET_END_HOUR=25\n' > "$CONF"
printf 'loud\n' > "$STATE"
FAKE_NOW="$IN_WINDOW_EPOCH"
( main ) 2>/dev/null
RC_E6=$?
if [[ "$RC_E6" == "0" && "$(cat "$STATE")" == "loud" ]]; then pass "E6 config parse error: exit 0 and state untouched"; else fail "E6 config parse error: exit 0 and state untouched"; fi
if [[ ! -s "$KUBECTL_LOG" && ! -s "$SYSTEMCTL_LOG" ]]; then pass "E6 config parse error: no actions attempted"; else fail "E6 config parse error: no actions attempted"; fi

# E7: override disabled while quiet -> released outside the window
write_machine_conf 1
printf 'quiet\n' > "$STATE"
: > "$KUBECTL_LOG"; : > "$SYSTEMCTL_LOG"
write_machine_conf 0
FAKE_NOW="$OUT_WINDOW_EPOCH"
( main ) 2>/dev/null
if [[ "$(cat "$STATE")" == "loud" ]]; then pass "E7 disable override: released to loud outside the window"; else fail "E7 disable override: released to loud outside the window"; fi
if grep -q 'suspend.:false' "$KUBECTL_LOG"; then pass "E7 disable override: CronJob resumed"; else fail "E7 disable override: CronJob resumed"; fi

# ---------------------------------------------------------------------------
# F. Override / enabled semantics
# ---------------------------------------------------------------------------
QUIET_START_HOUR=20
QUIET_END_HOUR=7
FAKE_NOW=""
E_EPOCH=$(command date -u -d "2026-09-08 12:00:00 UTC" +%s)  # outside window

QUIET_ENABLED=0
QUIET_OVERRIDE=1
if [[ "$(desired_state_at "$E_EPOCH")" == "loud" ]]; then pass "F feature disabled wins over override and window"; else fail "F feature disabled wins over override and window"; fi

QUIET_ENABLED=1
QUIET_OVERRIDE=1
if [[ "$(desired_state_at "$E_EPOCH")" == "quiet" ]]; then pass "F override forces quiet outside the window"; else fail "F override forces quiet outside the window"; fi

# ---------------------------------------------------------------------------
# G. State file round-trip and fail-soft read
# ---------------------------------------------------------------------------
if write_state "quiet" && [[ "$(read_state)" == "quiet" ]]; then pass "G write_state quiet / read_state quiet"; else fail "G write_state quiet / read_state quiet"; fi
if write_state "loud" && [[ "$(read_state)" == "loud" ]]; then pass "G write_state loud / read_state loud"; else fail "G write_state loud / read_state loud"; fi
printf 'garbage\n' > "$STATE"
if [[ "$(read_state)" == "unknown" ]]; then pass "G garbage state file reads as unknown"; else fail "G garbage state file reads as unknown"; fi
rm -f "$STATE"
if [[ "$(read_state)" == "unknown" ]] && ! ls "$STATE".tmp.* >/dev/null 2>&1; then
    pass "G missing state file reads as unknown; no tmp file left behind"
else
    fail "G missing state file reads as unknown; no tmp file left behind"
fi

# ---------------------------------------------------------------------------
# H. Structural tests: module 21 wiring and deliverables
# ---------------------------------------------------------------------------
if [[ -f "$REPO_DIR/modules/21-quiet-hours.sh" ]]; then pass "H module 21 file exists"; else fail "H module 21 file exists"; fi
if grep -q '^run()' "$REPO_DIR/modules/21-quiet-hours.sh" 2>/dev/null; then pass "H module 21 defines run()"; else fail "H module 21 defines run()"; fi
if grep -qF '[21]="Quiet hours (HDD activity)"' "$REPO_DIR/install.sh" 2>/dev/null; then pass "H install.sh has MODULE_DESC[21]"; else fail "H install.sh has MODULE_DESC[21]"; fi
if grep -qE '^MODULE_ORDER=\(.* 21\)$' "$REPO_DIR/install.sh" 2>/dev/null; then pass "H install.sh MODULE_ORDER ends with 21"; else fail "H install.sh MODULE_ORDER ends with 21"; fi
if [[ -f "$REPO_DIR/quiet-hours/quiet-hours.sh" ]]; then pass "H quiet-hours/quiet-hours.sh present"; else fail "H quiet-hours/quiet-hours.sh present"; fi
if [[ -f "$REPO_DIR/quiet-hours/project-tv-quiet-hours" ]]; then pass "H quiet-hours/project-tv-quiet-hours present"; else fail "H quiet-hours/project-tv-quiet-hours present"; fi

SVC="$REPO_DIR/quiet-hours/project-tv-quiet-hours.service"
if [[ -f "$SVC" ]] && grep -q '^\[Unit\]' "$SVC" && grep -q '^\[Service\]' "$SVC" \
   && grep -q 'Type=oneshot' "$SVC" && grep -qF 'ExecStart=/usr/local/lib/project-tv/quiet-hours.sh' "$SVC"; then
    pass "H service unit: [Unit]/[Service], oneshot, runs the core script"
else
    fail "H service unit: [Unit]/[Service], oneshot, runs the core script"
fi

TMR="$REPO_DIR/quiet-hours/project-tv-quiet-hours.timer"
if [[ -f "$TMR" ]] && grep -q '^\[Unit\]' "$TMR" && grep -q '^\[Timer\]' "$TMR" && grep -q '^\[Install\]' "$TMR" \
   && grep -q 'OnBootSec=' "$TMR" && grep -qF 'OnCalendar=*:0/15' "$TMR" && grep -q 'WantedBy=timers.target' "$TMR"; then
    pass "H timer unit: [Unit]/[Timer]/[Install], 15-minute cadence, runs once at boot"
else
    fail "H timer unit: [Unit]/[Timer]/[Install], 15-minute cadence, runs once at boot"
fi

for f in \
    "quiet-hours/quiet-hours.sh" \
    "quiet-hours/project-tv-quiet-hours" \
    "modules/21-quiet-hours.sh" \
    "install.sh" \
    "test/run_tests.sh" \
    "test/scripts/test_installer.sh" \
    "test/scripts/test_quiet_hours.sh"; do
    if bash -n "$REPO_DIR/$f" 2>/dev/null; then
        pass "H bash -n clean: $f"
    else
        fail "H bash -n clean: $f"
    fi
done

USAGE_OUT=$(bash "$REPO_DIR/quiet-hours/project-tv-quiet-hours" usage 2>/dev/null)
if [[ "$USAGE_OUT" == *20:00-07:00* ]]; then pass "H CLI usage output shows the 20:00-07:00 default window"; else fail "H CLI usage output shows the 20:00-07:00 default window"; fi
if grep -qF 'test_quiet_hours.sh' "$REPO_DIR/test/run_tests.sh" 2>/dev/null; then pass "H run_tests.sh invokes test_quiet_hours.sh"; else fail "H run_tests.sh invokes test_quiet_hours.sh"; fi

# ---------------------------------------------------------------------------
# I. Regression checks for the item 10 fix round
#    (Shadow's 4 should-fix + 3 nits, Omega's 2 lows, see the planning doc)
# ---------------------------------------------------------------------------

# Module 21 runs in a sandbox: the installer helpers are stub functions,
# log_cmd records without executing (so install/mkdir/systemctl never
# touch the host), the config path is redirected to the scratch dir via
# QUIET_HOURS_CONF_PATH, and the kubectl/systemctl stubs from section E
# record the detection calls.
# shellcheck source=/dev/null
source "$REPO_DIR/modules/21-quiet-hours.sh"

I_LC_LOG="$WORK/logcmd.log"
log_section() { :; }
log_info() { :; }
log_warn() { :; }
log_success() { :; }
log_cmd() { echo "$*" >> "$I_LC_LOG"; }
set_module_status() { :; }
ask_yes_no() { return 0; }

# Scripted answers for ask_number, one per call, in a file: the module
# reads each answer in a $(...) subshell, so a variable counter would
# never advance and the re-prompt loop would run forever. An exhausted
# queue yields an empty answer, which aborts the module's 10# arithmetic
# instead of looping.
I_ANS="$WORK/ask-number.answers"
ask_number() {
    local a
    IFS= read -r a < "$I_ANS"
    sed -i 1d "$I_ANS"
    echo "$a"
}

# I1: start==end guard with leading-zero input (Shadow should-fix 3)
rm -f "$CONF"
: > "$I_LC_LOG"
printf '%s\n' 7 07 7 8 > "$I_ANS"
OUT_I=$(QUIET_HOURS_CONF_PATH="$CONF" K8S_NAMESPACE="project-tv" PROJECT_ROOT="$REPO_DIR" run 2>/dev/null)
RC_I=$?
if [[ "$OUT_I" == *"must differ"* ]]; then
    pass "I start==end: leading-zero input (7 vs 07) trips the re-prompt"
else
    fail "I start==end: leading-zero input (7 vs 07) trips the re-prompt"
fi
if grep -qx 'QUIET_START_HOUR=7' "$CONF" && grep -qx 'QUIET_END_HOUR=8' "$CONF"; then
    pass "I start==end: config gets the normalised window (7/8, no leading zeros)"
else
    fail "I start==end: config gets the normalised window (7/8, no leading zeros)"
fi
if [[ $RC_I -eq 0 ]] && grep -qx 'QUIET_OVERRIDE=0' "$CONF"; then
    pass "I fresh install: module completes with QUIET_OVERRIDE=0"
else
    fail "I fresh install: module completes with QUIET_OVERRIDE=0 (rc=$RC_I)"
fi
if grep -qF 'mkdir -p /usr/local/lib/project-tv' "$I_LC_LOG"; then
    pass "I lib-directory mkdir is routed through log_cmd"
else
    fail "I lib-directory mkdir is routed through log_cmd"
fi
if grep -qF "mkdir -p $WORK" "$I_LC_LOG"; then
    pass "I config-directory mkdir is routed through log_cmd"
else
    fail "I config-directory mkdir is routed through log_cmd"
fi

# I2: a module re-run must not drop a live override (Shadow should-fix 2)
cat > "$CONF" << 'EOF'
QUIET_START_HOUR=22
QUIET_END_HOUR=5
QUIET_ENABLED=1
QUIET_OVERRIDE=1
QUIET_K8S_CRONJOBS="jellyfin-library-refresh"
QUIET_SYSTEMD_UNITS="sanoid.timer"
EOF
printf '%s\n' 20 7 > "$I_ANS"
OUT_I=$(QUIET_HOURS_CONF_PATH="$CONF" K8S_NAMESPACE="project-tv" PROJECT_ROOT="$REPO_DIR" run 2>/dev/null)
RC_I=$?
if grep -qx 'QUIET_OVERRIDE=1' "$CONF"; then
    pass "I module re-run carries a live QUIET_OVERRIDE=1 into the new config"
else
    fail "I module re-run carries a live QUIET_OVERRIDE=1 into the new config"
fi
if [[ $RC_I -eq 0 ]] && grep -qx 'QUIET_START_HOUR=20' "$CONF" && grep -qx 'QUIET_END_HOUR=7' "$CONF"; then
    pass "I module re-run applies the new window (20/7)"
else
    fail "I module re-run applies the new window (20/7)"
fi
if [[ "$OUT_I" == *"kept on from the previous install"* ]]; then
    pass "I module re-run mentions the override carry-over in the summary"
else
    fail "I module re-run mentions the override carry-over in the summary"
fi

# I3: the k8s namespace is persisted and honoured (Shadow should-fix 1)
rm -f "$CONF" "$KUBECTL_LOG"
printf '%s\n' 20 7 > "$I_ANS"
OUT_I=$(QUIET_HOURS_CONF_PATH="$CONF" K8S_NAMESPACE="media" PROJECT_ROOT="$REPO_DIR" run 2>/dev/null)
RC_I=$?
if grep -qx 'QUIET_K8S_NAMESPACE=media' "$CONF"; then
    pass "I module persists the detection namespace in the config (QUIET_K8S_NAMESPACE=media)"
else
    fail "I module persists the detection namespace in the config (QUIET_K8S_NAMESPACE=media)"
fi
if grep -qF 'kubectl -n media get cronjob jellyfin-library-refresh' "$KUBECTL_LOG"; then
    pass "I module detection ran kubectl in the configured namespace"
else
    fail "I module detection ran kubectl in the configured namespace"
fi
# The core resolves the namespace per load_config; each case runs in a
# fresh bash because the provenance marker (did the env var set the
# namespace?) is captured at source time.
NS_I=$(QUIET_HOURS_CONF="$CONF" bash -c 'unset QUIET_HOURS_NAMESPACE; source "$1"; load_config 2>/dev/null; printf "%s" "$QUIET_HOURS_NAMESPACE"' _ "$CORE")
if [[ "$NS_I" == "media" ]]; then
    pass "I core resolves the namespace from the config key when the env var is unset"
else
    fail "I core resolves the namespace from the config key when the env var is unset (got $NS_I)"
fi
NS_I=$(QUIET_HOURS_CONF="$CONF" QUIET_HOURS_NAMESPACE=envns bash -c 'source "$1"; load_config 2>/dev/null; printf "%s" "$QUIET_HOURS_NAMESPACE"' _ "$CORE")
if [[ "$NS_I" == "envns" ]]; then
    pass "I env QUIET_HOURS_NAMESPACE wins over the config key"
else
    fail "I env QUIET_HOURS_NAMESPACE wins over the config key (got $NS_I)"
fi
printf 'QUIET_START_HOUR=20\nQUIET_END_HOUR=7\n' > "$WORK/ns-default.conf"
NS_I=$(QUIET_HOURS_CONF="$WORK/ns-default.conf" bash -c 'unset QUIET_HOURS_NAMESPACE; source "$1"; load_config 2>/dev/null; printf "%s" "$QUIET_HOURS_NAMESPACE"' _ "$CORE")
if [[ "$NS_I" == "project-tv" ]]; then
    pass "I namespace defaults to project-tv with no env and no key"
else
    fail "I namespace defaults to project-tv with no env and no key (got $NS_I)"
fi

# I4: target lists and the namespace are allowlist-validated (Omega low 1)
printf 'QUIET_START_HOUR=20\nQUIET_END_HOUR=7\nQUIET_SYSTEMD_UNITS="--foo sanoid.timer"\n' > "$CONF"
if load_config 2>/dev/null; then
    fail "I allowlist: unit list with an option token is rejected (rc 1)"
else
    pass "I allowlist: unit list with an option token is rejected (rc 1)"
fi
printf 'QUIET_K8S_CRONJOBS="jellyfin-library-refresh --all"\n' > "$CONF"
if load_config 2>/dev/null; then
    fail "I allowlist: cronjob list with an option token is rejected (rc 1)"
else
    pass "I allowlist: cronjob list with an option token is rejected (rc 1)"
fi
printf 'QUIET_K8S_NAMESPACE="media;rm -rf /"\n' > "$CONF"
if load_config 2>/dev/null; then
    fail "I allowlist: malformed namespace is rejected (rc 1)"
else
    pass "I allowlist: malformed namespace is rejected (rc 1)"
fi
printf 'QUIET_SYSTEMD_UNITS=""\nQUIET_K8S_CRONJOBS=""\n' > "$CONF"
if load_config 2>/dev/null && [[ -z "$QUIET_SYSTEMD_UNITS" && -z "$QUIET_K8S_CRONJOBS" ]]; then
    pass "I allowlist: empty target lists are accepted (module writes them when no targets are found)"
else
    fail "I allowlist: empty target lists are accepted (module writes them when no targets are found)"
fi

# I5: an in-place upgrade must not kill the installer (Shadow should-fix 4).
# install.sh cannot be sourced (it runs main at the end), so the functions
# are extracted verbatim.
eval "$(sed -n '/^init_status() {/,/^}/p' "$REPO_DIR/install.sh")"
eval "$(sed -n '/^set_module_status() {/,/^}/p' "$REPO_DIR/install.sh")"
eval "$(sed -n '/^get_module_status() {/,/^}/p' "$REPO_DIR/install.sh")"
eval "$(sed -n '/^MODULE_ORDER=/p' "$REPO_DIR/install.sh")"

STATUS_FILE="$WORK/install-status"
I_LAST=$(( ${#MODULE_ORDER[@]} - 1 ))
: > "$STATUS_FILE"
for m in "${MODULE_ORDER[@]:0:I_LAST}"; do
    echo "$m:pending" >> "$STATUS_FILE"
done
V_I=$(get_module_status 21); RC_I=$?
if [[ $RC_I -eq 0 && "$V_I" == "pending" ]]; then
    pass "I in-place upgrade: missing status line reads as pending with rc 0 (set -e safe)"
else
    fail "I in-place upgrade: missing status line reads as pending with rc 0 (set -e safe) (rc=$RC_I v=$V_I)"
fi
init_status
if grep -qx '21:pending' "$STATUS_FILE"; then
    pass "I in-place upgrade: init_status backfills the new module into the old file"
else
    fail "I in-place upgrade: init_status backfills the new module into the old file"
fi
set_module_status 21 completed
V_I=$(get_module_status 21)
if [[ "$V_I" == "completed" ]]; then
    pass "I in-place upgrade: status is recorded for the new module after the backfill"
else
    fail "I in-place upgrade: status is recorded for the new module after the backfill (got $V_I)"
fi

# I6: the trigger_now fallback runs the resolved core path (Shadow nit 2)
CLI_FILE="$REPO_DIR/quiet-hours/project-tv-quiet-hours"
if sed -n '/^trigger_now() {/,/^}/p' "$CLI_FILE" | grep -q 'CORE_PATH'; then
    pass "I trigger_now fallback uses the resolved core path (CORE_PATH)"
else
    fail "I trigger_now fallback uses the resolved core path (CORE_PATH)"
fi
if [[ -f /usr/local/lib/project-tv/quiet-hours.sh ]]; then
    # An installed copy shadows the repo layout on this host; pin the
    # resolution order structurally instead.
    if sed -n '/^core_script_path() {/,/^}/p' "$CLI_FILE" | grep -qF '/usr/local/lib/project-tv/quiet-hours.sh'; then
        pass "I core_script_path checks the installed path first (structural: installed copy present)"
    else
        fail "I core_script_path checks the installed path first (structural: installed copy present)"
    fi
    if ! sed -n '/^trigger_now() {/,/^}/p' "$CLI_FILE" | grep -qF '/usr/local/lib/project-tv/quiet-hours.sh'; then
        pass "I trigger_now has no hardcoded installed-path fallback (structural)"
    else
        fail "I trigger_now has no hardcoded installed-path fallback (structural)"
    fi
else
    # Functional: the CLI functions are extracted into the scratch dir
    # next to a stand-in core that records its own path when executed;
    # the systemctl stub refuses the unit, so the fallback must run the
    # core that core_script_path resolved.
    sed -n '/^SERVICE=/p; /^core_script_path() {/,/^}/p; /^load_core() {/,/^}/p; /^trigger_now() {/,/^}/p' "$CLI_FILE" > "$WORK/cli-funcs.sh"
    printf '#!/bin/bash\nif [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then\n    printf "%%s\\n" "$0" >> "%s/core-ran.log"\nfi\n' "$WORK" > "$WORK/quiet-hours.sh"
    chmod +x "$WORK/quiet-hours.sh"
    cat > "$WORK/cli6.sh" << 'EOS'
set -uo pipefail
W="$1"
systemctl() { return 1; }
export QUIET_HOURS_CONF="$W/conf-cli"
# shellcheck source=/dev/null
source "$W/cli-funcs.sh"
out=$(load_core && trigger_now)
rc=$?
printf 'OUT:%s\n' "$out"
exit "$rc"
EOS
    rm -f "$WORK/core-ran.log"
    I6_OUT=$(bash "$WORK/cli6.sh" "$WORK" 2>/dev/null)
    I6_RC=$?
    if [[ $I6_RC -eq 0 ]] && [[ "$I6_OUT" == *"service unit not available; the script was run directly"* ]]; then
        pass "I trigger_now fallback runs the core directly when the unit is absent"
    else
        fail "I trigger_now fallback runs the core directly when the unit is absent (rc=$I6_RC)"
    fi
    if [[ -f "$WORK/core-ran.log" && "$(cat "$WORK/core-ran.log")" == "$WORK/quiet-hours.sh" ]]; then
        pass "I trigger_now fallback executed the resolved repo-layout core"
    else
        fail "I trigger_now fallback executed the resolved repo-layout core (executed: $(cat "$WORK/core-ran.log" 2>/dev/null))"
    fi
fi

# I7: the dead now_hour variable is gone (Shadow nit 1)
if ! grep -q 'now_hour' "$CLI_FILE"; then
    pass "I dead now_hour is gone from the CLI (SC2034)"
else
    fail "I dead now_hour is gone from the CLI (SC2034)"
fi

echo ""
echo "# Results: $PASS passed, $FAIL failed out of $((PASS+FAIL))"
[[ "$FAIL" == "0" ]]
