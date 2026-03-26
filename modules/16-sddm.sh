#!/bin/bash
# 16-sddm.sh — SDDM autologin configuration

run() {
    log_section "SDDM Autologin Configuration"

    if ! command -v sddm &>/dev/null; then
        log_warn "SDDM is not installed. Skipping."
        return 0
    fi

    local target_user="${SUDO_USER:-$(whoami)}"

    if ask_yes_no "Enable SDDM autologin for user '$target_user'?"; then
        mkdir -p /etc/sddm.conf.d
        cat > /etc/sddm.conf.d/autologin.conf << EOF
[Autologin]
User=${target_user}
Session=plasma.desktop
EOF
        log_success "SDDM autologin enabled for $target_user (session: plasma.desktop)"
    else
        log_info "SDDM autologin skipped"
    fi
}
