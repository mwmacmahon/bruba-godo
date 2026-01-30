#!/bin/bash
# Push content bundles to bot memory
#
# Usage:
#   ./tools/push.sh              # Push default bundle (bot)
#   ./tools/push.sh --dry-run    # Show what would be synced
#   ./tools/push.sh --verbose    # Detailed output
#   ./tools/push.sh --no-index   # Skip memory reindex
#
# Reads bundles.yaml for filter configuration, syncs bundles/bot/ to bot's memory/
#
# IMPORTANT: This script ADDS files to bot memory. It does NOT delete existing files.
# To sync with deletion, use rsync --delete manually with the full content set.
#
# Logs: logs/push.log

set -e

# Load shared functions
source "$(dirname "$0")/lib.sh"

# Parse arguments
NO_INDEX=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-index)
            NO_INDEX=true
            shift
            ;;
        *)
            break
            ;;
    esac
done

if ! parse_common_args "$@"; then
    echo "Usage: $0 [--dry-run] [--verbose] [--no-index]"
    echo ""
    echo "Push content bundles to bot memory."
    echo ""
    echo "Options:"
    echo "  --dry-run, -n   Show what would be synced without doing it"
    echo "  --verbose, -v   Show detailed output"
    echo "  --quiet, -q     Summary output only (default)"
    echo "  --no-index      Skip memory reindex after sync"
    exit 0
fi

# Load config
load_config

# Check prerequisites
require_commands rsync python3

# Set up logging
LOG_FILE="$LOG_DIR/push.log"
mkdir -p "$LOG_DIR"
rotate_log "$LOG_FILE"

log "=== Pushing Content to Bot ==="

# Check if bundles directory exists
if [[ ! -d "$BUNDLES_DIR/bot" ]]; then
    log "No bundle found at $BUNDLES_DIR/bot"
    log "Run bundle generation first (content from reference/ with filters from bundles.yaml)"
    echo "No bundle found. Generate bundles first."
    exit 1
fi

# Count files to sync
FILE_COUNT=$(find "$BUNDLES_DIR/bot" -type f -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
log "Files to sync: $FILE_COUNT"

if [[ "$FILE_COUNT" -eq 0 ]]; then
    log "No files to sync"
    echo "No files to sync"
    exit 0
fi

# Rsync options (no --delete to preserve existing content)
RSYNC_OPTS="-avz"
if [[ "$DRY_RUN" == "true" ]]; then
    RSYNC_OPTS="$RSYNC_OPTS --dry-run"
fi
if [[ "$VERBOSE" == "true" ]]; then
    RSYNC_OPTS="$RSYNC_OPTS --verbose"
else
    RSYNC_OPTS="$RSYNC_OPTS --quiet"
fi

# Sync to bot
log "Syncing to $SSH_HOST:$REMOTE_WORKSPACE/memory/"

if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY RUN] Would sync $FILE_COUNT files"
    rsync $RSYNC_OPTS "$BUNDLES_DIR/bot/" "$SSH_HOST:$REMOTE_WORKSPACE/memory/"
else
    rsync $RSYNC_OPTS "$BUNDLES_DIR/bot/" "$SSH_HOST:$REMOTE_WORKSPACE/memory/"
    log "Synced $FILE_COUNT files"

    # Trigger reindex
    if [[ "$NO_INDEX" != "true" ]]; then
        log "Triggering memory reindex..."
        if bot_cmd "clawdbot memory index" 2>/dev/null; then
            log "Memory indexed"
        else
            log "Warning: Memory index failed (may need manual reindex)"
        fi
    fi
fi

log "=== Push Complete ==="
echo "Push: $FILE_COUNT files"
