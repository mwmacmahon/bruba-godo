#!/bin/bash
#
# session-status.sh - Show session health for agents
#
# Usage:
#   session-status.sh all              # All agents' sessions
#   session-status.sh <agent-id>       # Single agent
#
# Displays: agent, sessionId (short), totalTokens, model, updatedAt
# Requires: jq, openclaw gateway access
#
# Version: 1.0.0
# Updated: 2026-02-06

set -e

JQ=$(command -v jq)
VALID_AGENTS="bruba-main bruba-manager bruba-guru bruba-rex bruba-web"

usage() {
    echo "Usage: session-status.sh <agent-id|all>"
    echo ""
    echo "Show session health for agents."
    echo ""
    echo "Arguments:"
    echo "  all            Show all agents"
    echo "  <agent-id>     Show specific agent (e.g. bruba-web)"
    echo ""
    echo "Valid agents: $VALID_AGENTS"
    exit 1
}

TARGET="${1:?$(usage)}"

if [[ "$TARGET" == "all" ]]; then
    # Get all sessions via gateway call
    RAW=$(openclaw gateway call sessions.list --json 2>/dev/null)
    if [[ -z "$RAW" ]]; then
        echo "Error: No response from sessions.list"
        exit 1
    fi

    # Format as table
    echo "$RAW" | $JQ -r '
        [.sessions[] | select(.key | endswith(":main"))] |
        sort_by(.key) |
        .[] |
        [
            (.key | split(":")[1]),
            (.sessionId // "none" | .[:8]),
            (.totalTokens // 0 | tostring),
            (.model // "unknown"),
            ((.updatedAt // 0) / 1000 | strftime("%Y-%m-%d %H:%M"))
        ] | @tsv
    ' | (echo -e "AGENT\tSESSION\tTOKENS\tMODEL\tUPDATED"; cat) | column -t -s $'\t'
else
    # Validate agent
    if [[ ! " $VALID_AGENTS " =~ " $TARGET " ]]; then
        echo "Error: Invalid agent '$TARGET'"
        echo "Valid agents: $VALID_AGENTS"
        exit 1
    fi

    # Get single agent session
    RAW=$(openclaw gateway call sessions.list --json 2>/dev/null)
    echo "$RAW" | $JQ --arg key "agent:${TARGET}:main" '
        .sessions[] | select(.key == $key) | {
            agent: (.key | split(":")[1]),
            sessionId: .sessionId,
            totalTokens: .totalTokens,
            inputTokens: .inputTokens,
            outputTokens: .outputTokens,
            model: .model,
            updatedAt: ((.updatedAt // 0) / 1000 | strftime("%Y-%m-%d %H:%M:%S"))
        }
    '
fi
