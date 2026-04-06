#!/bin/bash
# install.sh — Project TV - Rocky Linux Edition Installer
# Interactive installer for deploying a Kubernetes-based media server on Rocky Linux.
#
# Usage: sudo ./install.sh
#
# All output is logged to logs/install-YYYYMMDD-HHMMSS.log

set -euo pipefail

# Resolve the project root directory
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PROJECT_ROOT

# Source library functions
source "$PROJECT_ROOT/lib/logging.sh"
source "$PROJECT_ROOT/lib/prompts.sh"
source "$PROJECT_ROOT/lib/k8s-helpers.sh"
source "$PROJECT_ROOT/lib/validators.sh"
source "$PROJECT_ROOT/config/defaults.conf"

# Module definitions: number, filename, description
declare -A MODULE_DESC
MODULE_DESC=(
    [00]="Preflight checks"
    [01]="Timezone setup"
    [02]="ZFS storage"
    [03]="Kubernetes (kubeadm)"
    [04]="K8s namespace"
    [05]="K8s storage (PV/PVC)"
    [06]="px4_drv TV tuner driver"
    [07]="EPGStation + Mirakurun"
    [08]="Jellyfin"
    [09]="Tube Archivist"
    [10]="Navidrome"
    [11]="Jellyfin library refresh"
    [12]="Sanoid snapshots"
    [14]="KDE customisation"
    [15]="Browser installation"
    [16]="SDDM autologin"
    [17]="Firewall rules"
    [18]="Desktop applications"
    [19]="Prometheus monitoring"
    [20]="Grafana dashboards"
    [21]="VNC server (remote desktop)"
)

# Module order
# System setup first (00-06), then desktop/firewall/storage (12,14-18),
# then K8s apps (07-11), then monitoring (19-20)
MODULE_ORDER=(00 01 02 03 04 05 06 17 16 15 18 14 12 07 08 09 10 11 19 20 21)

# Status tracking file
STATUS_FILE="$PROJECT_ROOT/logs/.install-status"

# Initialise status tracking
init_status() {
    mkdir -p "$(dirname "$STATUS_FILE")"
    if [[ ! -f "$STATUS_FILE" ]]; then
        for mod in "${MODULE_ORDER[@]}"; do
            echo "$mod:pending" >> "$STATUS_FILE"
        done
    fi
}

# Update module status
set_module_status() {
    local mod="$1"
    local status="$2"
    if [[ -f "$STATUS_FILE" ]]; then
        sed -i "s/^${mod}:.*/${mod}:${status}/" "$STATUS_FILE"
    fi
}

# Get module status
get_module_status() {
    local mod="$1"
    if [[ -f "$STATUS_FILE" ]]; then
        grep "^${mod}:" "$STATUS_FILE" 2>/dev/null | cut -d: -f2
    else
        echo "pending"
    fi
}

# Run a single module
run_module() {
    local mod="$1"
    local module_file="$PROJECT_ROOT/modules/${mod}-*.sh"

    # Find the module file using glob
    local found_file
    found_file=$(ls $module_file 2>/dev/null | head -1)

    if [[ -z "$found_file" || ! -f "$found_file" ]]; then
        log_error "Module file not found for module $mod"
        return 1
    fi

    log_section "Module $mod: ${MODULE_DESC[$mod]}"

    set_module_status "$mod" "running"

    if source "$found_file" && run 2>&1; then
        set_module_status "$mod" "completed"
        log_success "Module $mod: ${MODULE_DESC[$mod]} — completed"
        return 0
    else
        local rc=$?
        set_module_status "$mod" "failed"
        log_error "Module $mod: ${MODULE_DESC[$mod]} — failed (exit code $rc)"
        return $rc
    fi
}

# Display installation status
show_status() {
    echo ""
    echo "Installation Status"
    echo "==================="
    for mod in "${MODULE_ORDER[@]}"; do
        local status
        status=$(get_module_status "$mod")
        local symbol
        case "$status" in
            completed) symbol="[OK]" ;;
            failed)    symbol="[!!]" ;;
            running)   symbol="[..]" ;;
            skipped)   symbol="[--]" ;;
            *)         symbol="[  ]" ;;
        esac
        printf "  %s  %s  %s\n" "$symbol" "$mod" "${MODULE_DESC[$mod]}"
    done
    echo ""
}

