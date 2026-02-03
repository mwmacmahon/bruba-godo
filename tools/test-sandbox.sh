#!/bin/bash
#
# test-sandbox.sh - Verify Docker sandbox security and functionality
#
# Usage: ./tools/test-sandbox.sh [--all|--security|--functional]
#
# Runs tests against the bot's containerized agents to verify:
# - Security: containers cannot access sensitive host files
# - Functional: exec/file operation path split works correctly
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
PASS=0
FAIL=0
SKIP=0

# Test mode
MODE="${1:---all}"

print_result() {
    local status="$1"
    local test_name="$2"
    local detail="${3:-}"

    case "$status" in
        pass)
            echo -e "${GREEN}✓${NC} $test_name"
            ((PASS++))
            ;;
        fail)
            echo -e "${RED}✗${NC} $test_name"
            [[ -n "$detail" ]] && echo "  $detail"
            ((FAIL++))
            ;;
        skip)
            echo -e "${YELLOW}○${NC} $test_name (skipped)"
            ((SKIP++))
            ;;
    esac
}

# Get container name for an agent
get_container_name() {
    local agent="$1"
    # OpenClaw container naming: openclaw-sandbox-{agent-id}
    echo "openclaw-sandbox-$agent"
}

# Check if container exists and is running
container_running() {
    local container="$1"
    ssh bruba "docker ps --filter name=$container --format '{{.Names}}'" 2>/dev/null | grep -q "$container"
}

# Run command in container, return exit code
container_exec() {
    local container="$1"
    shift
    ssh bruba "docker exec $container $*" 2>/dev/null
    return $?
}

# =============================================================================
# Security Tests
# =============================================================================

run_security_tests() {
    echo ""
    echo "=== Security Tests ==="
    echo ""

    local container
    container=$(get_container_name "bruba-main")

    # Check container is running
    if ! container_running "$container"; then
        echo "Container $container not running. Start gateway first."
        print_result skip "All security tests" "Container not running"
        return
    fi

    # Test 1: Cannot access exec-approvals.json
    echo "Testing container isolation..."

    if container_exec "$container" "cat /root/.openclaw/exec-approvals.json" >/dev/null 2>&1; then
        print_result fail "Cannot access exec-approvals.json" "Container CAN read the file!"
    else
        print_result pass "Cannot access exec-approvals.json"
    fi

    # Test 2: Cannot access host filesystem
    if container_exec "$container" "ls /Users/bruba/" >/dev/null 2>&1; then
        print_result fail "Cannot access host filesystem" "Container CAN access /Users/bruba/"
    else
        print_result pass "Cannot access host filesystem"
    fi

    # Test 3: Cannot write to tools directory on ANY agent (defense-in-depth)
    echo "Testing tools/:ro on all agents..."

    local agents=("bruba-main" "bruba-guru" "bruba-manager" "bruba-web")
    for agent in "${agents[@]}"; do
        local agent_container
        agent_container=$(get_container_name "$agent")

        if ! container_running "$agent_container"; then
            print_result skip "$agent: tools/ read-only" "Container not running"
            continue
        fi

        if container_exec "$agent_container" "touch /workspace/tools/test-write.txt" >/dev/null 2>&1; then
            # Clean up if somehow it succeeded
            container_exec "$agent_container" "rm -f /workspace/tools/test-write.txt" 2>/dev/null
            print_result fail "$agent: tools/ read-only" "Container CAN write to tools/"
        else
            print_result pass "$agent: tools/ read-only"
        fi
    done

    # Test 4: Cannot access openclaw.json
    if container_exec "$container" "cat /root/.openclaw/openclaw.json" >/dev/null 2>&1; then
        print_result fail "Cannot access openclaw.json" "Container CAN read the config!"
    else
        print_result pass "Cannot access openclaw.json"
    fi

    # Test 5: CAN access workspace (positive test)
    if container_exec "$container" "ls /workspace/" >/dev/null 2>&1; then
        print_result pass "Can access /workspace/ (expected)"
    else
        print_result fail "Can access /workspace/ (expected)" "Container cannot access workspace!"
    fi

    # Test 6: CAN access shared directory (positive test)
    if container_exec "$container" "ls /workspaces/shared/" >/dev/null 2>&1; then
        print_result pass "Can access /workspaces/shared/ (expected)"
    else
        print_result fail "Can access /workspaces/shared/ (expected)" "Container cannot access shared!"
    fi

    # Test 7: Message tool in sandbox ceiling (critical - keeps breaking!)
    echo ""
    echo "Testing tool permissions (sandbox ceiling)..."

    local sandbox_allow
    sandbox_allow=$(ssh bruba 'cat ~/.openclaw/openclaw.json | python3 -c "import json,sys; d=json.load(sys.stdin); print(\",\".join(d.get(\"tools\",{}).get(\"sandbox\",{}).get(\"tools\",{}).get(\"allow\",[])))"' 2>/dev/null)

    if echo "$sandbox_allow" | grep -q "message"; then
        print_result pass "message in sandbox tools.allow"
    else
        print_result fail "message in sandbox tools.allow" "CRITICAL: Voice replies will be broken! Run ./tools/fix-message-tool.sh"
    fi

    # Check bruba-main has message
    local main_msg
    main_msg=$(ssh bruba 'cat ~/.openclaw/openclaw.json | python3 -c "import json,sys; d=json.load(sys.stdin); agents=d.get(\"agents\",{}).get(\"list\",[]); a=[x for x in agents if x.get(\"id\")==\"bruba-main\"]; allow=a[0].get(\"tools\",{}).get(\"allow\",[]) if a else []; print(\"message\" in allow)"' 2>/dev/null)

    if [[ "$main_msg" == "True" ]]; then
        print_result pass "bruba-main has message tool"
    else
        print_result fail "bruba-main has message tool" "Run ./tools/fix-message-tool.sh"
    fi

    # Check bruba-guru has message
    local guru_msg
    guru_msg=$(ssh bruba 'cat ~/.openclaw/openclaw.json | python3 -c "import json,sys; d=json.load(sys.stdin); agents=d.get(\"agents\",{}).get(\"list\",[]); a=[x for x in agents if x.get(\"id\")==\"bruba-guru\"]; allow=a[0].get(\"tools\",{}).get(\"allow\",[]) if a else []; print(\"message\" in allow)"' 2>/dev/null)

    if [[ "$guru_msg" == "True" ]]; then
        print_result pass "bruba-guru has message tool"
    else
        print_result fail "bruba-guru has message tool" "Run ./tools/fix-message-tool.sh"
    fi
}

