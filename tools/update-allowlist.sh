#!/bin/bash
# Update bot's exec-approvals allowlist with component tool entries
#
# Usage:
#   ./tools/update-allowlist.sh              # Interactive sync (add missing, remove orphans)
#   ./tools/update-allowlist.sh --check      # Check status only (no changes)
#   ./tools/update-allowlist.sh --add-only   # Only add missing entries
#   ./tools/update-allowlist.sh --dry-run    # Show what would change
#
# Reads components/*/allowlist.json files and syncs with
# the bot's ~/.clawdbot/exec-approvals.json
#
# Detects:
#   - Missing entries: in components but not on bot (need to add)
#   - Orphan entries: on bot but not in components (may need to remove)
#
# Logs: logs/allowlist.log

set -e

# Load shared functions
source "$(dirname "$0")/lib.sh"

# Parse arguments
CHECK_ONLY=false
ADD_ONLY=false
REMOVE_ONLY=false
args=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --check)
            CHECK_ONLY=true
            shift
            ;;
        --add-only)
            ADD_ONLY=true
            shift
            ;;
        --remove-only)
            REMOVE_ONLY=true
            shift
            ;;
        *)
            args+=("$1")
            shift
            ;;
    esac
done

if ! parse_common_args "${args[@]}"; then
    echo "Usage: $0 [--check] [--add-only] [--remove-only] [--dry-run] [--verbose]"
    echo ""
    echo "Sync bot's exec-approvals allowlist with component tool entries."
    echo ""
    echo "Options:"
    echo "  --check         Check status only (list discrepancies)"
    echo "  --add-only      Only add missing entries (don't remove orphans)"
    echo "  --remove-only   Only remove orphan entries (don't add missing)"
    echo "  --dry-run, -n   Show what would change without doing it"
    echo "  --verbose, -v   Show detailed output"
    exit 0
fi

# Load config
load_config

# Check prerequisites
require_commands jq

# Set up logging
LOG_FILE="$LOG_DIR/allowlist.log"
mkdir -p "$LOG_DIR"

log "=== Updating Exec-Approvals Allowlist ==="

# Get allowlist_sections for an agent from config.yaml
# Usage: get_allowlist_sections "bruba-main"
# Outputs: component names, one per line
get_allowlist_sections() {
    local agent_name="$1"
    local config_file="$ROOT_DIR/config.yaml"

    python3 -c "
import yaml
import sys
try:
    with open('$config_file') as f:
        config = yaml.safe_load(f)
    sections = config.get('agents', {}).get('$agent_name', {}).get('allowlist_sections', [])
    for s in sections:
        print(s)
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null
}

# Get all agents that have allowlist_sections defined
# Usage: get_agents_with_allowlists
# Outputs: agent names, one per line
get_agents_with_allowlists() {
    local config_file="$ROOT_DIR/config.yaml"

    python3 -c "
import yaml
import sys
try:
    with open('$config_file') as f:
        config = yaml.safe_load(f)
    for name, cfg in config.get('agents', {}).items():
        if cfg and cfg.get('allowlist_sections'):
            print(name)
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null
}

# Get workspace for an agent from config.yaml
# Usage: get_agent_workspace "bruba-main"
get_agent_workspace() {
    local agent_name="$1"
    local config_file="$ROOT_DIR/config.yaml"

    python3 -c "
import yaml
import sys
try:
    with open('$config_file') as f:
        config = yaml.safe_load(f)
    workspace = config.get('agents', {}).get('$agent_name', {}).get('workspace', '')
    print(workspace or '')
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null
}

