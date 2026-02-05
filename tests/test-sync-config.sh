#!/bin/bash
# Tests for tools/sync-openclaw-config.sh
#
# Usage:
#   ./tests/test-sync-config.sh              # Run all tests
#   ./tests/test-sync-config.sh --quick      # Skip SSH tests
#   ./tests/test-sync-config.sh --verbose    # Show detailed output
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
# Test: parse-yaml.py --to-json converts keys
# ============================================================
test_parse_yaml_to_json() {
    echo ""
    echo "=== Test: parse-yaml.py --to-json converts keys ==="

    local temp_file
    temp_file=$(mktemp)

    cat > "$temp_file" << 'EOF'
openclaw:
  compaction:
    mode: safeguard
    reserve_tokens_floor: 20000
    memory_flush:
      enabled: true
      soft_threshold_tokens: 40000
  context_pruning:
    mode: cache-ttl
    ttl: 1h
  max_concurrent: 4
EOF

    local result
    result=$("$ROOT_DIR/tools/helpers/parse-yaml.py" "$temp_file" --to-json openclaw.compaction)

    rm -f "$temp_file"

    # Check camelCase conversion
    if echo "$result" | grep -q '"reserveTokensFloor"' && \
       echo "$result" | grep -q '"memoryFlush"' && \
       echo "$result" | grep -q '"softThresholdTokens"'; then
        pass "parse-yaml.py --to-json converts snake_case to camelCase"
    else
        fail "parse-yaml.py --to-json should convert keys to camelCase"
        log "Result: $result"
    fi
}

# ============================================================
# Test: parse-yaml.py handles nested structures
# ============================================================
test_parse_yaml_nested() {
    echo ""
    echo "=== Test: parse-yaml.py handles nested structures ==="

    local temp_file
    temp_file=$(mktemp)

    cat > "$temp_file" << 'EOF'
agents:
  test-manager:
    heartbeat:
      every: 15m
      active_hours:
        start: "07:00"
        end: "22:00"
EOF

    local result
    result=$("$ROOT_DIR/tools/helpers/parse-yaml.py" "$temp_file" --to-json agents.test-manager.heartbeat)

    rm -f "$temp_file"

    # Check nested activeHours
    if echo "$result" | grep -q '"activeHours"' && \
       echo "$result" | grep -q '"start"' && \
       echo "$result" | grep -q '"end"'; then
        pass "parse-yaml.py handles nested structures with camelCase"
    else
        fail "parse-yaml.py should handle nested structures"
        log "Result: $result"
    fi
}

# ============================================================
# Test: sync-openclaw-config.sh shows help
# ============================================================
test_sync_config_help() {
    echo ""
    echo "=== Test: sync-openclaw-config.sh shows help ==="

    local output exit_code=0
    output=$("$ROOT_DIR/tools/sync-openclaw-config.sh" --help 2>&1) || exit_code=$?

    if [[ $exit_code -eq 0 ]] && \
       echo "$output" | grep -q "Sync config.yaml settings" && \
       echo "$output" | grep -q -- "--check" && \
       echo "$output" | grep -q -- "--dry-run"; then
        pass "sync-openclaw-config.sh shows help with options"
    else
        fail "sync-openclaw-config.sh --help failed"
        log "Exit: $exit_code"
        log "Output: $output"
    fi
}

# ============================================================
# Test: sync-openclaw-config.sh detects missing openclaw section
# ============================================================
test_sync_config_no_section() {
    echo ""
    echo "=== Test: sync-openclaw-config.sh handles missing section ==="

    local temp_dir
    temp_dir=$(mktemp -d)

    # Create minimal config without openclaw section
    cat > "$temp_dir/config.yaml" << 'EOF'
version: 2

transport: sudo

ssh:
  host: bruba

remote:
  home: /Users/bruba
  workspace: /Users/bruba/agents/bruba-main
  openclaw: /Users/bruba/.openclaw
  agent_id: bruba-main

local:
  mirror: mirror
  sessions: sessions
  logs: logs
  intake: intake
  reference: reference
  exports: exports
EOF

    mkdir -p "$temp_dir/logs"

    # Copy required files
    mkdir -p "$temp_dir/tools/helpers"
    cp "$ROOT_DIR/tools/lib.sh" "$temp_dir/tools/"
    cp "$ROOT_DIR/tools/helpers/parse-yaml.py" "$temp_dir/tools/helpers/"

    local output exit_code=0
    # Run in check mode (won't try to connect to bot)
    output=$(
        cd "$temp_dir"
        ROOT_DIR="$temp_dir" bash -c '
            source tools/lib.sh
            load_config
            if ! has_openclaw_config; then
                echo "No openclaw section"
                exit 0
            fi
        '
    ) || exit_code=$?

    rm -rf "$temp_dir"

    if echo "$output" | grep -q "No openclaw section"; then
        pass "sync-openclaw-config.sh detects missing openclaw section"
    else
        fail "sync-openclaw-config.sh should detect missing section"
        log "Output: $output"
    fi
}

