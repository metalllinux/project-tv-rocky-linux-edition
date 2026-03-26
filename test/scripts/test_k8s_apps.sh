#!/bin/bash
# test_k8s_apps.sh — Kubernetes application health test suite (TAP format)
# Run on a system where the installer has completed.

set -uo pipefail

echo "TAP version 13"
echo "1..20"

PASS=0
FAIL=0
NS="project-tv"

pass() { PASS=$((PASS+1)); echo "ok $((PASS+FAIL)) - $1"; }
fail() { FAIL=$((FAIL+1)); echo "not ok $((PASS+FAIL)) - $1"; }

HOST_IP=$(hostname -I | awk '{print $1}')

# === Category D: Kubernetes Health ===

# D-01: Node is Ready
if kubectl get nodes --no-headers 2>/dev/null | grep -q "Ready"; then
    pass "D-01 Node is Ready"
else
    fail "D-01 Node is not Ready"
fi

# D-02: Namespace exists
if kubectl get namespace "$NS" &>/dev/null; then
    pass "D-02 Namespace $NS exists"
else
    fail "D-02 Namespace $NS not found"
fi

# D-03: All pods Running
NOT_RUNNING=$(kubectl get pods -n "$NS" --no-headers 2>/dev/null | grep -v -E 'Running|Completed' | wc -l)
if (( NOT_RUNNING == 0 )); then
    pass "D-03 All pods are Running"
else
    fail "D-03 $NOT_RUNNING pod(s) not Running"
fi

# D-04: No pod restarts > 5
HIGH_RESTARTS=$(kubectl get pods -n "$NS" --no-headers 2>/dev/null | awk '{if($4+0 > 5) print $1}' | wc -l)
if (( HIGH_RESTARTS == 0 )); then
    pass "D-04 No pods with excessive restarts"
else
    fail "D-04 $HIGH_RESTARTS pod(s) with >5 restarts"
fi

# D-05: CronJob exists
if kubectl get cronjob jellyfin-library-refresh -n "$NS" &>/dev/null; then
    pass "D-05 Jellyfin library refresh CronJob exists"
else
    fail "D-05 Jellyfin library refresh CronJob not found"
fi

# === Category C: Application API Health ===

# C-JF-01: Jellyfin health
if curl -sf "http://${HOST_IP}:30096/health" 2>/dev/null | grep -qi "healthy"; then
    pass "C-JF-01 Jellyfin /health returns Healthy"
else
    fail "C-JF-01 Jellyfin /health check failed"
fi

# C-JF-02: Jellyfin system info
if curl -sf "http://${HOST_IP}:30096/System/Info/Public" 2>/dev/null | grep -q "ServerName"; then
    pass "C-JF-02 Jellyfin /System/Info/Public returns server info"
else
    fail "C-JF-02 Jellyfin system info check failed"
fi

# C-EP-01: EPGStation API
if curl -sf "http://${HOST_IP}:30888/api/version" 2>/dev/null | grep -q "version"; then
    pass "C-EP-01 EPGStation /api/version responds"
else
    fail "C-EP-01 EPGStation API check failed"
fi

# C-MK-01: Mirakurun API
if curl -sf "http://${HOST_IP}:30772/api/status" 2>/dev/null | grep -q "version\|time"; then
    pass "C-MK-01 Mirakurun /api/status responds"
else
    fail "C-MK-01 Mirakurun API check failed"
fi

# C-TA-01: Tube Archivist health
if curl -sf "http://${HOST_IP}:30800/health" 2>/dev/null; then
    pass "C-TA-01 Tube Archivist /health responds"
else
    fail "C-TA-01 Tube Archivist health check failed"
fi

# C-NV-01: Navidrome ping
if curl -sf "http://${HOST_IP}:30453/api/ping" 2>/dev/null; then
    pass "C-NV-01 Navidrome /api/ping responds"
else
    fail "C-NV-01 Navidrome ping check failed"
fi

# === Category E: Pod Log Health ===

check_pod_logs() {
    local deploy="$1"
    local test_id="$2"
    local errors
    errors=$(kubectl logs "deployment/$deploy" -n "$NS" --tail=100 2>&1 | \
        grep -ciE 'FATAL|panic|OOM|OutOfMemory|CrashLoopBackOff')
    if (( errors == 0 )); then
        pass "$test_id $deploy logs clean"
    else
        fail "$test_id $deploy has $errors critical log entries"
    fi
}

check_pod_logs "mirakurun" "E-01"
check_pod_logs "mariadb" "E-02"
check_pod_logs "epgstation" "E-03"
check_pod_logs "jellyfin" "E-04"
check_pod_logs "tubearchivist" "E-05"
check_pod_logs "elasticsearch" "E-06"
check_pod_logs "redis" "E-07"
check_pod_logs "navidrome" "E-08"

# === Summary ===

# D-06: All services have endpoints
SVC_NO_ENDPOINTS=$(kubectl get endpoints -n "$NS" --no-headers 2>/dev/null | awk '{if($2=="<none>") print $1}' | wc -l)
if (( SVC_NO_ENDPOINTS == 0 )); then
    pass "D-06 All services have endpoints"
else
    fail "D-06 $SVC_NO_ENDPOINTS service(s) have no endpoints"
fi

echo ""
echo "# Results: $PASS passed, $FAIL failed out of $((PASS+FAIL))"
