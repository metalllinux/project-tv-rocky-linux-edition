#!/bin/bash
# test_zfs.sh — ZFS functionality test suite (TAP format)
# Run on a system with ZFS installed. Requires a spare block device for testing.

set -uo pipefail

echo "TAP version 13"
echo "1..6"

PASS=0
FAIL=0
TEST_POOL="testpool-ptv"

pass() { PASS=$((PASS+1)); echo "ok $((PASS+FAIL)) - $1"; }
fail() { FAIL=$((FAIL+1)); echo "not ok $((PASS+FAIL)) - $1"; }

# C-ZF-01: ZFS module loaded
if lsmod | grep -q '^zfs'; then
    pass "C-ZF-01 ZFS module loaded"
else
    # Try to load it
    sudo modprobe zfs 2>/dev/null
    if lsmod | grep -q '^zfs'; then
        pass "C-ZF-01 ZFS module loaded (after modprobe)"
    else
        fail "C-ZF-01 ZFS module not available"
    fi
fi

# Create a file-backed device for testing (avoids needing a real disk)
TEST_FILE="/tmp/zfs-test-$(date +%s).img"
truncate -s 512M "$TEST_FILE"

# C-ZF-02: Pool creation
if sudo zpool create "$TEST_POOL" "$TEST_FILE" 2>/dev/null; then
    pass "C-ZF-02 Pool creation"
else
    fail "C-ZF-02 Pool creation failed"
    rm -f "$TEST_FILE"
    echo "# Aborting remaining tests"
    echo "# Results: $PASS passed, $FAIL failed"
    exit 0
fi

# C-ZF-03: Dataset creation
if sudo zfs create "${TEST_POOL}/data" 2>/dev/null; then
    pass "C-ZF-03 Dataset creation"
else
    fail "C-ZF-03 Dataset creation failed"
fi

# C-ZF-04: Snapshot creation
# Write a test file first
echo "test data" | sudo tee "/${TEST_POOL}/data/testfile" >/dev/null
if sudo zfs snapshot "${TEST_POOL}/data@snap1" 2>/dev/null; then
    pass "C-ZF-04 Snapshot creation"
else
    fail "C-ZF-04 Snapshot creation failed"
fi

# C-ZF-05: Snapshot rollback
echo "modified" | sudo tee "/${TEST_POOL}/data/testfile" >/dev/null
if sudo zfs rollback "${TEST_POOL}/data@snap1" 2>/dev/null; then
    local_content=$(cat "/${TEST_POOL}/data/testfile" 2>/dev/null)
    if [[ "$local_content" == "test data" ]]; then
        pass "C-ZF-05 Snapshot rollback restores data"
    else
        fail "C-ZF-05 Snapshot rollback did not restore data"
    fi
else
    fail "C-ZF-05 Snapshot rollback failed"
fi

# C-ZF-06: Pool destroy
if sudo zpool destroy "$TEST_POOL" 2>/dev/null; then
    pass "C-ZF-06 Pool destroy"
else
    fail "C-ZF-06 Pool destroy failed"
fi

# Cleanup
rm -f "$TEST_FILE"

echo ""
echo "# Results: $PASS passed, $FAIL failed out of $((PASS+FAIL))"
