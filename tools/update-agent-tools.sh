#!/bin/bash
# Update bot's openclaw.json agent tool configs from config.yaml
#
# Usage:
#   ./tools/update-agent-tools.sh              # Sync all agents + subagents
#   ./tools/update-agent-tools.sh --agent=X    # Sync specific agent only
#   ./tools/update-agent-tools.sh --check      # Check status only (no changes)
#   ./tools/update-agent-tools.sh --dry-run    # Show what would change
#
# Reads tool configs from config.yaml and patches the bot's openclaw.json.
# Preserves existing settings (tokens, channels, etc).
#
# Logs: logs/agent-tools.log

set -e

# Load shared functions
source "$(dirname "$0")/lib.sh"

# Parse arguments
CHECK_ONLY=false
AGENT_FILTER=""
args=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --check)
            CHECK_ONLY=true
            shift
            ;;
        --agent=*)
            AGENT_FILTER="${1#*=}"
            shift
            ;;
        *)
            args+=("$1")
            shift
            ;;
    esac
done

if ! parse_common_args "${args[@]}"; then
    echo "Usage: $0 [--check] [--agent=NAME] [--dry-run] [--verbose]"
    echo ""
    echo "Sync agent tool configs from config.yaml to bot's openclaw.json."
    echo ""
    echo "Options:"
    echo "  --check         Check status only (list discrepancies)"
    echo "  --agent=NAME    Only sync specific agent"
    echo "  --dry-run, -n   Show what would change without doing it"
    echo "  --verbose, -v   Show detailed output"
    exit 0
fi

# Load config
load_config

# Check prerequisites
require_commands jq python3

# Set up logging
LOG_FILE="$LOG_DIR/agent-tools.log"
mkdir -p "$LOG_DIR"

log "=== Updating Agent Tool Configs ==="

# Get current openclaw.json from bot
get_current_config() {
    bot_cmd "cat $REMOTE_OPENCLAW/openclaw.json" 2>/dev/null
}

# Get agent's current tools from openclaw.json
# Usage: get_current_agent_tools "bruba-main" "$current_config"
get_current_agent_tools() {
    local agent="$1"
    local config="$2"
    echo "$config" | jq -c ".agents.list[] | select(.id == \"$agent\") | .tools // {}"
}

# Compare two JSON arrays/objects
# Returns 0 if equal, 1 if different
# For arrays, compares sorted values (order-independent)
json_equal() {
    local a="$1"
    local b="$2"
    # Sort arrays before comparing to handle different ordering
    local a_sorted b_sorted
    a_sorted=$(echo "$a" | jq -S 'if type == "array" then sort else . end')
    b_sorted=$(echo "$b" | jq -S 'if type == "array" then sort else . end')
    [[ "$a_sorted" == "$b_sorted" ]]
}

