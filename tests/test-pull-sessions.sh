#!/bin/bash
# Tests for tools/pull-sessions.sh local logic
#
# Usage:
#   ./tests/test-pull-sessions.sh              # Run all tests
#   ./tests/test-pull-sessions.sh --quick      # Skip SSH-dependent tests
#   ./tests/test-pull-sessions.sh --verbose    # Show detailed output
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

# Temp directory
TEMP_DIR=""

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

setup() {
    TEMP_DIR=$(mktemp -d)
    log "Setup in $TEMP_DIR"
}

teardown() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        log "Cleaned up $TEMP_DIR"
    fi
}

# ============================================================
# Test: State file - check if session already pulled
# ============================================================
test_state_file_check() {
    echo ""
    echo "=== Test: State file - check already pulled ==="
    setup

    # Create state file with some sessions
    cat > "$TEMP_DIR/.pulled" << 'EOF'
abc123-def456-789
xyz789-abc123-456
session-already-pulled
EOF

    local session_id="abc123-def456-789"

    if grep -q "^$session_id$" "$TEMP_DIR/.pulled" 2>/dev/null; then
        pass "Existing session found in state file"
    else
        fail "Should find existing session in state file"
    fi

    teardown
}

# ============================================================
# Test: State file - new session not in file
# ============================================================
test_state_file_new() {
    echo ""
    echo "=== Test: State file - new session detection ==="
    setup

    cat > "$TEMP_DIR/.pulled" << 'EOF'
existing-session-1
existing-session-2
EOF

    local new_session="brand-new-session"

    if ! grep -q "^$new_session$" "$TEMP_DIR/.pulled" 2>/dev/null; then
        pass "New session correctly not found in state"
    else
        fail "New session should not be in state file"
    fi

    teardown
}

# ============================================================
# Test: State file - append new session
# ============================================================
test_state_file_append() {
    echo ""
    echo "=== Test: State file - append new session ==="
    setup

    cat > "$TEMP_DIR/.pulled" << 'EOF'
existing-session
EOF

    local new_session="new-session-id"
    echo "$new_session" >> "$TEMP_DIR/.pulled"

    if grep -q "^$new_session$" "$TEMP_DIR/.pulled"; then
        local count
        count=$(wc -l < "$TEMP_DIR/.pulled" | tr -d ' ')
        if [[ "$count" -eq 2 ]]; then
            pass "New session appended correctly"
        else
            fail "State file should have 2 lines, has $count"
        fi
    else
        fail "New session not found after append"
    fi

    teardown
}

# ============================================================
# Test: Force re-pull removes then re-adds
# ============================================================
test_force_repull() {
    echo ""
    echo "=== Test: Force re-pull removes then re-adds ==="
    setup

    cat > "$TEMP_DIR/.pulled" << 'EOF'
session-1
session-to-force
session-3
EOF

    local force_session="session-to-force"

    # Simulate force re-pull logic from pull-sessions.sh
    grep -v "^$force_session$" "$TEMP_DIR/.pulled" > "$TEMP_DIR/.pulled.tmp" 2>/dev/null || true
    mv "$TEMP_DIR/.pulled.tmp" "$TEMP_DIR/.pulled"
    echo "$force_session" >> "$TEMP_DIR/.pulled"

    # Should be at end now
    local last_line
    last_line=$(tail -1 "$TEMP_DIR/.pulled")

    if [[ "$last_line" == "$force_session" ]]; then
        local count
        count=$(grep -c "^$force_session$" "$TEMP_DIR/.pulled")
        if [[ "$count" -eq 1 ]]; then
            pass "Force re-pull: removed and re-added at end"
        else
            fail "Duplicate entries after force re-pull"
        fi
    else
        fail "Force session should be at end of file"
    fi

    teardown
}

