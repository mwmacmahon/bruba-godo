#!/bin/bash
#
# session-reset.sh - Reset agent sessions via gateway call
#
# Usage:
#   session-reset.sh <agent-id>        # Reset single agent
#   session-reset.sh all               # Reset all reset_cycle agents
#
# Uses openclaw gateway call sessions.reset — the only confirmed working method.
# Sessions via sessions_send "/reset" do NOT work.
#
# Version: 1.0.0
# Updated: 2026-02-06

set -e

VALID_AGENTS="bruba-main bruba-manager bruba-guru bruba-rex bruba-web"
RESET_CYCLE_AGENTS="bruba-main bruba-guru bruba-rex"

usage() {
    echo "Usage: session-reset.sh <agent-id|all>"
    echo ""
    echo "Reset agent sessions via gateway call."
    echo ""
    echo "Arguments:"
    echo "  all            Reset all cycle agents: $RESET_CYCLE_AGENTS"
    echo "  <agent-id>     Reset specific agent"
    echo ""
    echo "Valid agents: $VALID_AGENTS"
    exit 1
}

TARGET="${1:?$(usage)}"

reset_agent() {
    local agent="$1"
    echo "Resetting $agent..."
    local result
    result=$(openclaw gateway call sessions.reset --params "{\"key\":\"agent:${agent}:main\"}" 2>&1)
    if [[ $? -eq 0 ]]; then
        echo "  OK: $agent reset"
    else
        echo "  FAIL: $agent — $result"
        return 1
    fi
}

if [[ "$TARGET" == "all" ]]; then
    ERRORS=0
    for agent in $RESET_CYCLE_AGENTS; do
        reset_agent "$agent" || ERRORS=$((ERRORS + 1))
    done
    # Also reset manager (separate from cycle)
    reset_agent "bruba-manager" || ERRORS=$((ERRORS + 1))

    echo ""
    if [[ $ERRORS -gt 0 ]]; then
        echo "Completed with $ERRORS errors"
        exit 1
    else
        echo "All agents reset successfully"
    fi
else
    # Validate agent
    if [[ ! " $VALID_AGENTS " =~ " $TARGET " ]]; then
        echo "Error: Invalid agent '$TARGET'"
        echo "Valid agents: $VALID_AGENTS"
        exit 1
    fi

    reset_agent "$TARGET"
fi
