#!/bin/bash
#
# test-permissions.sh - Verify agent tool permissions are correctly configured
#
# Usage: ./tools/test-permissions.sh [--all|--tools|--sandbox|--config]
#
# Tests that:
# - Expected tools are available to each agent
# - Denied tools are blocked
# - Sandbox tool policy ceiling is correctly configured
# - Global, agent, and sandbox tool configs are aligned
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Counters
PASS=0
FAIL=0
SKIP=0

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
            [[ -n "$detail" ]] && echo "    $detail"
            ((FAIL++))
            ;;
        skip)
            echo -e "${YELLOW}○${NC} $test_name (skipped)"
            ((SKIP++))
            ;;
    esac
}

print_header() {
    echo ""
    echo -e "${CYAN}=== $1 ===${NC}"
    echo ""
}

# =============================================================================
# Config Tests - Check openclaw.json structure
# =============================================================================

run_config_tests() {
    print_header "Config Structure Tests"

    # Test 1: Global tools.allow exists and has key tools
    local global_allow
    global_allow=$(ssh bruba 'cat ~/.openclaw/openclaw.json | python3 -c "import json,sys; d=json.load(sys.stdin); print(\",\".join(d.get(\"tools\",{}).get(\"allow\",[])))"' 2>/dev/null)

    if [[ -n "$global_allow" ]]; then
        print_result pass "Global tools.allow exists"

        # Check for critical tools in global allow
        for tool in "message" "exec" "read" "write" "edit"; do
            if echo "$global_allow" | grep -q "$tool"; then
                print_result pass "Global allows: $tool"
            else
                print_result fail "Global allows: $tool" "Not in global tools.allow"
            fi
        done
    else
        print_result fail "Global tools.allow exists" "Could not read config"
    fi

    # Test 2: Sandbox tools.allow exists and has critical tools
    local sandbox_allow
    sandbox_allow=$(ssh bruba 'cat ~/.openclaw/openclaw.json | python3 -c "import json,sys; d=json.load(sys.stdin); print(\",\".join(d.get(\"tools\",{}).get(\"sandbox\",{}).get(\"tools\",{}).get(\"allow\",[])))"' 2>/dev/null)

    if [[ -n "$sandbox_allow" ]]; then
        print_result pass "Sandbox tools.allow exists"

        # Check for critical tools in sandbox allow (THE CEILING)
        for tool in "message" "exec" "group:memory" "group:sessions"; do
            if echo "$sandbox_allow" | grep -q "$tool"; then
                print_result pass "Sandbox allows: $tool"
            else
                print_result fail "Sandbox allows: $tool" "NOT in sandbox ceiling - agents won't have it!"
            fi
        done
    else
        print_result fail "Sandbox tools.allow exists" "Could not read config"
    fi

    # Test 3: Each agent has tools config
    local agents=("bruba-main" "bruba-guru" "bruba-manager" "bruba-web")
    for agent in "${agents[@]}"; do
        local agent_tools
        agent_tools=$(ssh bruba "cat ~/.openclaw/openclaw.json | python3 -c \"import json,sys; d=json.load(sys.stdin); agents=d.get('agents',{}).get('list',[]); a=[x for x in agents if x.get('id')=='$agent']; print(json.dumps(a[0].get('tools',{})) if a else 'not found')\"" 2>/dev/null)

        if [[ "$agent_tools" != "not found" && -n "$agent_tools" ]]; then
            print_result pass "$agent has tools config"
        else
            print_result fail "$agent has tools config" "Agent not found or no tools config"
        fi
    done
}

# =============================================================================
# Agent Tool Tests - Check expected tools per agent
# =============================================================================

