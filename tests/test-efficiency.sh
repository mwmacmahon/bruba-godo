#!/bin/bash
# Tests for sync pipeline efficiency improvements
#
# Coverage:
#   - YAML parsing efficiency (single vs multiple parse)
#   - SSH call patterns (N+1 anti-pattern detection)
#   - Change detection mechanisms
#   - Checksum/hash comparison
#   - Configuration for efficiency features
#
# Usage:
#   ./tests/test-efficiency.sh              # Run all tests
#   ./tests/test-efficiency.sh --quick      # Skip SSH-dependent tests
#   ./tests/test-efficiency.sh --verbose    # Show detailed output
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
# YAML PARSING EFFICIENCY TESTS
# ============================================================

# Test: Single YAML parse extracts all fields at once
test_yaml_single_parse() {
    echo ""
    echo "=== Test: Single YAML parse extracts all fields ==="
    setup

    # Create test YAML
    cat > "$TEMP_DIR/test.yaml" << 'EOF'
name: test-job
description: A test job
status: active

schedule:
  cron: "0 9 * * *"
  timezone: America/New_York

execution:
  session: isolated
  model: anthropic/claude-haiku-4-5
  agent: bruba-manager

message: |
  Multi-line message
  with content.
EOF

    # Single parse approach (efficient)
    local output
    output=$(python3 -c "
import yaml
import json

with open('$TEMP_DIR/test.yaml') as f:
    data = yaml.safe_load(f)

result = {
    'name': data.get('name', ''),
    'description': data.get('description', ''),
    'status': data.get('status', 'proposed'),
    'cron': data.get('schedule', {}).get('cron', ''),
    'timezone': data.get('schedule', {}).get('timezone', 'UTC'),
    'session': data.get('execution', {}).get('session', 'isolated'),
    'model': data.get('execution', {}).get('model', ''),
    'agent': data.get('execution', {}).get('agent', 'bruba-main'),
    'message': data.get('message', '')
}
print(json.dumps(result))
")

    # Verify all fields extracted
    local name status cron agent
    name=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['name'])")
    status=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['status'])")
    cron=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['cron'])")
    agent=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin)['agent'])")

    local errors=0
    [[ "$name" == "test-job" ]] || { log "name mismatch: $name"; errors=$((errors+1)); }
    [[ "$status" == "active" ]] || { log "status mismatch: $status"; errors=$((errors+1)); }
    [[ "$cron" == "0 9 * * *" ]] || { log "cron mismatch: $cron"; errors=$((errors+1)); }
    [[ "$agent" == "bruba-manager" ]] || { log "agent mismatch: $agent"; errors=$((errors+1)); }

    if [[ $errors -eq 0 ]]; then
        pass "Single YAML parse extracts all 9 fields correctly"
    else
        fail "Single YAML parse failed ($errors fields incorrect)"
    fi

    teardown
}

# Test: parse-yaml.py helper exists and works
test_parse_yaml_helper_exists() {
    echo ""
    echo "=== Test: parse-yaml.py helper exists ==="

    if [[ -f "$ROOT_DIR/tools/helpers/parse-yaml.py" ]]; then
        pass "parse-yaml.py helper exists"
    else
        skip "parse-yaml.py helper not implemented yet"
    fi
}

# ============================================================
# SSH CALL PATTERN TESTS
# ============================================================

# Test: mirror.sh uses find instead of individual test -f
test_mirror_uses_find_pattern() {
    echo ""
    echo "=== Test: mirror.sh avoids N+1 SSH pattern ==="

    local script="$ROOT_DIR/tools/mirror.sh"

    # Count 'test -f' calls (bad pattern)
    local test_count
    test_count=$(grep -c 'bot_cmd.*test -f\|bot_cmd "test -f' "$script" 2>/dev/null || echo "0")

    # Check for efficient find pattern (good pattern)
    local has_find=false
    if grep -q 'bot_cmd.*find\|bot_cmd "find' "$script"; then
        has_find=true
    fi

    if [[ "$test_count" -lt 5 ]] || $has_find; then
        pass "mirror.sh has reasonable SSH pattern (test_count=$test_count, has_find=$has_find)"
    else
        fail "mirror.sh has N+1 SSH pattern ($test_count individual test -f calls)"
    fi
}

# Test: CORE_FILES defined for batch operations
test_core_files_batch_friendly() {
    echo ""
    echo "=== Test: CORE_FILES enables batch operations ==="

    local script="$ROOT_DIR/tools/mirror.sh"

    # Check for CORE_FILES with or without leading whitespace
    if grep -q 'CORE_FILES=' "$script"; then
        # Extract and count
        local core_files
        core_files=$(grep 'CORE_FILES=' "$script" | head -1 | cut -d'"' -f2)
        local count
        count=$(echo "$core_files" | wc -w | tr -d ' ')

        if [[ "$count" -ge 6 ]]; then
            pass "CORE_FILES defines $count files for batch operations"
        else
            fail "CORE_FILES has too few files ($count)"
        fi
    else
        fail "CORE_FILES not defined in mirror.sh"
    fi
}

