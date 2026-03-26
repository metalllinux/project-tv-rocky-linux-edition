#!/bin/bash
# test_rpm_install.sh — RPM installation test suite (TAP format)
# Run inside a test VM after copying the RPM.

set -uo pipefail

echo "TAP version 13"
echo "1..12"

PASS=0
FAIL=0

pass() { PASS=$((PASS+1)); echo "ok $((PASS+FAIL)) - $1"; }
fail() { FAIL=$((FAIL+1)); echo "not ok $((PASS+FAIL)) - $1"; }

RPM_FILE=$(find /tmp -name "px4_drv-dkms*.rpm" 2>/dev/null | head -1)

# A-01: RPM installs without errors
if [[ -n "$RPM_FILE" ]] && sudo dnf install -y "$RPM_FILE" &>/dev/null; then
    pass "A-01 RPM installs without errors"
else
    fail "A-01 RPM installation failed"
fi

# A-02: DKMS module registered
if dkms status px4_drv 2>/dev/null | grep -q "installed"; then
    pass "A-02 DKMS module registered and installed"
else
    fail "A-02 DKMS module not in installed state"
fi

# A-03: Kernel module built
if ls /lib/modules/$(uname -r)/updates/dkms/px4_drv.ko* &>/dev/null 2>&1 || \
   ls /lib/modules/$(uname -r)/extra/px4_drv.ko* &>/dev/null 2>&1; then
    pass "A-03 Kernel module file exists"
else
    fail "A-03 Kernel module file not found"
fi

# A-04: Module loads
if sudo modprobe px4_drv 2>/dev/null; then
    pass "A-04 Module loads via modprobe"
else
    fail "A-04 Module failed to load"
fi

# A-05: Module info correct
if modinfo px4_drv 2>/dev/null | grep -q "license.*GPL"; then
    pass "A-05 Module info shows GPL licence"
else
    fail "A-05 Module info missing or incorrect"
fi

# A-06: Firmware installed
if [[ -f /lib/firmware/it930x-firmware.bin ]]; then
    pass "A-06 Firmware file installed"
else
    fail "A-06 Firmware file not found"
fi

# A-07: Udev rules installed (check both legacy and modern paths)
if [[ -f /etc/udev/rules.d/99-px4video.rules ]] || [[ -f /usr/lib/udev/rules.d/99-px4video.rules ]]; then
    pass "A-07 Udev rules installed"
else
    fail "A-07 Udev rules not found"
fi

# A-08: RPM verification
if rpm -V px4_drv-dkms &>/dev/null; then
    pass "A-08 RPM verification clean"
else
    fail "A-08 RPM verification found issues"
fi

# A-09: RPM removal clean
if sudo dnf remove -y px4_drv-dkms &>/dev/null; then
    pass "A-09 RPM removal clean"
else
    fail "A-09 RPM removal failed"
fi

# A-10: DKMS unregistered after removal
if ! dkms status px4_drv 2>/dev/null | grep -q "installed"; then
    pass "A-10 DKMS unregistered after removal"
else
    fail "A-10 DKMS still registered after removal"
fi

# A-11: Reinstall after removal
if sudo dnf install -y "$RPM_FILE" &>/dev/null; then
    pass "A-11 Reinstall after removal succeeds"
else
    fail "A-11 Reinstall after removal failed"
fi

# A-12: Module loads after reinstall
if sudo modprobe px4_drv 2>/dev/null; then
    pass "A-12 Module loads after reinstall"
else
    fail "A-12 Module failed to load after reinstall"
fi

echo ""
echo "# Results: $PASS passed, $FAIL failed out of $((PASS+FAIL))"
