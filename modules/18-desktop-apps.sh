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
    # AppImages require FUSE to mount themselves — install fuse (provides fusermount)
    if ! rpm -q fuse &>/dev/null; then
        log_info "Installing fuse (required for AppImage)..."
        dnf install -y fuse 2>&1 || true
    fi

    echo ""
    echo "SeaDrive (Seafile virtual drive client)"
    echo ""
    echo "Download the SeaDrive AppImage from:"
    echo "  https://www.seafile.com/en/download/"
    echo ""
    echo "After downloading, place the AppImage in ~/Applications/ and make it executable:"
    echo "  mkdir -p ~/Applications"
    echo "  mv ~/Downloads/SeaDrive*.AppImage ~/Applications/SeaDrive.AppImage"
    echo "  chmod +x ~/Applications/SeaDrive.AppImage"
    echo ""
    log_success "SeaDrive download instructions displayed"
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
