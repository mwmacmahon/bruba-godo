#!/bin/bash
# Tests for tools/lib.sh shared functions
#
# Usage:
#   ./tests/test-lib.sh              # Run all tests
#   ./tests/test-lib.sh --quick      # Same (no SSH tests here)
#   ./tests/test-lib.sh --verbose    # Show detailed output
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
    mkdir -p "$TEMP_DIR/tools"

    # Copy lib.sh to temp
    cp "$ROOT_DIR/tools/lib.sh" "$TEMP_DIR/tools/"

    log "Setup in $TEMP_DIR"
}

teardown() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        log "Cleaned up $TEMP_DIR"
    fi
}

# ============================================================
# Test: load_config with valid config.yaml
# ============================================================
test_load_config_valid() {
    echo ""
    echo "=== Test: load_config with valid config ==="
    setup

    # Create valid config
    cat > "$TEMP_DIR/config.yaml" << 'EOF'
version: 2

ssh:
  host: testbot

remote:
  home: /Users/testuser
  workspace: /Users/testuser/clawd
  clawdbot: /Users/testuser/.clawdbot
  agent_id: test-agent

local:
  mirror: mirror
  sessions: sessions
  logs: logs
  intake: intake
  reference: reference
  exports: exports

clone_repo_code: true
EOF

    # Source lib.sh with overridden ROOT_DIR
    (
        cd "$TEMP_DIR"
        ROOT_DIR="$TEMP_DIR"
        source "$TEMP_DIR/tools/lib.sh"
        load_config

        # Verify values
        [[ "$SSH_HOST" == "testbot" ]] || exit 1
        [[ "$REMOTE_HOME" == "/Users/testuser" ]] || exit 2
        [[ "$REMOTE_WORKSPACE" == "/Users/testuser/clawd" ]] || exit 3
        [[ "$CLONE_REPO_CODE" == "true" ]] || exit 4
        [[ "$MIRROR_DIR" == "$TEMP_DIR/mirror" ]] || exit 5
    )

    if [[ $? -eq 0 ]]; then
        pass "load_config parses valid config correctly"
    else
        fail "load_config failed to parse valid config (exit $?)"
    fi

    teardown
}

# ============================================================
# Test: load_config with missing config.yaml
# ============================================================
test_load_config_missing() {
    echo ""
    echo "=== Test: load_config with missing config ==="
    setup

    # Don't create config.yaml

    local exit_code=0
    (
        cd "$TEMP_DIR"
        ROOT_DIR="$TEMP_DIR"
        source "$TEMP_DIR/tools/lib.sh"
        load_config 2>/dev/null
    ) || exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        pass "load_config returns error for missing config"
    else
        fail "load_config should fail when config.yaml missing"
    fi

    teardown
}

# ============================================================
# Test: load_config uses defaults for missing keys
# ============================================================
test_load_config_defaults() {
    echo ""
    echo "=== Test: load_config uses defaults ==="
    setup

    # Create minimal config (missing local paths)
    cat > "$TEMP_DIR/config.yaml" << 'EOF'
version: 2

ssh:
  host: testbot

remote:
  home: /Users/testuser
  workspace: /Users/testuser/clawd
  clawdbot: /Users/testuser/.clawdbot
  agent_id: test-agent
EOF

    (
        cd "$TEMP_DIR"
        ROOT_DIR="$TEMP_DIR"
        source "$TEMP_DIR/tools/lib.sh"
        load_config

        # Should use defaults
        [[ "$MIRROR_DIR" == "$TEMP_DIR/mirror" ]] || exit 1
        [[ "$CLONE_REPO_CODE" == "false" ]] || exit 2
    )

    if [[ $? -eq 0 ]]; then
        pass "load_config uses defaults for missing keys"
    else
        fail "load_config failed to use defaults"
    fi

    teardown
}

# ============================================================
# Test: parse_common_args recognizes flags
# ============================================================
test_parse_common_args_flags() {
    echo ""
    echo "=== Test: parse_common_args recognizes flags ==="
    setup

    (
        source "$TEMP_DIR/tools/lib.sh"

        # Test --dry-run
        parse_common_args --dry-run
        [[ "$DRY_RUN" == "true" ]] || exit 1

        # Test --verbose
        parse_common_args --verbose
        [[ "$VERBOSE" == "true" ]] || exit 2
        [[ "$QUIET" == "false" ]] || exit 3

        # Test --quiet
        parse_common_args --quiet
        [[ "$QUIET" == "true" ]] || exit 4
        [[ "$VERBOSE" == "false" ]] || exit 5

        # Test short flags
        parse_common_args -n -v
        [[ "$DRY_RUN" == "true" ]] || exit 6
        [[ "$VERBOSE" == "true" ]] || exit 7
    )

    if [[ $? -eq 0 ]]; then
        pass "parse_common_args recognizes all flags"
    else
        fail "parse_common_args failed on flags (exit $?)"
    fi

    teardown
}

