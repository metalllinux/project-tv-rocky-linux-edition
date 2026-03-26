#!/bin/bash
# 05-storage.sh — Generate and apply PV/PVC manifests from ZFS datasets
# Reads config/datasets.conf and creates hostPath PVs for each dataset.

DATASETS_CONF="$PROJECT_ROOT/config/datasets.conf"
STORAGE_DIR="$PROJECT_ROOT/manifests/storage"

run() {
    # Apply StorageClass
    log_cmd "Apply StorageClass" kubectl apply -f "$STORAGE_DIR/storageclass.yaml"

    # Check for datasets config
    if [[ ! -f "$DATASETS_CONF" ]]; then
        log_error "Dataset configuration not found at $DATASETS_CONF"
        log_info "Run module 02 (ZFS storage) first to create datasets."
        return 1
    fi

    log_info "Reading dataset configuration from $DATASETS_CONF"

    local count=0
    while IFS=: read -r ds_name ds_mount; do
        # Skip comments, empty lines, and config variables
        [[ "$ds_name" =~ ^#.*$ ]] && continue
        [[ -z "$ds_name" ]] && continue
        [[ "$ds_name" =~ ^ZFS_ ]] && continue

        log_info "Creating PV/PVC for dataset: $ds_name -> $ds_mount"

        # Sanitise name for K8s (lowercase, replace underscores with hyphens)
        local k8s_name
        k8s_name=$(echo "$ds_name" | tr '[:upper:]' '[:lower:]' | tr '_' '-')

        # Generate PV manifest
        cat > "$STORAGE_DIR/pv-${k8s_name}.yaml" << EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-${k8s_name}
  labels:
    type: local-zfs
    dataset: ${k8s_name}
spec:
  storageClassName: local-zfs
  capacity:
    storage: 1Ti
  accessModes:
  - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  hostPath:
    path: ${ds_mount}
    type: DirectoryOrCreate
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - $(hostname)
EOF

        # Generate PVC manifest
        cat > "$STORAGE_DIR/pvc-${k8s_name}.yaml" << EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-${k8s_name}
  namespace: ${K8S_NAMESPACE}
spec:
  storageClassName: local-zfs
  accessModes:
  - ReadWriteMany
  resources:
    requests:
      storage: 1Ti
  volumeName: pv-${k8s_name}
EOF

        # Apply PV then PVC
        kubectl apply -f "$STORAGE_DIR/pv-${k8s_name}.yaml" 2>&1
        kubectl apply -f "$STORAGE_DIR/pvc-${k8s_name}.yaml" 2>&1

        count=$((count + 1))
    done < "$DATASETS_CONF"

    log_success "Created $count PV/PVC pairs"
    echo ""
    kubectl get pv 2>&1
    echo ""
    kubectl get pvc -n "$K8S_NAMESPACE" 2>&1
}