# Sync agent tools
sync_agent_tools() {
    local agent="$1"
    local current_config="$2"

    # Get desired config from config.yaml
    local desired_allow
    local desired_deny
    desired_allow=$(get_agent_tools_allow "$agent")
    desired_deny=$(get_agent_tools_deny "$agent")

    # Skip if no tool config defined at all
    if [[ (-z "$desired_allow" || "$desired_allow" == "null") && (-z "$desired_deny" || "$desired_deny" == "null") ]]; then
        [[ "$VERBOSE" == "true" ]] && echo "  $agent: no tools config defined, skipping"
        return 0
    fi

    # Normalize empty/null to empty array for comparison
    [[ -z "$desired_allow" || "$desired_allow" == "null" ]] && desired_allow="[]"
    [[ -z "$desired_deny" || "$desired_deny" == "null" ]] && desired_deny="[]"

    # Get current config from bot
    local current_tools
    current_tools=$(get_current_agent_tools "$agent" "$current_config")
    local current_allow
    local current_deny
    current_allow=$(echo "$current_tools" | jq -c '.allow // []')
    current_deny=$(echo "$current_tools" | jq -c '.deny // []')

    # Compare - only check fields that are explicitly configured
    local allow_changed=false
    local deny_changed=false
    local has_allow_config=false
    local has_deny_config=false

    # Check if allow is explicitly configured (not empty array from normalization)
    if [[ "$desired_allow" != "[]" ]]; then
        has_allow_config=true
        if ! json_equal "$desired_allow" "$current_allow"; then
            allow_changed=true
        fi
    fi

    # Check if deny is explicitly configured
    if [[ "$desired_deny" != "[]" ]]; then
        has_deny_config=true
        if ! json_equal "$desired_deny" "$current_deny"; then
            deny_changed=true
        fi
    fi

    if [[ "$allow_changed" == "false" && "$deny_changed" == "false" ]]; then
        if [[ "$has_allow_config" == "true" || "$has_deny_config" == "true" ]]; then
            [[ "$VERBOSE" == "true" ]] && echo "  $agent: in sync"
        else
            [[ "$VERBOSE" == "true" ]] && echo "  $agent: no tools config defined, skipping"
        fi
        return 0
    fi

    # Show changes
    echo "  $agent:"
    if [[ "$allow_changed" == "true" ]]; then
        echo "    allow: $(echo "$current_allow" | jq -c '.') → $(echo "$desired_allow" | jq -c '.')"
    fi
    if [[ "$deny_changed" == "true" ]]; then
        echo "    deny:  $(echo "$current_deny" | jq -c '.') → $(echo "$desired_deny" | jq -c '.')"
    fi

    # Apply if not check/dry-run
    if [[ "$CHECK_ONLY" == "true" ]]; then
        return 1  # Signal discrepancy found
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        return 1  # Signal would change
    fi

    # Build jq filter to update this agent (only fields that are configured)
    local jq_filter=""
    if [[ "$has_allow_config" == "true" ]]; then
        jq_filter="(.agents.list[] | select(.id == \"$agent\") | .tools.allow) = $desired_allow"
    fi
    if [[ "$has_deny_config" == "true" ]]; then
        if [[ -n "$jq_filter" ]]; then
            jq_filter="$jq_filter | (.agents.list[] | select(.id == \"$agent\") | .tools.deny) = $desired_deny"
        else
            jq_filter="(.agents.list[] | select(.id == \"$agent\") | .tools.deny) = $desired_deny"
        fi
    fi

    # Apply to bot
    log "  Updating $agent tools on bot..."
    bot_cmd "jq '$jq_filter' $REMOTE_OPENCLAW/openclaw.json > /tmp/openclaw.json && mv /tmp/openclaw.json $REMOTE_OPENCLAW/openclaw.json"

    return 0
}

# Sync subagent tools
sync_subagent_tools() {
    local current_config="$1"

    # Get desired config from config.yaml
    local subagent_config
    subagent_config=$(get_subagents_config)

    if [[ -z "$subagent_config" || "$subagent_config" == "null" ]]; then
        [[ "$VERBOSE" == "true" ]] && echo "  subagents: no config defined, skipping"
        return 0
    fi

    local desired_allow
    local desired_deny
    desired_allow=$(echo "$subagent_config" | jq -c '.tools_allow // []')
    desired_deny=$(echo "$subagent_config" | jq -c '.tools_deny // []')

    # Get current from bot
    local current_subagent
    current_subagent=$(echo "$current_config" | jq -c '.tools.subagents.tools // {}')
    local current_allow
    local current_deny
    current_allow=$(echo "$current_subagent" | jq -c '.allow // []')
    current_deny=$(echo "$current_subagent" | jq -c '.deny // []')

    # Compare
    local allow_changed=false
    local deny_changed=false

    if ! json_equal "$desired_allow" "$current_allow"; then
        allow_changed=true
    fi

    if ! json_equal "$desired_deny" "$current_deny"; then
        deny_changed=true
    fi

    if [[ "$allow_changed" == "false" && "$deny_changed" == "false" ]]; then
        [[ "$VERBOSE" == "true" ]] && echo "  subagents: in sync"
        return 0
    fi

    # Show changes
    echo "  subagents:"
    if [[ "$allow_changed" == "true" ]]; then
        echo "    allow: $(echo "$current_allow" | jq -c '.') → $(echo "$desired_allow" | jq -c '.')"
    fi
    if [[ "$deny_changed" == "true" ]]; then
        echo "    deny:  $(echo "$current_deny" | jq -c '.') → $(echo "$desired_deny" | jq -c '.')"
    fi

    # Apply if not check/dry-run
    if [[ "$CHECK_ONLY" == "true" ]]; then
        return 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        return 1
    fi

    # Build jq filter
    local jq_filter
    jq_filter=".tools.subagents.tools.allow = $desired_allow | .tools.subagents.tools.deny = $desired_deny"

    # Apply to bot
    log "  Updating subagent tools on bot..."
    bot_cmd "jq '$jq_filter' $REMOTE_OPENCLAW/openclaw.json > /tmp/openclaw.json && mv /tmp/openclaw.json $REMOTE_OPENCLAW/openclaw.json"

    return 0
}

