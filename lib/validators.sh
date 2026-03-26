#!/bin/bash
# validators.sh — Input validation functions for the installer

# Validate that the system is running Rocky Linux
# Usage: validate_rocky_linux [required_major_version]
validate_rocky_linux() {
    local required_major="${1:-}"

    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot find /etc/os-release"
        return 1
    fi

    local os_id
    os_id=$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
    if [[ "$os_id" != "rocky" ]]; then
        log_error "This installer requires Rocky Linux. Detected: $os_id"
        return 1
    fi

    if [[ -n "$required_major" ]]; then
        local version_id
        version_id=$(grep '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"' | cut -d. -f1)
        if [[ "$version_id" != "$required_major" ]]; then
            log_warn "Expected Rocky Linux $required_major, detected $version_id"
            return 1
        fi
    fi

    return 0
}

# Validate that the script is running as root or with sudo
validate_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This installer must be run as root (use sudo ./install.sh)"
        return 1
    fi
    return 0
}

# Validate a ZFS pool name (alphanumeric, hyphens, underscores)
validate_pool_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
        echo "Pool name must start with a letter and contain only letters, numbers, hyphens, and underscores."
        return 1
    fi
    if [[ ${#name} -gt 64 ]]; then
        echo "Pool name must be 64 characters or fewer."
        return 1
    fi
    return 0
}

# Validate a ZFS dataset name (alphanumeric, hyphens, underscores)
validate_dataset_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; then
        echo "Dataset name must start with a letter or number and contain only letters, numbers, hyphens, underscores, and dots."
        return 1
    fi
    return 0
}

# Validate a mount point path (must be absolute)
validate_mount_point() {
    local path="$1"
    if [[ ! "$path" =~ ^/ ]]; then
        echo "Mount point must be an absolute path (starting with /)."
        return 1
    fi
    return 0
}

# Validate an IP address (basic IPv4 check)
validate_ip() {
    local ip="$1"
    if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 1
    fi
    local IFS='.'
    read -ra octets <<< "$ip"
    for octet in "${octets[@]}"; do
        if (( octet > 255 )); then
            return 1
        fi
    done
    return 0
}

# Validate a port number
validate_port() {
    local port="$1"
    if [[ ! "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
        return 1
    fi
    return 0
}

# Validate that a command is available
# Usage: validate_command "kubectl" "kubectl is required"
validate_command() {
    local cmd="$1"
    local msg="${2:-$cmd is not installed}"
    if ! command -v "$cmd" &>/dev/null; then
        log_error "$msg"
        return 1
    fi
    return 0
}

# Validate that a kernel module can be loaded
validate_kernel_module() {
    local module="$1"
    if lsmod | grep -q "^${module}"; then
        return 0
    fi
    if modprobe --dry-run "$module" &>/dev/null; then
        return 0
    fi
    log_error "Kernel module $module is not available"
    return 1
}

# Validate that a block device exists
validate_block_device() {
    local device="$1"
    if [[ ! -b "$device" ]]; then
        log_error "$device is not a valid block device"
        return 1
    fi
    return 0
}

# Validate minimum RAM (in MB)
validate_min_ram() {
    local required_mb="$1"
    local total_mb
    total_mb=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)
    if (( total_mb < required_mb )); then
        log_warn "System has ${total_mb}MB RAM, recommended minimum is ${required_mb}MB"
        return 1
    fi
    return 0
}

# Validate that a URL is reachable
validate_url() {
    local url="$1"
    local timeout="${2:-10}"
    if curl -sf --max-time "$timeout" "$url" &>/dev/null; then
        return 0
    fi
    return 1
}
