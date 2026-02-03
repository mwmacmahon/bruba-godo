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
# Test: get_openclaw_config returns settings
# ============================================================
test_get_openclaw_config() {
    echo ""
    echo "=== Test: get_openclaw_config returns settings ==="
    setup

    # Create config with openclaw section
    cat > "$TEMP_DIR/config.yaml" << 'EOF'
version: 3

ssh:
  host: testbot

remote:
  home: /Users/testuser
  workspace: /Users/testuser/clawd
  openclaw: /Users/testuser/.openclaw
  agent_id: test-agent

openclaw:
  model:
    primary: opus
    fallbacks:
      - anthropic/claude-sonnet-4-5
  compaction:
    mode: safeguard
    reserve_tokens_floor: 20000
  max_concurrent: 4
EOF

    # Copy parse-yaml.py helper
    mkdir -p "$TEMP_DIR/tools/helpers"
    cp "$ROOT_DIR/tools/helpers/parse-yaml.py" "$TEMP_DIR/tools/helpers/"

    local result exit_code=0
    result=$(
        cd "$TEMP_DIR"
        ROOT_DIR="$TEMP_DIR"
        source "$TEMP_DIR/tools/lib.sh"
        get_openclaw_config compaction
    ) || exit_code=$?

    # Check result contains mode and reserveTokensFloor (camelCase)
    if [[ $exit_code -eq 0 ]] && echo "$result" | grep -q '"mode"' && echo "$result" | grep -q '"reserveTokensFloor"'; then
        pass "get_openclaw_config returns settings with camelCase keys"
    else
        fail "get_openclaw_config failed or returned wrong keys"
        log "Result: $result"
    fi

    teardown
}

# ============================================================
# Test: get_agent_model returns agent model
# ============================================================
test_get_agent_model() {
    echo ""
    echo "=== Test: get_agent_model returns agent model ==="
    setup

    # Create config with agent model
    cat > "$TEMP_DIR/config.yaml" << 'EOF'
version: 3

ssh:
  host: testbot

remote:
  home: /Users/testuser
  workspace: /Users/testuser/clawd
  openclaw: /Users/testuser/.openclaw
  agent_id: test-agent

agents:
  test-main:
    workspace: /Users/testuser/agents/test-main
    model: sonnet
  test-manager:
    workspace: /Users/testuser/agents/test-manager
    model:
      primary: anthropic/claude-sonnet-4-5
      fallbacks:
        - anthropic/claude-haiku-4-5
EOF

    # Copy parse-yaml.py helper
    mkdir -p "$TEMP_DIR/tools/helpers"
    cp "$ROOT_DIR/tools/helpers/parse-yaml.py" "$TEMP_DIR/tools/helpers/"

    local result exit_code=0
    result=$(
        cd "$TEMP_DIR"
        ROOT_DIR="$TEMP_DIR"
        source "$TEMP_DIR/tools/lib.sh"
        get_agent_model test-main
    ) || exit_code=$?

    if [[ $exit_code -eq 0 ]] && [[ "$result" == "sonnet" ]]; then
        pass "get_agent_model returns string model"
    else
        fail "get_agent_model failed for string model"
        log "Result: $result"
    fi

    teardown
}

# ============================================================
# Test: get_agent_heartbeat returns heartbeat config
# ============================================================
test_get_agent_heartbeat() {
    echo ""
    echo "=== Test: get_agent_heartbeat returns config ==="
    setup

    # Create config with agent heartbeat
    cat > "$TEMP_DIR/config.yaml" << 'EOF'
version: 3

ssh:
  host: testbot

remote:
  home: /Users/testuser
  workspace: /Users/testuser/clawd
  openclaw: /Users/testuser/.openclaw
  agent_id: test-agent

agents:
  test-manager:
    workspace: /Users/testuser/agents/test-manager
    heartbeat:
      every: 15m
      model: anthropic/claude-haiku-4-5
      target: signal
      active_hours:
        start: "07:00"
        end: "22:00"
EOF

    # Copy parse-yaml.py helper
    mkdir -p "$TEMP_DIR/tools/helpers"
    cp "$ROOT_DIR/tools/helpers/parse-yaml.py" "$TEMP_DIR/tools/helpers/"

    local result exit_code=0
    result=$(
        cd "$TEMP_DIR"
        ROOT_DIR="$TEMP_DIR"
        source "$TEMP_DIR/tools/lib.sh"
        get_agent_heartbeat test-manager
    ) || exit_code=$?

    # Check result contains activeHours (camelCase)
    if [[ $exit_code -eq 0 ]] && echo "$result" | grep -q '"activeHours"'; then
        pass "get_agent_heartbeat returns config with camelCase keys"
    else
        fail "get_agent_heartbeat failed or returned wrong keys"
        log "Result: $result"
    fi

    teardown
}

