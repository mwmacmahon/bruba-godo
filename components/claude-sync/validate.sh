#!/bin/bash
# Claude Sync validation
#
# Validates claude-sync installation on the bot.
#
# Usage: ./components/claude-sync/validate.sh [--quick]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$ROOT_DIR/tools/lib.sh"

SYNC_DIR="/Users/bruba/claude-sync"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Parse arguments
QUICK_MODE=false
for arg in "$@"; do
    case $arg in
        --quick) QUICK_MODE=true ;;
        --help|-h)
            echo "Usage: ./components/claude-sync/validate.sh [--quick]"
            echo ""
            echo "Options:"
            echo "  --quick  Skip slow checks (browser launch test)"
            exit 0
            ;;
    esac
done

# Load config
load_config

# Track results
PASS=0
FAIL=0
WARN=0

check_pass() {
    echo -e "  ${GREEN}✓${NC} $1"
    ((PASS++))
}

check_fail() {
    echo -e "  ${RED}✗${NC} $1"
    ((FAIL++))
}

check_warn() {
    echo -e "  ${YELLOW}!${NC} $1"
    ((WARN++))
}

echo "=== Claude Sync Validation ==="
echo ""

# 1. Bot access
echo "Bot Access:"
if bot_exec "echo ok" >/dev/null 2>&1; then
    check_pass "Bot reachable"
else
    check_fail "Cannot reach bot"
    echo ""
    echo "=== Cannot continue without bot access ==="
    exit 1
fi

# 2. Directory structure
echo ""
echo "Directory Structure:"
if bot_exec "test -d $SYNC_DIR" 2>/dev/null; then
    check_pass "$SYNC_DIR exists"
else
    check_fail "$SYNC_DIR missing"
fi

if bot_exec "test -d $SYNC_DIR/profile" 2>/dev/null; then
    check_pass "profile/ exists"
else
    check_fail "profile/ missing"
fi

if bot_exec "test -d $SYNC_DIR/results" 2>/dev/null; then
    check_pass "results/ exists"
else
    check_fail "results/ missing"
fi

# 3. Deployed files
echo ""
echo "Deployed Files:"
for file in claude-research.py common.py selectors.json requirements.txt; do
    if bot_exec "test -f $SYNC_DIR/$file" 2>/dev/null; then
        check_pass "$file"
    else
        check_fail "$file missing"
    fi
done

# 4. Selectors.json valid JSON
SELECTORS_VALID=$(bot_exec "python3 -c \"import json; json.load(open('$SYNC_DIR/selectors.json'))\" 2>&1" || true)
if [[ -z "$SELECTORS_VALID" ]]; then
    check_pass "selectors.json valid JSON"
else
    check_fail "selectors.json invalid: $SELECTORS_VALID"
fi

# 5. Python venv
echo ""
echo "Python Environment:"
if bot_exec "test -f $SYNC_DIR/.venv/bin/python" 2>/dev/null; then
    check_pass "venv exists"
else
    check_fail "venv missing"
fi

PLAYWRIGHT_CHECK=$(bot_exec "cd $SYNC_DIR && source .venv/bin/activate && python -c 'import playwright; print(\"ok\")' 2>&1" || true)
if [[ "$PLAYWRIGHT_CHECK" == *"ok"* ]]; then
    check_pass "playwright importable"
else
    check_fail "playwright not importable: $PLAYWRIGHT_CHECK"
fi

# 6. Chromium installed
echo ""
echo "Browser:"
CHROMIUM_CHECK=$(bot_exec "cd $SYNC_DIR && source .venv/bin/activate && python -c \"
from playwright.sync_api import sync_playwright
with sync_playwright() as p:
    path = p.chromium.executable_path
    print('found' if path else 'missing')
\" 2>&1" || true)

if [[ "$CHROMIUM_CHECK" == *"found"* ]]; then
    check_pass "Chromium installed"
else
    check_warn "Chromium status unclear: ${CHROMIUM_CHECK:0:80}"
fi

# 7. Profile directory has content (indicates login was done)
echo ""
echo "Auth Status:"
PROFILE_FILES=$(bot_exec "ls $SYNC_DIR/profile/ 2>/dev/null | wc -l | tr -d ' '" || echo "0")
if [[ "$PROFILE_FILES" -gt 0 ]]; then
    check_pass "Profile has data ($PROFILE_FILES items)"
else
    check_warn "Profile empty — run setup.sh --login to authenticate"
fi

# 8. Shell wrapper accessible
echo ""
echo "Tool Integration:"
if bot_exec "test -f $SHARED_TOOLS/claude-research.sh" 2>/dev/null; then
    check_pass "claude-research.sh in SHARED_TOOLS"
else
    check_warn "claude-research.sh not yet in SHARED_TOOLS (push needed)"
fi

# Summary
echo ""
echo "=== Summary ==="
echo -e "  ${GREEN}Pass:${NC} $PASS  ${RED}Fail:${NC} $FAIL  ${YELLOW}Warn:${NC} $WARN"

if [[ $FAIL -gt 0 ]]; then
    exit 1
else
    exit 0
fi
