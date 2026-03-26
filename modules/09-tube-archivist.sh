#!/bin/bash
# 09-tube-archivist.sh — Deploy Tube Archivist + Redis + Elasticsearch

DATASETS_CONF="$PROJECT_ROOT/config/datasets.conf"

run() {
    log_section "Deploying Tube Archivist Stack"

    # Prompt for credentials
    echo ""
    echo "Tube Archivist credentials:"
    local ta_user ta_pass elastic_pass
    ta_user=$(ask_text "Tube Archivist username" "tubearchivist")
    ta_pass=$(ask_text "Tube Archivist password" "")
    elastic_pass=$(ask_text "Elasticsearch password" "")

    # Update secret
    local secret_file="$PROJECT_ROOT/manifests/tube-archivist/tubearchivist-secret.yaml"
    sed -i "s|CHANGE_ME_ELASTIC_PASSWORD|${elastic_pass}|" "$secret_file"
    sed -i "s|CHANGE_ME_TA_PASSWORD|${ta_pass}|" "$secret_file"

    # Update YouTube path from datasets.conf
    if [[ -f "$DATASETS_CONF" ]]; then
        local yt_mount
        yt_mount=$(grep '^youtube:' "$DATASETS_CONF" 2>/dev/null | cut -d: -f2)
        if [[ -n "$yt_mount" ]]; then
            log_info "Setting YouTube path to: $yt_mount"
            sed -i "s|path: /mnt/mediapool/youtube|path: ${yt_mount}|" \
                "$PROJECT_ROOT/manifests/tube-archivist/tubearchivist-deployment.yaml"
        fi
    fi

    # Ensure host directories
    mkdir -p /var/lib/project-tv/tube-archivist/{elasticsearch,redis,cache}

    # Set Elasticsearch data directory permissions
    chown -R 1000:1000 /var/lib/project-tv/tube-archivist/elasticsearch

    # Increase vm.max_map_count for Elasticsearch
    log_info "Setting vm.max_map_count for Elasticsearch..."
    sysctl -w vm.max_map_count=262144
    echo "vm.max_map_count=262144" > /etc/sysctl.d/elasticsearch.conf

    # Apply manifests in order: ES -> Redis -> Tube Archivist
    log_cmd "Apply secret" kubectl apply -f "$secret_file"

    log_cmd "Deploy Elasticsearch" kubectl apply -f "$PROJECT_ROOT/manifests/tube-archivist/elasticsearch-deployment.yaml"
    log_cmd "Deploy Elasticsearch Service" kubectl apply -f "$PROJECT_ROOT/manifests/tube-archivist/elasticsearch-service.yaml"
    k8s_wait_deployment "elasticsearch" 180

    log_cmd "Deploy Redis" kubectl apply -f "$PROJECT_ROOT/manifests/tube-archivist/redis-deployment.yaml"
    log_cmd "Deploy Redis Service" kubectl apply -f "$PROJECT_ROOT/manifests/tube-archivist/redis-service.yaml"
    k8s_wait_deployment "redis" 60

    log_cmd "Deploy Tube Archivist" kubectl apply -f "$PROJECT_ROOT/manifests/tube-archivist/tubearchivist-deployment.yaml"
    log_cmd "Deploy Tube Archivist Service" kubectl apply -f "$PROJECT_ROOT/manifests/tube-archivist/tubearchivist-service.yaml"
    k8s_wait_deployment "tubearchivist" 180

    # Verify
    echo ""
    kubectl get pods -n "$K8S_NAMESPACE" -l 'app in (elasticsearch,redis,tubearchivist)' 2>&1

    local host_ip
    host_ip=$(hostname -I | awk '{print $1}')

    log_success "Tube Archivist stack deployed"
    echo ""
    echo "Access: http://${host_ip}:30800"
    echo "Login: $ta_user / (your password)"
}
