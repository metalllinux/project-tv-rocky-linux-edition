#!/bin/bash
# 03-kubeadm.sh — Full upstream Kubernetes installation via kubeadm
# Installs containerd, kubeadm, kubelet, kubectl, initialises the cluster,
# installs Flannel CNI, and configures for single-node operation.

install_containerd() {
    log_section "Installing containerd"

    local rocky_major
    rocky_major=$(grep '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"' | cut -d. -f1)

    # Add Docker CE repo (for containerd.io package)
    log_cmd "Install Docker CE repo" dnf config-manager --add-repo \
        https://download.docker.com/linux/centos/docker-ce.repo

    # For Rocky 10, the Docker repo may need the releasever adjusted
    if [[ "$rocky_major" == "10" ]]; then
        log_info "Adjusting Docker repo for Rocky Linux 10..."
        if [[ -f /etc/yum.repos.d/docker-ce.repo ]]; then
            sed -i 's|\$releasever|9|g' /etc/yum.repos.d/docker-ce.repo
        fi
    fi

    # Install containerd
    log_cmd "Install containerd.io" dnf install -y containerd.io

    # Generate default config
    log_cmd "Generate containerd config" bash -c \
        "containerd config default > /etc/containerd/config.toml"

    # Enable SystemdCgroup
    log_info "Configuring containerd for systemd cgroup driver..."
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

    # Enable and start containerd
    log_cmd "Enable containerd" systemctl enable --now containerd

    log_success "containerd installed and configured"
}

configure_kernel() {
    log_section "Configuring kernel modules and sysctl"

    # Load required kernel modules (kube-proxy needs xt_* for iptables rules)
    cat > /etc/modules-load.d/k8s.conf << 'EOF'
overlay
br_netfilter
nf_conntrack
xt_conntrack
xt_comment
xt_mark
ip_tables
ip6_tables
nf_nat
EOF

    local mod
    for mod in overlay br_netfilter nf_conntrack xt_conntrack xt_comment xt_mark ip_tables ip6_tables nf_nat; do
        if modprobe "$mod" 2>/dev/null; then
            log_success "Loaded kernel module: $mod"
        else
            log_warn "Could not load kernel module: $mod (ensure kernel-modules-extra is installed)"
        fi
    done

    # Set required sysctl parameters
    cat > /etc/sysctl.d/k8s.conf << 'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

    log_cmd "Apply sysctl settings" sysctl --system

    log_success "Kernel modules and sysctl configured for Kubernetes"
}

install_kubeadm() {
    log_section "Installing kubeadm, kubelet, kubectl"

    # Disable swap (required by kubeadm)
    log_cmd "Disable swap" swapoff -a
    # Remove swap entries from fstab
    sed -i '/\sswap\s/d' /etc/fstab
    log_info "Swap disabled and removed from /etc/fstab"

    # Add Kubernetes repo
    local k8s_version="v1.32"
    log_info "Using Kubernetes repo version: $k8s_version"

    cat > /etc/yum.repos.d/kubernetes.repo << EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/${k8s_version}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/${k8s_version}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

    # Install packages
    log_cmd "Install kubeadm kubelet kubectl" \
        dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes

    # Enable kubelet (will start after kubeadm init)
    log_cmd "Enable kubelet" systemctl enable kubelet

    log_success "kubeadm $(kubeadm version -o short 2>/dev/null) installed"
    log_success "kubectl $(kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null | head -1)"
}

init_cluster() {
    log_section "Initialising Kubernetes cluster"

    # Check if cluster is already initialised
    if [[ -f /etc/kubernetes/admin.conf ]]; then
        log_warn "Kubernetes cluster appears to be already initialised."
        if ask_yes_no "Skip kubeadm init?" "default_yes"; then
            setup_kubeconfig
            return 0
        fi
        log_info "Re-initialising cluster..."
        kubeadm reset -f 2>&1 || true
    fi

    # Run kubeadm init
    log_cmd "kubeadm init" kubeadm init \
        --pod-network-cidr="$K8S_POD_NETWORK_CIDR"

    # Set up kubeconfig
    setup_kubeconfig

    log_success "Kubernetes cluster initialised"
}

setup_kubeconfig() {
    # Set up kubeconfig for the invoking user
    local target_user="${SUDO_USER:-root}"
    local target_home
    target_home=$(eval echo "~$target_user")

    mkdir -p "$target_home/.kube"
    cp -f /etc/kubernetes/admin.conf "$target_home/.kube/config"
    chown -R "$target_user:$target_user" "$target_home/.kube"

    # Also set for root
    if [[ "$target_user" != "root" ]]; then
        mkdir -p /root/.kube
        cp -f /etc/kubernetes/admin.conf /root/.kube/config
    fi

    export KUBECONFIG=/etc/kubernetes/admin.conf

    log_success "kubeconfig set up for $target_user and root"
}

