#!/bin/bash
# 15-browser.sh — Browser installation via Flatpak

# Browser definitions: display_name:flatpak_id
BROWSERS=(
    "Google Chrome:com.google.Chrome"
    "Brave Browser:com.brave.Browser"
    "Waterfox:net.waterfox.waterfox"
    "Firefox:org.mozilla.firefox"
    "Vivaldi:com.vivaldi.Vivaldi"
    "Chromium:org.chromium.Chromium"
    "Microsoft Edge:com.microsoft.Edge"
)

run() {
    log_section "Browser Installation"

    # Ensure Flatpak is installed
    if ! command -v flatpak &>/dev/null; then
        log_cmd "Install Flatpak" dnf install -y flatpak
    fi

    # Ensure Flathub remote
    if ! flatpak remote-list | grep -q flathub; then
        log_cmd "Add Flathub" flatpak remote-add --if-not-exists flathub \
            https://dl.flathub.org/repo/flathub.flatpakrepo
    fi

    # Build menu options
    local options=()
    for browser_def in "${BROWSERS[@]}"; do
        local name="${browser_def%%:*}"
        local app_id="${browser_def##*:}"
        local installed=""
        if flatpak list --app 2>/dev/null | grep -q "$app_id"; then
            installed=" [INSTALLED]"
        fi
        options+=("${name}${installed}")
    done

    echo ""
    echo "Select browsers to install via Flatpak"
    echo "======================================="
    for i in "${!options[@]}"; do
        printf "  [%d] %s\n" $((i + 1)) "${options[$i]}"
    done
    echo "  [s] Skip"
    echo ""

    read -rp "Enter numbers separated by spaces (or 'a' for all, 's' to skip): " selections

    if [[ "$selections" == "s" ]]; then
        log_info "Browser installation skipped"
        return 0
    fi

    if [[ "$selections" == "a" ]]; then
        selections=$(seq 1 ${#BROWSERS[@]} | tr '\n' ' ')
    fi

    local installed_count=0
    for sel in $selections; do
        if (( sel >= 1 && sel <= ${#BROWSERS[@]} )); then
            local browser_def="${BROWSERS[$((sel - 1))]}"
            local name="${browser_def%%:*}"
            local app_id="${browser_def##*:}"

            log_info "Installing $name ($app_id)..."
            if flatpak install -y flathub "$app_id" 2>&1; then
                log_success "$name installed"
                installed_count=$((installed_count + 1))
            else
                log_error "Failed to install $name"
            fi
        fi
    done

    log_success "Installed $installed_count browser(s)"

    # Offer to set default browser
    if (( installed_count > 0 )); then
        if ask_yes_no "Set a default browser?"; then
            # Build list of installed browsers
            local -a installed_browsers=()
            local -a installed_ids=()
            for browser_def in "${BROWSERS[@]}"; do
                local name="${browser_def%%:*}"
                local app_id="${browser_def##*:}"
                if flatpak list --app 2>/dev/null | grep -q "$app_id"; then
                    installed_browsers+=("$name")
                    installed_ids+=("$app_id")
                fi
            done

            local default_app=""
            if (( ${#installed_browsers[@]} == 1 )); then
                # Only one browser installed — use it automatically
                default_app="${installed_ids[0]}"
                echo "Setting ${installed_browsers[0]} ($default_app) as default..."
            else
                echo ""
                echo "Installed browsers:"
                for i in "${!installed_browsers[@]}"; do
                    printf "  [%d] %s (%s)\n" "$((i + 1))" "${installed_browsers[$i]}" "${installed_ids[$i]}"
                done
                echo ""
                local choice
                read -rp "Select a browser (1-${#installed_browsers[@]}): " choice
                if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#installed_browsers[@]} )); then
                    default_app="${installed_ids[$((choice - 1))]}"
                fi
            fi

            if [[ -n "$default_app" ]]; then
                local target_user="${SUDO_USER:-$(whoami)}"
                su - "$target_user" -c "xdg-settings set default-web-browser '${default_app}.desktop'" 2>/dev/null || \
                    log_warn "Could not set default browser (set it manually from KDE System Settings)"
                log_success "Default browser set to $default_app"
            fi
        fi
    fi
}
