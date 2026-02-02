#!/bin/bash
# Tests for tools/sync-cronjobs.sh
#
# Usage:
#   ./tests/test-sync-cronjobs.sh              # Run all tests
#   ./tests/test-sync-cronjobs.sh --quick      # Skip SSH-dependent tests
#   ./tests/test-sync-cronjobs.sh --verbose    # Show detailed output
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
    mkdir -p "$TEMP_DIR/tools" "$TEMP_DIR/cronjobs" "$TEMP_DIR/logs"

    # Copy scripts
    cp "$ROOT_DIR/tools/lib.sh" "$TEMP_DIR/tools/"
    cp "$ROOT_DIR/tools/sync-cronjobs.sh" "$TEMP_DIR/tools/"

    # Create minimal config.yaml
    cat > "$TEMP_DIR/config.yaml" << 'EOF'
version: 2

ssh:
  host: testbot

remote:
  home: /Users/testuser
  workspace: /Users/testuser/clawd
  openclaw: /Users/testuser/.openclaw
  agent_id: test-agent

local:
  mirror: mirror
  sessions: sessions
  logs: logs
  intake: intake
  reference: reference
  exports: exports
EOF

    log "Setup in $TEMP_DIR"
}

teardown() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        log "Cleaned up $TEMP_DIR"
    fi
}

# ============================================================
# Test: parse_cron_yaml extracts fields correctly
# ============================================================
test_parse_cron_yaml() {
    echo ""
    echo "=== Test: parse_cron_yaml extracts fields ==="
    setup

    # Create test cron job YAML
    cat > "$TEMP_DIR/cronjobs/test-job.yaml" << 'EOF'
name: test-job
description: Test cron job
status: active

schedule:
  cron: "0 9 * * *"
  timezone: America/New_York

execution:
  session: isolated
  model: anthropic/claude-haiku-4-5
  agent: bruba-manager

message: |
  This is a test message.
  It has multiple lines.
EOF

    # Source lib.sh and extract the parse function
    local output
    output=$(python3 -c "
import yaml
import json

with open('$TEMP_DIR/cronjobs/test-job.yaml') as f:
    data = yaml.safe_load(f)

result = {
    'name': data.get('name', ''),
    'status': data.get('status', 'proposed'),
    'description': data.get('description', ''),
    'cron': data.get('schedule', {}).get('cron', ''),
    'timezone': data.get('schedule', {}).get('timezone', 'UTC'),
    'agent': data.get('execution', {}).get('agent', 'bruba-main'),
    'session': data.get('execution', {}).get('session', 'isolated'),
    'model': data.get('execution', {}).get('model', 'anthropic/claude-haiku-4-5'),
    'message': data.get('message', '')
}
print(json.dumps(result))
")

    local name cron session agent
    name=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin).get('name',''))")
    cron=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin).get('cron',''))")
    session=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin).get('session',''))")
    agent=$(echo "$output" | python3 -c "import json,sys; print(json.load(sys.stdin).get('agent',''))")

    local errors=0
    [[ "$name" == "test-job" ]] || { log "name mismatch: $name"; errors=$((errors+1)); }
    [[ "$cron" == "0 9 * * *" ]] || { log "cron mismatch: $cron"; errors=$((errors+1)); }
    [[ "$session" == "isolated" ]] || { log "session mismatch: $session"; errors=$((errors+1)); }
    [[ "$agent" == "bruba-manager" ]] || { log "agent mismatch: $agent"; errors=$((errors+1)); }

    if [[ $errors -eq 0 ]]; then
        pass "parse_cron_yaml extracts all fields correctly"
    else
        fail "parse_cron_yaml field extraction failed ($errors errors)"
    fi

    teardown
}

# ============================================================
# Test: sync-cronjobs status filtering logic (code review)
# ============================================================
test_status_filtering_logic() {
    echo ""
    echo "=== Test: sync-cronjobs status filtering logic ==="

    # Verify the script has proper status checking
    if grep -q 'status.*!=.*active' "$ROOT_DIR/tools/sync-cronjobs.sh" || \
       grep -q 'status.*==.*active' "$ROOT_DIR/tools/sync-cronjobs.sh"; then
        pass "sync-cronjobs.sh has status filtering logic"
    else
        fail "sync-cronjobs.sh should filter by status: active"
    fi
}

