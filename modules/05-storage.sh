#!/bin/bash
# 05-storage.sh — Configure storage paths and generate PV/PVC manifests
# Prompts user to assign media directories to each application.
# Works with ZFS datasets (from module 02) or plain NVMe directories.

DATASETS_CONF="$PROJECT_ROOT/config/datasets.conf"
STORAGE_PATHS_CONF="$PROJECT_ROOT/config/storage-paths.conf"
STORAGE_DIR="$PROJECT_ROOT/manifests/storage"

# Build array of available directories (ZFS datasets or user-created)
declare -a AVAILABLE_DIRS=()

collect_zfs_dirs() {
    if [[ -f "$DATASETS_CONF" ]]; then
        while IFS=: read -r ds_name ds_mount; do
            [[ "$ds_name" =~ ^#.*$ ]] && continue
            [[ -z "$ds_name" ]] && continue
            [[ "$ds_name" =~ ^ZFS_ ]] && continue
            AVAILABLE_DIRS+=("$ds_mount")
        done < "$DATASETS_CONF"
    fi
}

create_nvme_dirs() {
    local target_user="${SUDO_USER:-$(whoami)}"
    local base_dir
    base_dir=$(ask_text "Base media directory" "/home/$target_user/media")

    local num_dirs
    num_dirs=$(ask_number "How many media directories do you want to create?" 1 20 5)

    for ((i = 1; i <= num_dirs; i++)); do
        echo ""
        echo "--- Directory $i of $num_dirs ---"
        local dir_name
        dir_name=$(ask_text "Directory $i name (e.g. tv, music, films)")
        local dir_path
        dir_path=$(ask_text "Path for '$dir_name'" "$base_dir/$dir_name")

        mkdir -p "$dir_path"
        chown "$target_user:$target_user" "$dir_path"
        AVAILABLE_DIRS+=("$dir_path")
        log_success "Created: $dir_path"
    done
}

show_available_dirs() {
    echo ""
    echo "Available directories:"
    for i in "${!AVAILABLE_DIRS[@]}"; do
        printf "  [%d] %s\n" "$((i + 1))" "${AVAILABLE_DIRS[$i]}"
    done
    echo ""
}

# Resolve user input to a path — accepts a number, custom path, or comma-separated list
resolve_path() {
    local input="$1"
    local multi="${2:-false}"

    if [[ "$multi" == "true" ]]; then
        # Handle comma-separated input for multi-path apps (Jellyfin)
        local paths=()
        IFS=',' read -ra selections <<< "$input"
        for sel in "${selections[@]}"; do
            sel=$(echo "$sel" | xargs)  # trim whitespace
            if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#AVAILABLE_DIRS[@]} )); then
                paths+=("${AVAILABLE_DIRS[$((sel - 1))]}")
            elif [[ "$sel" == /* ]]; then
                paths+=("$sel")
            else
                paths+=("$sel")
            fi
        done
        echo "${paths[*]}"
    else
        if [[ "$input" =~ ^[0-9]+$ ]] && (( input >= 1 && input <= ${#AVAILABLE_DIRS[@]} )); then
            echo "${AVAILABLE_DIRS[$((input - 1))]}"
        elif [[ "$input" == /* ]]; then
            echo "$input"
        else
            echo "$input"
        fi
    fi
}

prompt_app_path() {
    local app_name="$1"
    local default="$2"
    local multi="${3:-false}"

    local input
    if [[ "$multi" == "true" ]]; then
        input=$(ask_text "$app_name (comma-separated numbers or paths)" "$default")
    else
        input=$(ask_text "$app_name" "$default")
    fi

    local resolved
    resolved=$(resolve_path "$input" "$multi")
    echo "  → $resolved" >&2
    echo "$resolved"
}

configure_storage_paths() {
    log_section "Storage Path Configuration"

    echo ""
    echo "Assign a storage path for each application."
    echo "Enter a number from the list, or type a custom path."
    echo ""

    # Determine sensible defaults
    local default_base=""
    if (( ${#AVAILABLE_DIRS[@]} > 0 )); then
        default_base=$(dirname "${AVAILABLE_DIRS[0]}")
    else
        local target_user="${SUDO_USER:-$(whoami)}"
        default_base="/home/$target_user/media"
    fi

    # Find likely defaults from available dirs
    local default_tv="$default_base/tv"
    local default_music="$default_base/music"
    local default_youtube="$default_base/youtube"
    local default_jellyfin=""
    local default_rips="$default_base/rips"

    # Try to match existing dirs
    for d in "${AVAILABLE_DIRS[@]}"; do
        case "$(basename "$d")" in
            tv|recorded) default_tv="$d" ;;
            music) default_music="$d" ;;
            youtube) default_youtube="$d" ;;
            rips|makemkv) default_rips="$d" ;;
        esac
    done

    # For Jellyfin, default to all available dirs
    if (( ${#AVAILABLE_DIRS[@]} > 0 )); then
        default_jellyfin=$(printf '%s,' "${AVAILABLE_DIRS[@]}")
        default_jellyfin="${default_jellyfin%,}"  # remove trailing comma
    else
        default_jellyfin="$default_base"
    fi

    show_available_dirs

    local epg_path jellyfin_paths navidrome_path ta_path makemkv_path prometheus_path grafana_path

    epg_path=$(prompt_app_path "EPGStation recordings" "$default_tv")
    jellyfin_paths=$(prompt_app_path "Jellyfin media libraries" "$default_jellyfin" "true")
    navidrome_path=$(prompt_app_path "Navidrome music" "$default_music")
    ta_path=$(prompt_app_path "Tube Archivist downloads" "$default_youtube")
    makemkv_path=$(prompt_app_path "MakeMKV output" "$default_rips")
    prometheus_path=$(prompt_app_path "Prometheus data" "/var/lib/project-tv/prometheus/data")
    grafana_path=$(prompt_app_path "Grafana data" "/var/lib/project-tv/grafana/data")

    # Create directories that don't exist
    local target_user="${SUDO_USER:-$(whoami)}"
    for p in $epg_path $navidrome_path $ta_path $makemkv_path $prometheus_path $grafana_path; do
        if [[ ! -d "$p" ]]; then
            mkdir -p "$p"
            chown "$target_user:$target_user" "$p"
            log_info "Created directory: $p"
        fi
    done
    # Jellyfin paths (space-separated)
    for p in $jellyfin_paths; do
        if [[ ! -d "$p" ]]; then
            mkdir -p "$p"
            chown "$target_user:$target_user" "$p"
            log_info "Created directory: $p"
        fi
    done

    # Write storage-paths.conf
    cat > "$STORAGE_PATHS_CONF" << EOF
# Storage paths for application media data
# Generated by installer on $(date)
EPGSTATION_RECORDED=$epg_path
JELLYFIN_MEDIA=$jellyfin_paths
NAVIDROME_MUSIC=$navidrome_path
TUBEARCHIVIST_DOWNLOADS=$ta_path
MAKEMKV_OUTPUT=$makemkv_path
PROMETHEUS_DATA=$prometheus_path
GRAFANA_DATA=$grafana_path
EOF

    log_info "Storage path configuration:"
    cat "$STORAGE_PATHS_CONF"
    log_success "Storage paths saved to $STORAGE_PATHS_CONF"
}

generate_pvcs() {
    # Apply StorageClass
    log_cmd "Apply StorageClass" kubectl apply -f "$STORAGE_DIR/storageclass.yaml"

    # Check for datasets config (ZFS PVs)
    if [[ -f "$DATASETS_CONF" ]]; then
        log_info "Generating PV/PVC manifests from ZFS datasets..."

        local count=0
        while IFS=: read -r ds_name ds_mount; do
            [[ "$ds_name" =~ ^#.*$ ]] && continue
            [[ -z "$ds_name" ]] && continue
            [[ "$ds_name" =~ ^ZFS_ ]] && continue

            local k8s_name
            k8s_name=$(echo "$ds_name" | tr '[:upper:]' '[:lower:]' | tr '_' '-')

            cat > "$STORAGE_DIR/pv-${k8s_name}.yaml" << EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-${k8s_name}
  labels:
    type: local-zfs
    dataset: ${k8s_name}
spec:
  storageClassName: local-zfs
  capacity:
    storage: 1Ti
  accessModes:
  - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  hostPath:
    path: ${ds_mount}
    type: DirectoryOrCreate
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - $(hostname)
EOF

            cat > "$STORAGE_DIR/pvc-${k8s_name}.yaml" << EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-${k8s_name}
  namespace: ${K8S_NAMESPACE}
spec:
  storageClassName: local-zfs
  accessModes:
  - ReadWriteMany
  resources:
    requests:
      storage: 1Ti
  volumeName: pv-${k8s_name}
EOF

            kubectl apply -f "$STORAGE_DIR/pv-${k8s_name}.yaml" 2>&1
            kubectl apply -f "$STORAGE_DIR/pvc-${k8s_name}.yaml" 2>&1
            count=$((count + 1))
        done < "$DATASETS_CONF"

        log_success "Created $count PV/PVC pairs"
        echo ""
        kubectl get pv 2>&1
        echo ""
        kubectl get pvc -n "$K8S_NAMESPACE" 2>&1
    else
        log_info "No ZFS datasets — skipping PV/PVC generation"
    fi
}

run() {
    # Check if storage paths already configured
    if [[ -f "$STORAGE_PATHS_CONF" ]]; then
        log_info "Storage paths already configured:"
        cat "$STORAGE_PATHS_CONF"
        if ! ask_yes_no "Reconfigure storage paths?" "default_no"; then
            generate_pvcs
            return 0
        fi
    fi

    # Collect available directories
    collect_zfs_dirs

    if (( ${#AVAILABLE_DIRS[@]} == 0 )); then
        log_info "No ZFS datasets found. Creating directories on NVMe."
        echo ""
        create_nvme_dirs
    else
        log_info "ZFS datasets found:"
        for d in "${AVAILABLE_DIRS[@]}"; do
            echo "  $d"
        done
    fi

    # Configure which app uses which directory
    configure_storage_paths

    # Generate PV/PVCs if ZFS
    generate_pvcs
}
