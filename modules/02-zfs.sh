#!/bin/bash
# 02-zfs.sh — ZFS installation and dynamic pool/dataset creation
# Installs OpenZFS, creates a pool, and interactively creates user-specified datasets.

DATASETS_CONF="$PROJECT_ROOT/config/datasets.conf"

install_zfs() {
    log_info "Installing ZFS..."

    local rocky_major
    rocky_major=$(grep '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"' | cut -d. -f1)

    # Install kernel-devel for the running kernel
    log_cmd "Install kernel-devel" dnf install -y "kernel-devel-$(uname -r)" || \
        log_cmd "Install kernel-devel (latest)" dnf install -y kernel-devel

    # Install EPEL (needed for DKMS on some versions)
    log_cmd "Install EPEL" dnf install -y epel-release

    # Install ZFS repo
    case "$rocky_major" in
        10)
            log_cmd "Install ZFS repo for EL10" \
                dnf install -y "https://zfsonlinux.org/epel/zfs-release-3-0.el${rocky_major}.noarch.rpm"
            ;;
        9)
            log_cmd "Install ZFS repo for EL9" \
                dnf install -y "https://zfsonlinux.org/epel/zfs-release-2-3.el${rocky_major}.noarch.rpm"
            ;;
        8)
            log_cmd "Install ZFS repo for EL8" \
                dnf install -y "https://zfsonlinux.org/epel/zfs-release-2-2.el${rocky_major}.noarch.rpm"
            ;;
        *)
            log_error "Unsupported Rocky Linux version $rocky_major for ZFS"
            return 1
            ;;
    esac

    # Install DKMS-based ZFS (preferred for compatibility)
    log_cmd "Install ZFS DKMS" dnf install -y zfs-dkms zfs

    # Load ZFS kernel module
    log_cmd "Load ZFS module" modprobe zfs

    # Verify
    if ! lsmod | grep -q '^zfs'; then
        log_error "ZFS module failed to load"
        return 1
    fi

    log_success "ZFS installed: $(zfs version 2>/dev/null | head -1)"
}

create_pool() {
    log_section "ZFS Pool Creation"

    # Show available disks
    echo ""
    echo "Available block devices:"
    echo "========================"
    lsblk -d -n -o NAME,SIZE,TYPE,MOUNTPOINT,MODEL | grep -v "loop\|sr" | while read -r line; do
        echo "  $line"
    done
    echo ""
    echo "Disk IDs (recommended for pool creation):"
    echo "==========================================="
    ls -1 /dev/disk/by-id/ 2>/dev/null | grep -v "part\|wwn" | while read -r line; do
        echo "  /dev/disk/by-id/$line"
    done
    echo ""

    # Pool name
    local pool_name
    while true; do
        pool_name=$(ask_text "Enter ZFS pool name" "$ZFS_POOL_NAME")
        if validate_pool_name "$pool_name"; then
            break
        fi
    done

    # Check if pool already exists
    if zpool list "$pool_name" &>/dev/null; then
        log_warn "Pool '$pool_name' already exists."
        if ask_yes_no "Use existing pool?" "default_yes"; then
            ZFS_POOL_NAME="$pool_name"
            return 0
        fi
    fi

    # Pool type
    local pool_type
    pool_type=$(ask_menu "Select pool type" "mirror (2 disks, redundant)" "single (1 disk, no redundancy)" "raidz1 (3+ disks)" "raidz2 (4+ disks)")
    local pool_type_name
    case "$pool_type" in
        1) pool_type_name="mirror" ;;
        2) pool_type_name="" ;;
        3) pool_type_name="raidz1" ;;
        4) pool_type_name="raidz2" ;;
    esac

    # Disk selection
    local min_disks=1
    case "$pool_type_name" in
        mirror) min_disks=2 ;;
        raidz1) min_disks=3 ;;
        raidz2) min_disks=4 ;;
    esac

    echo ""
    local disks=()
    local disk_count
    disk_count=$(ask_number "How many disks for the pool?" "$min_disks" 12 "$min_disks")

    for ((i = 1; i <= disk_count; i++)); do
        local disk
        disk=$(ask_text "Enter disk $i (run 'ls -l /dev/disk/by-id/' to list disk IDs)")
        if [[ ! -e "$disk" ]]; then
            log_warn "$disk does not exist. Are you sure?"
            if ! ask_yes_no "Continue with this disk path?"; then
                return 1
            fi
        fi
        disks+=("$disk")
    done

    # Mount base
    local mount_base
    mount_base=$(ask_text "Enter base mount path" "$ZFS_MOUNT_BASE")

    # Confirm
    echo ""
    echo "Pool configuration:"
    echo "  Name: $pool_name"
    echo "  Type: ${pool_type_name:-single}"
    echo "  Disks: ${disks[*]}"
    echo "  Mount: $mount_base/$pool_name"
    echo "  ashift: $ZFS_ASHIFT"
    echo ""

    if ! ask_yes_no "Create this pool?"; then
        log_info "Pool creation cancelled."
        return 1
    fi

    # Check if any disks have existing filesystems
    local force_flag=""
    local has_existing=false
    for d in "${disks[@]}"; do
        if blkid "$d" &>/dev/null || blkid "${d}-part"* &>/dev/null 2>&1; then
            has_existing=true
            log_warn "Disk $d contains an existing filesystem or partition table:"
            blkid "$d"* 2>/dev/null | while read -r line; do echo "  $line"; done
        fi
    done
    if $has_existing; then
        echo ""
        log_warn "One or more disks contain existing data. ALL DATA WILL BE DESTROYED."
        if ask_yes_no "Force pool creation and overwrite existing data?" "default_no"; then
            force_flag="-f"
        else
            log_info "Pool creation cancelled."
            return 1
        fi
    fi

    # Create mount point
    mkdir -p "$mount_base"

    # Create pool
    local pool_cmd="zpool create $force_flag -o ashift=$ZFS_ASHIFT -O mountpoint=$mount_base/$pool_name $pool_name"
    if [[ -n "$pool_type_name" ]]; then
        pool_cmd="$pool_cmd $pool_type_name"
    fi
    pool_cmd="$pool_cmd ${disks[*]}"

    if ! log_cmd "Create ZFS pool" bash -c "$pool_cmd"; then
        log_error "Pool creation failed. Check the disk paths and pool type."
        return 1
    fi

    ZFS_POOL_NAME="$pool_name"
    ZFS_MOUNT_BASE="$mount_base"

    log_success "ZFS pool '$pool_name' created at $mount_base/$pool_name"
    zpool status "$pool_name" 2>&1
}

