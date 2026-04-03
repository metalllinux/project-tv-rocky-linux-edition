#!/bin/bash
# 07-epgstation.sh — Deploy Mirakurun + MariaDB + EPGStation on Kubernetes

DATASETS_CONF="$PROJECT_ROOT/config/datasets.conf"

run() {
    log_section "Deploying EPGStation Stack (Mirakurun + MariaDB + EPGStation)"

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

    # Update recorded TV path from datasets.conf if available
    if [[ -f "$DATASETS_CONF" ]]; then
        local tv_mount
        tv_mount=$(grep '^tv:' "$DATASETS_CONF" 2>/dev/null | cut -d: -f2)
        if [[ -n "$tv_mount" ]]; then
            log_info "Setting recorded TV path to: $tv_mount"
            sed -i "s|path: /mnt/mediapool/tv|path: ${tv_mount}|" \
                "$PROJECT_ROOT/manifests/epgstation/epgstation-deployment.yaml"
        fi
    fi

    # Ensure host directories exist
    mkdir -p /var/lib/project-tv/mirakurun/data
    mkdir -p /var/lib/project-tv/mariadb/data
    mkdir -p /var/lib/project-tv/epgstation/{data,thumbnail,logs}

    # Apply manifests in order
    log_cmd "Apply MariaDB secret" kubectl apply -f "$PROJECT_ROOT/manifests/epgstation/mariadb-secret.yaml"
    log_cmd "Apply Mirakurun ConfigMap" kubectl apply -f "$PROJECT_ROOT/manifests/epgstation/mirakurun-configmap.yaml"
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
}
