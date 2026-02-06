#!/bin/bash
#
# session-broadcast.sh - Send messages to multiple agents via sessions_send
#
# Usage:
#   session-broadcast.sh <template> [agent1 agent2 ...]
#   session-broadcast.sh prep                    # Prep message to reset_cycle agents
#   session-broadcast.sh export                  # Export message to export_cycle agents
#   session-broadcast.sh wake                    # Wake message to wake_cycle agents
#   session-broadcast.sh custom "message" agent1 agent2  # Custom message to specific agents
#
# Templates are loaded from the messages/ directory next to this script.
#
# Version: 1.0.0
# Updated: 2026-02-06

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MESSAGES_DIR="$SCRIPT_DIR/../messages"

VALID_AGENTS="bruba-main bruba-manager bruba-guru bruba-rex bruba-web"
RESET_CYCLE="bruba-main bruba-guru bruba-rex"
EXPORT_CYCLE="bruba-main bruba-rex"
WAKE_CYCLE="bruba-main bruba-guru bruba-rex bruba-web"

usage() {
    echo "Usage: session-broadcast.sh <template> [args...]"
    echo ""
    echo "Templates:"
    echo "  prep                    Send prep message to reset_cycle agents"
    echo "  export                  Send export message to export_cycle agents"
    echo "  wake                    Send wake message to wake_cycle agents"
    echo "  custom \"msg\" a1 a2     Send custom message to specific agents"
    echo ""
    echo "Agent cycles:"
    echo "  reset_cycle: $RESET_CYCLE"
    echo "  export_cycle: $EXPORT_CYCLE"
    echo "  wake_cycle: $WAKE_CYCLE"
    exit 1
}

TEMPLATE="${1:?$(usage)}"
shift

send_to_agent() {
    local agent="$1"
    local message="$2"
    echo "  Sending to $agent..."
    openclaw agent --agent "$agent" --message "$message" 2>&1 || echo "  WARN: Failed to send to $agent"
}

case "$TEMPLATE" in
    prep)
        MSG=$(cat "$MESSAGES_DIR/prep.txt")
        echo "Broadcasting prep message to reset_cycle agents..."
        for agent in $RESET_CYCLE; do
            send_to_agent "$agent" "$MSG"
        done
        ;;
    export)
        MSG=$(cat "$MESSAGES_DIR/export.txt")
        echo "Broadcasting export message to export_cycle agents..."
        for agent in $EXPORT_CYCLE; do
            send_to_agent "$agent" "$MSG"
        done
        ;;
    wake)
        MSG=$(cat "$MESSAGES_DIR/wake.txt")
        echo "Broadcasting wake message to wake_cycle agents..."
        for agent in $WAKE_CYCLE; do
            send_to_agent "$agent" "$MSG"
        done
        ;;
    custom)
        MSG="$1"
        shift
        if [[ -z "$MSG" || $# -eq 0 ]]; then
            echo "Usage: session-broadcast.sh custom \"message\" agent1 agent2 ..."
            exit 1
        fi
        echo "Broadcasting custom message..."
        for agent in "$@"; do
            if [[ ! " $VALID_AGENTS " =~ " $agent " ]]; then
                echo "  SKIP: Invalid agent '$agent'"
                continue
            fi
            send_to_agent "$agent" "$MSG"
        done
        ;;
    *)
        echo "Error: Unknown template '$TEMPLATE'"
        usage
        ;;
esac

echo "Broadcast complete."
