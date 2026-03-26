#!/bin/bash
# k8s-helpers.sh — kubectl wrapper functions for the installer

KUBE_NAMESPACE="${KUBE_NAMESPACE:-project-tv}"

# Wait for a deployment to be ready
# Usage: k8s_wait_deployment "deployment-name" [timeout_seconds]
k8s_wait_deployment() {
    local name="$1"
    local timeout="${2:-300}"
    log_info "Waiting for deployment/$name to be ready (timeout: ${timeout}s)..."
    if kubectl rollout status "deployment/$name" -n "$KUBE_NAMESPACE" --timeout="${timeout}s" 2>&1; then
        log_success "Deployment $name is ready"
        return 0
    else
        log_error "Deployment $name did not become ready within ${timeout}s"
        kubectl describe "deployment/$name" -n "$KUBE_NAMESPACE" 2>&1 | tail -20
        return 1
    fi
}

# Wait for all pods in the namespace to be Running
# Usage: k8s_wait_all_pods [timeout_seconds]
k8s_wait_all_pods() {
    local timeout="${1:-300}"
    local elapsed=0
    log_info "Waiting for all pods in namespace $KUBE_NAMESPACE to be Running..."

    while (( elapsed < timeout )); do
        local not_ready
        not_ready=$(kubectl get pods -n "$KUBE_NAMESPACE" --no-headers 2>/dev/null | grep -v -E 'Running|Completed' | wc -l)
        if (( not_ready == 0 )); then
            log_success "All pods are Running"
            kubectl get pods -n "$KUBE_NAMESPACE" 2>&1
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done

    log_error "Not all pods are Running after ${timeout}s"
    kubectl get pods -n "$KUBE_NAMESPACE" 2>&1
    return 1
}

# Apply a manifest file or directory
# Usage: k8s_apply "path/to/manifest.yaml" or k8s_apply "path/to/dir/"
k8s_apply() {
    local path="$1"
    log_info "Applying manifest: $path"
    if kubectl apply -f "$path" -n "$KUBE_NAMESPACE" 2>&1; then
        log_success "Applied: $path"
        return 0
    else
        log_error "Failed to apply: $path"
        return 1
    fi
}

# Check if a resource exists
# Usage: k8s_exists "deployment" "name"
k8s_exists() {
    local kind="$1"
    local name="$2"
    kubectl get "$kind" "$name" -n "$KUBE_NAMESPACE" &>/dev/null
}

# Get pod logs for a deployment
# Usage: k8s_logs "deployment-name" [lines]
k8s_logs() {
    local name="$1"
    local lines="${2:-50}"
    kubectl logs "deployment/$name" -n "$KUBE_NAMESPACE" --tail="$lines" 2>&1
}

# Check pod logs for error patterns
# Usage: k8s_check_logs "deployment-name"
# Returns 0 if no critical errors found, 1 if errors detected
k8s_check_logs() {
    local name="$1"
    local errors
    errors=$(kubectl logs "deployment/$name" -n "$KUBE_NAMESPACE" --tail=100 2>&1 | \
        grep -iE 'FATAL|panic|OOM|OutOfMemory|CrashLoopBackOff' | head -5)

    if [[ -n "$errors" ]]; then
        log_warn "Critical log entries found in $name:"
        echo "$errors"
        return 1
    fi
    log_success "No critical errors in $name logs"
    return 0
}

# Print a summary of all pod statuses and log health
k8s_health_summary() {
    log_section "Kubernetes Health Summary"

    echo ""
    echo "=== Node Status ==="
    kubectl get nodes 2>&1
    echo ""

    echo "=== Pod Status (namespace: $KUBE_NAMESPACE) ==="
    kubectl get pods -n "$KUBE_NAMESPACE" -o wide 2>&1
    echo ""

    echo "=== Services ==="
    kubectl get svc -n "$KUBE_NAMESPACE" 2>&1
    echo ""

    echo "=== PV/PVC Status ==="
    kubectl get pv,pvc -n "$KUBE_NAMESPACE" 2>&1
    echo ""

    echo "=== CronJobs ==="
    kubectl get cronjobs -n "$KUBE_NAMESPACE" 2>&1
    echo ""

    echo "=== Log Health Check ==="
    local deployments
    deployments=$(kubectl get deployments -n "$KUBE_NAMESPACE" --no-headers -o custom-columns=":metadata.name" 2>/dev/null)
    for deploy in $deployments; do
        k8s_check_logs "$deploy"
    done
}

# Delete all resources in the namespace (for cleanup/reset)
# Usage: k8s_cleanup (requires confirmation)
k8s_cleanup() {
    log_warn "This will delete ALL resources in namespace $KUBE_NAMESPACE"
    kubectl delete all --all -n "$KUBE_NAMESPACE" 2>&1
}
