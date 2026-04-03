#!/bin/bash
# 07-epgstation.sh — Deploy Mirakurun + MariaDB + EPGStation on Kubernetes

DATASETS_CONF="$PROJECT_ROOT/config/datasets.conf"

run() {
    log_section "Deploying EPGStation Stack (Mirakurun + MariaDB + EPGStation)"

    # Check if already deployed
    if kubectl get deployment mariadb -n "$K8S_NAMESPACE" &>/dev/null && \
       kubectl get deployment mirakurun -n "$K8S_NAMESPACE" &>/dev/null && \
       kubectl get deployment epgstation -n "$K8S_NAMESPACE" &>/dev/null; then
        log_info "EPGStation stack is already deployed:"
        kubectl get pods -n "$K8S_NAMESPACE" -l 'app in (mirakurun,mariadb,epgstation)' 2>&1
        if ! ask_yes_no "Redeploy EPGStation stack?" "default_no"; then
            log_success "EPGStation stack — already running"
            return 0
        fi
    fi

    # Build custom container images (Mirakurun with recpt1, EPGStation with ffmpeg)
    if ! ctr -n k8s.io images ls -q | grep -q 'localhost/mirakurun-px4drv:latest'; then
        log_info "Building custom Mirakurun image with recpt1 (for px4_drv TV tuner support)..."
        if command -v podman &>/dev/null; then
            log_cmd "Build Mirakurun image" podman build -t localhost/mirakurun-px4drv:latest "$PROJECT_ROOT/docker/mirakurun/"
            podman save -o /tmp/mirakurun-px4drv.tar localhost/mirakurun-px4drv:latest 2>/dev/null
            ctr -n k8s.io images import /tmp/mirakurun-px4drv.tar 2>/dev/null
            rm -f /tmp/mirakurun-px4drv.tar
        fi
    else
        log_info "Custom Mirakurun image already exists"
    fi

    if ! ctr -n k8s.io images ls -q | grep -q 'localhost/epgstation-ffmpeg:latest'; then
        log_info "Building custom EPGStation image with ffmpeg (for live streaming)..."
        if command -v podman &>/dev/null; then
            log_cmd "Build EPGStation image" podman build -t localhost/epgstation-ffmpeg:latest "$PROJECT_ROOT/docker/epgstation/"
            podman save -o /tmp/epgstation-ffmpeg.tar localhost/epgstation-ffmpeg:latest 2>/dev/null
            ctr -n k8s.io images import /tmp/epgstation-ffmpeg.tar 2>/dev/null
            rm -f /tmp/epgstation-ffmpeg.tar
        fi
    else
        log_info "Custom EPGStation image already exists"
    fi

    # Prompt for MariaDB credentials
    local db_root_pass db_user_pass
    echo ""
    echo "MariaDB credentials for EPGStation:"
    db_root_pass=$(ask_text "MariaDB root password" "")
    db_user_pass=$(ask_text "MariaDB epgstation user password" "")

    # Update secret
    local secret_file="$PROJECT_ROOT/manifests/epgstation/mariadb-secret.yaml"
    sed -i "s|CHANGE_ME_ROOT_PASSWORD|${db_root_pass}|" "$secret_file"
    sed -i "s|CHANGE_ME_EPGSTATION_PASSWORD|${db_user_pass}|" "$secret_file"

    # Update EPGStation config with DB password
    local config_file="$PROJECT_ROOT/manifests/epgstation/epgstation-configmap.yaml"
    sed -i "s|CHANGE_ME_EPGSTATION_PASSWORD|${db_user_pass}|" "$config_file"

    # Update recorded TV path from storage-paths.conf
    local storage_conf="$PROJECT_ROOT/config/storage-paths.conf"
    if [[ -f "$storage_conf" ]]; then
        local tv_mount
        tv_mount=$(grep '^EPGSTATION_RECORDED=' "$storage_conf" 2>/dev/null | cut -d= -f2)
        if [[ -n "$tv_mount" ]]; then
            log_info "Setting recorded TV path to: $tv_mount"
            sed -i "s|path: /mnt/mediapool/tv|path: ${tv_mount}|" \
                "$PROJECT_ROOT/manifests/epgstation/epgstation-deployment.yaml"
        fi
    fi

    # Ensure host directories exist
    mkdir -p /var/lib/project-tv/mirakurun/{config,data}
    mkdir -p /var/lib/project-tv/mariadb/data
    mkdir -p /var/lib/project-tv/epgstation/{data,thumbnail,logs}

    # Copy Mirakurun tuner config to writable host directory (if not already present)
    if [[ ! -f /var/lib/project-tv/mirakurun/config/tuners.yml ]]; then
        # Extract tuners.yml from the ConfigMap YAML
        python3 -c "
import yaml, sys
with open('$PROJECT_ROOT/manifests/epgstation/mirakurun-configmap.yaml') as f:
    cm = yaml.safe_load(f)
print(cm['data']['tuners.yml'])
" > /var/lib/project-tv/mirakurun/config/tuners.yml 2>/dev/null || \
        # Fallback: copy directly from the manifest data section
        sed -n '/^  tuners.yml: |/,/^  channels.yml:/{ /^  tuners.yml: |/d; /^  channels.yml:/d; s/^    //; p; }' \
            "$PROJECT_ROOT/manifests/epgstation/mirakurun-configmap.yaml" \
            > /var/lib/project-tv/mirakurun/config/tuners.yml
        log_info "Copied tuners.yml to host config directory"
    fi
    # Create empty channels.yml if not present (will be populated by channel scan)
    if [[ ! -f /var/lib/project-tv/mirakurun/config/channels.yml ]]; then
        echo "[]" > /var/lib/project-tv/mirakurun/config/channels.yml
        log_info "Created empty channels.yml (run a channel scan after deployment)"
    fi

    # Apply manifests in order
    log_cmd "Apply MariaDB secret" kubectl apply -f "$PROJECT_ROOT/manifests/epgstation/mariadb-secret.yaml"
    log_cmd "Apply EPGStation ConfigMap" kubectl apply -f "$PROJECT_ROOT/manifests/epgstation/epgstation-configmap.yaml"

    log_cmd "Deploy MariaDB" kubectl apply -f "$PROJECT_ROOT/manifests/epgstation/mariadb-deployment.yaml"
    log_cmd "Deploy MariaDB Service" kubectl apply -f "$PROJECT_ROOT/manifests/epgstation/mariadb-service.yaml"

    # Wait for MariaDB (first pull is ~400MB, allow extra time)
    k8s_wait_deployment "mariadb" 300

    log_cmd "Deploy Mirakurun" kubectl apply -f "$PROJECT_ROOT/manifests/epgstation/mirakurun-deployment.yaml"
    log_cmd "Deploy Mirakurun Service" kubectl apply -f "$PROJECT_ROOT/manifests/epgstation/mirakurun-service.yaml"

    # Wait for Mirakurun (first pull can be slow)
    k8s_wait_deployment "mirakurun" 300

    log_cmd "Deploy EPGStation" kubectl apply -f "$PROJECT_ROOT/manifests/epgstation/epgstation-deployment.yaml"
    log_cmd "Deploy EPGStation Service" kubectl apply -f "$PROJECT_ROOT/manifests/epgstation/epgstation-service.yaml"

    # Wait for EPGStation
    k8s_wait_deployment "epgstation" 180

    # Verify
    echo ""
    log_info "EPGStation stack status:"
    kubectl get pods -n "$K8S_NAMESPACE" -l 'app in (mirakurun,mariadb,epgstation)' 2>&1
    echo ""
    kubectl get svc -n "$K8S_NAMESPACE" -l 'app in (mirakurun,mariadb,epgstation)' 2>&1

    log_success "EPGStation stack deployed"
    echo ""
    local host_ip
    host_ip=$(hostname -I | awk '{print $1}')
    echo "Access points:"
    echo "  Mirakurun: http://${host_ip}:30772"
    echo "  EPGStation: http://${host_ip}:30888"

    # Offer to run channel scans
    echo ""
    echo "Channel Scanning"
    echo "================"
    echo "Mirakurun needs to scan for TV channels before EPGStation can record."
    echo "Each scan takes a few minutes."
    echo ""

    # Helper to get current channel count from Mirakurun API
    get_channel_count() {
        curl -s http://localhost:30772/api/config/channels 2>/dev/null | \
            python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0"
    }

    if ask_yes_no "Scan for terrestrial (GR) channels?"; then
        local before_count
        before_count=$(get_channel_count)
        log_info "Scanning terrestrial channels (this may take a few minutes)..."
        curl -s -X PUT "http://localhost:30772/api/config/channels/scan?type=GR&setDisabledOnAdd=false" > /dev/null 2>&1
        local after_count
        after_count=$(get_channel_count)
        log_success "Terrestrial scan complete — $((after_count - before_count)) new channel(s) found ($after_count total)"
    fi

    if ask_yes_no "Scan for BS satellite channels?"; then
        local before_count
        before_count=$(get_channel_count)
        log_info "Scanning BS satellite channels (this may take a few minutes)..."
        curl -s -X PUT "http://localhost:30772/api/config/channels/scan?type=BS&setDisabledOnAdd=false" > /dev/null 2>&1
        local after_count
        after_count=$(get_channel_count)
        log_success "BS satellite scan complete — $((after_count - before_count)) new channel(s) found ($after_count total)"
    fi

    if ask_yes_no "Scan for CS satellite channels?"; then
        local before_count
        before_count=$(get_channel_count)
        log_info "Scanning CS satellite channels (this may take a few minutes)..."
        curl -s -X PUT "http://localhost:30772/api/config/channels/scan?type=CS&setDisabledOnAdd=false" > /dev/null 2>&1
        local after_count
        after_count=$(get_channel_count)
        log_success "CS satellite scan complete — $((after_count - before_count)) new channel(s) found ($after_count total)"
    fi

    # Show final channel count
    local total_channels
    total_channels=$(get_channel_count)

    # Restart Mirakurun to load scanned channels into services
    if (( total_channels > 0 )); then
        log_info "Restarting Mirakurun to load scanned channels..."
        kubectl rollout restart deployment mirakurun -n "$K8S_NAMESPACE" 2>/dev/null
        k8s_wait_deployment "mirakurun" 120

        # Wait for services to be populated
        log_info "Waiting for Mirakurun to gather service data from channels..."
        local svc_timeout=180
        local svc_elapsed=0
        local svc_count=0
        while (( svc_elapsed < svc_timeout )); do
            svc_count=$(curl -s http://localhost:30772/api/services 2>/dev/null | \
                python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
            if (( svc_count > 0 )); then
                break
            fi
            sleep 10
            svc_elapsed=$((svc_elapsed + 10))
            log_info "  Gathering services... ($svc_elapsed/${svc_timeout}s)"
        done
        log_success "Total channels: $total_channels, services: $svc_count"

        # Restart EPGStation so it picks up the new services from Mirakurun
        log_info "Restarting EPGStation to load channel data..."
        kubectl rollout restart deployment epgstation -n "$K8S_NAMESPACE" 2>/dev/null
        k8s_wait_deployment "epgstation" 180
        log_success "EPGStation restarted — EPG data will populate within 10 minutes"
    else
        log_warn "No channels found — run a channel scan from the Mirakurun web UI"
    fi

    echo ""
    echo "You can re-scan at any time via the Mirakurun web UI: http://${host_ip}:30772"
    echo "Live TV and programme guide: http://${host_ip}:30888"
}