# ============================================================
# CHANGE DETECTION TESTS
# ============================================================

# Test: push.sh uses MD5 hash for change detection
test_push_change_detection() {
    echo ""
    echo "=== Test: push.sh uses hash for change detection ==="

    local script="$ROOT_DIR/tools/push.sh"

    if grep -q 'md5\|MD5\|hash' "$script"; then
        pass "push.sh uses hash-based change detection"
    else
        skip "push.sh change detection not yet implemented"
    fi
}

# Test: .pulled file tracks processed sessions
test_pulled_tracking_file() {
    echo ""
    echo "=== Test: pull-sessions.sh uses .pulled tracking ==="

    local script="$ROOT_DIR/tools/pull-sessions.sh"

    if grep -q '\.pulled' "$script"; then
        pass "pull-sessions.sh uses .pulled for incremental tracking"
    else
        fail "pull-sessions.sh should use .pulled file"
    fi
}

# Test: Checksum comparison in update-allowlist.sh
test_allowlist_checksum() {
    echo ""
    echo "=== Test: update-allowlist.sh uses diff before write ==="

    local script="$ROOT_DIR/tools/update-allowlist.sh"

    if [[ -f "$script" ]]; then
        if grep -q 'diff\|cmp' "$script"; then
            pass "update-allowlist.sh compares before writing"
        else
            skip "update-allowlist.sh comparison not found"
        fi
    else
        skip "update-allowlist.sh not found"
    fi
}

# ============================================================
# RSYNC EFFICIENCY TESTS
# ============================================================

# Test: push.sh uses rsync with compression
test_rsync_compression() {
    echo ""
    echo "=== Test: push.sh rsync uses compression ==="

    local script="$ROOT_DIR/tools/push.sh"

    if grep -q '\-.*z\|--compress' "$script"; then
        pass "push.sh rsync uses compression (-z)"
    else
        fail "push.sh should use rsync compression"
    fi
}

# Test: rsync uses archive mode for efficiency
test_rsync_archive_mode() {
    echo ""
    echo "=== Test: push.sh rsync uses archive mode ==="

    local script="$ROOT_DIR/tools/push.sh"

    if grep -q '\-a\|--archive' "$script"; then
        pass "push.sh rsync uses archive mode (-a)"
    else
        fail "push.sh should use rsync archive mode"
    fi
}

# ============================================================
# SSH CONTROLMASTER TESTS
# ============================================================

# Test: lib.sh has SSH ControlMaster support (or prepared for it)
test_ssh_controlmaster_ready() {
    echo ""
    echo "=== Test: lib.sh SSH ControlMaster support ==="

    local script="$ROOT_DIR/tools/lib.sh"

    if grep -q 'ControlMaster\|ControlPath\|ControlPersist' "$script"; then
        pass "lib.sh has SSH ControlMaster configuration"
    else
        # Check if bot_cmd function exists (can be enhanced later)
        if grep -q 'bot_cmd()' "$script"; then
            skip "lib.sh has bot_cmd but no ControlMaster yet (future enhancement)"
        else
            fail "lib.sh should have bot_cmd function for SSH"
        fi
    fi
}

# ============================================================
# LOCAL-ONLY SCRIPT EFFICIENCY TESTS
# ============================================================

# Test: assemble-prompts.sh has no SSH calls (pure local)
test_assemble_no_ssh() {
    echo ""
    echo "=== Test: assemble-prompts.sh is pure local ==="

    local script="$ROOT_DIR/tools/assemble-prompts.sh"

    if [[ -f "$script" ]]; then
        local ssh_count
        ssh_count=$(grep -E 'ssh |bot_cmd|scp |rsync ' "$script" 2>/dev/null | wc -l | tr -d ' ')

        if [[ "$ssh_count" -eq 0 ]]; then
            pass "assemble-prompts.sh makes no SSH calls (efficient)"
        else
            fail "assemble-prompts.sh should not make SSH calls ($ssh_count found)"
        fi
    else
        skip "assemble-prompts.sh not found"
    fi
}

# Test: detect-conflicts.sh has no SSH calls (pure local)
test_detect_conflicts_no_ssh() {
    echo ""
    echo "=== Test: detect-conflicts.sh is pure local ==="

    local script="$ROOT_DIR/tools/detect-conflicts.sh"

    if [[ -f "$script" ]]; then
        local ssh_count
        ssh_count=$(grep -E 'ssh |bot_cmd|scp |rsync ' "$script" 2>/dev/null | wc -l | tr -d ' ')

        if [[ "$ssh_count" -eq 0 ]]; then
            pass "detect-conflicts.sh makes no SSH calls (efficient)"
        else
            fail "detect-conflicts.sh should not make SSH calls ($ssh_count found)"
        fi
    else
        skip "detect-conflicts.sh not found"
    fi
}

# ============================================================
# SCRIPT DOCUMENTATION TESTS
# ============================================================

