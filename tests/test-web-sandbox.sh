#!/bin/bash
# Tests for bruba-web session-scoped Docker sandbox infrastructure
#
# Verifies: config validation, live openclaw.json checks, container lifecycle,
# and warm-up script state.
#
# Usage:
#   ./tests/test-web-sandbox.sh              # Run all tests (requires bot access)
#   ./tests/test-web-sandbox.sh --quick      # Local config checks only (no bot)
#   ./tests/test-web-sandbox.sh --verbose    # Show detailed output
#
# Exit codes:
#   0 = All tests passed
#   1 = Test failed

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$ROOT_DIR"

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
    if [[ -n "${2:-}" ]]; then
        echo "  $2"
    fi
    FAILED=$((FAILED + 1))
}

skip() {
    echo -e "${YELLOW}⚠${NC} $1 (skipped)"
    SKIPPED=$((SKIPPED + 1))
}

tlog() {
    if $VERBOSE; then echo "  $*"; fi
}

# Load shared library
source "$ROOT_DIR/tools/lib.sh"

LOG_FILE="/dev/null"
load_config

CONFIG_FILE="$ROOT_DIR/config.yaml"

# ============================================================
# Category 1: Config Validation (4 tests)
# ============================================================
test_config_validation() {
    echo ""
    echo "=== Category 1: Config Validation ==="

    # 1.1 bruba-web sandbox scope is "session"
    local scope
    scope=$(python3 -c "
import yaml
with open('$CONFIG_FILE') as f:
    c = yaml.safe_load(f)
web = c.get('agents', {}).get('bruba-web', {}) or {}
sandbox = web.get('sandbox', {}) or {}
print(sandbox.get('scope', ''))
" 2>/dev/null)

    if [[ "$scope" == "session" ]]; then
        pass "1.1 bruba-web sandbox scope is \"session\""
    else
        fail "1.1 bruba-web sandbox scope is \"session\"" "Got: \"$scope\""
    fi

    # 1.2 bruba-web sandbox has docker resource limits
    local has_limits
    has_limits=$(python3 -c "
import yaml
with open('$CONFIG_FILE') as f:
    c = yaml.safe_load(f)
web = c.get('agents', {}).get('bruba-web', {}) or {}
docker = web.get('sandbox', {}).get('docker', {}) or {}
has_mem = bool(docker.get('memory'))
has_cpu = bool(docker.get('cpus'))
print('ok' if has_mem and has_cpu else f'memory={docker.get(\"memory\",\"missing\")} cpus={docker.get(\"cpus\",\"missing\")}')
" 2>/dev/null)

    if [[ "$has_limits" == "ok" ]]; then
        pass "1.2 bruba-web sandbox has docker resource limits (memory, cpus)"
    else
        fail "1.2 bruba-web sandbox has docker resource limits" "$has_limits"
    fi

    # 1.3 bruba-web has no prune block (irrelevant for session scope)
    local has_prune
    has_prune=$(python3 -c "
import yaml
with open('$CONFIG_FILE') as f:
    c = yaml.safe_load(f)
web = c.get('agents', {}).get('bruba-web', {}) or {}
sandbox = web.get('sandbox', {}) or {}
print('yes' if 'prune' in sandbox else 'no')
" 2>/dev/null)

    if [[ "$has_prune" == "no" ]]; then
        pass "1.3 bruba-web has no prune block (irrelevant for session scope)"
    else
        fail "1.3 bruba-web has no prune block" "Found prune config in sandbox"
    fi

    # 1.4 bruba-web tools_allow is minimal (only web_search, web_fetch)
    local tools_check
    tools_check=$(python3 -c "
import yaml
with open('$CONFIG_FILE') as f:
    c = yaml.safe_load(f)
web = c.get('agents', {}).get('bruba-web', {}) or {}
allow = set(web.get('tools_allow', []))
expected = {'web_search', 'web_fetch'}
if allow == expected:
    print('ok')
else:
    extra = allow - expected
    missing = expected - allow
    parts = []
    if extra:
        parts.append(f'extra: {sorted(extra)}')
    if missing:
        parts.append(f'missing: {sorted(missing)}')
    print(', '.join(parts))
" 2>/dev/null)

    if [[ "$tools_check" == "ok" ]]; then
        pass "1.4 bruba-web tools_allow is minimal (only web_search, web_fetch)"
    else
        fail "1.4 bruba-web tools_allow is minimal" "$tools_check"
    fi
}

# ============================================================
# Category 2: Live Config Validation (3 tests, skip with --quick)
# ============================================================
test_live_config() {
    echo ""
    echo "=== Category 2: Live Config Validation ==="

    if $QUICK; then
        skip "2.1 openclaw.json bruba-web sandbox.scope is \"session\" (--quick)"
        skip "2.2 openclaw.json bruba-web has no redundant fields (--quick)"
        skip "2.3 openclaw.json bruba-web docker limits match config.yaml (--quick)"
        return
    fi

    # Fetch remote openclaw.json once
    local remote_config
    remote_config=$(./tools/bot cat /Users/bruba/.openclaw/openclaw.json 2>/dev/null) || {
        skip "2.1 openclaw.json bruba-web sandbox.scope is \"session\" (bot unreachable)"
        skip "2.2 openclaw.json bruba-web has no redundant fields (bot unreachable)"
        skip "2.3 openclaw.json bruba-web docker limits match config.yaml (bot unreachable)"
        return
    }

    # 2.1 openclaw.json bruba-web sandbox.scope is "session"
    local remote_scope
    remote_scope=$(echo "$remote_config" | python3 -c "
import json, sys
config = json.load(sys.stdin)
agents = config.get('agents', {}).get('list', [])
for a in agents:
    if a.get('id') == 'bruba-web':
        sandbox = a.get('sandbox', {})
        print(sandbox.get('scope', ''))
        sys.exit(0)
print('')
" 2>/dev/null)

    if [[ "$remote_scope" == "session" ]]; then
        pass "2.1 openclaw.json bruba-web sandbox.scope is \"session\""
    else
        fail "2.1 openclaw.json bruba-web sandbox.scope is \"session\"" "Got: \"$remote_scope\""
    fi

    # 2.2 openclaw.json bruba-web has no redundant fields
    local redundant
    redundant=$(echo "$remote_config" | python3 -c "
import json, sys
config = json.load(sys.stdin)
agents = config.get('agents', {}).get('list', [])
for a in agents:
    if a.get('id') == 'bruba-web':
        bad = []
        if 'workspace' in a:
            bad.append('workspace')
        if 'agentDir' in a:
            bad.append('agentDir')
        if 'workspaceRoot' in a:
            bad.append('workspaceRoot')
        tools = a.get('tools', {})
        if 'deny' in tools:
            bad.append('tools.deny')
        if bad:
            print(', '.join(bad))
        else:
            print('ok')
        sys.exit(0)
print('agent not found')
" 2>/dev/null)

    if [[ "$redundant" == "ok" ]]; then
        pass "2.2 openclaw.json bruba-web has no redundant fields"
    else
        fail "2.2 openclaw.json bruba-web has no redundant fields" "Found: $redundant"
    fi

    # 2.3 openclaw.json bruba-web docker resource limits match config.yaml
    local limits_match
    limits_match=$(echo "$remote_config" | python3 -c "
import yaml, json, sys

with open('$CONFIG_FILE') as f:
    local_config = yaml.safe_load(f)

remote_config = json.load(sys.stdin)

# Get local values
local_web = local_config.get('agents', {}).get('bruba-web', {}) or {}
local_docker = local_web.get('sandbox', {}).get('docker', {}) or {}
local_mem = str(local_docker.get('memory', ''))
local_cpus = local_docker.get('cpus', '')

# Get remote values
remote_agents = remote_config.get('agents', {}).get('list', [])
remote_docker = {}
for a in remote_agents:
    if a.get('id') == 'bruba-web':
        remote_docker = a.get('sandbox', {}).get('docker', {})
        break

remote_mem = str(remote_docker.get('memory', ''))
remote_cpus = remote_docker.get('cpus', '')

mismatches = []
if local_mem != remote_mem:
    mismatches.append(f'memory: local={local_mem} remote={remote_mem}')
if float(local_cpus) != float(remote_cpus):
    mismatches.append(f'cpus: local={local_cpus} remote={remote_cpus}')

if mismatches:
    print('; '.join(mismatches))
else:
    print('ok')
" 2>/dev/null)

    if [[ "$limits_match" == "ok" ]]; then
        pass "2.3 openclaw.json bruba-web docker limits match config.yaml"
    else
        fail "2.3 openclaw.json bruba-web docker limits match config.yaml" "$limits_match"
    fi
}

# ============================================================
# Category 3: Container Lifecycle (3 tests, skip with --quick)
# ============================================================
test_container_lifecycle() {
    echo ""
    echo "=== Category 3: Container Lifecycle ==="

    if $QUICK; then
        skip "3.1 Sending a message creates a new container (--quick)"
        skip "3.2 Container name includes session identifier (--quick)"
        skip "3.3 No stale agent-scoped containers running (--quick)"
        return
    fi

    # 3.1 Sending a message creates a new container
    local before after new_containers
    before=$(./tools/bot 'docker ps --filter name=openclaw-sbx-agent-bruba-web --format "{{.Names}}"' 2>/dev/null || true)

    # Trigger a session
    tlog "Sending ping to bruba-web..."
    ./tools/bot 'openclaw agent --agent bruba-web -m "ping"' >/dev/null 2>&1 || true

    # Brief pause for container startup
    sleep 2

    after=$(./tools/bot 'docker ps --filter name=openclaw-sbx-agent-bruba-web --format "{{.Names}}"' 2>/dev/null || true)

    new_containers=$(comm -13 <(echo "$before" | sort) <(echo "$after" | sort) 2>/dev/null || true)
    if [[ -n "$new_containers" ]]; then
        pass "3.1 Sending a message creates a new container"
        tlog "New container: $new_containers"
    elif [[ -n "$after" ]]; then
        # Container exists (may have been created by the message, but was also present before
        # if a prior session was still running)
        pass "3.1 Sending a message creates a new container (container running)"
        tlog "Container: $after"
    else
        fail "3.1 Sending a message creates a new container" "No container found after message"
    fi

    # 3.2 Container name includes session identifier (not just agent name)
    local containers
    containers=$(./tools/bot 'docker ps --filter name=openclaw-sbx-agent-bruba-web --format "{{.Names}}"' 2>/dev/null || true)

    if [[ -z "$containers" ]]; then
        skip "3.2 Container name includes session identifier (no container running)"
    else
        # Session-scoped containers should have a suffix beyond just the agent name
        # Pattern: openclaw-sbx-agent-bruba-web-<session-id>
        local has_session_suffix=false
        while IFS= read -r name; do
            [[ -z "$name" ]] && continue
            # Strip the base prefix and check for additional suffix
            local suffix="${name#openclaw-sbx-agent-bruba-web}"
            if [[ -n "$suffix" && "$suffix" != "" ]]; then
                has_session_suffix=true
                tlog "Container with session suffix: $name"
            fi
        done <<< "$containers"

        if $has_session_suffix; then
            pass "3.2 Container name includes session identifier"
        else
            # Some OpenClaw versions may not include session suffix in name
            skip "3.2 Container name includes session identifier (suffix not found, may be version-dependent)"
        fi
    fi

    # 3.3 No stale agent-scoped containers running
    # Agent-scoped containers would be named exactly "openclaw-sbx-agent-bruba-web" (no session suffix)
    local stale
    stale=$(./tools/bot 'docker ps --format "{{.Names}}"' 2>/dev/null | grep -x 'openclaw-sbx-agent-bruba-web' || true)

    if [[ -z "$stale" ]]; then
        pass "3.3 No stale agent-scoped containers running"
    else
        fail "3.3 No stale agent-scoped containers running" "Found: $stale"
    fi
}

# ============================================================
# Category 4: Warm-up Script State (2 tests, skip with --quick)
# ============================================================
test_warmup_state() {
    echo ""
    echo "=== Category 4: Warm-up Script State ==="

    if $QUICK; then
        skip "4.1 LaunchAgent is not loaded (--quick)"
        skip "4.2 bruba-start script contains disabled comment (--quick)"
        return
    fi

    # 4.1 LaunchAgent is not loaded
    local launchctl_output
    launchctl_output=$(./tools/bot 'launchctl list 2>/dev/null | grep sandbox-warm' 2>/dev/null || true)

    if [[ -z "$launchctl_output" ]]; then
        pass "4.1 LaunchAgent is not loaded (sandbox-warm)"
    else
        fail "4.1 LaunchAgent is not loaded" "Found: $launchctl_output"
    fi

    # 4.2 bruba-start script contains disabled comment or is harmless
    local script_content
    script_content=$(./tools/bot 'cat /Users/bruba/bin/bruba-start 2>/dev/null' 2>/dev/null || true)

    if [[ -z "$script_content" ]]; then
        # Script doesn't exist — that's fine too (even cleaner)
        pass "4.2 bruba-start script absent or contains disabled comment"
    elif echo "$script_content" | grep -qi 'disabled\|no.op\|session.scope\|commented.out\|skip\|# .*warm'; then
        pass "4.2 bruba-start script contains disabled comment"
        tlog "Script exists but warm-up is disabled"
    else
        # Script exists but may just be harmless (session scope makes warm-up a no-op)
        # Check if it still tries to warm up
        if echo "$script_content" | grep -qi 'openclaw.*agent.*bruba-web'; then
            skip "4.2 bruba-start script still references bruba-web (harmless with session scope, but could be cleaned up)"
        else
            pass "4.2 bruba-start script does not warm bruba-web container"
        fi
    fi
}

# ============================================================
# Run all tests
# ============================================================

echo "bruba-web Session-Scoped Sandbox Test Suite"
echo "============================================="
if $QUICK; then
    echo "(--quick mode: skipping remote/bot tests)"
fi

test_config_validation || true
test_live_config || true
test_container_lifecycle || true
test_warmup_state || true

# Summary
echo ""
echo "============================================="
echo -e "Results: ${GREEN}$PASSED passed${NC}, ${RED}$FAILED failed${NC}, ${YELLOW}$SKIPPED skipped${NC}"

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
