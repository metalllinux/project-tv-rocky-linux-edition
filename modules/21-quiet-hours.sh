#!/bin/bash
# 21-quiet-hours.sh — Quiet hours for background HDD activity
#
# Installs a host-level state machine (quiet-hours/quiet-hours.sh) driven by
# a 15-minute systemd timer. During the configured window (default
# 20:00-07:00) the scheduled background sources that wake the hard drives
# are suspended: the Jellyfin library refresh CronJob, and the sanoid and
# plocate systemd timers when present. Outside the window they are
# restored. Active TV playback is never affected: only the scheduled
# background sources are managed.
#
# QUIET_HOURS_CONF_PATH overrides the config path (test suite only;
# production uses /etc/project-tv/quiet-hours.conf).

run() {
    log_section "Quiet Hours (background HDD activity)"

    echo ""
    echo "During the quiet window, the scheduled background sources that wake"
    echo "the hard drives are suspended and restored outside it:"
    echo "  - the Jellyfin library refresh CronJob (k8s, from module 11)"
    echo "  - sanoid.timer (ZFS snapshots) and plocate-updatedb.timer, when present"
    echo "Active TV playback is not affected."
    echo ""

    if ! ask_yes_no "Enable quiet hours?"; then
        log_info "Quiet hours declined; the module is marked skipped."
        set_module_status "21" "skipped"
        return 0
    fi

    local start_hour end_hour
    while true; do
        start_hour=$(ask_number "Quiet window start hour" 0 23 20)
        end_hour=$(ask_number "Quiet window end hour (exclusive)" 0 23 7)
        # Compare with 10# normalisation: ask_number accepts leading zeros
        # ("07" passes its range test), and the string comparison "7" ==
        # "07" is false, which would let a start==end window (quiet 24/7
        # in the core) slip past the guard.
        if (( 10#$start_hour == 10#$end_hour )); then
            echo "The start and end hour must differ: equal hours would mean the drives are quiet 24/7."
            echo "Please enter different hours."
        else
            break
        fi
    done
    start_hour=$((10#$start_hour))
    end_hour=$((10#$end_hour))

    # Detect which of the default targets exist on this host. The config must
    # never name a target that does not exist: a failing step would block the
    # state file from advancing and every tick would log the same error.
    local quiet_units=""
    local unit
    for unit in sanoid.timer plocate-updatedb.timer; do
        if systemctl cat "$unit" >/dev/null 2>&1; then
            quiet_units="${quiet_units}${quiet_units:+ }$unit"
        else
            log_info "Unit $unit is not present on this host; it is not a quiet-hours target."
        fi
    done

    local quiet_cronjobs=""
    if command -v kubectl &>/dev/null; then
        if kubectl -n "$K8S_NAMESPACE" get cronjob jellyfin-library-refresh >/dev/null 2>&1; then
            quiet_cronjobs="jellyfin-library-refresh"
        else
            log_warn "CronJob jellyfin-library-refresh not found in namespace $K8S_NAMESPACE; the k8s target is skipped. Run module 11, then re-run this module to add it."
        fi
    else
        log_warn "kubectl is not available; the k8s target is skipped. Run module 03, then re-run this module to add it."
    fi

    if [[ -z "$quiet_units" && -z "$quiet_cronjobs" ]]; then
        log_warn "No quiet-hours targets found yet. The mechanism is installed with an empty target list and stays inert until targets are added to the config."
    fi

    # Config path, overridable for the test suite (production always uses
    # /etc/project-tv/quiet-hours.conf).
    local conf_path="${QUIET_HOURS_CONF_PATH:-/etc/project-tv/quiet-hours.conf}"

    # A re-run must not drop a live override: carry QUIET_OVERRIDE over
    # from the existing config so an 'enable' survives an installer
    # re-run. Only a clean 0/1 value is honoured; anything else starts
    # fresh at 0.
    local existing_override=0
    local old_line
    if [[ -f "$conf_path" ]]; then
        old_line=$(grep '^QUIET_OVERRIDE=' "$conf_path" 2>/dev/null | tail -n1) || true
        if [[ "$old_line" =~ ^QUIET_OVERRIDE=([01])$ ]]; then
            existing_override="${BASH_REMATCH[1]}"
        fi
    fi

    # Install the state machine, the CLI, and the systemd units
    log_cmd "Create quiet-hours lib directory" mkdir -p /usr/local/lib/project-tv
    log_cmd "Install quiet-hours state machine" install -m 0755 "$PROJECT_ROOT/quiet-hours/quiet-hours.sh" /usr/local/lib/project-tv/quiet-hours.sh
    log_cmd "Install quiet-hours CLI" install -m 0755 "$PROJECT_ROOT/quiet-hours/project-tv-quiet-hours" /usr/local/bin/project-tv-quiet-hours
    log_cmd "Install quiet-hours service" install -m 0644 "$PROJECT_ROOT/quiet-hours/project-tv-quiet-hours.service" /etc/systemd/system/project-tv-quiet-hours.service
    log_cmd "Install quiet-hours timer" install -m 0644 "$PROJECT_ROOT/quiet-hours/project-tv-quiet-hours.timer" /etc/systemd/system/project-tv-quiet-hours.timer

    # Write the config
    log_cmd "Create quiet-hours config directory" mkdir -p "$(dirname "$conf_path")"
    cat > "$conf_path" << EOF
# Project TV quiet hours configuration
# Generated by installer module 21 on $(date)
# Window: start inclusive, end exclusive. Hours are 0-23.
# QUIET_OVERRIDE=1 forces the quiet state outside the window (set by
# 'project-tv-quiet-hours enable', cleared by 'project-tv-quiet-hours disable').
# QUIET_K8S_NAMESPACE pins the k8s namespace the targets were detected in,
# so the state machine patches the CronJob where it actually lives.
QUIET_START_HOUR=${start_hour}
QUIET_END_HOUR=${end_hour}
QUIET_ENABLED=1
QUIET_OVERRIDE=${existing_override}
QUIET_K8S_NAMESPACE=${K8S_NAMESPACE}
QUIET_K8S_CRONJOBS="${quiet_cronjobs}"
QUIET_SYSTEMD_UNITS="${quiet_units}"
EOF
    chmod 0644 "$conf_path"

    log_cmd "Reload systemd" systemctl daemon-reload
    log_cmd "Enable quiet-hours timer" systemctl enable --now project-tv-quiet-hours.timer
    # One-shot run seeds the state file and applies the current state
    log_cmd "Apply current quiet-hours state" systemctl start project-tv-quiet-hours.service

    echo ""
    echo "Quiet hours installed:"
    echo "  Window:   $(printf '%02d' "$start_hour"):00 - $(printf '%02d' "$end_hour"):00"
    echo "  Targets:  CronJobs [${quiet_cronjobs:-none}]  units [${quiet_units:-none}]"
    if [[ "$existing_override" == "1" ]]; then
        echo "  Override:   kept on from the previous install (persists until 'project-tv-quiet-hours disable')"
    fi
    echo ""
    echo "Commands:"
    echo "  project-tv-quiet-hours status    show state"
    echo "  project-tv-quiet-hours enable    force quiet now (persists until disable)"
    echo "  project-tv-quiet-hours disable   remove the override"
    echo ""
    log_success "Quiet hours active: $(printf '%02d' "$start_hour"):00 - $(printf '%02d' "$end_hour"):00"
}