# Collect required entries from configured component allowlist.json files
# Usage: collect_required_entries "bruba-main" "/Users/bruba/agents/bruba-main"
collect_required_entries() {
    local agent_name="$1"
    local workspace="$2"
    local entries="[]"

    # Get configured components for this agent
    local components
    components=$(get_allowlist_sections "$agent_name")

    if [[ -z "$components" ]]; then
        echo "[]"
        return
    fi

    while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue

        # Parse component:variant syntax
        local component="$entry"
        local variant=""
        if [[ "$entry" == *:* ]]; then
            component="${entry%%:*}"
            variant="${entry#*:}"
        fi

        # Resolve to exactly one file (no fallback)
        local allowlist_file
        if [[ -n "$variant" ]]; then
            allowlist_file="$ROOT_DIR/components/$component/allowlist.${variant}.json"
        else
            allowlist_file="$ROOT_DIR/components/$component/allowlist.json"
        fi

        if [[ -f "$allowlist_file" ]]; then
            # Log to stderr to avoid capturing in subshell output
            echo "  Found: $entry → $(basename "$allowlist_file")" >&2

            # Read entries and expand ${WORKSPACE} and ${SHARED_TOOLS} placeholders
            local component_entries
            component_entries=$(jq -c '.entries' "$allowlist_file" | \
                sed -e "s|\${WORKSPACE}|$workspace|g" \
                    -e "s|\${SHARED_TOOLS}|$SHARED_TOOLS|g")

            # Merge into entries array using jq properly
            entries=$(jq -n --argjson a "$entries" --argjson b "$component_entries" '$a + $b')
        else
            echo "  Warning: $entry has no allowlist file" >&2
        fi
    done <<< "$components"

    echo "$entries"
}

# Get current allowlist from bot for an agent
# Usage: get_current_allowlist "bruba-main"
get_current_allowlist() {
    local agent_name="$1"
    local current
    current=$(bot_cmd "cat $REMOTE_OPENCLAW/exec-approvals.json" 2>/dev/null) || {
        log "Warning: Could not read exec-approvals.json from bot"
        echo "[]"
        return
    }

    # Extract allowlist for this agent
    echo "$current" | jq -r ".agents[\"$agent_name\"].allowlist // []"
}

# Find entries that are required but not present (need to add)
find_missing_entries() {
    local required="$1"
    local current="$2"

    # Get list of current patterns
    local current_patterns
    current_patterns=$(echo "$current" | jq -r '.[].pattern')

    # Filter required entries to those not in current
    echo "$required" | jq --arg patterns "$current_patterns" '
        map(select(.pattern as $p | ($patterns | split("\n") | map(select(. != "")) | index($p)) == null))
    '
}

# Find entries on bot that are not in required list (orphans to remove)
# Matches any path containing /tools/ (clawd, per-agent, shared, legacy locations)
# Usage: find_orphan_entries "$required" "$current" "$workspace"
find_orphan_entries() {
    local required="$1"
    local current="$2"
    local workspace="$3"

    # Get list of required patterns
    local required_patterns
    required_patterns=$(echo "$required" | jq -r '.[].pattern')

    # Filter current entries to those:
    # 1. Match any tools path pattern (covers clawd, per-agent, shared, and legacy locations)
    # 2. Not in required list
    echo "$current" | jq --arg patterns "$required_patterns" --arg workspace "$workspace" '
        map(select(
            (.pattern | contains("/tools/")) and
            (.pattern as $p | ($patterns | split("\n") | map(select(. != "")) | index($p)) == null)
        ))
    '
}

# Get list of agents with allowlist_sections
AGENTS_WITH_ALLOWLISTS=$(get_agents_with_allowlists)

if [[ -z "$AGENTS_WITH_ALLOWLISTS" ]]; then
    log "No agents have allowlist_sections configured"
    echo "No agents have allowlist_sections configured in config.yaml"
    exit 0
fi

# Track overall state
TOTAL_MISSING=0
TOTAL_ORPHANS=0
TOTAL_REQUIRED=0
BACKUP_DONE=false
CHANGES_MADE=0
ADDED_COUNT=0
REMOVED_COUNT=0

