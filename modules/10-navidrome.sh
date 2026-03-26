#!/bin/bash
# 10-navidrome.sh — Deploy Navidrome music server

DATASETS_CONF="$PROJECT_ROOT/config/datasets.conf"

run() {
    log_section "Deploying Navidrome Music Server"

    # Update music path from datasets.conf
    if [[ -f "$DATASETS_CONF" ]]; then
        local music_mount
        music_mount=$(grep '^music:' "$DATASETS_CONF" 2>/dev/null | cut -d: -f2)
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
