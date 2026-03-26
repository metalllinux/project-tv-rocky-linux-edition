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

    # Japanese input (fcitx5-mozc)
    if ask_yes_no "Install Japanese input (fcitx5-mozc)?"; then
        log_cmd "Install fcitx5-mozc" dnf install -y fcitx5 fcitx5-mozc fcitx5-configtool

        # Set environment variables
        cat > /etc/profile.d/fcitx5.sh << 'EOF'
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
EOF
        log_success "fcitx5-mozc installed"
    fi

    log_success "KDE customisation complete"
}
