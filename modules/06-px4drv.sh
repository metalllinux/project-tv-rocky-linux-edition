#!/bin/bash
# 06-px4drv.sh — Install px4_drv TV tuner DKMS driver
# Installs from the RPM if available, otherwise builds from source.

run() {
    log_section "px4_drv TV Tuner Driver Installation"

    # Check if already installed
    if lsmod | grep -q '^px4_drv'; then
        log_info "px4_drv module is already loaded"
        modinfo px4_drv 2>&1 | head -5
        if ask_yes_no "Skip px4_drv installation?" "default_yes"; then
            return 0
        fi
    fi

    # Install prerequisites
    log_cmd "Install build prerequisites" dnf install -y \
        dkms gcc make "kernel-devel-$(uname -r)" epel-release

    # Install card reader support
    log_info "Installing SmartCard reader support (for B-CAS card)..."
    log_cmd "Install pcsc packages" dnf install -y \
        pcsc-lite pcsc-lite-devel pcsc-lite-ccid

    log_cmd "Enable pcscd" systemctl enable --now pcscd

    # Check for pre-built RPM
    local rpm_file
    rpm_file=$(find "$PROJECT_ROOT/drivers" -name "px4_drv-dkms*.rpm" 2>/dev/null | head -1)

    if [[ -n "$rpm_file" ]]; then
        log_info "Found pre-built RPM: $rpm_file"
        log_cmd "Install px4_drv RPM" dnf install -y "$rpm_file"
    else
        log_info "No pre-built RPM found, building from source..."
        install_from_source
    fi

    # Load the module
    log_cmd "Load px4_drv module" modprobe px4_drv

    # Verify
    if lsmod | grep -q '^px4_drv'; then
        log_success "px4_drv module loaded successfully"
        modinfo px4_drv 2>&1
    else
        log_error "px4_drv module failed to load"
        return 1
    fi

    # Check for devices
    if ls /dev/px4video* &>/dev/null; then
        log_success "TV tuner devices detected:"
        ls -la /dev/px4video* 2>&1
    else
        log_info "No /dev/px4video* devices found (normal if TV tuner hardware is not connected)"
    fi

    # Check SmartCard reader
    if lsusb 2>/dev/null | grep -qi "SCM\|04e6:5116\|SmartCard"; then
        log_success "SmartCard reader detected"
        if systemctl is-active pcscd &>/dev/null; then
            log_success "pcscd service is running"
        else
            log_warn "pcscd service is not running"
        fi
    else
        log_info "No SmartCard reader detected"
    fi
}

install_from_source() {
    local src_dir=$(mktemp -d)
    local version="0.5.5"

    log_cmd "Clone px4_drv" git clone --depth 1 \
        https://github.com/metalllinux/px4_drv.git "$src_dir/px4_drv"

    cd "$src_dir/px4_drv" || return 1

    # Patch for Rocky Linux 10 (kernel 6.12) — EL backported the objtool
    # module_init() requirement from 6.15.4, so lower the version gate
    local driver_module="driver/driver_module.c"
    if [[ -f "$driver_module" ]] && grep -q 'KERNEL_VERSION(6,15,4)' "$driver_module"; then
        log_info "Patching driver_module.c for kernel 6.12+ compatibility..."
        sed -i 's/KERNEL_VERSION(6,15,4)/KERNEL_VERSION(6,12,0)/g' "$driver_module"
    fi

    # Install via DKMS
    local dkms_name="px4_drv"
    local dkms_src="/usr/src/${dkms_name}-${version}"

    # Copy source to DKMS location
    mkdir -p "$dkms_src"
    cp -a driver/ "$dkms_src/"
    cp -a include/ "$dkms_src/"
    cp -a dkms.conf "$dkms_src/"
    if [[ -d dkms/ ]]; then
        cp -a dkms/ "$dkms_src/"
    fi

    # Install firmware and udev rules
    cp -f etc/it930x-firmware.bin /lib/firmware/
    cp -f etc/99-px4video.rules /etc/udev/rules.d/

    # Register with DKMS (remove old entry if present)
    if dkms status -m "$dkms_name" -v "$version" 2>/dev/null | grep -q "$dkms_name"; then
        log_info "Removing existing DKMS entry for ${dkms_name}/${version}..."
        dkms remove -m "$dkms_name" -v "$version" --all 2>/dev/null || true
    fi
    log_cmd "DKMS add" dkms add -m "$dkms_name" -v "$version"
    log_cmd "DKMS build" dkms build -m "$dkms_name" -v "$version"
    log_cmd "DKMS install" dkms install -m "$dkms_name" -v "$version"

    # Reload udev rules
    udevadm control --reload-rules
    udevadm trigger

    # Cleanup
    rm -rf "$src_dir"

    cd "$PROJECT_ROOT" || true
}
