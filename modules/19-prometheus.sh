#!/bin/bash
# 19-prometheus.sh — Deploy Prometheus monitoring

run() {
    log_section "Deploying Prometheus Monitoring"

    # Read storage path from storage-paths.conf or use default
    local storage_conf="$PROJECT_ROOT/config/storage-paths.conf"
    local prom_data="/var/lib/project-tv/prometheus/data"
    if [[ -f "$storage_conf" ]]; then
        local conf_path
        conf_path=$(grep '^PROMETHEUS_DATA=' "$storage_conf" 2>/dev/null | cut -d= -f2)
        [[ -n "$conf_path" ]] && prom_data="$conf_path"
    fi

    # Ensure host directories (Prometheus runs as nobody/65534)
    mkdir -p "$prom_data"
    chown -R 65534:65534 "$prom_data"

    # Update manifest with configured path
    sed -i "s|path: /var/lib/project-tv/prometheus/data|path: ${prom_data}|" \
        "$PROJECT_ROOT/manifests/prometheus/deployment.yaml"

    # Apply RBAC first, then config, then deployment
    log_cmd "Deploy Prometheus RBAC" kubectl apply -f "$PROJECT_ROOT/manifests/prometheus/rbac.yaml"
    log_cmd "Deploy Prometheus ConfigMap" kubectl apply -f "$PROJECT_ROOT/manifests/prometheus/configmap.yaml"
    log_cmd "Deploy Prometheus" kubectl apply -f "$PROJECT_ROOT/manifests/prometheus/deployment.yaml"
    log_cmd "Deploy Prometheus Service" kubectl apply -f "$PROJECT_ROOT/manifests/prometheus/service.yaml"

    k8s_wait_deployment "prometheus" 300

    # Verify
    kubectl get pods -n "$K8S_NAMESPACE" -l app=prometheus 2>&1

    local host_ip
    host_ip=$(hostname -I | awk '{print $1}')

    log_success "Prometheus deployed"
    echo ""
    echo "Access: http://${host_ip}:30090"
    echo "Prometheus will scrape pods with annotation prometheus.io/scrape: 'true'"
}
