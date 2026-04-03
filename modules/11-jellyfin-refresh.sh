#!/bin/bash
# 11-jellyfin-refresh.sh — Deploy Jellyfin library refresh CronJob
# Replaces the virt-manager VM + xdotool approach from v2.

run() {
    log_section "Jellyfin Library Refresh CronJob"

    echo ""
    echo "This CronJob triggers a Jellyfin library scan via the REST API."
    echo ""
    local host_ip
    host_ip=$(hostname -I | awk '{print $1}')
    echo "A Jellyfin API key is required. If you haven't generated one yet:"
    echo "  1. Open Jellyfin in your browser: http://${host_ip}:30096"
    echo "  2. Complete the initial setup wizard (create your user and add media libraries)"
    echo "  3. Go to Settings > Administration > Dashboard > API Keys > New API Key"
    echo "  4. Name it 'library-refresh' and copy the key"
    echo ""

    if ! ask_yes_no "Have you completed Jellyfin setup and generated an API key?"; then
        log_info "Complete the Jellyfin setup at http://${host_ip}:30096 and re-run this module when ready."
        return 0
    fi

    local api_key
    api_key=$(ask_text "Enter Jellyfin API key (or 'skip' to set up later)" "skip")

    if [[ "$api_key" != "skip" && "$api_key" != "PLACEHOLDER_GENERATE_IN_JELLYFIN_ADMIN" ]]; then
        # Update the secret with the real API key
        log_cmd "Update Jellyfin API secret" bash -c \
            "kubectl -n $K8S_NAMESPACE create secret generic jellyfin-api-secret --from-literal=api-key='$api_key' --dry-run=client -o yaml | kubectl apply -f -"
    else
        log_warn "API key not set. The CronJob will fail until the secret is updated."
        log_info "Update later with:"
        log_info "  kubectl -n $K8S_NAMESPACE create secret generic jellyfin-api-secret \\"
        log_info "    --from-literal=api-key=YOUR_KEY --dry-run=client -o yaml | kubectl apply -f -"
    fi

    # Configure schedule
    echo ""
    echo "CronJob schedule format:"
    echo "  ┌───────────── minute (0-59)"
    echo "  │ ┌───────────── hour (0-23)"
    echo "  │ │ ┌───────────── day of month (1-31)"
    echo "  │ │ │ ┌───────────── month (1-12)"
    echo "  │ │ │ │ ┌───────────── day of week (0-6, Sun=0)"
    echo "  │ │ │ │ │"
    echo "  * * * * *"
    echo ""
    echo "Examples:"
    echo "  0 * * * *     = every hour (default)"
    echo "  */30 * * * *  = every 30 minutes"
    echo "  0 */6 * * *   = every 6 hours"
    echo ""
    local schedule
    while true; do
        schedule=$(ask_text "CronJob schedule (cron format)" "0 * * * *")
        # Validate: must have exactly 5 fields
        local field_count
        field_count=$(echo "$schedule" | wc -w)
        if (( field_count == 5 )); then
            break
        fi
        log_error "Invalid cron format: expected 5 fields, got $field_count. Please try again."
    done

    sed -i "s|schedule: \"0 \* \* \* \*\"|schedule: \"${schedule}\"|" \
        "$PROJECT_ROOT/manifests/cronjobs/jellyfin-library-refresh.yaml"

    # Apply CronJob
    if ! log_cmd "Deploy library refresh CronJob" kubectl apply -f \
        "$PROJECT_ROOT/manifests/cronjobs/jellyfin-library-refresh.yaml"; then
        log_error "CronJob deployment failed"
        return 1
    fi

    kubectl get cronjobs -n "$K8S_NAMESPACE" 2>&1

    log_success "Jellyfin library refresh CronJob deployed (schedule: $schedule)"
}
