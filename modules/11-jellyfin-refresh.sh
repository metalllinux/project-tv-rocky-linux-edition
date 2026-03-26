#!/bin/bash
# 11-jellyfin-refresh.sh — Deploy Jellyfin library refresh CronJob
# Replaces the virt-manager VM + xdotool approach from v2.

run() {
    log_section "Jellyfin Library Refresh CronJob"

    echo ""
    echo "This CronJob triggers a Jellyfin library scan via the REST API."
    echo "It replaces the VM-based xdotool approach from Project TV v2."
    echo ""
    echo "A Jellyfin API key is required. If you haven't generated one yet:"
    echo "  1. Open Jellyfin in your browser"
    echo "  2. Go to Administration > API Keys > Add"
    echo "  3. Name it 'library-refresh' and copy the key"
    echo ""

    local api_key
    api_key=$(ask_text "Enter Jellyfin API key (or 'skip' to set up later)" "skip")

    if [[ "$api_key" != "skip" && "$api_key" != "PLACEHOLDER_GENERATE_IN_JELLYFIN_ADMIN" ]]; then
        # Update the secret with the real API key
        log_cmd "Update Jellyfin API secret" kubectl -n "$K8S_NAMESPACE" \
            create secret generic jellyfin-api-secret \
            --from-literal=api-key="$api_key" \
            --dry-run=client -o yaml | kubectl apply -f -
    else
        log_warn "API key not set. The CronJob will fail until the secret is updated."
        log_info "Update later with:"
        log_info "  kubectl -n $K8S_NAMESPACE create secret generic jellyfin-api-secret \\"
        log_info "    --from-literal=api-key=YOUR_KEY --dry-run=client -o yaml | kubectl apply -f -"
    fi

    # Configure schedule
    local schedule
    schedule=$(ask_text "CronJob schedule (cron format)" "0 * * * *")
    sed -i "s|schedule: \"0 \* \* \* \*\"|schedule: \"${schedule}\"|" \
        "$PROJECT_ROOT/manifests/cronjobs/jellyfin-library-refresh.yaml"

    # Apply CronJob
    log_cmd "Deploy library refresh CronJob" kubectl apply -f \
        "$PROJECT_ROOT/manifests/cronjobs/jellyfin-library-refresh.yaml"

    kubectl get cronjobs -n "$K8S_NAMESPACE" 2>&1

    log_success "Jellyfin library refresh CronJob deployed (schedule: $schedule)"
}
