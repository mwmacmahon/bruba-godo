#!/bin/bash
#
# fix-message-tool.sh - Check and fix the message tool configuration
#
# The message tool has disappeared multiple times due to:
# 1. Missing from tools.sandbox.tools.allow (sandbox ceiling)
# 2. Missing from agent tools.allow
# 3. Missing from global tools.allow
#
# This script checks all three levels and fixes if needed.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "========================================"
echo "  Message Tool Configuration Check"
echo "========================================"
echo ""

# Check all levels
check_result=$(ssh bruba 'python3 << "PYCHECK"
import json

with open("/Users/bruba/.openclaw/openclaw.json", "r") as f:
    config = json.load(f)

issues = []
fixes_needed = []

# Check 1: Global tools.allow
global_allow = config.get("tools", {}).get("allow", [])
if "message" not in global_allow:
    issues.append("MISSING from global tools.allow")
    fixes_needed.append("global")
else:
    print("✓ Global tools.allow: message present")

# Check 2: Sandbox tools.allow (THE CEILING)
sandbox_allow = config.get("tools", {}).get("sandbox", {}).get("tools", {}).get("allow", [])
if "message" not in sandbox_allow:
    issues.append("MISSING from tools.sandbox.tools.allow (SANDBOX CEILING)")
    fixes_needed.append("sandbox")
else:
    print("✓ Sandbox tools.allow: message present")

# Check 3: bruba-main tools.allow
agents = config.get("agents", {}).get("list", [])
main = next((a for a in agents if a.get("id") == "bruba-main"), None)
if main:
    main_allow = main.get("tools", {}).get("allow", [])
    if "message" not in main_allow:
        issues.append("MISSING from bruba-main tools.allow")
        fixes_needed.append("bruba-main")
    else:
        print("✓ bruba-main tools.allow: message present")

# Check 4: bruba-guru tools.allow
guru = next((a for a in agents if a.get("id") == "bruba-guru"), None)
if guru:
    guru_allow = guru.get("tools", {}).get("allow", [])
    if "message" not in guru_allow:
        issues.append("MISSING from bruba-guru tools.allow")
        fixes_needed.append("bruba-guru")
    else:
        print("✓ bruba-guru tools.allow: message present")

if issues:
    print()
    print("ISSUES FOUND:")
    for issue in issues:
        print(f"  ✗ {issue}")
    print()
    print("FIXES_NEEDED:" + ",".join(fixes_needed))
else:
    print()
    print("All checks passed. Message tool is correctly configured.")
    print("FIXES_NEEDED:none")
PYCHECK
' 2>/dev/null)

echo "$check_result"
echo ""

# Extract fixes needed
fixes_needed=$(echo "$check_result" | grep "FIXES_NEEDED:" | cut -d: -f2)

if [[ "$fixes_needed" == "none" ]]; then
    echo -e "${GREEN}No fixes needed.${NC}"
    exit 0
fi

echo -e "${YELLOW}Applying fixes...${NC}"
echo ""

# Apply fixes
ssh bruba 'python3 << "PYFIX"
import json

with open("/Users/bruba/.openclaw/openclaw.json", "r") as f:
    config = json.load(f)

modified = False

# Fix global tools.allow
global_allow = config.get("tools", {}).get("allow", [])
if "message" not in global_allow:
    global_allow.append("message")
    config["tools"]["allow"] = global_allow
    print("Fixed: Added message to global tools.allow")
    modified = True

# Fix sandbox tools.allow
sandbox_tools = config.get("tools", {}).get("sandbox", {}).get("tools", {})
sandbox_allow = sandbox_tools.get("allow", [])
if "message" not in sandbox_allow:
    sandbox_allow.append("message")
    if "sandbox" not in config["tools"]:
        config["tools"]["sandbox"] = {}
    if "tools" not in config["tools"]["sandbox"]:
        config["tools"]["sandbox"]["tools"] = {}
    config["tools"]["sandbox"]["tools"]["allow"] = sandbox_allow
    print("Fixed: Added message to sandbox tools.allow")
    modified = True

# Fix bruba-main
agents = config.get("agents", {}).get("list", [])
for agent in agents:
    if agent.get("id") == "bruba-main":
        allow = agent.get("tools", {}).get("allow", [])
        if "message" not in allow:
            allow.append("message")
            if "tools" not in agent:
                agent["tools"] = {}
            agent["tools"]["allow"] = allow
            print("Fixed: Added message to bruba-main tools.allow")
            modified = True

# Fix bruba-guru
for agent in agents:
    if agent.get("id") == "bruba-guru":
        allow = agent.get("tools", {}).get("allow", [])
        if "message" not in allow:
            allow.append("message")
            if "tools" not in agent:
                agent["tools"] = {}
            agent["tools"]["allow"] = allow
            print("Fixed: Added message to bruba-guru tools.allow")
            modified = True

if modified:
    with open("/Users/bruba/.openclaw/openclaw.json", "w") as f:
        json.dump(config, f, indent=2)
    print()
    print("Config saved. Restart gateway to apply.")
else:
    print("No modifications needed.")
PYFIX
'

echo ""
echo -e "${YELLOW}Restarting gateway...${NC}"
ssh bruba 'openclaw gateway restart'

echo ""
echo -e "${GREEN}Done. Message tool should now be available.${NC}"
echo ""
echo "To verify, run: ./tools/test-permissions.sh --sandbox"
