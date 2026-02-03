#!/bin/bash
# Tests for tools/sync-memory.sh
#
# Usage:
#   ./tests/test-sync-memory.sh              # Run all tests
#   ./tests/test-sync-memory.sh --quick      # Skip SSH-dependent tests
#   ./tests/test-sync-memory.sh --verbose    # Show detailed output
#
# Exit codes:
#   0 = All tests passed
#   1 = Test failed

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Counters
PASSED=0
FAILED=0
SKIPPED=0

# Options
VERBOSE=false
QUICK=false

# Parse args
for arg in "$@"; do
    case $arg in
        --verbose|-v) VERBOSE=true ;;
        --quick) QUICK=true ;;
    esac
done

# Helpers
pass() {
    echo -e "${GREEN}✓${NC} $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo -e "${RED}✗${NC} $1"
    FAILED=$((FAILED + 1))
}

skip() {
    echo -e "${YELLOW}⚠${NC} $1 (skipped)"
    SKIPPED=$((SKIPPED + 1))
}

log() {
    if $VERBOSE; then echo "  $*"; fi
}

# ============================================================
# Test: Script exists and is executable
# ============================================================
test_script_exists() {
    echo ""
    echo "=== Test: Script exists and is executable ==="

    local script="$ROOT_DIR/tools/sync-memory.sh"

    if [[ -f "$script" ]]; then
        if [[ -x "$script" ]]; then
            pass "sync-memory.sh exists and is executable"
        else
            fail "sync-memory.sh exists but is not executable"
        fi
    else
        fail "sync-memory.sh does not exist"
    fi
}

# ============================================================
# Test: Sources lib.sh
# ============================================================
test_sources_lib() {
    echo ""
    echo "=== Test: Sources lib.sh ==="

    local script="$ROOT_DIR/tools/sync-memory.sh"

    if grep -q 'source.*lib.sh' "$script"; then
        pass "Script sources lib.sh"
    else
        fail "Script should source lib.sh"
    fi
}

# ============================================================
# Test: Uses SSH_HOST variable
# ============================================================
test_uses_ssh_host() {
    echo ""
    echo "=== Test: Uses SSH_HOST variable ==="

    local script="$ROOT_DIR/tools/sync-memory.sh"

    if grep -q 'SSH_HOST' "$script"; then
        pass "Script uses SSH_HOST"
    else
        fail "Script should use SSH_HOST variable"
    fi
}

# ============================================================
# Test: Agent list is correct (bruba-main, bruba-guru, bruba-manager - NOT bruba-web)
# ============================================================
test_agent_list() {
    echo ""
    echo "=== Test: Agent list (main, guru, manager - NOT web) ==="

    local script="$ROOT_DIR/tools/sync-memory.sh"

    # Extract the AGENTS variable
    local agents_line
    agents_line=$(grep '^AGENTS=' "$script" 2>/dev/null || grep 'AGENTS="' "$script" 2>/dev/null || echo "")

    local has_main=false
    local has_guru=false
    local has_manager=false
    local has_web=false

    if echo "$agents_line" | grep -q "bruba-main"; then
        has_main=true
    fi
    if echo "$agents_line" | grep -q "bruba-guru"; then
        has_guru=true
    fi
    if echo "$agents_line" | grep -q "bruba-manager"; then
        has_manager=true
    fi
    if echo "$agents_line" | grep -q "bruba-web"; then
        has_web=true
    fi

    log "AGENTS line: $agents_line"
    log "has_main=$has_main, has_guru=$has_guru, has_manager=$has_manager, has_web=$has_web"

    if $has_main && $has_guru && $has_manager && ! $has_web; then
        pass "Agent list includes main, guru, manager but NOT web"
    else
        fail "Agent list should be: bruba-main bruba-guru bruba-manager (NOT bruba-web)"
    fi
}

