#!/bin/bash
# 10-navidrome.sh — Deploy Navidrome music server

DATASETS_CONF="$PROJECT_ROOT/config/datasets.conf"

run() {
    log_section "Deploying Navidrome Music Server"

    # Check if already deployed
    if kubectl get deployment navidrome -n "$K8S_NAMESPACE" &>/dev/null; then
        log_info "Navidrome is already deployed:"
        kubectl get pods -n "$K8S_NAMESPACE" -l app=navidrome 2>&1
        if ! ask_yes_no "Redeploy Navidrome?" "default_no"; then
            log_success "Navidrome — already running"
            return 0
        fi
    fi

    # Update music path from storage-paths.conf
    local storage_conf="$PROJECT_ROOT/config/storage-paths.conf"
    if [[ -f "$storage_conf" ]]; then
        local music_mount
        music_mount=$(grep '^NAVIDROME_MUSIC=' "$storage_conf" 2>/dev/null | cut -d= -f2)
        if [[ -n "$music_mount" ]]; then
            log_info "Setting music path to: $music_mount"
            sed -i "s|path: /mnt/mediapool/music|path: ${music_mount}|" \
                "$PROJECT_ROOT/manifests/navidrome/deployment.yaml"
        fi
    fi

    # Ensure host directories
    mkdir -p /var/lib/project-tv/navidrome/data

    # Apply
    log_cmd "Deploy Navidrome" kubectl apply -f "$PROJECT_ROOT/manifests/navidrome/deployment.yaml"
    log_cmd "Deploy Navidrome Service" kubectl apply -f "$PROJECT_ROOT/manifests/navidrome/service.yaml"

    k8s_wait_deployment "navidrome" 60

    # Verify
    kubectl get pods -n "$K8S_NAMESPACE" -l app=navidrome 2>&1

    local host_ip
    host_ip=$(hostname -I | awk '{print $1}')

    log_success "Navidrome deployed"
    echo ""
    echo "Access: http://${host_ip}:30453"
    echo "Create your admin account on first visit."
}
