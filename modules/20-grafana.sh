#!/bin/bash
# 20-grafana.sh — Deploy Grafana dashboards

run() {
    log_section "Deploying Grafana"

    # Prompt for admin password
    local admin_pass
    admin_pass=$(ask_text "Enter Grafana admin password" "admin")
    sed -i "s|CHANGE_ME_GRAFANA_ADMIN_PASSWORD|${admin_pass}|" \
        "$PROJECT_ROOT/manifests/grafana/deployment.yaml"

    # Read storage path from storage-paths.conf or use default
    local storage_conf="$PROJECT_ROOT/config/storage-paths.conf"
    local grafana_data="/var/lib/project-tv/grafana/data"
    if [[ -f "$storage_conf" ]]; then
        local conf_path
        conf_path=$(grep '^GRAFANA_DATA=' "$storage_conf" 2>/dev/null | cut -d= -f2)
        [[ -n "$conf_path" ]] && grafana_data="$conf_path"
    fi

    # Ensure host directories (Grafana runs as UID 472)
    mkdir -p "$grafana_data"
    chown -R 472:472 "$grafana_data"

    # Update manifest with configured path
    sed -i "s|path: /var/lib/project-tv/grafana/data|path: ${grafana_data}|" \
        "$PROJECT_ROOT/manifests/grafana/deployment.yaml"

    # Apply
    log_cmd "Deploy Grafana datasource" kubectl apply -f "$PROJECT_ROOT/manifests/grafana/datasource.yaml"
    log_cmd "Deploy Grafana" kubectl apply -f "$PROJECT_ROOT/manifests/grafana/deployment.yaml"
    log_cmd "Deploy Grafana Service" kubectl apply -f "$PROJECT_ROOT/manifests/grafana/service.yaml"

    k8s_wait_deployment "grafana" 300

    # Verify
    kubectl get pods -n "$K8S_NAMESPACE" -l app=grafana -o wide 2>&1

    local host_ip
    host_ip=$(hostname -I | awk '{print $1}')

    log_success "Grafana deployed"
    echo ""
    echo "Access: http://${host_ip}:30300"
    echo "Prometheus is pre-configured as the default datasource."
}