# ============================================================
# Test: has_openclaw_config detects section
# ============================================================
test_has_openclaw_config() {
    echo ""
    echo "=== Test: has_openclaw_config detects section ==="
    setup

    # Create config WITHOUT openclaw section
    cat > "$TEMP_DIR/config.yaml" << 'EOF'
version: 2

ssh:
  host: testbot

remote:
  home: /Users/testuser
  workspace: /Users/testuser/clawd
  openclaw: /Users/testuser/.openclaw
  agent_id: test-agent
EOF

    # Copy parse-yaml.py helper
    mkdir -p "$TEMP_DIR/tools/helpers"
    cp "$ROOT_DIR/tools/helpers/parse-yaml.py" "$TEMP_DIR/tools/helpers/"

    local exit_code=0
    (
        cd "$TEMP_DIR"
        ROOT_DIR="$TEMP_DIR"
        source "$TEMP_DIR/tools/lib.sh"
        has_openclaw_config
    ) || exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        pass "has_openclaw_config returns false when missing"
    else
        fail "has_openclaw_config should return false when section missing"
    fi

    # Now add openclaw section
    cat >> "$TEMP_DIR/config.yaml" << 'EOF'

openclaw:
  max_concurrent: 4
EOF

    exit_code=0
    (
        cd "$TEMP_DIR"
        ROOT_DIR="$TEMP_DIR"
        source "$TEMP_DIR/tools/lib.sh"
        has_openclaw_config
    ) || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        pass "has_openclaw_config returns true when present"
    else
        fail "has_openclaw_config should return true when section present"
    fi

    teardown
}

# ============================================================
# Test: get_voice_config returns voice settings
# ============================================================
test_get_voice_config() {
    echo ""
    echo "=== Test: get_voice_config returns voice settings ==="
    setup

    # Create config with voice section
    cat > "$TEMP_DIR/config.yaml" << 'EOF'
version: 3

ssh:
  host: testbot

remote:
  home: /Users/testuser
  workspace: /Users/testuser/clawd
  openclaw: /Users/testuser/.openclaw
  agent_id: test-agent

openclaw:
  voice:
    stt:
      enabled: true
      max_bytes: 20971520
      timeout_seconds: 120
      language: en
      models:
        - provider: groq
          model: whisper-large-v3-turbo
    tts:
      auto: inbound
      provider: elevenlabs
      max_text_length: 4000
      timeout_ms: 30000
      elevenlabs:
        voice_id: "test-voice-id"
        model_id: "eleven_multilingual_v2"
        voice_settings:
          stability: 0.5
          similarity_boost: 0.75
          speed: 1.0
EOF

    # Copy parse-yaml.py helper
    mkdir -p "$TEMP_DIR/tools/helpers"
    cp "$ROOT_DIR/tools/helpers/parse-yaml.py" "$TEMP_DIR/tools/helpers/"

    local result exit_code=0
    result=$(
        cd "$TEMP_DIR"
        ROOT_DIR="$TEMP_DIR"
        source "$TEMP_DIR/tools/lib.sh"
        get_voice_config stt
    ) || exit_code=$?

    # Check result contains camelCase keys
    if [[ $exit_code -eq 0 ]] && echo "$result" | grep -q '"maxBytes"' && echo "$result" | grep -q '"timeoutSeconds"'; then
        pass "get_voice_config stt returns settings with camelCase keys"
    else
        fail "get_voice_config stt failed or returned wrong keys"
        log "Result: $result"
    fi

    # Test TTS section
    result=$(
        cd "$TEMP_DIR"
        ROOT_DIR="$TEMP_DIR"
        source "$TEMP_DIR/tools/lib.sh"
        get_voice_config tts
    ) || exit_code=$?

    # Check TTS result contains camelCase keys
    if [[ $exit_code -eq 0 ]] && echo "$result" | grep -q '"maxTextLength"' && echo "$result" | grep -q '"timeoutMs"' && echo "$result" | grep -q '"voiceId"'; then
        pass "get_voice_config tts returns settings with camelCase keys"
    else
        fail "get_voice_config tts failed or returned wrong keys"
        log "Result: $result"
    fi

    teardown
}

# ============================================================
# Test: get_voice_config returns empty when missing
# ============================================================
test_get_voice_config_missing() {
    echo ""
    echo "=== Test: get_voice_config returns empty when missing ==="
    setup

    # Create config WITHOUT voice section
    cat > "$TEMP_DIR/config.yaml" << 'EOF'
version: 3

ssh:
  host: testbot

remote:
  home: /Users/testuser
  workspace: /Users/testuser/clawd
  openclaw: /Users/testuser/.openclaw
  agent_id: test-agent

openclaw:
  max_concurrent: 4
EOF

    # Copy parse-yaml.py helper
    mkdir -p "$TEMP_DIR/tools/helpers"
    cp "$ROOT_DIR/tools/helpers/parse-yaml.py" "$TEMP_DIR/tools/helpers/"

    local result exit_code=0
    result=$(
        cd "$TEMP_DIR"
        ROOT_DIR="$TEMP_DIR"
        source "$TEMP_DIR/tools/lib.sh"
        get_voice_config stt
    ) || exit_code=$?

    # Should return empty (not error)
    if [[ -z "$result" || "$result" == "" ]]; then
        pass "get_voice_config returns empty when voice section missing"
    else
        fail "get_voice_config should return empty when section missing"
        log "Result: $result"
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
test_get_openclaw_config
test_get_agent_model
test_get_agent_heartbeat
test_has_openclaw_config
test_get_voice_config
test_get_voice_config_missing

# Summary
echo ""
echo "================="
echo -e "Results: ${GREEN}$PASSED passed${NC}, ${RED}$FAILED failed${NC}, ${YELLOW}$SKIPPED skipped${NC}"

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