create_datasets() {
    log_section "ZFS Dataset Creation"

    local num_datasets
    num_datasets=$(ask_number "How many datasets do you want to create?" 1 50 15)

    # Clear existing datasets config
    echo "# ZFS dataset configuration — generated by installer" > "$DATASETS_CONF"
    echo "# Format: dataset_name:mount_point" >> "$DATASETS_CONF"
    echo "ZFS_POOL_NAME=$ZFS_POOL_NAME" >> "$DATASETS_CONF"
    echo "ZFS_MOUNT_BASE=$ZFS_MOUNT_BASE" >> "$DATASETS_CONF"
    echo "" >> "$DATASETS_CONF"

    local pool_mount="$ZFS_MOUNT_BASE/$ZFS_POOL_NAME"

    for ((i = 1; i <= num_datasets; i++)); do
        echo ""
        echo "--- Dataset $i of $num_datasets ---"

        local ds_name
        while true; do
            ds_name=$(ask_text "Dataset $i name (e.g. anime, films, music)")
            if validate_dataset_name "$ds_name"; then
                break
            fi
        done

        local ds_mount
        ds_mount=$(ask_text "Mount point for '$ds_name'" "$pool_mount/$ds_name")

        # Create the dataset
        local full_ds_name="$ZFS_POOL_NAME/$ds_name"
        if zfs list "$full_ds_name" &>/dev/null; then
            log_warn "Dataset '$full_ds_name' already exists, skipping creation."
        else
            log_cmd "Create dataset $full_ds_name" \
                zfs create -o mountpoint="$ds_mount" "$full_ds_name"
        fi

        # Set ownership to the invoking user (SUDO_USER if available)
        local owner="${SUDO_USER:-$(whoami)}"
        chown "$owner:$owner" "$ds_mount" 2>/dev/null || true

        # Record in config
        echo "$ds_name:$ds_mount" >> "$DATASETS_CONF"

        log_success "Dataset $full_ds_name mounted at $ds_mount"
    done

    echo ""
    log_success "Created $num_datasets dataset(s). Configuration saved to $DATASETS_CONF"
    echo ""
    echo "Datasets:"
    zfs list -r "$ZFS_POOL_NAME" 2>&1
}

run() {
    # Install ZFS if not present
    if command -v zfs &>/dev/null && lsmod | grep -q '^zfs'; then
        log_info "ZFS is already installed: $(zfs version 2>/dev/null | head -1)"
        if ! ask_yes_no "Skip ZFS installation?" "default_yes"; then
            install_zfs || { log_error "ZFS installation failed — cannot continue with storage setup."; return 1; }
        fi
    else
        install_zfs || { log_error "ZFS installation failed — cannot continue with storage setup."; return 1; }
    fi

    # Create pool
    create_pool || return 1

    # Create datasets
    create_datasets
}