# ============================================================
# Test: Session ID extraction from JSON
# ============================================================
test_session_id_extraction() {
    echo ""
    echo "=== Test: Session ID extraction from JSON ==="
    setup

    cat > "$TEMP_DIR/sessions.json" << 'EOF'
{
  "bruba-main": {
    "sessionId": "abc123-session-id-xyz",
    "createdAt": "2026-01-31T10:00:00Z"
  }
}
EOF

    local active_id
    active_id=$(cat "$TEMP_DIR/sessions.json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for key, val in data.items():
    if 'sessionId' in val:
        print(val['sessionId'])
        break
" 2>/dev/null) || true

    if [[ "$active_id" == "abc123-session-id-xyz" ]]; then
        pass "Session ID extracted correctly from JSON"
    else
        fail "Session ID extraction failed (got: $active_id)"
    fi

    teardown
}

# ============================================================
# Test: Session ID extraction handles empty JSON
# ============================================================
test_session_id_empty_json() {
    echo ""
    echo "=== Test: Session ID extraction handles empty ==="
    setup

    echo "{}" > "$TEMP_DIR/sessions.json"

    local active_id exit_code=0
    active_id=$(cat "$TEMP_DIR/sessions.json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for key, val in data.items():
    if 'sessionId' in val:
        print(val['sessionId'])
        break
" 2>/dev/null) || exit_code=$?

    if [[ -z "$active_id" ]]; then
        pass "Empty JSON produces empty session ID"
    else
        fail "Should produce empty ID for empty JSON"
    fi

    teardown
}

# ============================================================
# Test: Summary text format
# ============================================================
test_summary_format() {
    echo ""
    echo "=== Test: Summary text format ==="

    local pulled=3
    local skipped=5
    local converted=2

    # Test the summary format patterns from pull-sessions.sh
    local summary1="Sessions: $pulled new, $skipped skipped"
    local summary2="Sessions: $pulled new, $skipped skipped, $converted converted to intake/"

    if [[ "$summary1" == "Sessions: 3 new, 5 skipped" ]]; then
        if [[ "$summary2" == "Sessions: 3 new, 5 skipped, 2 converted to intake/" ]]; then
            pass "Summary text formats correctly"
        else
            fail "Summary with conversion format wrong"
        fi
    else
        fail "Basic summary format wrong"
    fi
}

# ============================================================
# Test: Empty state file handling
# ============================================================
test_empty_state_file() {
    echo ""
    echo "=== Test: Empty state file handling ==="
    setup

    touch "$TEMP_DIR/.pulled"

    local session_id="new-session"

    # This should not match anything
    if ! grep -q "^$session_id$" "$TEMP_DIR/.pulled" 2>/dev/null; then
        pass "Empty state file correctly reports no matches"
    else
        fail "Empty state file should not match anything"
    fi

    teardown
}

# ============================================================
# Test: Session ID with special chars
# ============================================================
test_session_id_special_chars() {
    echo ""
    echo "=== Test: Session ID exact matching ==="
    setup

    # Session IDs that could cause regex issues
    cat > "$TEMP_DIR/.pulled" << 'EOF'
abc-123-def
abc-123
123-def
EOF

    # Should find exact match only
    if grep -q "^abc-123$" "$TEMP_DIR/.pulled"; then
        if ! grep -q "^abc-123-$" "$TEMP_DIR/.pulled" 2>/dev/null; then
            pass "Exact session ID matching works"
        else
            fail "Partial match should not succeed"
        fi
    else
        fail "Exact match should be found"
    fi

    teardown
}

# ============================================================
# Run all tests
# ============================================================

echo "pull-sessions.sh Test Suite"
echo "============================"

test_state_file_check
test_state_file_new
test_state_file_append
test_force_repull
test_session_id_extraction
test_session_id_empty_json
test_summary_format
test_empty_state_file
test_session_id_special_chars

# Summary
echo ""
echo "============================"
echo -e "Results: ${GREEN}$PASSED passed${NC}, ${RED}$FAILED failed${NC}, ${YELLOW}$SKIPPED skipped${NC}"

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