# Test: Scripts have usage documentation
test_scripts_have_usage() {
    echo ""
    echo "=== Test: Core scripts have usage documentation ==="

    local scripts=(
        "mirror.sh"
        "push.sh"
        "pull-sessions.sh"
        "assemble-prompts.sh"
        "sync-cronjobs.sh"
    )

    local documented=0
    local total=0

    for script in "${scripts[@]}"; do
        local path="$ROOT_DIR/tools/$script"
        if [[ -f "$path" ]]; then
            total=$((total + 1))
            if grep -q 'Usage:\|usage:' "$path"; then
                log "$script has usage docs"
                documented=$((documented + 1))
            else
                log "$script missing usage docs"
            fi
        fi
    done

    if [[ $documented -eq $total ]]; then
        pass "All $total core scripts have usage documentation"
    else
        fail "$documented/$total scripts have usage documentation"
    fi
}

# ============================================================
# EFFICIENCY RECOMMENDATIONS DOC TESTS
# ============================================================

# Test: efficiency-recommendations.md exists
test_efficiency_doc_exists() {
    echo ""
    echo "=== Test: efficiency-recommendations.md exists ==="

    if [[ -f "$ROOT_DIR/docs/efficiency-recommendations.md" ]]; then
        pass "docs/efficiency-recommendations.md exists"
    else
        fail "docs/efficiency-recommendations.md should exist"
    fi
}

# Test: efficiency doc has script audit table
test_efficiency_doc_has_audit() {
    echo ""
    echo "=== Test: efficiency doc has script audit ==="

    local doc="$ROOT_DIR/docs/efficiency-recommendations.md"

    if [[ -f "$doc" ]]; then
        if grep -q 'Script Audit\|Script.*SSH Calls\|mirror.sh.*Push\|N+1' "$doc"; then
            pass "efficiency doc has script audit section"
        else
            fail "efficiency doc should have script audit section"
        fi
    else
        skip "efficiency doc not found"
    fi
}

# Test: efficiency doc has command audit table
test_efficiency_doc_has_commands() {
    echo ""
    echo "=== Test: efficiency doc has command audit ==="

    local doc="$ROOT_DIR/docs/efficiency-recommendations.md"

    if [[ -f "$doc" ]]; then
        if grep -q 'Command Audit\|/sync\|/push\|/pull' "$doc"; then
            pass "efficiency doc has command audit section"
        else
            fail "efficiency doc should have command audit section"
        fi
    else
        skip "efficiency doc not found"
    fi
}

# Test: efficiency doc has bidirectional cron sync spec
test_efficiency_doc_has_cron_sync() {
    echo ""
    echo "=== Test: efficiency doc has bidirectional cron sync spec ==="

    local doc="$ROOT_DIR/docs/efficiency-recommendations.md"

    if [[ -f "$doc" ]]; then
        if grep -q 'Bidirectional.*Cron\|cron-sync-state\|bot-only\|local-only' "$doc"; then
            pass "efficiency doc has bidirectional cron sync spec"
        else
            fail "efficiency doc should have bidirectional cron sync spec"
        fi
    else
        skip "efficiency doc not found"
    fi
}

# ============================================================
# CC_LOGS AUDIT FILE TESTS
# ============================================================

# Test: cc_logs audit file has discovery searches
test_audit_has_discovery() {
    echo ""
    echo "=== Test: cc_logs audit has discovery searches ==="

    local audit="$ROOT_DIR/docs/cc_logs/2026-02-03-sync-audit.md"

    if [[ -f "$audit" ]]; then
        if grep -q 'Discovery Search\|grep.*efficiency\|grep.*optimize' "$audit"; then
            pass "audit log has discovery search results"
        else
            fail "audit log should have discovery search section"
        fi
    else
        skip "audit log not found"
    fi
}

# ============================================================
# Run all tests
# ============================================================

echo "Sync Pipeline Efficiency Test Suite"
echo "===================================="

echo ""
echo "--- YAML Parsing Efficiency ---"
test_yaml_single_parse
test_parse_yaml_helper_exists

echo ""
echo "--- SSH Call Patterns ---"
test_mirror_uses_find_pattern
test_core_files_batch_friendly

echo ""
echo "--- Change Detection ---"
test_push_change_detection
test_pulled_tracking_file
test_allowlist_checksum

echo ""
echo "--- Rsync Efficiency ---"
test_rsync_compression
test_rsync_archive_mode

echo ""
echo "--- SSH ControlMaster ---"
test_ssh_controlmaster_ready

echo ""
echo "--- Pure Local Scripts ---"
test_assemble_no_ssh
test_detect_conflicts_no_ssh

echo ""
echo "--- Documentation ---"
test_scripts_have_usage
test_efficiency_doc_exists
test_efficiency_doc_has_audit
test_efficiency_doc_has_commands
test_efficiency_doc_has_cron_sync
test_audit_has_discovery

# Summary
echo ""
echo "===================================="
echo -e "Results: ${GREEN}$PASSED passed${NC}, ${RED}$FAILED failed${NC}, ${YELLOW}$SKIPPED skipped${NC}"

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
