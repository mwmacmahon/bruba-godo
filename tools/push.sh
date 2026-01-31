#!/bin/bash
# Push content exports to bot memory
#
# Usage:
#   ./tools/push.sh              # Push default export (bot)
#   ./tools/push.sh --dry-run    # Show what would be synced
#   ./tools/push.sh --verbose    # Detailed output
#   ./tools/push.sh --no-index   # Skip memory reindex
#
# Reads exports.yaml for filter configuration, syncs exports/bot/ to bot's memory/
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

# Read remote_path from exports.yaml for bot profile
REMOTE_PATH=$(python3 -c "
import yaml
with open('$ROOT_DIR/exports.yaml') as f:
    config = yaml.safe_load(f)
    path = config.get('exports', {}).get('bot', {}).get('remote_path', 'memory')
    print(path if path else 'memory')
" 2>/dev/null || echo "memory")
if [[ -z "$REMOTE_PATH" ]]; then
    REMOTE_PATH="memory"
fi
log "Remote path: $REMOTE_PATH"

# Check if exports directory exists
if [[ ! -d "$EXPORTS_DIR/bot" ]]; then
    log "No export found at $EXPORTS_DIR/bot"
    log "Run /export first to generate filtered exports from reference/"
    echo "No export found. Run /export first."
    exit 1
fi

# Count files to sync
FILE_COUNT=$(find "$EXPORTS_DIR/bot" -type f -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
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
log "Syncing to $SSH_HOST:$REMOTE_WORKSPACE/$REMOTE_PATH/"

if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY RUN] Would sync $FILE_COUNT files"
    rsync $RSYNC_OPTS "$EXPORTS_DIR/bot/" "$SSH_HOST:$REMOTE_WORKSPACE/$REMOTE_PATH/"
else
    rsync $RSYNC_OPTS "$EXPORTS_DIR/bot/" "$SSH_HOST:$REMOTE_WORKSPACE/$REMOTE_PATH/"
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