# ============================================================
# Test: lib.sh get_openclaw_config function
# ============================================================
test_lib_get_openclaw_config() {
    echo ""
    echo "=== Test: lib.sh get_openclaw_config function ==="

    local temp_dir
    temp_dir=$(mktemp -d)

    # Create config with openclaw section
    cat > "$temp_dir/config.yaml" << 'EOF'
version: 3

ssh:
  host: bruba

remote:
  home: /Users/bruba
  workspace: /Users/bruba/agents/bruba-main
  openclaw: /Users/bruba/.openclaw
  agent_id: bruba-main

openclaw:
  model:
    primary: opus
    fallbacks:
      - anthropic/claude-sonnet-4-5
  compaction:
    mode: safeguard
    reserve_tokens_floor: 20000
  max_concurrent: 4

local:
  mirror: mirror
  sessions: sessions
  logs: logs
EOF

    # Copy required files
    mkdir -p "$temp_dir/tools/helpers"
    cp "$ROOT_DIR/tools/lib.sh" "$temp_dir/tools/"
    cp "$ROOT_DIR/tools/helpers/parse-yaml.py" "$temp_dir/tools/helpers/"

    local result exit_code=0
    result=$(
        cd "$temp_dir"
        ROOT_DIR="$temp_dir" bash -c '
            source tools/lib.sh
            get_openclaw_config model
        '
    ) || exit_code=$?

    rm -rf "$temp_dir"

    if [[ $exit_code -eq 0 ]] && echo "$result" | grep -q '"primary"' && echo "$result" | grep -q "opus"; then
        pass "get_openclaw_config returns model settings"
    else
        fail "get_openclaw_config should return model settings"
        log "Result: $result"
    fi
}

# ============================================================
# Test: lib.sh get_agent_heartbeat function
# ============================================================
test_lib_get_agent_heartbeat() {
    echo ""
    echo "=== Test: lib.sh get_agent_heartbeat function ==="

    local temp_dir
    temp_dir=$(mktemp -d)

    # Create config with agent heartbeat
    cat > "$temp_dir/config.yaml" << 'EOF'
version: 3

ssh:
  host: bruba

remote:
  home: /Users/bruba
  workspace: /Users/bruba/agents/bruba-main
  openclaw: /Users/bruba/.openclaw
  agent_id: bruba-main

agents:
  bruba-manager:
    workspace: /Users/bruba/agents/bruba-manager
    heartbeat:
      every: 15m
      model: anthropic/claude-haiku-4-5
      target: signal
      active_hours:
        start: "07:00"
        end: "22:00"

local:
  mirror: mirror
  sessions: sessions
  logs: logs
EOF

    # Copy required files
    mkdir -p "$temp_dir/tools/helpers"
    cp "$ROOT_DIR/tools/lib.sh" "$temp_dir/tools/"
    cp "$ROOT_DIR/tools/helpers/parse-yaml.py" "$temp_dir/tools/helpers/"

    local result exit_code=0
    result=$(
        cd "$temp_dir"
        ROOT_DIR="$temp_dir" bash -c '
            source tools/lib.sh
            get_agent_heartbeat bruba-manager
        '
    ) || exit_code=$?

    rm -rf "$temp_dir"

    # Check for camelCase key
    if [[ $exit_code -eq 0 ]] && echo "$result" | grep -q '"activeHours"'; then
        pass "get_agent_heartbeat returns config with camelCase keys"
    else
        fail "get_agent_heartbeat should return config with camelCase keys"
        log "Result: $result"
    fi
}

# ============================================================
# Test: parse-yaml.py converts voice keys to camelCase
# ============================================================
test_parse_yaml_voice_keys() {
    echo ""
    echo "=== Test: parse-yaml.py converts voice keys to camelCase ==="

    local temp_file
    temp_file=$(mktemp)

    cat > "$temp_file" << 'EOF'
openclaw:
  voice:
    stt:
      enabled: true
      max_bytes: 20971520
      timeout_seconds: 120
    tts:
      auto: inbound
      max_text_length: 4000
      timeout_ms: 30000
      elevenlabs:
        voice_id: "test-id"
        model_id: "eleven_multilingual_v2"
        voice_settings:
          similarity_boost: 0.75
EOF

    local result
    result=$("$ROOT_DIR/tools/helpers/parse-yaml.py" "$temp_file" --to-json openclaw.voice.stt)

    rm -f "$temp_file"

    # Check STT camelCase conversion
    if echo "$result" | grep -q '"maxBytes"' && \
       echo "$result" | grep -q '"timeoutSeconds"'; then
        pass "parse-yaml.py converts STT keys to camelCase"
    else
        fail "parse-yaml.py should convert STT keys to camelCase"
        log "Result: $result"
    fi

    # Test TTS keys
    temp_file=$(mktemp)
    cat > "$temp_file" << 'EOF'
openclaw:
  voice:
    tts:
      auto: inbound
      max_text_length: 4000
      timeout_ms: 30000
      elevenlabs:
        voice_id: "test-id"
        model_id: "eleven_multilingual_v2"
        voice_settings:
          similarity_boost: 0.75
EOF

    result=$("$ROOT_DIR/tools/helpers/parse-yaml.py" "$temp_file" --to-json openclaw.voice.tts)

    rm -f "$temp_file"

    # Check TTS camelCase conversion
    if echo "$result" | grep -q '"maxTextLength"' && \
       echo "$result" | grep -q '"timeoutMs"' && \
       echo "$result" | grep -q '"voiceId"' && \
       echo "$result" | grep -q '"modelId"' && \
       echo "$result" | grep -q '"voiceSettings"' && \
       echo "$result" | grep -q '"similarityBoost"'; then
        pass "parse-yaml.py converts TTS keys to camelCase"
    else
        fail "parse-yaml.py should convert TTS keys to camelCase"
        log "Result: $result"
    fi
}

