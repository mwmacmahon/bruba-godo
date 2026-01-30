#!/bin/bash
# Signal channel validation
#
# Validates signal-cli configuration on the bot to catch issues like:
# - ELF binaries on macOS (wrong binary format)
# - Missing binaries or permissions
# - Port conflicts
# - Unlinked accounts
#
# Usage: ./components/signal/validate.sh [--fix] [--quick]

# Find repo root and load shared functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$ROOT_DIR/tools/lib.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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
            echo "Usage: ./components/signal/validate.sh [--fix] [--quick]"
            echo ""
            echo "Options:"
            echo "  --fix    Show remediation commands for failures"
            echo "  --quick  Skip slow checks (account verification)"
            echo ""
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
FIXES=()

# Helper functions
check_pass() {
    echo -e "  ${GREEN}✓${NC} $1"
    ((PASS++))
}

check_fail() {
    echo -e "  ${RED}✗${NC} $1"
    ((FAIL++))
    if [[ -n "$2" ]]; then
        FIXES+=("$2")
    fi
}

check_warn() {
    echo -e "  ${YELLOW}!${NC} $1"
    ((WARN++))
}

echo "=== Signal Channel Validation ==="
echo ""

# 1. Check if signal channel is enabled
echo "Channel Status:"
CHANNEL_ENABLED=$(ssh "$SSH_HOST" 'cat ~/.clawdbot/clawdbot.json 2>/dev/null' | jq -r '.channels.signal.enabled // false')
if [[ "$CHANNEL_ENABLED" == "true" ]]; then
    check_pass "Signal channel enabled"
else
    check_fail "Signal channel disabled" "Enable in clawdbot.json: .channels.signal.enabled = true"
fi

# 2. Get cliPath from config
CLI_PATH=$(ssh "$SSH_HOST" 'cat ~/.clawdbot/clawdbot.json 2>/dev/null' | jq -r '.channels.signal.cliPath // "/opt/homebrew/bin/signal-cli"')
echo ""
echo "Binary Checks (cliPath: $CLI_PATH):"

# 3. Check binary exists
BINARY_EXISTS=$(ssh "$SSH_HOST" "test -f '$CLI_PATH' && echo yes || echo no")
if [[ "$BINARY_EXISTS" == "yes" ]]; then
    check_pass "Binary exists at $CLI_PATH"
else
    check_fail "Binary not found at $CLI_PATH" "Install: brew install signal-cli"
fi

# 4. Check binary format (critical for ELF vs Mach-O issue)
if [[ "$BINARY_EXISTS" == "yes" ]]; then
    FILE_TYPE=$(ssh "$SSH_HOST" "file '$CLI_PATH' 2>/dev/null")

    # Detect remote OS
    REMOTE_OS=$(ssh "$SSH_HOST" "uname -s")

    if [[ "$REMOTE_OS" == "Darwin" ]]; then
        # macOS should have Mach-O or shell script
        if echo "$FILE_TYPE" | grep -qE "(Mach-O|shell script|POSIX shell)"; then
            check_pass "Binary format: compatible with macOS"
        elif echo "$FILE_TYPE" | grep -q "ELF"; then
            check_fail "Binary is ELF (Linux) but running on macOS!" \
                "Fix: Set cliPath to /opt/homebrew/bin/signal-cli (not embedded binary)"
        else
            check_warn "Unknown binary type: $FILE_TYPE"
        fi
    else
        # Linux should have ELF
        if echo "$FILE_TYPE" | grep -q "ELF"; then
            check_pass "Binary format: compatible with Linux"
        elif echo "$FILE_TYPE" | grep -qE "(Mach-O)"; then
            check_fail "Binary is Mach-O (macOS) but running on Linux!" \
                "Fix: Install Linux version of signal-cli"
        else
            check_warn "Unknown binary type: $FILE_TYPE"
        fi
    fi
fi

# 5. Check binary executes (version check)
if [[ "$BINARY_EXISTS" == "yes" ]]; then
    VERSION_OUTPUT=$(ssh "$SSH_HOST" "'$CLI_PATH' --version 2>&1" || true)
    if echo "$VERSION_OUTPUT" | grep -qE "signal-cli [0-9]"; then
        VERSION=$(echo "$VERSION_OUTPUT" | grep -oE "signal-cli [0-9]+\.[0-9]+\.[0-9]+" | head -1)
        check_pass "Binary executes: $VERSION"
    else
        # Check for common errors
        if echo "$VERSION_OUTPUT" | grep -qi "java"; then
            check_fail "Java not found or incompatible" "Fix: brew install openjdk"
        elif echo "$VERSION_OUTPUT" | grep -qi "permission"; then
            check_fail "Permission denied" "Fix: chmod +x '$CLI_PATH'"
        else
            check_fail "Binary won't execute: ${VERSION_OUTPUT:0:50}..." ""
        fi
    fi
fi

# 6. Check HTTP port
echo ""
echo "Port Check:"
HTTP_PORT=$(ssh "$SSH_HOST" 'cat ~/.clawdbot/clawdbot.json 2>/dev/null' | jq -r '.channels.signal.httpPort // 8080')

PORT_IN_USE=$(ssh "$SSH_HOST" "lsof -i :$HTTP_PORT -t 2>/dev/null | head -1")
if [[ -z "$PORT_IN_USE" ]]; then
    check_pass "Port $HTTP_PORT available"
else
    # Check if it's signal-cli using it (that's OK)
    PORT_PROCESS=$(ssh "$SSH_HOST" "lsof -i :$HTTP_PORT 2>/dev/null | grep LISTEN | head -1")
    if echo "$PORT_PROCESS" | grep -qi "signal\|java"; then
        check_pass "Port $HTTP_PORT in use by signal-cli (expected)"
    else
        check_fail "Port $HTTP_PORT in use by another process" \
            "Fix: Change httpPort to 8088 in clawdbot.json"
    fi
fi

# 7. Check account linked (slow - skip in quick mode)
if [[ "$QUICK_MODE" != "true" && "$BINARY_EXISTS" == "yes" ]]; then
    echo ""
    echo "Account Check:"

    # Try to list accounts
    ACCOUNTS=$(ssh "$SSH_HOST" "'$CLI_PATH' -a /Users/bruba/.local/share/signal-cli/data listAccounts 2>&1" || true)

    if echo "$ACCOUNTS" | grep -qE "^\+[0-9]+"; then
        PHONE=$(echo "$ACCOUNTS" | grep -oE "^\+[0-9]+" | head -1)
        check_pass "Account linked: $PHONE"
    elif echo "$ACCOUNTS" | grep -qi "no accounts"; then
        check_fail "No accounts linked" "Link with: signal-cli link"
    else
        check_warn "Could not verify account status"
    fi
else
    echo ""
    echo "Account Check: (skipped in quick mode)"
fi

# Summary
echo ""
echo "=== Summary ==="
echo -e "  ${GREEN}Pass:${NC} $PASS  ${RED}Fail:${NC} $FAIL  ${YELLOW}Warn:${NC} $WARN"

# Show fixes if requested
if [[ "$SHOW_FIX" == "true" && ${#FIXES[@]} -gt 0 ]]; then
    echo ""
    echo "=== Remediation ==="
    for fix in "${FIXES[@]}"; do
        echo "  → $fix"
    done
fi

# Exit code based on failures
if [[ $FAIL -gt 0 ]]; then
    exit 1
else
    exit 0
fi