# Process each agent - collect info, show discrepancies, and update in one pass
process_agent() {
    local agent="$1"
    local workspace

    workspace=$(get_agent_workspace "$agent")
    if [[ -z "$workspace" ]]; then
        log "Warning: $agent has no workspace configured, skipping"
        return
    fi

    local components
    components=$(get_allowlist_sections "$agent")
    local component_count
    component_count=$(echo "$components" | grep -c . 2>/dev/null || echo "0")

    log ""
    log "Agent: $agent ($component_count components)"
    log "Workspace: $workspace"

    log "Collecting required entries..."
    local required
    required=$(collect_required_entries "$agent" "$workspace")
    local required_count
    required_count=$(echo "$required" | jq 'length')
    TOTAL_REQUIRED=$((TOTAL_REQUIRED + required_count))
    log "Required entries: $required_count"

    log "Fetching current allowlist..."
    local current
    current=$(get_current_allowlist "$agent")
    local current_count
    current_count=$(echo "$current" | jq 'length')
    log "Current entries: $current_count"

    log "Finding discrepancies..."
    local missing
    missing=$(find_missing_entries "$required" "$current")
    local missing_count
    missing_count=$(echo "$missing" | jq 'length')
    TOTAL_MISSING=$((TOTAL_MISSING + missing_count))

    local orphans
    orphans=$(find_orphan_entries "$required" "$current" "$workspace")
    local orphan_count
    orphan_count=$(echo "$orphans" | jq 'length')
    TOTAL_ORPHANS=$((TOTAL_ORPHANS + orphan_count))

    log "Missing: $missing_count, Orphans: $orphan_count"

    # Show discrepancies for this agent
    if [[ "$missing_count" -gt 0 || "$orphan_count" -gt 0 ]]; then
        echo ""
        echo "Agent: $agent"

        if [[ "$missing_count" -gt 0 ]]; then
            echo "  Missing entries (need to add):"
            echo "$missing" | jq -r '.[] | "    + \(.id): \(.pattern)"'
        fi

        if [[ "$orphan_count" -gt 0 ]]; then
            echo "  Orphan entries (not in components):"
            echo "$orphans" | jq -r '.[] | "    - \(.id // "unknown"): \(.pattern)"'
        fi
    fi

    # If check-only or dry-run, don't make changes
    if [[ "$CHECK_ONLY" == "true" ]]; then
        return
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        return
    fi

    # Backup before first change
    if [[ "$BACKUP_DONE" != "true" && ("$missing_count" -gt 0 || "$orphan_count" -gt 0) ]]; then
        BACKUP_FILE="$REMOTE_OPENCLAW/exec-approvals.json.backup"
        log "Backing up to $BACKUP_FILE..."
        bot_cmd "cp $REMOTE_OPENCLAW/exec-approvals.json $BACKUP_FILE"
        BACKUP_DONE=true
    fi

    # Add missing entries (unless --remove-only)
    if [[ "$missing_count" -gt 0 && "$REMOVE_ONLY" != "true" ]]; then
        log "Adding $missing_count entries for $agent..."
        local missing_json
        missing_json=$(echo "$missing" | jq -c '.')

        # Do the jq update locally, then push the result
        local current_json
        current_json=$(bot_cmd "cat $REMOTE_OPENCLAW/exec-approvals.json")
        local updated_json
        updated_json=$(echo "$current_json" | jq --arg agent "$agent" --argjson new "$missing_json" '.agents[$agent].allowlist += $new')

        # Write to temp file and copy to bot
        local tmp_file="/tmp/exec-approvals-$$.json"
        echo "$updated_json" > "$tmp_file"

        case "$BOT_TRANSPORT" in
            sudo)
                # Copy via sudo as bot user
                cat "$tmp_file" | sudo -u "$BOT_USER" tee "$REMOTE_OPENCLAW/exec-approvals.json" > /dev/null
                ;;
            *)
                scp $SSH_OPTS -q "$tmp_file" "$BOT_USER@$BOT_HOST:$REMOTE_OPENCLAW/exec-approvals.json"
                ;;
        esac
        rm -f "$tmp_file"

        ADDED_COUNT=$((ADDED_COUNT + missing_count))
        CHANGES_MADE=1
    fi

    # Remove orphan entries (unless --add-only)
    if [[ "$orphan_count" -gt 0 && "$ADD_ONLY" != "true" ]]; then
        log "Removing $orphan_count orphan entries for $agent..."
        # Get patterns to remove
        local orphan_patterns
        orphan_patterns=$(echo "$orphans" | jq -c '[.[].pattern]')

        # Do the jq update locally, then push the result
        local current_json
        current_json=$(bot_cmd "cat $REMOTE_OPENCLAW/exec-approvals.json")
        local updated_json
        updated_json=$(echo "$current_json" | jq --arg agent "$agent" --argjson remove "$orphan_patterns" '.agents[$agent].allowlist |= map(select(.pattern as $p | ($remove | index($p)) == null))')

        # Write to temp file and copy to bot
        local tmp_file="/tmp/exec-approvals-$$.json"
        echo "$updated_json" > "$tmp_file"

        case "$BOT_TRANSPORT" in
            sudo)
                # Copy via sudo as bot user
                cat "$tmp_file" | sudo -u "$BOT_USER" tee "$REMOTE_OPENCLAW/exec-approvals.json" > /dev/null
                ;;
            *)
                scp $SSH_OPTS -q "$tmp_file" "$BOT_USER@$BOT_HOST:$REMOTE_OPENCLAW/exec-approvals.json"
                ;;
        esac
        rm -f "$tmp_file"

        REMOVED_COUNT=$((REMOVED_COUNT + orphan_count))
        CHANGES_MADE=1
    fi
}