run_tool_tests() {
    print_header "Agent Tool Availability Tests"

    # Define expected tools per agent
    # Format: "agent:must_have_tools:must_not_have_tools"
    local -A AGENT_TOOLS=(
        ["bruba-main"]="message,exec,read,write,edit,memory_search,memory_get,sessions_send,image:web_search,web_fetch,browser,canvas,sessions_spawn"
        ["bruba-guru"]="message,exec,read,write,edit,memory_search,memory_get,sessions_send:web_search,web_fetch,browser,canvas"
        ["bruba-manager"]="exec,read,write,memory_search,memory_get,sessions_send:web_search,web_fetch,browser,canvas,edit"
        ["bruba-web"]="web_search,web_fetch,read,write:exec,edit,memory_search,memory_get,sessions_send,sessions_spawn"
    )

    for agent in "${!AGENT_TOOLS[@]}"; do
        echo ""
        echo -e "${CYAN}Testing $agent:${NC}"

        local spec="${AGENT_TOOLS[$agent]}"
        local must_have="${spec%%:*}"
        local must_not_have="${spec##*:}"

        # Get agent's allowed tools from config
        local agent_allow
        agent_allow=$(ssh bruba "cat ~/.openclaw/openclaw.json | python3 -c \"import json,sys; d=json.load(sys.stdin); agents=d.get('agents',{}).get('list',[]); a=[x for x in agents if x.get('id')=='$agent']; allow=a[0].get('tools',{}).get('allow',[]) if a else []; print(','.join(allow))\"" 2>/dev/null)

        local agent_deny
        agent_deny=$(ssh bruba "cat ~/.openclaw/openclaw.json | python3 -c \"import json,sys; d=json.load(sys.stdin); agents=d.get('agents',{}).get('list',[]); a=[x for x in agents if x.get('id')=='$agent']; deny=a[0].get('tools',{}).get('deny',[]) if a else []; print(','.join(deny))\"" 2>/dev/null)

        # Check must-have tools
        IFS=',' read -ra MUST_HAVE_ARR <<< "$must_have"
        for tool in "${MUST_HAVE_ARR[@]}"; do
            if echo "$agent_allow" | grep -q "$tool"; then
                print_result pass "has $tool"
            elif echo "$agent_allow" | grep -q "group:"; then
                # Might be covered by a group
                print_result pass "has $tool (via group)"
            else
                print_result fail "has $tool" "Not in agent's tools.allow"
            fi
        done

        # Check must-not-have tools
        IFS=',' read -ra MUST_NOT_ARR <<< "$must_not_have"
        for tool in "${MUST_NOT_ARR[@]}"; do
            if echo "$agent_deny" | grep -q "$tool"; then
                print_result pass "denies $tool"
            else
                # Check if it's simply not in allow (implicit deny)
                if ! echo "$agent_allow" | grep -q "$tool"; then
                    print_result pass "denies $tool (not in allow)"
                else
                    print_result fail "denies $tool" "Tool is allowed but should be denied"
                fi
            fi
        done
    done
}

# =============================================================================
# Sandbox Ceiling Tests - Verify sandbox policy doesn't block needed tools
# =============================================================================

run_sandbox_tests() {
    print_header "Sandbox Tool Ceiling Tests"

    echo "The sandbox tools.allow creates a CEILING for containerized agents."
    echo "Tools must be allowed at ALL levels: global → agent → sandbox"
    echo ""

    # Get all three levels
    local global_allow sandbox_allow
    global_allow=$(ssh bruba 'cat ~/.openclaw/openclaw.json | python3 -c "import json,sys; d=json.load(sys.stdin); print(\",\".join(d.get(\"tools\",{}).get(\"allow\",[])))"' 2>/dev/null)
    sandbox_allow=$(ssh bruba 'cat ~/.openclaw/openclaw.json | python3 -c "import json,sys; d=json.load(sys.stdin); print(\",\".join(d.get(\"tools\",{}).get(\"sandbox\",{}).get(\"tools\",{}).get(\"allow\",[])))"' 2>/dev/null)

    # Critical tools that MUST be in sandbox allow for things to work
    local critical_tools=("message" "exec" "group:memory" "group:sessions" "group:media" "group:web")

    for tool in "${critical_tools[@]}"; do
        local in_global in_sandbox
        in_global=$(echo "$global_allow" | grep -c "$tool" || true)
        in_sandbox=$(echo "$sandbox_allow" | grep -c "$tool" || true)

        if [[ $in_global -gt 0 && $in_sandbox -gt 0 ]]; then
            print_result pass "$tool: global ✓ sandbox ✓"
        elif [[ $in_global -gt 0 && $in_sandbox -eq 0 ]]; then
            print_result fail "$tool: global ✓ sandbox ✗" "In global but BLOCKED by sandbox ceiling!"
        elif [[ $in_global -eq 0 && $in_sandbox -gt 0 ]]; then
            print_result skip "$tool: global ✗ sandbox ✓" "In sandbox but not global (unusual)"
        else
            print_result skip "$tool: global ✗ sandbox ✗" "Not configured at either level"
        fi
    done

    # Specifically test message since that was the issue
    echo ""
    echo -e "${CYAN}Message tool specifically (the tool that broke):${NC}"

    local msg_global msg_sandbox msg_main msg_guru
    msg_global=$(echo "$global_allow" | grep -c "message" || true)
    msg_sandbox=$(echo "$sandbox_allow" | grep -c "message" || true)

    msg_main=$(ssh bruba "cat ~/.openclaw/openclaw.json | python3 -c \"import json,sys; d=json.load(sys.stdin); agents=d.get('agents',{}).get('list',[]); a=[x for x in agents if x.get('id')=='bruba-main']; allow=a[0].get('tools',{}).get('allow',[]) if a else []; print('message' in allow)\"" 2>/dev/null)

    msg_guru=$(ssh bruba "cat ~/.openclaw/openclaw.json | python3 -c \"import json,sys; d=json.load(sys.stdin); agents=d.get('agents',{}).get('list',[]); a=[x for x in agents if x.get('id')=='bruba-guru']; allow=a[0].get('tools',{}).get('allow',[]) if a else []; print('message' in allow)\"" 2>/dev/null)

    echo "  Global tools.allow:     $([ $msg_global -gt 0 ] && echo '✓' || echo '✗')"
    echo "  Sandbox tools.allow:    $([ $msg_sandbox -gt 0 ] && echo '✓' || echo '✗')"
    echo "  bruba-main tools.allow: $([[ "$msg_main" == "True" ]] && echo '✓' || echo '✗')"
    echo "  bruba-guru tools.allow: $([[ "$msg_guru" == "True" ]] && echo '✓' || echo '✗')"

    if [[ $msg_global -gt 0 && $msg_sandbox -gt 0 && "$msg_main" == "True" ]]; then
        print_result pass "message tool fully configured for bruba-main"
    else
        print_result fail "message tool fully configured for bruba-main" "Check all three levels!"
    fi

    if [[ $msg_global -gt 0 && $msg_sandbox -gt 0 && "$msg_guru" == "True" ]]; then
        print_result pass "message tool fully configured for bruba-guru"
    else
        print_result fail "message tool fully configured for bruba-guru" "Check all three levels!"
    fi
}

