#!/bin/bash
# Pull closed bot sessions locally
#
# Usage:
#   ./tools/pull-sessions.sh              # Pull new closed sessions (quiet)
#   ./tools/pull-sessions.sh --verbose    # Show detailed output
#   ./tools/pull-sessions.sh --dry-run    # Show what would be pulled
#   ./tools/pull-sessions.sh --force UUID # Force re-pull specific session
#
# Closed sessions are immutable - once pulled, they never need re-pulling.
# Active session is skipped (still being written).
#
# Output: sessions/*.jsonl (raw JSONL files)
# State: sessions/.pulled (list of pulled session IDs)
# Logs: logs/pull.log

set -e

# Load shared functions
source "$(dirname "$0")/lib.sh"

FORCE_SESSION=""

# Parse arguments
parse_common_args "$@"
set -- "${REMAINING_ARGS[@]}"

while [[ $# -gt 0 ]]; do
    case $1 in
        --force|-f)
            FORCE_SESSION="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [--dry-run] [--verbose] [--force UUID]"
            echo ""
            echo "Pull closed bot sessions locally."
            echo ""
            echo "Options:"
            echo "  --dry-run, -n     Show what would be pulled"
            echo "  --verbose, -v     Show detailed output"
            echo "  --quiet, -q       Summary output only (default)"
            echo "  --force, -f UUID  Force re-pull a specific session"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Load config
load_config

# Set up paths and logging
STATE_FILE="$SESSIONS_DIR/.pulled"
LOG_FILE="$LOG_DIR/pull.log"

mkdir -p "$SESSIONS_DIR" "$LOG_DIR"
touch "$STATE_FILE"
rotate_log "$LOG_FILE"

log "=== Pulling Bot Sessions ==="
log "Sessions dir: $SESSIONS_DIR"

# Get active session ID
log "Checking active session..."
SESSIONS_JSON=$(bot_cmd "cat $REMOTE_SESSIONS/sessions.json" 2>/dev/null) || {
    log "ERROR: Could not read sessions.json"
    exit 1
}

# Extract active session ID (Python handles the nested structure)
ACTIVE_ID=$(echo "$SESSIONS_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for key, val in data.items():
    if 'sessionId' in val:
        print(val['sessionId'])
        break
" 2>/dev/null) || {
    log "ERROR: Could not parse active session ID"
    exit 1
}

log "Active session (skipping): ${ACTIVE_ID:0:8}..."

# List all session files
SESSION_FILES=$(bot_cmd "ls $REMOTE_SESSIONS/*.jsonl 2>/dev/null" | sort) || {
    log "No session files found"
    echo "Sessions: 0 new"
    exit 0
}

# Count stats
TOTAL=0
SKIPPED_ACTIVE=0
SKIPPED_PULLED=0
PULLED=0

for session_file in $SESSION_FILES; do
    TOTAL=$((TOTAL + 1))
    session_id=$(basename "$session_file" .jsonl)

    # Skip active session
    if [[ "$session_id" == "$ACTIVE_ID" ]]; then
        log "  Skip (active): ${session_id:0:8}..."
        SKIPPED_ACTIVE=$((SKIPPED_ACTIVE + 1))
        continue
    fi

    # Skip already pulled (unless forcing)
    if [[ "$session_id" != "$FORCE_SESSION" ]] && grep -q "^$session_id$" "$STATE_FILE" 2>/dev/null; then
        log "  Skip (pulled): ${session_id:0:8}..."
        SKIPPED_PULLED=$((SKIPPED_PULLED + 1))
        continue
    fi

    output_file="$SESSIONS_DIR/$session_id.jsonl"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "  Would pull: ${session_id:0:8}..."
        PULLED=$((PULLED + 1))
        continue
    fi

    log "  Pulling: ${session_id:0:8}..."

    # Copy session file
    if ! bot_scp "$session_file" "$output_file" 2>/dev/null; then
        log "    ERROR: Failed to copy"
        continue
    fi

    # Record as pulled
    if [[ "$session_id" == "$FORCE_SESSION" ]]; then
        grep -v "^$session_id$" "$STATE_FILE" > "$STATE_FILE.tmp" 2>/dev/null || true
        mv "$STATE_FILE.tmp" "$STATE_FILE"
    fi
    echo "$session_id" >> "$STATE_FILE"

    log "    OK"
    PULLED=$((PULLED + 1))
done

log ""
log "=== Summary ==="
log "Total: $TOTAL, Active: $SKIPPED_ACTIVE, Already pulled: $SKIPPED_PULLED"
if [[ "$DRY_RUN" == "true" ]]; then
    log "Would pull: $PULLED"
else
    log "Pulled: $PULLED"
fi

echo "Sessions: $PULLED new, $SKIPPED_PULLED skipped"
