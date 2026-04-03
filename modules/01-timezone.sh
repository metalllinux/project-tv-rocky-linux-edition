#!/bin/bash
# 01-timezone.sh — Set the system timezone

run() {
    log_info "Current timezone: $(timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo 'unknown')"

    local tz
    tz=$(ask_text "Enter timezone" "$TIMEZONE")

    # Validate timezone (file check avoids pipefail issues with grep -q)
    if [[ ! -f "/usr/share/zoneinfo/$tz" ]]; then
        log_error "Invalid timezone: $tz"
        log_info "List valid timezones with: timedatectl list-timezones"
        return 1
    fi

    log_cmd "Set timezone to $tz" timedatectl set-timezone "$tz"

    # Enable NTP synchronisation
    log_cmd "Enable NTP synchronisation" timedatectl set-ntp true

    log_success "Timezone set to $tz"
    timedatectl 2>&1
}