# ============================================================
# Test: Has correct exclude patterns
# ============================================================
test_exclude_patterns() {
    echo ""
    echo "=== Test: Has correct rsync exclude patterns ==="

    local script="$ROOT_DIR/tools/sync-memory.sh"
    local required_excludes=(".git" "sessions/" "logs/" "mirror/" "exports/" "intake/")
    local found_all=true

    for pattern in "${required_excludes[@]}"; do
        if ! grep -q "exclude.*$pattern" "$script"; then
            log "Missing exclude: $pattern"
            found_all=false
        fi
    done

    if $found_all; then
        pass "All required exclude patterns present"
    else
        fail "Missing required exclude patterns"
    fi
}

# ============================================================
# Test: Rsync uses --delete and -av flags
# ============================================================
test_rsync_flags() {
    echo ""
    echo "=== Test: Rsync uses --delete and -av flags ==="

    local script="$ROOT_DIR/tools/sync-memory.sh"
    local has_delete=false
    local has_av=false

    if grep -q 'rsync.*--delete' "$script"; then
        has_delete=true
    fi
    if grep -q 'rsync.*-av' "$script"; then
        has_av=true
    fi

    if $has_delete && $has_av; then
        pass "Rsync uses both --delete and -av flags"
    else
        fail "Rsync should use --delete and -av flags (has_delete=$has_delete, has_av=$has_av)"
    fi
}

# ============================================================
# Test: Calls openclaw memory index at end
# ============================================================
test_memory_index() {
    echo ""
    echo "=== Test: Calls openclaw memory index ==="

    local script="$ROOT_DIR/tools/sync-memory.sh"

    if grep -q 'openclaw memory index' "$script"; then
        pass "Script calls openclaw memory index"
    else
        fail "Script should call 'openclaw memory index' at end"
    fi
}

# ============================================================
# Test: Checks for workspace-snapshot directory
# ============================================================
test_workspace_snapshot_check() {
    echo ""
    echo "=== Test: Checks for workspace-snapshot directory ==="

    local script="$ROOT_DIR/tools/sync-memory.sh"

    if grep -q 'workspace-snapshot' "$script"; then
        pass "Script checks for workspace-snapshot directory"
    else
        fail "Script should check for workspace-snapshot directory before syncing"
    fi
}

# ============================================================
# Test: Has DS_Store and tmp excludes
# ============================================================
test_ds_store_exclude() {
    echo ""
    echo "=== Test: Excludes .DS_Store and *.tmp files ==="

    local script="$ROOT_DIR/tools/sync-memory.sh"
    local has_ds_store=false
    local has_tmp=false

    if grep -q "exclude.*DS_Store" "$script"; then
        has_ds_store=true
    fi
    if grep -q "exclude.*\.tmp" "$script"; then
        has_tmp=true
    fi

    if $has_ds_store && $has_tmp; then
        pass "Excludes .DS_Store and *.tmp"
    else
        fail "Should exclude .DS_Store and *.tmp (has_ds_store=$has_ds_store, has_tmp=$has_tmp)"
    fi
}

# ============================================================
# Test: Uses BOT_BASE or similar base path
# ============================================================
test_bot_base_path() {
    echo ""
    echo "=== Test: Uses base path for agents ==="

    local script="$ROOT_DIR/tools/sync-memory.sh"

    if grep -q 'BOT_BASE\|/Users/bruba/agents' "$script"; then
        pass "Uses base path for agent directories"
    else
        fail "Should use BOT_BASE or /Users/bruba/agents path"
    fi
}

# ============================================================
# Run all tests
# ============================================================

echo "sync-memory.sh Test Suite"
echo "========================="

test_script_exists
test_sources_lib
test_uses_ssh_host
test_agent_list
test_exclude_patterns
test_rsync_flags
test_memory_index
test_workspace_snapshot_check
test_ds_store_exclude
test_bot_base_path

# Summary
echo ""
echo "========================="
echo -e "Results: ${GREEN}$PASSED passed${NC}, ${RED}$FAILED failed${NC}, ${YELLOW}$SKIPPED skipped${NC}"

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