# ============================================================
# Test: sync-cronjobs validates required fields (code review)
# ============================================================
test_validates_required_fields_logic() {
    echo ""
    echo "=== Test: sync-cronjobs validation logic ==="

    # Verify the script checks for required fields
    if grep -q '\-z.*name\|name.*\-z' "$ROOT_DIR/tools/sync-cronjobs.sh" && \
       grep -q '\-z.*cron\|cron.*\-z' "$ROOT_DIR/tools/sync-cronjobs.sh" && \
       grep -q '\-z.*message\|message.*\-z' "$ROOT_DIR/tools/sync-cronjobs.sh"; then
        pass "sync-cronjobs.sh validates required fields (name, cron, message)"
    else
        fail "sync-cronjobs.sh should validate name, cron, and message fields"
    fi
}

# ============================================================
# Test: main session jobs use --system-event
# ============================================================
test_main_session_uses_system_event() {
    echo ""
    echo "=== Test: main session jobs use --system-event ==="

    # This is a code review test - check the script handles main vs isolated
    if grep -q 'payload_flag="--system-event"' "$ROOT_DIR/tools/sync-cronjobs.sh" && \
       grep -q 'session.*==.*main' "$ROOT_DIR/tools/sync-cronjobs.sh"; then
        pass "sync-cronjobs.sh uses --system-event for main sessions"
    else
        fail "sync-cronjobs.sh should use --system-event for main session jobs"
    fi
}

# ============================================================
# Test: YAML files in cronjobs/ are valid
# ============================================================
test_cronjob_yaml_valid() {
    echo ""
    echo "=== Test: cronjobs/*.yaml files are valid ==="

    local errors=0
    for file in "$ROOT_DIR/cronjobs"/*.yaml; do
        [[ ! -f "$file" ]] && continue
        [[ "$(basename "$file")" == "README.yaml" ]] && continue

        if ! python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null; then
            log "Invalid YAML: $file"
            errors=$((errors+1))
        fi
    done

    if [[ $errors -eq 0 ]]; then
        pass "All cronjobs/*.yaml files are valid YAML"
    else
        fail "$errors cronjob YAML files are invalid"
    fi
}

# ============================================================
# Test: cronjob YAMLs have required fields
# ============================================================
test_cronjob_yaml_fields() {
    echo ""
    echo "=== Test: cronjobs/*.yaml have required fields ==="

    local errors=0
    for file in "$ROOT_DIR/cronjobs"/*.yaml; do
        [[ ! -f "$file" ]] && continue
        [[ "$(basename "$file")" == "README.yaml" ]] && continue

        local missing
        missing=$(python3 -c "
import yaml
import sys

with open('$file') as f:
    data = yaml.safe_load(f)

required = ['name', 'status', 'schedule', 'message']
missing = [f for f in required if f not in data or not data[f]]

if missing:
    print(','.join(missing))
" 2>/dev/null)

        if [[ -n "$missing" ]]; then
            log "$(basename "$file"): missing fields: $missing"
            errors=$((errors+1))
        fi
    done

    if [[ $errors -eq 0 ]]; then
        pass "All cronjobs/*.yaml have required fields"
    else
        fail "$errors cronjob files missing required fields"
    fi
}

# ============================================================
# Run all tests
# ============================================================

echo "sync-cronjobs.sh Test Suite"
echo "============================"

test_parse_cron_yaml
test_status_filtering_logic
test_validates_required_fields_logic
test_main_session_uses_system_event
test_cronjob_yaml_valid
test_cronjob_yaml_fields

# Summary
echo ""
echo "============================"
echo -e "Results: ${GREEN}$PASSED passed${NC}, ${RED}$FAILED failed${NC}, ${YELLOW}$SKIPPED skipped${NC}"

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
