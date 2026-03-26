#!/bin/bash
# run_tests.sh — Master test orchestrator for Project TV - Rocky Edition
#
# Usage:
#   ./run_tests.sh <vm-name> <run-number>
#   ./run_tests.sh rocky10-test 1
#
# Prerequisites:
#   - VMs created via virt-install with kickstart files
#   - Base snapshots taken: virsh snapshot-create-as <vm> base-install
#   - RPM built and available

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

VM_NAME="${1:-}"
RUN_NUM="${2:-1}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_BASE="$HOME/test-results"

if [[ -z "$VM_NAME" ]]; then
    echo "Usage: $0 <vm-name> <run-number>"
    echo ""
    echo "Available VMs:"
    virsh list --all --name 2>/dev/null
    exit 1
fi

RESULTS_DIR="$RESULTS_BASE/${VM_NAME}/run${RUN_NUM}"
mkdir -p "$RESULTS_DIR"

LOG_FILE="$RESULTS_DIR/test-run-${TIMESTAMP}.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "========================================"
echo "Project TV Test Run"
echo "VM: $VM_NAME"
echo "Run: $RUN_NUM"
echo "Date: $(date)"
echo "Results: $RESULTS_DIR"
echo "========================================"

# Step 1: Revert to clean snapshot
echo ""
echo "=== Reverting VM to base-install snapshot ==="
virsh snapshot-revert "$VM_NAME" base-install
echo "Snapshot reverted."

# Step 2: Start VM
echo ""
echo "=== Starting VM ==="
virsh start "$VM_NAME" 2>/dev/null || echo "VM may already be running"

# Step 3: Wait for SSH
echo ""
echo "=== Waiting for SSH ==="
VM_IP=""
for i in $(seq 1 60); do
    VM_IP=$(virsh domifaddr "$VM_NAME" 2>/dev/null | grep ipv4 | awk '{print $4}' | cut -d/ -f1 | head -1)
    if [[ -n "$VM_IP" ]]; then
        if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no testuser@"$VM_IP" true 2>/dev/null; then
            echo "SSH ready at $VM_IP"
            break
        fi
    fi
    echo "  Waiting... ($i/60)"
    sleep 10
done

if [[ -z "$VM_IP" ]]; then
    echo "ERROR: Could not determine VM IP address"
    exit 1
fi

# Step 4: Copy test materials
echo ""
echo "=== Copying test materials to VM ==="
# Copy RPM
RPM_FILE=$(find "$PROJECT_DIR/drivers" "$HOME/rpmbuild/RPMS" -name "px4_drv-dkms*.rpm" 2>/dev/null | head -1)
if [[ -n "$RPM_FILE" ]]; then
    scp -o StrictHostKeyChecking=no "$RPM_FILE" testuser@"$VM_IP":/tmp/
    echo "RPM copied: $RPM_FILE"
fi

# Copy test scripts
scp -o StrictHostKeyChecking=no -r "$SCRIPT_DIR/scripts/" testuser@"$VM_IP":/tmp/test-scripts/
echo "Test scripts copied"

# Copy project repo for installer tests
scp -o StrictHostKeyChecking=no -r "$PROJECT_DIR" testuser@"$VM_IP":/tmp/project-tv-rocky-edition/
echo "Project repo copied"

# Step 5: Run tests
echo ""
echo "=== Running RPM Installation Tests ==="
ssh -o StrictHostKeyChecking=no testuser@"$VM_IP" "bash /tmp/test-scripts/test_rpm_install.sh" | tee "$RESULTS_DIR/rpm-tests.tap"

echo ""
echo "=== Running Installer Validation Tests ==="
ssh -o StrictHostKeyChecking=no testuser@"$VM_IP" "bash /tmp/test-scripts/test_installer.sh /tmp/project-tv-rocky-edition" | tee "$RESULTS_DIR/installer-tests.tap"

echo ""
echo "=== Running ZFS Tests ==="
ssh -o StrictHostKeyChecking=no testuser@"$VM_IP" "bash /tmp/test-scripts/test_zfs.sh" | tee "$RESULTS_DIR/zfs-tests.tap"

# Step 6: Collect system info
echo ""
echo "=== Collecting system information ==="
ssh -o StrictHostKeyChecking=no testuser@"$VM_IP" "cat /etc/os-release" > "$RESULTS_DIR/os-release.txt"
ssh -o StrictHostKeyChecking=no testuser@"$VM_IP" "uname -a" > "$RESULTS_DIR/kernel.txt"
ssh -o StrictHostKeyChecking=no testuser@"$VM_IP" "rpm -qa | sort" > "$RESULTS_DIR/packages.txt"

# Step 7: Shutdown VM
echo ""
echo "=== Shutting down VM ==="
virsh shutdown "$VM_NAME" 2>/dev/null || true

# Step 8: Summary
echo ""
echo "========================================"
echo "Test Run Complete"
echo "========================================"
echo "Results saved to: $RESULTS_DIR"
echo ""
echo "Test result files:"
ls -la "$RESULTS_DIR/"
echo ""

# Parse TAP results for summary
total_pass=0
total_fail=0
for tap_file in "$RESULTS_DIR"/*.tap; do
    if [[ -f "$tap_file" ]]; then
        p=$(grep -c '^ok ' "$tap_file" 2>/dev/null || echo 0)
        f=$(grep -c '^not ok ' "$tap_file" 2>/dev/null || echo 0)
        total_pass=$((total_pass + p))
        total_fail=$((total_fail + f))
        echo "  $(basename "$tap_file"): $p passed, $f failed"
    fi
done
echo ""
echo "TOTAL: $total_pass passed, $total_fail failed"
