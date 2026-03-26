#!/bin/bash
# build_rpm.sh — Build the px4_drv DKMS RPM package
#
# Prerequisites:
#   sudo dnf install -y rpm-build rpmdevtools
#
# Usage:
#   ./build_rpm.sh [path-to-px4_drv-source]
#
# If no source path is given, it will clone from GitHub.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="0.5.5"
PKG_NAME="px4_drv"
SPEC_FILE="$SCRIPT_DIR/px4_drv-dkms.spec"

# Set up rpmbuild tree
rpmdev-setuptree 2>/dev/null || true
RPM_TOPDIR="$HOME/rpmbuild"

echo "=== px4_drv DKMS RPM Builder ==="
echo "Version: $VERSION"
echo "Spec: $SPEC_FILE"
echo "RPM build dir: $RPM_TOPDIR"
echo ""

# Get source
SOURCE_DIR="${1:-}"
if [[ -z "$SOURCE_DIR" ]]; then
    CLONE_DIR=$(mktemp -d)
    echo "Cloning px4_drv from GitHub..."
    git clone --depth 1 --branch "v${VERSION}" \
        https://github.com/tsukumijima/px4_drv.git \
        "$CLONE_DIR/${PKG_NAME}-${VERSION}" 2>/dev/null || \
    git clone --depth 1 \
        https://github.com/metalllinux/px4_drv.git \
        "$CLONE_DIR/${PKG_NAME}-${VERSION}"
    SOURCE_DIR="$CLONE_DIR/${PKG_NAME}-${VERSION}"
    CLEANUP_CLONE=true
else
    CLEANUP_CLONE=false
fi

# Create source tarball
echo "Creating source tarball..."
TARBALL="${RPM_TOPDIR}/SOURCES/${PKG_NAME}-${VERSION}.tar.gz"
PARENT_DIR=$(dirname "$SOURCE_DIR")
BASENAME=$(basename "$SOURCE_DIR")

# Ensure the directory name matches what the spec expects
if [[ "$BASENAME" != "${PKG_NAME}-${VERSION}" ]]; then
    TEMP_DIR=$(mktemp -d)
    cp -a "$SOURCE_DIR" "$TEMP_DIR/${PKG_NAME}-${VERSION}"
    tar -czf "$TARBALL" -C "$TEMP_DIR" "${PKG_NAME}-${VERSION}"
    rm -rf "$TEMP_DIR"
else
    tar -czf "$TARBALL" -C "$PARENT_DIR" "${PKG_NAME}-${VERSION}"
fi

echo "Tarball: $TARBALL"

# Copy spec file
cp "$SPEC_FILE" "${RPM_TOPDIR}/SPECS/"

# Build RPM
echo ""
echo "Building RPM..."
rpmbuild -ba "${RPM_TOPDIR}/SPECS/px4_drv-dkms.spec"

echo ""
echo "=== Build Complete ==="
echo "RPMs:"
find "${RPM_TOPDIR}/RPMS" -name "*.rpm" -print
echo ""
echo "Source RPMs:"
find "${RPM_TOPDIR}/SRPMS" -name "*.rpm" -print

# Cleanup
if $CLEANUP_CLONE; then
    rm -rf "$CLONE_DIR"
fi
