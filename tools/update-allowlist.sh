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
log "Agent ID: $REMOTE_AGENT_ID"
log "Workspace: $REMOTE_WORKSPACE"

# Collect required entries from all component allowlist.json files
collect_required_entries() {
    local entries="[]"

    for allowlist_file in "$ROOT_DIR/components"/*/allowlist.json; do
        if [[ -f "$allowlist_file" ]]; then
            local component
            component=$(basename "$(dirname "$allowlist_file")")
            # Log to stderr to avoid capturing in subshell output
            echo "  Found: $component/allowlist.json" >&2

            # Read entries and expand ${WORKSPACE} placeholder
            local component_entries
            component_entries=$(jq -c '.entries' "$allowlist_file" | \
                sed "s|\${WORKSPACE}|$REMOTE_WORKSPACE|g")

            # Merge into entries array using jq properly
            entries=$(jq -n --argjson a "$entries" --argjson b "$component_entries" '$a + $b')
        fi
    done

    echo "$entries"
}

# Get current allowlist from bot
get_current_allowlist() {
    local current
    current=$(bot_cmd "cat $REMOTE_CLAWDBOT/exec-approvals.json" 2>/dev/null) || {
        log "Warning: Could not read exec-approvals.json from bot"
        echo "[]"
        return
    }

    # Extract allowlist for this agent
    echo "$current" | jq -r ".agents[\"$REMOTE_AGENT_ID\"].allowlist // []"
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
# Only considers entries matching component tool paths (~/clawd/tools/*)
find_orphan_entries() {
    local required="$1"
    local current="$2"

    # Get list of required patterns
    local required_patterns
    required_patterns=$(echo "$required" | jq -r '.[].pattern')

    # Filter current entries to those:
    # 1. Match component tool path pattern (*/clawd/tools/*)
    # 2. Not in required list
    echo "$current" | jq --arg patterns "$required_patterns" --arg workspace "$REMOTE_WORKSPACE" '
        map(select(
            (.pattern | contains("/clawd/tools/") or contains($workspace + "/tools/")) and
            (.pattern as $p | ($patterns | split("\n") | map(select(. != "")) | index($p)) == null)
        ))
    '
}

log "Collecting required entries from components..."
REQUIRED=$(collect_required_entries)
REQUIRED_COUNT=$(echo "$REQUIRED" | jq 'length')
log "Required entries: $REQUIRED_COUNT"

log "Fetching current allowlist from bot..."
CURRENT=$(get_current_allowlist)
CURRENT_COUNT=$(echo "$CURRENT" | jq 'length')
log "Current entries: $CURRENT_COUNT"

log "Finding discrepancies..."
MISSING=$(find_missing_entries "$REQUIRED" "$CURRENT")
MISSING_COUNT=$(echo "$MISSING" | jq 'length')

ORPHANS=$(find_orphan_entries "$REQUIRED" "$CURRENT")
ORPHAN_COUNT=$(echo "$ORPHANS" | jq 'length')

log "Missing entries: $MISSING_COUNT"
log "Orphan entries: $ORPHAN_COUNT"

# Check if everything is in sync
if [[ "$MISSING_COUNT" -eq 0 && "$ORPHAN_COUNT" -eq 0 ]]; then
    log "Allowlist is in sync"
    echo "Allowlist: in sync ($REQUIRED_COUNT component entries)"
    exit 0
fi

# Show discrepancies
if [[ "$MISSING_COUNT" -gt 0 ]]; then
    echo ""
    echo "Missing entries (need to add):"
    echo "$MISSING" | jq -r '.[] | "  + \(.id): \(.pattern)"'
fi

if [[ "$ORPHAN_COUNT" -gt 0 ]]; then
    echo ""
    echo "Orphan entries (not in components):"
    echo "$ORPHANS" | jq -r '.[] | "  - \(.id // "unknown"): \(.pattern)"'
fi
echo ""

# Exit if check only
if [[ "$CHECK_ONLY" == "true" ]]; then
    echo "Allowlist status:"
    [[ "$MISSING_COUNT" -gt 0 ]] && echo "  $MISSING_COUNT entries to add"
    [[ "$ORPHAN_COUNT" -gt 0 ]] && echo "  $ORPHAN_COUNT orphan entries"
    exit 0
fi

# Exit if dry run
if [[ "$DRY_RUN" == "true" ]]; then
    [[ "$MISSING_COUNT" -gt 0 ]] && echo "[DRY RUN] Would add $MISSING_COUNT entries"
    [[ "$ORPHAN_COUNT" -gt 0 ]] && echo "[DRY RUN] Would remove $ORPHAN_COUNT orphan entries"
    exit 0
fi

# Backup before any changes
BACKUP_FILE="$REMOTE_CLAWDBOT/exec-approvals.json.backup"
log "Backing up to $BACKUP_FILE..."
bot_cmd "cp $REMOTE_CLAWDBOT/exec-approvals.json $BACKUP_FILE"

CHANGES_MADE=0

# Add missing entries (unless --remove-only)
if [[ "$MISSING_COUNT" -gt 0 && "$REMOVE_ONLY" != "true" ]]; then
    log "Adding missing entries to exec-approvals.json..."
    MISSING_JSON=$(echo "$MISSING" | jq -c '.')
    bot_cmd "cat $REMOTE_CLAWDBOT/exec-approvals.json | jq --argjson new '$MISSING_JSON' '.agents[\"$REMOTE_AGENT_ID\"].allowlist += \$new' > /tmp/exec-approvals.json && mv /tmp/exec-approvals.json $REMOTE_CLAWDBOT/exec-approvals.json"
    log "Added $MISSING_COUNT entries"
    CHANGES_MADE=1
fi

# Remove orphan entries (unless --add-only)
if [[ "$ORPHAN_COUNT" -gt 0 && "$ADD_ONLY" != "true" ]]; then
    log "Removing orphan entries from exec-approvals.json..."
    # Get patterns to remove
    ORPHAN_PATTERNS=$(echo "$ORPHANS" | jq -c '[.[].pattern]')
    bot_cmd "cat $REMOTE_CLAWDBOT/exec-approvals.json | jq --argjson remove '$ORPHAN_PATTERNS' '.agents[\"$REMOTE_AGENT_ID\"].allowlist |= map(select(.pattern as \$p | (\$remove | index(\$p)) == null))' > /tmp/exec-approvals.json && mv /tmp/exec-approvals.json $REMOTE_CLAWDBOT/exec-approvals.json"
    log "Removed $ORPHAN_COUNT entries"
    CHANGES_MADE=1
fi

log "=== Update Complete ==="

echo ""
echo "Allowlist updated:"
[[ "$MISSING_COUNT" -gt 0 && "$REMOVE_ONLY" != "true" ]] && echo "  Added $MISSING_COUNT entries"
[[ "$ORPHAN_COUNT" -gt 0 && "$ADD_ONLY" != "true" ]] && echo "  Removed $ORPHAN_COUNT orphan entries"
echo "Backup saved to: $BACKUP_FILE"

if [[ "$CHANGES_MADE" -eq 1 ]]; then
    echo ""
    echo "IMPORTANT: Restart daemon to apply changes:"
    echo "  ssh $SSH_HOST 'clawdbot daemon restart'"
fi
echo ""