# Main execution
log "Fetching current config from bot..."
CURRENT_CONFIG=$(get_current_config)

if [[ -z "$CURRENT_CONFIG" ]]; then
    echo "ERROR: Could not read openclaw.json from bot" >&2
    exit 1
fi

# Backup before changes (unless check/dry-run)
if [[ "$CHECK_ONLY" != "true" && "$DRY_RUN" != "true" ]]; then
    log "Creating backup..."
    bot_cmd "cp $REMOTE_OPENCLAW/openclaw.json $REMOTE_OPENCLAW/openclaw.json.backup"
fi

CHANGES_FOUND=0

# Sync agent tools
if [[ -n "$AGENT_FILTER" ]]; then
    # Single agent
    echo "Checking $AGENT_FILTER..."
    if ! sync_agent_tools "$AGENT_FILTER" "$CURRENT_CONFIG"; then
        CHANGES_FOUND=1
    fi
else
    # All agents with tools config
    echo "Checking agent tools..."
    for agent in $(get_agents); do
        # Skip agents without workspace (like bruba-helper)
        load_agent_config "$agent"
        [[ -z "$AGENT_WORKSPACE" || "$AGENT_WORKSPACE" == "null" ]] && continue

        if ! sync_agent_tools "$agent" "$CURRENT_CONFIG"; then
            CHANGES_FOUND=1
        fi

        # Re-fetch config if we made changes (for next iteration)
        if [[ "$CHECK_ONLY" != "true" && "$DRY_RUN" != "true" && $CHANGES_FOUND -eq 1 ]]; then
            CURRENT_CONFIG=$(get_current_config)
        fi
    done

    # Sync subagent tools
    echo "Checking subagent tools..."
    if ! sync_subagent_tools "$CURRENT_CONFIG"; then
        CHANGES_FOUND=1
    fi
fi

log "=== Update Complete ==="

# Summary
echo ""
if [[ "$CHECK_ONLY" == "true" ]]; then
    if [[ $CHANGES_FOUND -eq 0 ]]; then
        echo "Agent tools: in sync"
    else
        echo "Agent tools: discrepancies found (run without --check to apply)"
    fi
elif [[ "$DRY_RUN" == "true" ]]; then
    if [[ $CHANGES_FOUND -eq 0 ]]; then
        echo "[DRY RUN] Agent tools: in sync"
    else
        echo "[DRY RUN] Would update agent tools (run without --dry-run to apply)"
    fi
else
    if [[ $CHANGES_FOUND -eq 0 ]]; then
        echo "Agent tools: in sync"
    else
        echo "Agent tools: updated"
        echo ""
        echo "IMPORTANT: Restart gateway to apply changes:"
        echo "  ./tools/bot openclaw gateway restart"
    fi
fi
