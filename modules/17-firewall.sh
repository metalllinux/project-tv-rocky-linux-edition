#!/bin/bash
# 17-firewall.sh — firewalld port rules for all services

run() {
    log_section "Firewall Configuration"

    if ! systemctl is-active firewalld &>/dev/null; then
        log_info "firewalld is not currently running."
        if ask_yes_no "Enable and start firewalld?"; then
            log_cmd "Install firewalld" dnf install -y firewalld
            log_cmd "Enable firewalld" systemctl enable --now firewalld
        else
            log_info "Firewall configuration skipped (firewalld not running)"
            return 0
        fi
    fi

    local ports=(
        "8096/tcp:Jellyfin"
        "8888/tcp:EPGStation HTTP"
        "8889/tcp:EPGStation Socket.IO"
        "40772/tcp:Mirakurun"
        "8000/tcp:Tube Archivist"
        "4533/tcp:Navidrome"
        "6443/tcp:K8s API server"
        "10250/tcp:kubelet"
        "9100/tcp:Node Exporter (Prometheus)"
        "30090/tcp:Prometheus NodePort"
        "30300/tcp:Grafana NodePort"
        "30096/tcp:Jellyfin NodePort"
        "30772/tcp:Mirakurun NodePort"
        "30888/tcp:EPGStation NodePort"
        "30889/tcp:EPGStation Socket.IO NodePort"
        "30800/tcp:Tube Archivist NodePort"
        "30453/tcp:Navidrome NodePort"
    )

    echo ""
    echo "The following ports will be opened in firewalld:"
    for port_def in "${ports[@]}"; do
        local port="${port_def%%:*}"
        local desc="${port_def##*:}"
        printf "  %-15s %s\n" "$port" "$desc"
    done
    echo ""

    if ! ask_yes_no "Open these ports?"; then
        log_info "Firewall configuration skipped"
        return 0
    fi

    for port_def in "${ports[@]}"; do
        local port="${port_def%%:*}"
        local desc="${port_def##*:}"
        log_cmd "Open $port ($desc)" firewall-cmd --permanent --add-port="$port"
    done

    log_cmd "Reload firewalld" firewall-cmd --reload

    log_success "Firewall rules applied"
    firewall-cmd --list-ports 2>&1
}
