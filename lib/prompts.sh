#!/bin/bash
# prompts.sh — Interactive prompt helpers for the installer

# Ask a yes/no question. Returns 0 for yes, 1 for no.
# Usage: ask_yes_no "Question?" [default_yes|default_no]
ask_yes_no() {
    local question="$1"
    local default="${2:-default_yes}"
    local prompt

    if [[ "$default" == "default_yes" ]]; then
        prompt="$question [Y/n]: "
    else
        prompt="$question [y/N]: "
    fi

    while true; do
        read -rp "$prompt" answer
        case "${answer,,}" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
            "")
                if [[ "$default" == "default_yes" ]]; then
                    return 0
                else
                    return 1
                fi
                ;;
            *) echo "Please answer y or n." ;;
        esac
    done
}

# Ask for text input with a default value.
# Usage: result=$(ask_text "Prompt" "default_value")
ask_text() {
    local question="$1"
    local default="$2"
    local answer

    if [[ -n "$default" ]]; then
        read -rp "$question [$default]: " answer
        answer="${answer:-$default}"
        # Strip trailing carriage returns and whitespace
        answer="${answer%"${answer##*[![:space:]]}"}"
        answer="${answer#"${answer%%[![:space:]]*}"}"
        echo "$answer"
    else
        while true; do
            read -rp "$question: " answer
            answer="${answer%"${answer##*[![:space:]]}"}"
            answer="${answer#"${answer%%[![:space:]]*}"}"
            if [[ -n "$answer" ]]; then
                echo "$answer"
                return
            fi
            echo "Please enter a value." >&2
        done
    fi
}

# Ask for a number within a range.
# Usage: result=$(ask_number "Prompt" min max default)
ask_number() {
    local question="$1"
    local min="$2"
    local max="$3"
    local default="$4"
    local answer

    while true; do
        if [[ -n "$default" ]]; then
            read -rp "$question ($min-$max) [$default]: " answer
            answer="${answer:-$default}"
        else
            read -rp "$question ($min-$max): " answer
        fi

        if [[ "$answer" =~ ^[0-9]+$ ]] && (( answer >= min && answer <= max )); then
            echo "$answer"
            return
        fi
        echo "Please enter a number between $min and $max." >&2
    done
}

# Present a menu and return the selected option number (1-based).
# Usage: choice=$(ask_menu "Title" "Option 1" "Option 2" "Option 3")
ask_menu() {
    local title="$1"
    shift
    local options=("$@")
    local num_options=${#options[@]}

    echo "" >&2
    echo "$title" >&2
    echo "$(printf '=%.0s' $(seq 1 ${#title}))" >&2
    for i in "${!options[@]}"; do
        printf "  [%d] %s\n" $((i + 1)) "${options[$i]}" >&2
    done
    echo "" >&2

    local choice
    while true; do
        read -rp "Select an option (1-$num_options): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= num_options )); then
            echo "$choice"
            return
        fi
        echo "Please enter a number between 1 and $num_options." >&2
    done
}

# Present a multi-select menu. Returns space-separated indices (1-based).
# Usage: choices=$(ask_multi_menu "Title" "Option 1" "Option 2" "Option 3")
ask_multi_menu() {
    local title="$1"
    shift
    local options=("$@")
    local num_options=${#options[@]}

    echo "" >&2
    echo "$title" >&2
    echo "$(printf '=%.0s' $(seq 1 ${#title}))" >&2
    for i in "${!options[@]}"; do
        printf "  [%d] %s\n" $((i + 1)) "${options[$i]}" >&2
    done
    echo "" >&2

    local choices
    while true; do
        read -rp "Select options (space-separated numbers, or 'a' for all, 's' to skip): " choices
        if [[ "$choices" == "s" ]]; then
            echo ""
            return
        fi
        if [[ "$choices" == "a" ]]; then
            echo "$(seq 1 "$num_options" | tr '\n' ' ')"
            return
        fi
        # Validate all entries are valid numbers
        local valid=true
        for c in $choices; do
            if ! [[ "$c" =~ ^[0-9]+$ ]] || (( c < 1 || c > num_options )); then
                echo "Invalid selection: $c" >&2
                valid=false
                break
            fi
        done
        if $valid && [[ -n "$choices" ]]; then
            echo "$choices"
            return
        fi
        echo "Please enter valid option numbers separated by spaces." >&2
    done
}

# Display a warning and ask for confirmation
# Usage: ask_confirm_warning "Warning message"
ask_confirm_warning() {
    local message="$1"
    echo ""
    echo "WARNING: $message"
    echo ""
    ask_yes_no "Do you want to proceed?" "default_no"
}
