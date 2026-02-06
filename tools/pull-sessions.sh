#!/bin/bash
# Pull closed bot sessions locally and convert to delimited markdown
#
# Usage:
#   ./tools/pull-sessions.sh              # Pull new closed sessions (quiet)
#   ./tools/pull-sessions.sh --verbose    # Show detailed output
#   ./tools/pull-sessions.sh --dry-run    # Show what would be pulled
#   ./tools/pull-sessions.sh --force UUID # Force re-pull specific session
#   ./tools/pull-sessions.sh --no-convert # Skip markdown conversion
#
# Closed sessions are immutable - once pulled, they never need re-pulling.
# Active session is skipped (still being written).
#
# Pipeline (per agent with content_pipeline: true):
#   1. Pull JSONL to sessions/{agent}/
#   2. Convert to delimited markdown in intake/{agent}/ (via distill CLI)
#
# Output: sessions/{agent}/*.jsonl (raw JSONL), intake/{agent}/*.md (delimited markdown)
# State: sessions/{agent}/.pulled (list of pulled session IDs per agent)
# Logs: logs/pull.log

set -e

# Load shared functions
source "$(dirname "$0")/lib.sh"

FORCE_SESSION=""
NO_CONVERT=false

# Parse arguments (parse_common_args returns 1 for --help)
if ! parse_common_args "$@"; then
    # Show help was requested
    echo "Usage: $0 [--dry-run] [--verbose] [--force UUID] [--no-convert]"
    echo ""
    echo "Pull closed bot sessions locally and convert to delimited markdown."
    echo "Iterates over agents with content_pipeline: true in config.yaml."
    echo ""
    echo "Options:"
    echo "  --dry-run, -n     Show what would be pulled"
    echo "  --verbose, -v     Show detailed output"
    echo "  --quiet, -q       Summary output only (default)"
    echo "  --force, -f UUID  Force re-pull a specific session"
    echo "  --no-convert      Skip conversion to markdown (raw JSONL only)"
    exit 0
fi
set -- "${REMAINING_ARGS[@]}"

while [[ $# -gt 0 ]]; do
    case $1 in
        --force|-f)
            FORCE_SESSION="$2"
            shift 2
            ;;
        --no-convert)
            NO_CONVERT=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Load config
load_config

# Set up logging
LOG_FILE="$LOG_DIR/pull.log"
mkdir -p "$LOG_DIR"
rotate_log "$LOG_FILE"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Get content pipeline agents
CP_AGENTS=()
while IFS= read -r agent; do
    [[ -n "$agent" ]] && CP_AGENTS+=("$agent")
done < <(get_content_pipeline_agents)

if [[ ${#CP_AGENTS[@]} -eq 0 ]]; then
    echo "No agents with content_pipeline: true"
    exit 0
fi

log "=== Pulling Bot Sessions ==="
log "Content pipeline agents: ${CP_AGENTS[*]}"

# Grand totals
GRAND_PULLED=0
GRAND_SKIPPED=0
GRAND_CONVERTED=0

for agent in "${CP_AGENTS[@]}"; do
    load_agent_config "$agent"

    # Per-agent paths (from lib.sh load_agent_config)
    AGENT_STATE_FILE="$AGENT_SESSIONS_DIR/.pulled"

    mkdir -p "$AGENT_SESSIONS_DIR" "$AGENT_INTAKE_DIR"
    touch "$AGENT_STATE_FILE"

    log ""
    log "--- Agent: $agent ---"
    log "Sessions dir: $AGENT_SESSIONS_DIR"

    # Get active session ID for this agent
    log "Checking active session..."
    SESSIONS_JSON=$(bot_cmd "cat $AGENT_REMOTE_SESSIONS/sessions.json" 2>/dev/null) || {
        log "WARNING: Could not read sessions.json for $agent, skipping"
        continue
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
        log "WARNING: Could not parse active session ID for $agent, skipping"
        continue
    }

    log "Active session (skipping): ${ACTIVE_ID:0:8}..."

    # List all session files for this agent
    SESSION_FILES=$(bot_cmd "ls $AGENT_REMOTE_SESSIONS/*.jsonl 2>/dev/null" | sort) || {
        log "No session files found for $agent"
        continue
    }

    # Track newly pulled sessions for conversion
    NEWLY_PULLED=()

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
        if [[ "$session_id" != "$FORCE_SESSION" ]] && grep -q "^$session_id$" "$AGENT_STATE_FILE" 2>/dev/null; then
            log "  Skip (pulled): ${session_id:0:8}..."
            SKIPPED_PULLED=$((SKIPPED_PULLED + 1))
            continue
        fi

        output_file="$AGENT_SESSIONS_DIR/$session_id.jsonl"

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
            grep -v "^$session_id$" "$AGENT_STATE_FILE" > "$AGENT_STATE_FILE.tmp" 2>/dev/null || true
            mv "$AGENT_STATE_FILE.tmp" "$AGENT_STATE_FILE"
        fi
        echo "$session_id" >> "$AGENT_STATE_FILE"

        # Track for conversion
        NEWLY_PULLED+=("$output_file")

        log "    OK"
        PULLED=$((PULLED + 1))
    done

    log ""
    log "  $agent: Total: $TOTAL, Active: $SKIPPED_ACTIVE, Already pulled: $SKIPPED_PULLED"
    if [[ "$DRY_RUN" == "true" ]]; then
        log "  Would pull: $PULLED"
    else
        log "  Pulled: $PULLED"
    fi

    # Convert newly pulled sessions to delimited markdown
    CONVERTED=0
    if [[ "$NO_CONVERT" != "true" ]] && [[ "$DRY_RUN" != "true" ]] && [[ ${#NEWLY_PULLED[@]} -gt 0 ]]; then
        log ""
        log "  Converting to Markdown..."

        for jsonl_file in "${NEWLY_PULLED[@]}"; do
            session_id=$(basename "$jsonl_file" .jsonl)
            log "    Converting: ${session_id:0:8}..."

            if python3 -m components.distill.lib.cli parse-jsonl "$jsonl_file" -o "$AGENT_INTAKE_DIR" 2>/dev/null; then
                log "      -> $AGENT_INTAKE_DIR/$session_id.md"
                CONVERTED=$((CONVERTED + 1))
            else
                log "      ERROR: Conversion failed"
            fi
        done

        log "  Converted: $CONVERTED sessions"
    fi

    GRAND_PULLED=$((GRAND_PULLED + PULLED))
    GRAND_SKIPPED=$((GRAND_SKIPPED + SKIPPED_PULLED))
    GRAND_CONVERTED=$((GRAND_CONVERTED + CONVERTED))

    echo "$agent: $PULLED new, $SKIPPED_PULLED skipped, $CONVERTED converted"
done

log ""
log "=== Summary ==="

if [[ "$NO_CONVERT" == "true" ]]; then
    echo "Sessions: $GRAND_PULLED new, $GRAND_SKIPPED skipped (conversion skipped)"
elif [[ "$GRAND_CONVERTED" -gt 0 ]]; then
    echo "Sessions: $GRAND_PULLED new, $GRAND_SKIPPED skipped, $GRAND_CONVERTED converted"
else
    echo "Sessions: $GRAND_PULLED new, $GRAND_SKIPPED skipped"
fi
