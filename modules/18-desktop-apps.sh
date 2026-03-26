#!/bin/bash
# 18-desktop-apps.sh — Optional desktop applications

run() {
    log_section "Desktop Applications"

    # SeaDrive
    if ask_yes_no "Install SeaDrive desktop client (Seafile virtual drive for Dolphin)?"; then
        install_seadrive
    fi

    # MakeMKV
    if ask_yes_no "Install MakeMKV (DVD/Blu-ray ripper) via Flatpak?"; then
        install_flatpak_app "MakeMKV" "com.makemkv.MakeMKV"
    fi

    # Jellyfin Media Player
    if ask_yes_no "Install Jellyfin Media Player via Flatpak?"; then
        install_flatpak_app "Jellyfin Media Player" "com.github.iwalton3.jellyfin-media-player"
    fi

    log_success "Desktop application installation complete"
}

install_seadrive() {
    log_info "Installing SeaDrive desktop client..."

    local rocky_major
    rocky_major=$(grep '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"' | cut -d. -f1)

    # Try Flatpak first
    if command -v flatpak &>/dev/null; then
        log_info "Checking Flathub for SeaDrive..."
        if flatpak search seadrive 2>/dev/null | grep -qi seadrive; then
            log_cmd "Install SeaDrive via Flatpak" flatpak install -y flathub com.seafile.seadrive-gui
            log_success "SeaDrive installed via Flatpak"
            return 0
        fi
    fi

    # Try RPM repo
    log_info "Attempting RPM installation..."
    cat > /etc/yum.repos.d/seadrive.repo << EOF
[seadrive]
name=seadrive
baseurl=https://linux-clients.seafile.com/seadrive-packages/rocky\$releasever/
gpgcheck=0
enabled=1
EOF

    if dnf install -y seadrive-gui 2>&1; then
        log_success "SeaDrive installed via RPM"
    else
        log_warn "SeaDrive RPM installation failed. You may need to install manually."
        log_info "Visit: https://www.seafile.com/en/download/"
        # Clean up repo file if install failed
        rm -f /etc/yum.repos.d/seadrive.repo
    fi
}

install_flatpak_app() {
    local name="$1"
    local app_id="$2"

    if ! command -v flatpak &>/dev/null; then
        log_cmd "Install Flatpak" dnf install -y flatpak
    fi

    if ! flatpak remote-list | grep -q flathub; then
        flatpak remote-add --if-not-exists flathub \
            https://dl.flathub.org/repo/flathub.flatpakrepo
    fi

    if flatpak install -y flathub "$app_id" 2>&1; then
        log_success "$name installed"
    else
        log_error "Failed to install $name ($app_id)"
    fi
}