# Process each agent
while IFS= read -r agent; do
    [[ -z "$agent" ]] && continue
    process_agent "$agent"
done <<< "$AGENTS_WITH_ALLOWLISTS"

# Handle check-only and dry-run exits
if [[ "$CHECK_ONLY" == "true" ]]; then
    echo ""
    if [[ "$TOTAL_MISSING" -eq 0 && "$TOTAL_ORPHANS" -eq 0 ]]; then
        echo "Allowlists: in sync ($TOTAL_REQUIRED total component entries)"
        while IFS= read -r agent; do
            [[ -z "$agent" ]] && continue
            components=$(get_allowlist_sections "$agent")
            component_list=$(echo "$components" | tr '\n' ',' | sed 's/,$//')
            echo "  $agent: $component_list"
        done <<< "$AGENTS_WITH_ALLOWLISTS"
    else
        echo "Allowlist status:"
        [[ "$TOTAL_MISSING" -gt 0 ]] && echo "  $TOTAL_MISSING entries to add"
        [[ "$TOTAL_ORPHANS" -gt 0 ]] && echo "  $TOTAL_ORPHANS orphan entries"
    fi
    exit 0
fi

if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    if [[ "$TOTAL_MISSING" -eq 0 && "$TOTAL_ORPHANS" -eq 0 ]]; then
        echo "Allowlists: in sync ($TOTAL_REQUIRED total component entries)"
    else
        [[ "$TOTAL_MISSING" -gt 0 ]] && echo "[DRY RUN] Would add $TOTAL_MISSING entries"
        [[ "$TOTAL_ORPHANS" -gt 0 ]] && echo "[DRY RUN] Would remove $TOTAL_ORPHANS orphan entries"
    fi
    exit 0
fi

# Check if everything was already in sync
if [[ "$TOTAL_MISSING" -eq 0 && "$TOTAL_ORPHANS" -eq 0 ]]; then
    log ""
    log "All allowlists are in sync"
    echo ""
    echo "Allowlists: in sync ($TOTAL_REQUIRED total component entries)"
    while IFS= read -r agent; do
        [[ -z "$agent" ]] && continue
        components=$(get_allowlist_sections "$agent")
        component_list=$(echo "$components" | tr '\n' ',' | sed 's/,$//')
        echo "  $agent: $component_list"
    done <<< "$AGENTS_WITH_ALLOWLISTS"
    exit 0
fi

log "=== Update Complete ==="

echo ""
echo "Allowlist updated:"
[[ "$ADDED_COUNT" -gt 0 ]] && echo "  Added $ADDED_COUNT entries"
[[ "$REMOVED_COUNT" -gt 0 ]] && echo "  Removed $REMOVED_COUNT orphan entries"
echo "Backup saved to: $BACKUP_FILE"

if [[ "$CHANGES_MADE" -eq 1 ]]; then
    echo ""
    echo "IMPORTANT: Restart daemon to apply changes:"
    echo "  openclaw gateway restart"
fi
echo ""
