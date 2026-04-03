#!/bin/bash
# 14-kde.sh — KDE desktop customisations for media server use

run() {
    log_section "KDE Desktop Customisation"

    # Check if KDE is installed
    if ! rpm -q plasma-desktop &>/dev/null && ! rpm -q plasma-workspace &>/dev/null; then
        log_info "KDE Plasma not detected. Installing..."
        log_cmd "Install KDE Plasma" dnf groupinstall -y "KDE Plasma Workspaces"
    else
        log_success "KDE Plasma is installed"
    fi

    local target_user="${SUDO_USER:-$(whoami)}"
    local target_home
    target_home=$(eval echo "~$target_user")

    # Disable lock screen
    if ask_yes_no "Disable KDE lock screen?" "default_yes"; then
        local screenlocker_dir="$target_home/.config"
        mkdir -p "$screenlocker_dir"
        # kscreenlockerrc
        cat > "$screenlocker_dir/kscreenlockerrc" << 'EOF'
[Daemon]
Autolock=false
LockOnResume=false
EOF
        chown "$target_user:$target_user" "$screenlocker_dir/kscreenlockerrc"
        log_success "Lock screen disabled"
    fi

    # Disable screen power saving
    if ask_yes_no "Disable screen power saving (prevent screen blank)?" "default_yes"; then
        local powermanagement_dir="$target_home/.config"
        cat > "$powermanagement_dir/powermanagementprofilesrc" << 'EOF'
[AC][DPMSControl]
idleTime=0
lockBeforeTurnOff=0

[AC][SuspendSession]
idleTime=0
suspendThenHibernate=false
suspendType=0
EOF
        chown "$target_user:$target_user" "$powermanagement_dir/powermanagementprofilesrc"
        log_success "Screen power saving disabled"
    fi

    # Japanese input (ibus-anthy — fcitx5-mozc is not available in Rocky 10 repos)
    if ask_yes_no "Install Japanese input (ibus-anthy)?"; then
        if ! log_cmd "Install ibus-anthy" dnf install -y ibus ibus-anthy ibus-gtk3 ibus-gtk4 ibus-setup; then
            log_error "Japanese input installation failed"
        else
            # Set environment variables for IBus
            cat > /etc/profile.d/ibus-japanese.sh << 'EOF'
export GTK_IM_MODULE=ibus
export QT_IM_MODULE=ibus
export XMODIFIERS=@im=ibus
EOF
            log_success "ibus-anthy installed — log out and back in, then configure via IBus Preferences"
        fi
    fi

    log_success "KDE customisation complete"
}
