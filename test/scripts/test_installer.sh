#!/bin/bash
# test_installer.sh — Installer validation test suite (TAP format)
# Checks that installer files are correct and the structure is valid.

set -uo pipefail

echo "TAP version 13"
echo "1..12"

PASS=0
FAIL=0

pass() { PASS=$((PASS+1)); echo "ok $((PASS+FAIL)) - $1"; }
fail() { FAIL=$((FAIL+1)); echo "not ok $((PASS+FAIL)) - $1"; }

REPO_DIR="${1:-/tmp/project-tv-rocky-edition}"

# B-01: install.sh exists and is executable
if [[ -x "$REPO_DIR/install.sh" ]]; then
    pass "B-01 install.sh exists and is executable"
else
    fail "B-01 install.sh missing or not executable"
fi

# B-02: All module files exist
ALL_MODULES=true
for i in $(seq -w 0 18); do
    if ! ls "$REPO_DIR/modules/${i}-"*.sh &>/dev/null; then
        echo "# Missing module $i"
        ALL_MODULES=false
    fi
done
if $ALL_MODULES; then
    pass "B-02 All 19 module files present"
else
    fail "B-02 Some module files missing"
fi

# B-03: Library files exist
if [[ -f "$REPO_DIR/lib/logging.sh" ]] && \
   [[ -f "$REPO_DIR/lib/prompts.sh" ]] && \
   [[ -f "$REPO_DIR/lib/k8s-helpers.sh" ]] && \
   [[ -f "$REPO_DIR/lib/validators.sh" ]]; then
    pass "B-03 All library files present"
else
    fail "B-03 Some library files missing"
fi

# B-04: Config defaults exist
if [[ -f "$REPO_DIR/config/defaults.conf" ]]; then
    pass "B-04 Config defaults present"
else
    fail "B-04 Config defaults missing"
fi

# B-05: Manifests directory structure
EXPECTED_DIRS=("epgstation" "jellyfin" "tube-archivist" "navidrome" "cronjobs" "storage")
ALL_DIRS=true
for dir in "${EXPECTED_DIRS[@]}"; do
    if [[ ! -d "$REPO_DIR/manifests/$dir" ]]; then
        echo "# Missing manifests/$dir"
        ALL_DIRS=false
    fi
done
if $ALL_DIRS; then
    pass "B-05 Manifest directory structure correct"
else
    fail "B-05 Some manifest directories missing"
fi

# B-06: README exists
if [[ -f "$REPO_DIR/README.md" ]]; then
    pass "B-06 README.md exists"
else
    fail "B-06 README.md missing"
fi

# B-07: LICENSE exists
if [[ -f "$REPO_DIR/LICENSE" ]]; then
    pass "B-07 LICENSE exists"
else
    fail "B-07 LICENSE missing"
fi

# B-08: RPM spec exists
if [[ -f "$REPO_DIR/drivers/px4_drv/px4_drv-dkms.spec" ]]; then
    pass "B-08 RPM spec file exists"
else
    fail "B-08 RPM spec file missing"
fi

# B-09: No hardcoded passwords in manifests (except CHANGE_ME placeholders)
BAD_PASSWORDS=$(grep -rn 'password\|Password' "$REPO_DIR/manifests/" 2>/dev/null | \
    grep -v 'CHANGE_ME\|PLACEHOLDER\|valueFrom\|secretKeyRef\|key:\|name:' | wc -l)
if (( BAD_PASSWORDS == 0 )); then
    pass "B-09 No hardcoded passwords in manifests"
else
    fail "B-09 Found $BAD_PASSWORDS potential hardcoded passwords"
fi

# B-10: All shell scripts have valid bash syntax
SYNTAX_ERRORS=0
while IFS= read -r script; do
    if ! bash -n "$script" 2>/dev/null; then
        echo "# Syntax error in: $script"
        SYNTAX_ERRORS=$((SYNTAX_ERRORS + 1))
    fi
done < <(find "$REPO_DIR" -name "*.sh" -type f)
if (( SYNTAX_ERRORS == 0 )); then
    pass "B-10 All shell scripts have valid syntax"
else
    fail "B-10 $SYNTAX_ERRORS script(s) have syntax errors"
fi

# B-11: YAML manifests are valid
YAML_ERRORS=0
if python3 -c "import yaml" 2>/dev/null; then
    while IFS= read -r yaml; do
        if ! python3 -c "import yaml; yaml.safe_load(open('$yaml'))" 2>/dev/null; then
            echo "# YAML error in: $yaml"
            YAML_ERRORS=$((YAML_ERRORS + 1))
        fi
    done < <(find "$REPO_DIR/manifests" -name "*.yaml" -type f)
    if (( YAML_ERRORS == 0 )); then
        pass "B-11 All YAML manifests are valid"
    else
        fail "B-11 $YAML_ERRORS YAML file(s) have errors"
    fi
else
    # Fallback: check YAML syntax with kubectl dry-run or basic grep
    while IFS= read -r yaml; do
        if ! grep -q 'apiVersion' "$yaml" 2>/dev/null; then
            echo "# Missing apiVersion in: $yaml"
            YAML_ERRORS=$((YAML_ERRORS + 1))
        fi
    done < <(find "$REPO_DIR/manifests" -name "*.yaml" -type f)
    if (( YAML_ERRORS == 0 )); then
        pass "B-11 All YAML manifests have valid structure (pyyaml not available for deep check)"
    else
        fail "B-11 $YAML_ERRORS YAML file(s) missing apiVersion"
    fi
fi

# B-12: AI Usage policy present in README
if grep -q "Fedora AI-Assisted Contribution Policy" "$REPO_DIR/README.md" 2>/dev/null; then
    pass "B-12 AI Usage policy present in README"
else
    fail "B-12 AI Usage policy missing from README"
fi

echo ""
echo "# Results: $PASS passed, $FAIL failed out of $((PASS+FAIL))"
