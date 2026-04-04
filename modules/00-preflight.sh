#!/bin/bash
# 00-preflight.sh — System checks before installation
# Verifies Rocky Linux version, hardware, kernel, and prerequisites.

run() {
    log_info "Running preflight checks..."

    local failed=0

    # Check Rocky Linux
    log_info "Checking operating system..."
    if validate_rocky_linux; then
        local version
        version=$(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')
        log_success "Operating system: $version"
    else
        log_error "This installer requires Rocky Linux."
        failed=1
    fi

    # Check Rocky Linux major version
    local rocky_major
    rocky_major=$(grep '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"' | cut -d. -f1)
    log_info "Rocky Linux major version: $rocky_major"
    if [[ "$rocky_major" == "10" ]]; then
        log_success "Rocky Linux 10 — primary supported version"
    elif [[ "$rocky_major" == "9" ]]; then
        log_warn "Rocky Linux 9 — supported with some differences (see PLATFORM_NOTES.md)"
    elif [[ "$rocky_major" == "8" ]]; then
        log_warn "Rocky Linux 8 — supported with some differences (see PLATFORM_NOTES.md)"
    else
        log_warn "Rocky Linux $rocky_major — not tested, proceed with caution"
    fi

    # Check architecture
    local arch
    arch=$(uname -m)
    if [[ "$arch" == "x86_64" ]]; then
        log_success "Architecture: $arch"
    else
        log_error "Unsupported architecture: $arch (x86_64 required)"
        failed=1
    fi

    # Check kernel
    log_info "Kernel: $(uname -r)"

    # Check RAM
    local total_ram_mb
    total_ram_mb=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)
    if (( total_ram_mb >= 16384 )); then
        log_success "RAM: ${total_ram_mb}MB (meets 16GB recommendation)"
    elif (( total_ram_mb >= 8192 )); then
        log_warn "RAM: ${total_ram_mb}MB (16GB recommended, some services may be constrained)"
    else
        log_warn "RAM: ${total_ram_mb}MB (16GB recommended)"
    fi

    # Check CPU cores
    local cpu_cores
    cpu_cores=$(nproc)
    if (( cpu_cores >= 4 )); then
        log_success "CPU cores: $cpu_cores"
    else
        log_warn "CPU cores: $cpu_cores (4+ recommended)"
    fi

    # Check internet connectivity
    log_info "Checking internet connectivity..."
    if curl -sf --max-time 10 https://dl.rockylinux.org/ &>/dev/null; then
        log_success "Internet connectivity: OK"
    else
        log_error "Cannot reach dl.rockylinux.org — internet required for installation"
        failed=1
    fi

    # Check sudo/root
    if [[ $EUID -eq 0 ]]; then
        log_success "Running as root"
    else
        log_error "Not running as root"
        failed=1
    fi

    # Install prerequisites if missing
    log_info "Checking prerequisites..."
    local missing_pkgs=()

    rpm -q "kernel-devel-$(uname -r)" &>/dev/null || missing_pkgs+=("kernel-devel-$(uname -r)")
    rpm -q "kernel-modules-extra-$(uname -r)" &>/dev/null || missing_pkgs+=("kernel-modules-extra-$(uname -r)")
    rpm -q git &>/dev/null || missing_pkgs+=("git")
    rpm -q gcc &>/dev/null || missing_pkgs+=("gcc")
    rpm -q make &>/dev/null || missing_pkgs+=("make")
    rpm -q curl &>/dev/null || missing_pkgs+=("curl")
    rpm -q podman &>/dev/null || missing_pkgs+=("podman")
    rpm -q epel-release &>/dev/null || missing_pkgs+=("epel-release")

    if (( ${#missing_pkgs[@]} > 0 )); then
        log_info "Installing missing prerequisites: ${missing_pkgs[*]}"
        if ask_yes_no "Install ${#missing_pkgs[@]} missing package(s)?"; then
            dnf install -y "${missing_pkgs[@]}" 2>&1 || true
            # Enable CRB repo (needed for some dependencies)
            dnf config-manager --set-enabled crb 2>/dev/null || true
            log_success "Prerequisites installed"
        else
            log_warn "Some prerequisites are missing — modules may fail"
        fi
    else
        log_success "All prerequisites installed"
    fi

    # Load netfilter modules for Kubernetes (if kernel-modules-extra is available)
    for mod in nf_conntrack br_netfilter xt_conntrack overlay; do
        modprobe "$mod" 2>/dev/null || true
    done

    # Check available disk devices (for ZFS)
    log_info "Available block devices:"
    lsblk -d -n -o NAME,SIZE,TYPE,MOUNTPOINT 2>&1 | while read -r line; do
        log_info "  $line"
    done

    # Check for TV tuner hardware (informational)
    log_info "Checking for PX TV tuner hardware..."
    if lsusb 2>/dev/null | grep -qi "plex\|px4\|0511:073f\|N'Able"; then
        log_success "PX TV tuner detected via USB"
        lsusb 2>/dev/null | grep -i "plex\|px4\|0511:073f\|N'Able" | while read -r line; do
            log_info "  $line"
        done
    else
        log_info "No PX TV tuner detected (OK if not using TV recording features)"
    fi

    # Check for SmartCard reader
    if lsusb 2>/dev/null | grep -qi "SCM\|04e6:5116\|SmartCard"; then
        log_success "SmartCard reader detected via USB"
    else
        log_info "No SmartCard reader detected (needed for B-CAS card with Mirakurun)"
    fi

    # Check existing installations
    log_info "Checking for existing installations..."
    if command -v kubectl &>/dev/null; then
        log_info "  kubectl: $(kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null | head -1)"
    else
        log_info "  kubectl: not installed"
    fi
    if command -v kubeadm &>/dev/null; then
        log_info "  kubeadm: $(kubeadm version -o short 2>/dev/null || echo 'installed')"
    else
        log_info "  kubeadm: not installed"
    fi
    if command -v zfs &>/dev/null; then
        log_info "  ZFS: $(zfs version 2>/dev/null | head -1 || echo 'installed')"
    else
        log_info "  ZFS: not installed"
    fi
    if command -v flatpak &>/dev/null; then
        log_success "  Flatpak: installed"
    else
        log_info "  Flatpak: not installed"
    fi

    # Summary
    echo ""
    if (( failed > 0 )); then
        log_error "Preflight checks found $failed critical issue(s). Please resolve before continuing."
        return 1
    else
        log_success "All preflight checks passed."
        return 0
    fi
}