# Display the main menu
show_main_menu() {
    echo ""
    echo "Project TV - Rocky Linux Edition Installer"
    echo "====================================="
    echo ""
    echo "  [1]  Full Installation (run all modules in order)"
    echo "  [2]  Run a specific module"
    echo "  [3]  View installation status"
    echo "  [4]  View log file"
    echo "  [5]  K8s health summary"
    echo "  [q]  Quit"
    echo ""
}

# Display module selection menu
show_module_menu() {
    echo ""
    echo "Available modules:"
    echo ""
    for mod in $(printf '%s\n' "${!MODULE_DESC[@]}" | sort -n); do
        local status
        status=$(get_module_status "$mod")
        local marker=""
        [[ "$status" == "completed" ]] && marker=" (done)"
        [[ "$status" == "failed" ]] && marker=" (FAILED)"
        printf "  %s  %s%s\n" "$mod" "${MODULE_DESC[$mod]}" "$marker"
    done
    echo ""
}

# Full installation
run_full_install() {
    log_section "Starting Full Installation"

    for mod in "${MODULE_ORDER[@]}"; do
        local status
        status=$(get_module_status "$mod")

        if [[ "$status" == "completed" ]]; then
            log_info "Module $mod already completed, skipping."
            if ! ask_yes_no "  Re-run module $mod (${MODULE_DESC[$mod]})?" "default_no"; then
                continue
            fi
        fi

        echo ""
        echo "Next: Module $mod — ${MODULE_DESC[$mod]}"
        if ask_yes_no "  Run this module?"; then
            if ! run_module "$mod"; then
                log_error "Module $mod failed."
                if ! ask_yes_no "  Continue with the next module?"; then
                    log_info "Installation stopped by user after module $mod failure."
                    return 1
                fi
            fi
        else
            set_module_status "$mod" "skipped"
            log_info "Module $mod skipped by user."
        fi
    done

    log_section "Installation Complete"
    local errors
    errors=$(count_errors)
    if (( errors > 0 )); then
        log_warn "$errors error(s) recorded. Check the log: $(get_log_file)"
    else
        log_success "All modules completed successfully."
    fi
    show_status
}

# Main entry point
main() {
    # Check root
    if ! validate_root; then
        echo "ERROR: This installer must be run as root (use: sudo ./install.sh)"
        exit 1
    fi

    # Initialise logging
    init_log

    # Initialise status tracking
    init_status

    log_info "Installer started"

    while true; do
        show_main_menu
        read -rp "Select an option: " choice

        case "$choice" in
            1)
                run_full_install
                ;;
            2)
                show_module_menu
                read -rp "Enter module number (0-20): " mod
                # Zero-pad single digits (e.g. 2 -> 02)
                if [[ "$mod" =~ ^[0-9]$ ]]; then
                    mod="0$mod"
                fi
                if [[ -n "${MODULE_DESC[$mod]+x}" ]]; then
                    run_module "$mod"
                else
                    echo "Invalid module number: $mod"
                fi
                ;;
            3)
                show_status
                ;;
            4)
                if [[ -f "$LOG_FILE" ]]; then
                    echo ""
                    echo "Log file: $LOG_FILE"
                    echo "Last 30 log entries:"
                    echo "---"
                    grep '^\[' "$LOG_FILE" | tail -30
                    echo "---"
                    echo ""
                    local err_count
                    err_count=$(grep -c '\[ERROR\]' "$LOG_FILE" 2>/dev/null || echo "0")
                    echo "Errors found: $err_count"
                else
                    echo "No log file found."
                fi
                ;;
            5)
                if command -v kubectl &>/dev/null; then
                    k8s_health_summary
                else
                    echo "kubectl is not installed. Run module 03 first."
                fi
                ;;
            q|Q)
                log_info "Installer exited by user"
                echo "Log file saved to: $(get_log_file)"
                exit 0
                ;;
            *)
                echo "Invalid option: $choice"
                ;;
        esac
    done
}

main "$@"
