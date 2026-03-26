#!/bin/bash
# 08-jellyfin.sh — Deploy Jellyfin on Kubernetes
# Dynamically generates volume mounts from datasets.conf.

DATASETS_CONF="$PROJECT_ROOT/config/datasets.conf"

generate_jellyfin_deployment() {
    local deploy_file="$PROJECT_ROOT/manifests/jellyfin/deployment-generated.yaml"

    # Read datasets
    local volume_mounts=""
    local volumes=""

    if [[ -f "$DATASETS_CONF" ]]; then
        while IFS=: read -r ds_name ds_mount; do
            [[ "$ds_name" =~ ^#.*$ ]] && continue
            [[ -z "$ds_name" ]] && continue
            [[ "$ds_name" =~ ^ZFS_ ]] && continue

            local k8s_name
            k8s_name=$(echo "$ds_name" | tr '[:upper:]' '[:lower:]' | tr '_' '-')

            volume_mounts="${volume_mounts}
        - name: media-${k8s_name}
          mountPath: /data/${ds_name}
          readOnly: true"

            volumes="${volumes}
      - name: media-${k8s_name}
        hostPath:
          path: ${ds_mount}
          type: DirectoryOrCreate"
        done < "$DATASETS_CONF"
    fi

    cat > "$deploy_file" << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jellyfin
  namespace: project-tv
  labels:
    app: jellyfin
spec:
  replicas: 1
  selector:
    matchLabels:
      app: jellyfin
  template:
    metadata:
      labels:
        app: jellyfin
    spec:
      containers:
      - name: jellyfin
        image: ${JELLYFIN_IMAGE}
        ports:
        - containerPort: 8096
          name: http
        env:
        - name: PUID
          value: "${PUID}"
        - name: PGID
          value: "${PGID}"
        - name: TZ
          value: "${TIMEZONE}"
        volumeMounts:
        - name: config
          mountPath: /config
        - name: cache
          mountPath: /cache${volume_mounts}
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
          limits:
            memory: "2Gi"
            cpu: "4000m"
        livenessProbe:
          httpGet:
            path: /health
            port: 8096
          initialDelaySeconds: 30
          periodSeconds: 30
        readinessProbe:
          httpGet:
            path: /health
            port: 8096
          initialDelaySeconds: 15
          periodSeconds: 10
      volumes:
      - name: config
        hostPath:
          path: /var/lib/project-tv/jellyfin/config
          type: DirectoryOrCreate
      - name: cache
        hostPath:
          path: /var/lib/project-tv/jellyfin/cache
          type: DirectoryOrCreate${volumes}
EOF

    echo "$deploy_file"
}

run() {
    log_section "Deploying Jellyfin"

    # Ensure host directories
    mkdir -p /var/lib/project-tv/jellyfin/{config,cache}

    # Generate deployment with dynamic media mounts
    local deploy_file
    deploy_file=$(generate_jellyfin_deployment)
    log_info "Generated Jellyfin deployment with media mounts from datasets.conf"

    # Apply
    log_cmd "Deploy Jellyfin" kubectl apply -f "$deploy_file"
    log_cmd "Deploy Jellyfin Service" kubectl apply -f "$PROJECT_ROOT/manifests/jellyfin/service.yaml"
    log_cmd "Apply Jellyfin API Secret" kubectl apply -f "$PROJECT_ROOT/manifests/jellyfin/api-secret.yaml"

    # Wait
    k8s_wait_deployment "jellyfin" 180

    # Verify
    echo ""
    kubectl get pods -n "$K8S_NAMESPACE" -l app=jellyfin 2>&1

    local host_ip
    host_ip=$(hostname -I | awk '{print $1}')

    log_success "Jellyfin deployed"
    echo ""
    echo "Access: http://${host_ip}:30096"
    echo ""
    echo "IMPORTANT: After completing the Jellyfin setup wizard, generate an API key:"
    echo "  1. Go to Administration > API Keys"
    echo "  2. Click 'Add' and name it 'library-refresh'"
    echo "  3. Update the secret:"
    echo "     kubectl -n project-tv create secret generic jellyfin-api-secret \\"
    echo "       --from-literal=api-key=YOUR_API_KEY --dry-run=client -o yaml | kubectl apply -f -"
}