# ============================================================
# Test: parse_common_args returns 1 for --help
# ============================================================
test_parse_common_args_help() {
    echo ""
    echo "=== Test: parse_common_args returns 1 for --help ==="
    setup

    local exit_code=0
    (
        source "$TEMP_DIR/tools/lib.sh"
        parse_common_args --help
    ) || exit_code=$?

    if [[ $exit_code -eq 1 ]]; then
        pass "parse_common_args returns 1 for --help"
    else
        fail "parse_common_args should return 1 for --help"
    fi

    teardown
}

# ============================================================
# Test: require_commands succeeds for existing commands
# ============================================================
test_require_commands_success() {
    echo ""
    echo "=== Test: require_commands succeeds for existing ==="
    setup

    (
        source "$TEMP_DIR/tools/lib.sh"
        require_commands ls cat grep
    )

    if [[ $? -eq 0 ]]; then
        pass "require_commands succeeds for existing commands"
    else
        fail "require_commands should succeed for ls/cat/grep"
    fi

    teardown
}

# ============================================================
# Test: require_commands fails for missing commands
# ============================================================
test_require_commands_missing() {
    echo ""
    echo "=== Test: require_commands fails for missing ==="
    setup

    local output exit_code=0
    output=$(
        source "$TEMP_DIR/tools/lib.sh"
        require_commands ls nonexistent_cmd_xyz 2>&1
    ) || exit_code=$?

    if [[ $exit_code -ne 0 ]] && echo "$output" | grep -q "nonexistent_cmd_xyz"; then
        pass "require_commands fails and names missing command"
    else
        fail "require_commands should fail and name missing command"
        log "Output: $output"
    fi

    teardown
}

# ============================================================
# Test: rotate_log rotates large files
# ============================================================
test_rotate_log() {
    echo ""
    echo "=== Test: rotate_log rotates large files ==="
    setup

    # Create a log file over the size limit
    local log_file="$TEMP_DIR/test.log"
    dd if=/dev/zero of="$log_file" bs=1024 count=10 2>/dev/null  # 10KB

    (
        source "$TEMP_DIR/tools/lib.sh"
        # Rotate if over 5KB, keep 2
        rotate_log "$log_file" 5 2
    )

    if [[ -f "${log_file}.1" ]] && [[ ! -f "$log_file" ]]; then
        pass "rotate_log rotates file to .1"
    else
        fail "rotate_log should move file to .1"
        log "Original exists: $([[ -f "$log_file" ]] && echo yes || echo no)"
        log ".1 exists: $([[ -f "${log_file}.1" ]] && echo yes || echo no)"
    fi

    teardown
}

# ============================================================
# Test: rotate_log skips small files
# ============================================================
test_rotate_log_small() {
    echo ""
    echo "=== Test: rotate_log skips small files ==="
    setup

    # Create a small log file
    local log_file="$TEMP_DIR/test.log"
    echo "small content" > "$log_file"

    (
        source "$TEMP_DIR/tools/lib.sh"
        # 5KB threshold
        rotate_log "$log_file" 5 2
    )

    if [[ -f "$log_file" ]] && [[ ! -f "${log_file}.1" ]]; then
        pass "rotate_log skips small files"
    else
        fail "rotate_log should not rotate small files"
    fi

    teardown
}

# ============================================================
# Run all tests
# ============================================================

echo "lib.sh Test Suite"
echo "================="

test_load_config_valid
test_load_config_missing
test_load_config_defaults
test_parse_common_args_flags
test_parse_common_args_help
test_require_commands_success
test_require_commands_missing
test_rotate_log
test_rotate_log_small

# Summary
echo ""
echo "================="
echo -e "Results: ${GREEN}$PASSED passed${NC}, ${RED}$FAILED failed${NC}, ${YELLOW}$SKIPPED skipped${NC}"

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
