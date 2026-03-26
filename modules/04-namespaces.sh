#!/bin/bash
# 04-namespaces.sh — Create Kubernetes namespace for Project TV

run() {
    log_info "Creating Kubernetes namespace: $K8S_NAMESPACE"

    if kubectl get namespace "$K8S_NAMESPACE" &>/dev/null; then
        log_info "Namespace '$K8S_NAMESPACE' already exists"
    else
        log_cmd "Create namespace" kubectl apply -f "$PROJECT_ROOT/manifests/namespace.yaml"
    fi

    log_success "Namespace '$K8S_NAMESPACE' ready"
    kubectl get namespace "$K8S_NAMESPACE" 2>&1
}
