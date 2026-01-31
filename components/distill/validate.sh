#!/bin/bash
# Distill component validation
#
# Validates that distill is properly configured.
#
# Usage: ./components/distill/validate.sh [--fix] [--quick]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Parse arguments
SHOW_FIX=false
QUICK_MODE=false
for arg in "$@"; do
    case $arg in
        --fix)
            SHOW_FIX=true
            ;;
        --quick)
            QUICK_MODE=true
            ;;
        --help|-h)
            echo "Usage: ./components/distill/validate.sh [--fix] [--quick]"
            echo ""
            echo "Options:"
            echo "  --fix    Show remediation commands for failures"
            echo "  --quick  Skip slow checks"
            exit 0
            ;;
    esac
done

# Track results
PASS=0
FAIL=0
WARN=0
FIXES=()

check_pass() {
    echo -e "  ${GREEN}✓${NC} $1"
    PASS=$((PASS + 1))
}

check_fail() {
    echo -e "  ${RED}✗${NC} $1"
    FAIL=$((FAIL + 1))
    if [[ -n "$2" ]]; then
        FIXES+=("$2")
    fi
}

check_warn() {
    echo -e "  ${YELLOW}!${NC} $1"
    WARN=$((WARN + 1))
}

echo "=== Distill Component Validation ==="
echo ""

# 1. Python version
echo "Python:"
if command -v python3 &> /dev/null; then
    PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
    if python3 -c 'import sys; exit(0 if sys.version_info >= (3, 8) else 1)'; then
        check_pass "Python $PYTHON_VERSION (3.8+ required)"
    else
        check_fail "Python $PYTHON_VERSION (3.8+ required)" "Upgrade Python to 3.8+"
    fi
else
    check_fail "Python not found" "Install: brew install python3"
fi

# 2. Dependencies
echo ""
echo "Dependencies:"

if python3 -c "import yaml" 2>/dev/null; then
    check_pass "PyYAML installed"
else
    check_fail "PyYAML not installed" "pip3 install pyyaml"
fi

if python3 -c "import anthropic" 2>/dev/null; then
    check_pass "anthropic installed (AI summaries enabled)"
else
    check_warn "anthropic not installed (AI summaries disabled)"
fi

# 3. Config file
echo ""
echo "Configuration:"

if [[ -f "$SCRIPT_DIR/config.yaml" ]]; then
    check_pass "config.yaml exists"

    # Validate YAML syntax
    if python3 -c "import yaml; yaml.safe_load(open('$SCRIPT_DIR/config.yaml'))" 2>/dev/null; then
        check_pass "config.yaml valid YAML"
    else
        check_fail "config.yaml has syntax errors" "Check YAML syntax"
    fi
else
    check_fail "config.yaml missing" "Run setup.sh first"
fi

# 4. API key (optional)
if [[ -f "$ROOT_DIR/.env" ]] && grep -q "ANTHROPIC_API_KEY" "$ROOT_DIR/.env"; then
    check_pass "ANTHROPIC_API_KEY configured"
else
    check_warn "No ANTHROPIC_API_KEY (AI summaries disabled)"
fi

# 5. Directories
echo ""
echo "Directories:"

if [[ -d "$ROOT_DIR/sessions" ]]; then
    check_pass "sessions/ exists"
else
    check_warn "sessions/ missing (will be created on first pull)"
fi

if [[ -d "$ROOT_DIR/sessions/converted" ]]; then
    check_pass "sessions/converted/ exists"
else
    check_warn "sessions/converted/ missing"
fi

if [[ -d "$ROOT_DIR/reference/transcripts" ]]; then
    check_pass "reference/transcripts/ exists"
else
    check_warn "reference/transcripts/ missing"
fi

# Summary
echo ""
echo "=== Summary ==="
echo -e "  ${GREEN}Pass:${NC} $PASS  ${RED}Fail:${NC} $FAIL  ${YELLOW}Warn:${NC} $WARN"

if [[ "$SHOW_FIX" == "true" && ${#FIXES[@]} -gt 0 ]]; then
    echo ""
    echo "=== Remediation ==="
    for fix in "${FIXES[@]}"; do
        echo "  → $fix"
    done
fi

if [[ $FAIL -gt 0 ]]; then
    exit 1
else
    exit 0
fi