install_flannel() {
    log_section "Installing Flannel CNI"

    log_cmd "Install Flannel" kubectl apply -f \
        https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

    log_success "Flannel CNI manifest applied"

    # Wait for system pods to be operational
    log_info "Waiting for Flannel, kube-proxy, and CoreDNS to be ready (timeout: 120s)..."
    local timeout=120
    local elapsed=0
    while (( elapsed < timeout )); do
        local not_ready
        not_ready=$(kubectl get pods -A --no-headers 2>/dev/null | grep -v "Running\|Completed" | wc -l)
        if (( not_ready == 0 )); then
            log_success "All system pods are running"
            kubectl get pods -A 2>&1
            return 0
        fi
        sleep 10
        elapsed=$((elapsed + 10))
        log_info "  Waiting for $not_ready pod(s)... ($elapsed/${timeout}s)"
    done

    log_warn "Some system pods are not yet ready after ${timeout}s — continuing anyway"
    kubectl get pods -A 2>&1
}

configure_single_node() {
    log_section "Configuring single-node operation"

    # Remove control-plane taint so pods can schedule on this node
    log_cmd "Remove control-plane taint" kubectl taint nodes --all \
        node-role.kubernetes.io/control-plane- 2>/dev/null || true

    log_success "Control-plane taint removed — pods can schedule on this node"
}

wait_for_ready() {
    log_info "Waiting for node to become Ready..."
    local timeout=120
    local elapsed=0
    while (( elapsed < timeout )); do
        local status
        status=$(kubectl get nodes --no-headers 2>/dev/null | awk '{print $2}')
        if [[ "$status" == "Ready" ]]; then
            log_success "Node is Ready"
            kubectl get nodes 2>&1
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        log_info "  Waiting... ($elapsed/${timeout}s)"
    done

    log_error "Node did not become Ready within ${timeout}s"
    kubectl get nodes 2>&1
    kubectl describe nodes 2>&1 | tail -20
    return 1
}

handle_selinux() {
    log_section "SELinux Configuration"

    local current_mode
    current_mode=$(getenforce 2>/dev/null || echo "unknown")
    log_info "Current SELinux mode: $current_mode"

    if [[ "$current_mode" == "Enforcing" ]]; then
        echo ""
        echo "Kubernetes with privileged containers (needed for Mirakurun TV tuner"
        echo "device passthrough) typically requires SELinux in permissive mode."
        echo ""
        local choice
        choice=$(ask_menu "Select SELinux mode" \
            "Permissive (recommended for this setup)" \
            "Keep Enforcing (may require custom SELinux policies)")

        if [[ "$choice" == "1" ]]; then
            log_cmd "Set SELinux to permissive" setenforce 0
            sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
            log_success "SELinux set to permissive"
        else
            log_warn "SELinux remains enforcing — Mirakurun device passthrough may require custom policies"
        fi
    fi
}

run() {
    # SELinux first (affects everything else)
    handle_selinux

    # Configure kernel modules and sysctl
    configure_kernel

    # Install containerd if not present
    if command -v containerd &>/dev/null && systemctl is-active containerd &>/dev/null; then
        log_info "containerd is already installed and running"
        if ! ask_yes_no "Skip containerd installation?" "default_yes"; then
            install_containerd
        fi
    else
        install_containerd
    fi

    # Install kubeadm/kubelet/kubectl if not present
    if command -v kubeadm &>/dev/null; then
        log_info "kubeadm is already installed: $(kubeadm version -o short 2>/dev/null)"
        if ! ask_yes_no "Skip kubeadm installation?" "default_yes"; then
            install_kubeadm
        fi
    else
        install_kubeadm
    fi

    # Check if cluster is already fully set up
    if [[ -f /etc/kubernetes/admin.conf ]] && kubectl get nodes --no-headers 2>/dev/null | grep -q "Ready"; then
        log_info "Kubernetes cluster is already running and Ready"
        kubectl get nodes -o wide 2>&1
        echo ""
        kubectl get pods -A 2>&1
        log_success "Kubernetes cluster is ready — nothing to do"
        return 0
    fi

    # Initialise cluster
    init_cluster

    # Install Flannel CNI
    install_flannel

    # Configure for single-node
    configure_single_node

    # Wait for node to be ready
    wait_for_ready

    log_success "Kubernetes cluster is ready"
    echo ""
    kubectl get nodes -o wide 2>&1
    echo ""
    kubectl get pods -A 2>&1
}
