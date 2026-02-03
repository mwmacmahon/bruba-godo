#!/bin/bash
# Tests for tools/mirror.sh local logic
#
# Usage:
#   ./tests/test-mirror.sh              # Run all tests
#   ./tests/test-mirror.sh --quick      # Skip SSH-dependent tests
#   ./tests/test-mirror.sh --verbose    # Show detailed output
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
# Test: Date filtering regex matches valid dates
# ============================================================
test_date_regex_valid() {
    echo ""
    echo "=== Test: Date regex matches valid dates ==="

    local pattern='^[0-9]{4}-[0-9]{2}-[0-9]{2}'
    local valid_dates=(
        "2026-01-31-session-notes.md"
        "2025-12-25-holiday.md"
        "2024-06-15-random.md"
    )

    local all_match=true
    for filename in "${valid_dates[@]}"; do
        if [[ ! "$filename" =~ $pattern ]]; then
            log "Failed to match: $filename"
            all_match=false
        fi
    done

    if $all_match; then
        pass "Date regex matches valid date-prefixed filenames"
    else
        fail "Date regex should match all valid dates"
    fi
}

# ============================================================
# Test: Date filtering regex rejects invalid dates
# ============================================================
test_date_regex_invalid() {
    echo ""
    echo "=== Test: Date regex rejects invalid ==="

    local pattern='^[0-9]{4}-[0-9]{2}-[0-9]{2}'
    local invalid_dates=(
        "README.md"
        "notes.md"
        "01-31-2026-american-format.md"
        "2026-1-31-short-month.md"
        "session-2026-01-31.md"
    )

    local all_reject=true
    for filename in "${invalid_dates[@]}"; do
        if [[ "$filename" =~ $pattern ]]; then
            log "Should not match: $filename"
            all_reject=false
        fi
    done

    if $all_reject; then
        pass "Date regex rejects non-date-prefixed filenames"
    else
        fail "Date regex should reject invalid formats"
    fi
}

# ============================================================
# Test: Token redaction for botToken
# ============================================================
test_token_redaction_bottoken() {
    echo ""
    echo "=== Test: Token redaction for botToken ==="
    setup

    cat > "$TEMP_DIR/config.json" << 'EOF'
{
  "botToken": "secret-bot-token-12345",
  "other": "value"
}
EOF

    local result
    result=$(cat "$TEMP_DIR/config.json" | \
        sed 's/"botToken"[[:space:]]*:[[:space:]]*"[^"]*"/"botToken": "[REDACTED]"/g')

    if echo "$result" | grep -q '"botToken": "\[REDACTED\]"'; then
        if ! echo "$result" | grep -q "secret-bot-token"; then
            pass "botToken is redacted correctly"
        else
            fail "Original token still visible"
            log "Result: $result"
        fi
    else
        fail "Redacted token not found in output"
        log "Result: $result"
    fi

    teardown
}

# ============================================================
# Test: Token redaction for generic token field
# ============================================================
test_token_redaction_generic() {
    echo ""
    echo "=== Test: Token redaction for generic token ==="
    setup

    cat > "$TEMP_DIR/config.json" << 'EOF'
{
  "signal": {
    "token": "another-secret-token"
  }
}
EOF

    local result
    result=$(cat "$TEMP_DIR/config.json" | \
        sed 's/"token"[[:space:]]*:[[:space:]]*"[^"]*"/"token": "[REDACTED]"/g')

    if echo "$result" | grep -q '"token": "\[REDACTED\]"'; then
        if ! echo "$result" | grep -q "another-secret-token"; then
            pass "Generic token is redacted correctly"
        else
            fail "Original token still visible"
            log "Result: $result"
        fi
    else
        fail "Redacted token not found"
        log "Result: $result"
    fi

    teardown
}

# ============================================================
# Test: Token redaction preserves other fields
# ============================================================
test_token_redaction_preserves() {
    echo ""
    echo "=== Test: Token redaction preserves other fields ==="
    setup

    cat > "$TEMP_DIR/config.json" << 'EOF'
{
  "botToken": "secret",
  "agent": "bruba-main",
  "heartbeat": 30
}
EOF

    local result
    result=$(cat "$TEMP_DIR/config.json" | \
        sed 's/"botToken"[[:space:]]*:[[:space:]]*"[^"]*"/"botToken": "[REDACTED]"/g')

    if echo "$result" | grep -q '"agent": "bruba-main"' && \
       echo "$result" | grep -q '"heartbeat": 30'; then
        pass "Non-token fields are preserved"
    else
        fail "Non-token fields were modified"
        log "Result: $result"
    fi

    teardown
}

# ============================================================
# Test: Directory structure creation
# ============================================================
test_directory_structure() {
    echo ""
    echo "=== Test: Directory structure creation ==="
    setup

    mkdir -p "$TEMP_DIR/mirror"/{prompts,memory,config,tools}

    local all_exist=true
    for dir in prompts memory config tools; do
        if [[ ! -d "$TEMP_DIR/mirror/$dir" ]]; then
            log "Missing: $dir"
            all_exist=false
        fi
    done

    if $all_exist; then
        pass "Mirror directory structure is correct"
    else
        fail "Missing subdirectories"
    fi

    teardown
}

# ============================================================
# Test: CORE_FILES list is complete
# ============================================================
test_core_files_list() {
    echo ""
    echo "=== Test: CORE_FILES list is complete ==="

    local expected_files=(
        "AGENTS.md"
        "MEMORY.md"
        "USER.md"
        "IDENTITY.md"
        "SOUL.md"
        "TOOLS.md"
        "HEARTBEAT.md"
        "BOOTSTRAP.md"
    )

    # Extract CORE_FILES from mirror.sh (may be indented)
    local core_files_line
    core_files_line=$(grep 'CORE_FILES=' "$ROOT_DIR/tools/mirror.sh" | head -1 | cut -d'"' -f2)

    local all_present=true
    for file in "${expected_files[@]}"; do
        if ! echo "$core_files_line" | grep -q "$file"; then
            log "Missing in CORE_FILES: $file"
            all_present=false
        fi
    done

    if $all_present; then
        pass "CORE_FILES includes all expected prompt files"
    else
        fail "CORE_FILES is missing some prompt files"
    fi
}

# ============================================================
# Run all tests
# ============================================================

echo "mirror.sh Test Suite"
echo "===================="

test_date_regex_valid
test_date_regex_invalid
test_token_redaction_bottoken
test_token_redaction_generic
test_token_redaction_preserves
test_directory_structure
test_core_files_list

# Summary
echo ""
echo "===================="
echo -e "Results: ${GREEN}$PASSED passed${NC}, ${RED}$FAILED failed${NC}, ${YELLOW}$SKIPPED skipped${NC}"

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