# ============================================================
# Test: sync-openclaw-config.sh help includes voice section
# ============================================================
test_sync_config_help_voice() {
    echo ""
    echo "=== Test: sync-openclaw-config.sh help includes voice section ==="

    local output exit_code=0
    output=$("$ROOT_DIR/tools/sync-openclaw-config.sh" --help 2>&1) || exit_code=$?

    if [[ $exit_code -eq 0 ]] && \
       echo "$output" | grep -q "voice"; then
        pass "sync-openclaw-config.sh help includes voice section"
    else
        fail "sync-openclaw-config.sh help should include voice section"
        log "Output: $output"
    fi
}

# ============================================================
# Test: lib.sh get_bindings_config function
# ============================================================
test_lib_get_bindings_config() {
    echo ""
    echo "=== Test: lib.sh get_bindings_config function ==="

    local temp_dir
    temp_dir=$(mktemp -d)

    # Create config with bindings
    cat > "$temp_dir/config.yaml" << 'EOF'
version: 3

ssh:
  host: bruba

remote:
  home: /Users/bruba
  workspace: /Users/bruba/agents/bruba-main
  openclaw: /Users/bruba/.openclaw
  agent_id: bruba-main

bindings:
  - agent: bruba-main
    channel: bluebubbles
    peer:
      kind: dm
      id: "+1234567890"
  - agent: bruba-rex
    channel: bluebubbles
    peer:
      kind: dm
      id: "+0987654321"
  - agent: bruba-main
    channel: signal

local:
  mirror: mirror
  sessions: sessions
  logs: logs
EOF

    # Copy required files
    mkdir -p "$temp_dir/tools/helpers"
    cp "$ROOT_DIR/tools/lib.sh" "$temp_dir/tools/"
    cp "$ROOT_DIR/tools/helpers/parse-yaml.py" "$temp_dir/tools/helpers/"

    local result exit_code=0
    result=$(
        cd "$temp_dir"
        ROOT_DIR="$temp_dir" bash -c '
            source tools/lib.sh
            get_bindings_config
        '
    ) || exit_code=$?

    rm -rf "$temp_dir"

    # Check for proper structure: agentId (not agent), match.channel, match.peer
    # Use jq for reliable JSON parsing
    if [[ $exit_code -eq 0 ]] && \
       echo "$result" | jq -e '.[0].agentId == "bruba-main"' >/dev/null && \
       echo "$result" | jq -e '.[1].agentId == "bruba-rex"' >/dev/null && \
       echo "$result" | jq -e '.[0].match.channel == "bluebubbles"' >/dev/null && \
       echo "$result" | jq -e '.[2].match.channel == "signal"' >/dev/null && \
       echo "$result" | jq -e '.[0].match.peer.kind == "dm"' >/dev/null; then
        pass "get_bindings_config returns proper openclaw.json format"
    else
        fail "get_bindings_config should return proper openclaw.json format"
        log "Result: $result"
    fi
}

# ============================================================
# Run all tests
# ============================================================

echo "sync-openclaw-config.sh Test Suite"
echo "==================================="

test_parse_yaml_to_json
test_parse_yaml_nested
test_sync_config_help
test_sync_config_no_section
test_lib_get_openclaw_config
test_lib_get_agent_heartbeat
test_parse_yaml_voice_keys
test_sync_config_help_voice
test_lib_get_bindings_config

# SSH-dependent tests
if [[ "$QUICK" == "true" ]]; then
    skip "SSH-dependent tests (use without --quick to run)"
else
    echo ""
    echo "=== SSH-dependent tests ==="
    # These would require actual bot connection
    skip "sync-openclaw-config.sh --check (requires bot)"
fi

# Summary
echo ""
echo "==================================="
echo -e "Results: ${GREEN}$PASSED passed${NC}, ${RED}$FAILED failed${NC}, ${YELLOW}$SKIPPED skipped${NC}"

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
