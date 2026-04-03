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
    log_info "Installing SeaDrive desktop client via AppImage..."

    local target_user="${SUDO_USER:-$(whoami)}"
    local target_home
    target_home=$(eval echo "~$target_user")
    local appimage_dir="$target_home/Applications"
    local appimage_url="https://linux-clients.seafile.com/seadrive-sharedlib/seadrive-gui_2.0.28_x86-64.AppImage"
    local appimage_file="$appimage_dir/SeaDrive.AppImage"

    mkdir -p "$appimage_dir"

    log_info "Downloading SeaDrive AppImage..."
    if curl -fSL --connect-timeout 15 -o "$appimage_file" "$appimage_url" 2>&1; then
        chmod +x "$appimage_file"
        chown "$target_user:$target_user" "$appimage_dir" "$appimage_file"

        # Create desktop entry
        cat > "$target_home/.local/share/applications/seadrive.desktop" << EOF
[Desktop Entry]
Type=Application
Name=SeaDrive
Comment=Seafile virtual drive client
Exec=$appimage_file
Icon=seafile
Categories=Network;FileTransfer;
EOF
        chown "$target_user:$target_user" "$target_home/.local/share/applications/seadrive.desktop"
        log_success "SeaDrive installed at $appimage_file"
    else
        log_warn "SeaDrive download failed. Download manually from: https://www.seafile.com/en/download/"
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