# =============================================================================
# Functional Tests
# =============================================================================

run_functional_tests() {
    echo ""
    echo "=== Functional Tests (Path Split) ==="
    echo ""

    # Test 1: Exec with HOST paths works
    echo "Testing exec path handling..."

    # Use a simple command that exists on the host
    if ssh bruba 'ls /Users/bruba/agents/bruba-main/tools/' >/dev/null 2>&1; then
        print_result pass "Host paths accessible from host"
    else
        print_result fail "Host paths accessible from host"
    fi

    # Test 2: Check sandbox config is set
    local sandbox_mode
    sandbox_mode=$(ssh bruba 'cat ~/.openclaw/openclaw.json | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get(\"agents\",{}).get(\"defaults\",{}).get(\"sandbox\",{}).get(\"mode\",\"off\"))"' 2>/dev/null)

    if [[ "$sandbox_mode" == "all" ]]; then
        print_result pass "Sandbox mode is 'all'"
    else
        print_result fail "Sandbox mode is 'all'" "Got: $sandbox_mode"
    fi

    # Test 3: Check bruba-web has bridge network
    local web_network
    web_network=$(ssh bruba 'cat ~/.openclaw/openclaw.json | python3 -c "import json,sys; d=json.load(sys.stdin); agents=d.get(\"agents\",{}).get(\"list\",[]); web=[a for a in agents if a.get(\"id\")==\"bruba-web\"]; print(web[0].get(\"sandbox\",{}).get(\"docker\",{}).get(\"network\",\"none\") if web else \"not found\")"' 2>/dev/null)

    if [[ "$web_network" == "bridge" ]]; then
        print_result pass "bruba-web has bridge network"
    else
        print_result fail "bruba-web has bridge network" "Got: $web_network"
    fi

    # Test 4: Check bruba-main has tools:ro bind
    local main_binds
    main_binds=$(ssh bruba 'cat ~/.openclaw/openclaw.json | python3 -c "import json,sys; d=json.load(sys.stdin); agents=d.get(\"agents\",{}).get(\"list\",[]); main=[a for a in agents if a.get(\"id\")==\"bruba-main\"]; binds=main[0].get(\"sandbox\",{}).get(\"docker\",{}).get(\"binds\",[]) if main else []; print(binds)"' 2>/dev/null)

    if echo "$main_binds" | grep -q "tools:/workspace/tools:ro"; then
        print_result pass "bruba-main has tools:ro bind"
    else
        print_result fail "bruba-main has tools:ro bind" "Got: $main_binds"
    fi

    # Test 5: Gateway is running
    if ssh bruba 'openclaw gateway status' 2>/dev/null | grep -qi "running"; then
        print_result pass "Gateway is running"
    else
        print_result fail "Gateway is running"
    fi
}

# =============================================================================
# Container Status
# =============================================================================

show_container_status() {
    echo ""
    echo "=== Container Status ==="
    echo ""

    ssh bruba 'docker ps --filter "name=openclaw-sandbox" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"' 2>/dev/null || echo "Could not retrieve container status"
}

# =============================================================================
# Main
# =============================================================================

echo "========================================"
echo "  Bruba Sandbox Verification Tests"
echo "========================================"

case "$MODE" in
    --security)
        run_security_tests
        ;;
    --functional)
        run_functional_tests
        ;;
    --status)
        show_container_status
        ;;
    --all|*)
        show_container_status
        run_security_tests
        run_functional_tests
        ;;
esac

echo ""
echo "========================================"
echo "  Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}, ${YELLOW}$SKIP skipped${NC}"
echo "========================================"

# Exit with failure if any tests failed
[[ $FAIL -eq 0 ]]
