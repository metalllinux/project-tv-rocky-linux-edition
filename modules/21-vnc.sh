#!/bin/bash
# 21-vnc.sh — Set up VNC server for remote desktop access
# Uses krfb (KDE Desktop Sharing) which supports Wayland natively.

run() {
    log_section "VNC Server (Remote Desktop)"

    if ! ask_yes_no "Set up VNC server for remote desktop access?"; then
        log_info "Skipping VNC server setup"
        return 0
    fi

    # Install krfb (KDE's built-in VNC server)
    if ! rpm -q krfb &>/dev/null; then
        log_info "Installing krfb (KDE Desktop Sharing)..."
        log_cmd "Install krfb" dnf install -y krfb
    else
        log_success "krfb is already installed"
    fi

    # Detect the invoking user
    local target_user="${SUDO_USER:-$(ls /home/ 2>/dev/null | head -1)}"
    local target_home="/home/$target_user"

    if [[ -z "$target_user" ]]; then
        log_error "Could not detect user — skipping VNC configuration"
        return 1
    fi

    # Prompt for VNC password
    local vnc_password=""
    while [[ -z "$vnc_password" ]]; do
        read -rsp "Enter a password for VNC access: " vnc_password >&2
        echo "" >&2
        if [[ -z "$vnc_password" ]]; then
            echo "Please enter a password." >&2
        fi
    done

    # Configure krfb for unattended access
    log_info "Configuring krfb for unattended VNC access..."
    mkdir -p "$target_home/.config"
    cat > "$target_home/.config/krfbrc" << EOF
[Unattended]
allowUnattendedAccess=true
unattendedPassword=$vnc_password

[Desktop Sharing]
allowDesktopControl=true
allowUnattendedAccess=true
EOF
    chown "$target_user:$target_user" "$target_home/.config/krfbrc"

    # Create autostart entry so krfb starts on login
    mkdir -p "$target_home/.config/autostart"
    cat > "$target_home/.config/autostart/krfb.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=Desktop Sharing (VNC)
Comment=KDE Desktop Sharing for remote access
Exec=krfb --nodialog
Terminal=false
X-KDE-autostart-phase=2
EOF
    chown -R "$target_user:$target_user" "$target_home/.config/autostart"

    # Open firewall port for VNC
    if command -v firewall-cmd &>/dev/null; then
        if firewall-cmd --state &>/dev/null; then
            log_info "Opening firewall port 5900/tcp for VNC..."
            firewall-cmd --add-port=5900/tcp --permanent 2>/dev/null || true
            firewall-cmd --reload 2>/dev/null || true
            log_success "Firewall port 5900/tcp opened"
        fi
    fi

    # Try to start krfb now if a Wayland session is active
    local user_uid
    user_uid=$(id -u "$target_user")
    if [[ -S "/run/user/$user_uid/wayland-0" ]]; then
        log_info "Starting krfb in the current session..."
        su - "$target_user" -c "export XDG_RUNTIME_DIR=/run/user/$user_uid; export WAYLAND_DISPLAY=wayland-0; export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$user_uid/bus; nohup krfb --nodialog &>/dev/null &" || true
        sleep 2
        if pgrep -u "$target_user" krfb &>/dev/null; then
            log_success "krfb is running"
        else
            log_warn "krfb could not start now — it will start automatically on next login"
        fi
    else
        log_info "No active Wayland session — krfb will start automatically on next login"
    fi

    local host_ip
    host_ip=$(hostname -I | awk '{print $1}')

    log_success "VNC server configured"
    echo ""
    echo "Connect with any VNC client to: $host_ip:5900"
    echo "The VNC server will start automatically when you log in to KDE."
}