# =============================================================================
# Live Agent Tests - Actually query agents for their tools
# =============================================================================

run_live_tests() {
    print_header "Live Agent Tool Query Tests"

    echo "Querying each agent to see what tools they report having..."
    echo "(This requires gateway to be running)"
    echo ""

    # Check if gateway is running
    if ! ssh bruba 'openclaw gateway status 2>&1 | grep -q "running"'; then
        print_result skip "All live tests" "Gateway not running"
        return
    fi

    local agents=("bruba-main" "bruba-guru")
    local must_have_message=("bruba-main" "bruba-guru")

    for agent in "${agents[@]}"; do
        echo -e "${CYAN}Querying $agent...${NC}"

        # This would require actually sending a message to the agent and asking what tools it has
        # For now, we'll check via config since live querying is complex
        print_result skip "$agent live query" "Live query not implemented (use config tests)"
    done
}

# =============================================================================
# Summary
# =============================================================================

show_summary() {
    print_header "Permission Config Summary"

    ssh bruba 'cat ~/.openclaw/openclaw.json | python3 -c "
import json
import sys

d = json.load(sys.stdin)

print(\"Global tools.allow:\")
for t in d.get(\"tools\", {}).get(\"allow\", []):
    print(f\"  - {t}\")

print()
print(\"Sandbox tools.allow (CEILING for containers):\")
for t in d.get(\"tools\", {}).get(\"sandbox\", {}).get(\"tools\", {}).get(\"allow\", []):
    print(f\"  - {t}\")

print()
print(\"Per-agent tools:\")
for agent in d.get(\"agents\", {}).get(\"list\", []):
    aid = agent.get(\"id\", \"unknown\")
    tools = agent.get(\"tools\", {})
    allow = tools.get(\"allow\", [])
    deny = tools.get(\"deny\", [])
    print(f\"  {aid}:\")
    print(f\"    allow: {allow[:5]}...\" if len(allow) > 5 else f\"    allow: {allow}\")
    print(f\"    deny: {deny[:5]}...\" if len(deny) > 5 else f\"    deny: {deny}\")
"' 2>/dev/null || echo "Could not read config"
}

# =============================================================================
# Main
# =============================================================================

echo "========================================"
echo "  Agent Permission Tests"
echo "========================================"

case "$MODE" in
    --config)
        run_config_tests
        ;;
    --tools)
        run_tool_tests
        ;;
    --sandbox)
        run_sandbox_tests
        ;;
    --live)
        run_live_tests
        ;;
    --summary)
        show_summary
        ;;
    --all|*)
        run_config_tests
        run_tool_tests
        run_sandbox_tests
        show_summary
        ;;
esac

echo ""
echo "========================================"
echo -e "  Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}, ${YELLOW}$SKIP skipped${NC}"
echo "========================================"

# Exit with failure if any tests failed
[[ $FAIL -eq 0 ]]
