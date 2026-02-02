#!/usr/bin/env bash
# sync-cronjobs.sh - Sync cron job definitions to OpenClaw
#
# Reads YAML files from cronjobs/ and registers them with the bot.
# Only syncs jobs with status: active
#
# Usage:
#   ./tools/sync-cronjobs.sh [--verbose] [--dry-run]

set -euo pipefail

# Load shared functions
source "$(dirname "$0")/lib.sh"

# Parse arguments
parse_common_args "$@"

# Setup
load_config

CRONJOBS_DIR="$ROOT_DIR/cronjobs"
LOG_FILE="$LOG_DIR/sync-cronjobs.log"

mkdir -p "$LOG_DIR"

# Get existing cron jobs from bot
get_existing_jobs() {
    ./tools/bot openclaw cron list 2>/dev/null | grep -E "^\s*-\s*" | sed 's/^[[:space:]]*-[[:space:]]*//' || echo ""
}

# Parse a single YAML cron job file
parse_cron_yaml() {
    local file="$1"
    python3 -c "
import yaml
import json
import sys

try:
    with open('$file') as f:
        data = yaml.safe_load(f)

    # Extract fields
    result = {
        'name': data.get('name', ''),
        'status': data.get('status', 'proposed'),
        'description': data.get('description', ''),
        'cron': data.get('schedule', {}).get('cron', ''),
        'timezone': data.get('schedule', {}).get('timezone', 'UTC'),
        'agent': data.get('execution', {}).get('agent', 'bruba-main'),
        'session': data.get('execution', {}).get('session', 'isolated'),
        'model': data.get('execution', {}).get('model', 'anthropic/claude-haiku-4-5'),
        'message': data.get('message', '')
    }
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({'error': str(e)}), file=sys.stderr)
    sys.exit(1)
"
}

# Register a cron job with OpenClaw
register_job() {
    local name="$1"
    local cron="$2"
    local timezone="$3"
    local agent="$4"
    local session="$5"
    local message="$6"
    local description="$7"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] Would register: $name (session: $session)"
        return 0
    fi

    # Write message to temp file on bot to avoid quoting issues
    local tmp_file="/Users/bruba/.openclaw/tmp-cron-msg-$$.txt"
    echo "$message" | ssh "$SSH_HOST" "cat > '$tmp_file'"

    # Main sessions use --system-event, isolated use --message
    local payload_flag="--message"
    if [[ "$session" == "main" ]]; then
        payload_flag="--system-event"
    fi

    # Build and run the openclaw cron add command on bot
    local result
    if result=$(ssh "$SSH_HOST" "openclaw cron add \
        --name '$name' \
        --description '$description' \
        --cron '$cron' \
        --tz '$timezone' \
        --agent '$agent' \
        --session '$session' \
        $payload_flag \"\$(cat '$tmp_file')\" \
        && rm -f '$tmp_file'" 2>&1); then
        [[ "$VERBOSE" == "true" ]] && echo "$result"
        return 0
    else
        echo "ERROR: $result" >&2
        ssh "$SSH_HOST" "rm -f '$tmp_file'" 2>/dev/null || true
        return 1
    fi
}

main() {
    log "Starting cron job sync..."

    # Check for cronjobs directory
    if [[ ! -d "$CRONJOBS_DIR" ]]; then
        echo "ERROR: cronjobs/ directory not found" >&2
        exit 1
    fi

    # Get existing jobs
    local existing
    existing=$(get_existing_jobs)
    [[ "$VERBOSE" == "true" ]] && echo "Existing jobs: $existing"

    # Process each YAML file
    local synced=0
    local skipped=0
    local errors=0

    for file in "$CRONJOBS_DIR"/*.yaml; do
        [[ ! -f "$file" ]] && continue

        local filename
        filename=$(basename "$file")

        # Skip README
        [[ "$filename" == "README.yaml" ]] && continue

        # Parse YAML
        local job_data
        job_data=$(parse_cron_yaml "$file")

        local name status description cron timezone agent session message
        name=$(echo "$job_data" | python3 -c "import json,sys; print(json.load(sys.stdin).get('name',''))")
        status=$(echo "$job_data" | python3 -c "import json,sys; print(json.load(sys.stdin).get('status','proposed'))")
        description=$(echo "$job_data" | python3 -c "import json,sys; print(json.load(sys.stdin).get('description',''))")
        cron=$(echo "$job_data" | python3 -c "import json,sys; print(json.load(sys.stdin).get('cron',''))")
        timezone=$(echo "$job_data" | python3 -c "import json,sys; print(json.load(sys.stdin).get('timezone','UTC'))")
        agent=$(echo "$job_data" | python3 -c "import json,sys; print(json.load(sys.stdin).get('agent','bruba-main'))")
        session=$(echo "$job_data" | python3 -c "import json,sys; print(json.load(sys.stdin).get('session','isolated'))")
        message=$(echo "$job_data" | python3 -c "import json,sys; print(json.load(sys.stdin).get('message',''))")

        # Skip non-active jobs
        if [[ "$status" != "active" ]]; then
            [[ "$VERBOSE" == "true" ]] && echo "Skipping $name (status: $status)"
            ((skipped++))
            continue
        fi

        # Skip if already exists
        if echo "$existing" | grep -q "^$name\$"; then
            [[ "$VERBOSE" == "true" ]] && echo "Skipping $name (already exists)"
            ((skipped++))
            continue
        fi

        # Validate required fields
        if [[ -z "$name" || -z "$cron" || -z "$message" ]]; then
            echo "ERROR: Invalid job definition in $filename" >&2
            ((errors++))
            continue
        fi

        # Register the job
        echo "Registering: $name"
        if register_job "$name" "$cron" "$timezone" "$agent" "$session" "$message" "$description"; then
            log "Registered cron job: $name"
            ((synced++))
        else
            echo "ERROR: Failed to register $name" >&2
            ((errors++))
        fi
    done

    # Summary
    echo ""
    echo "Cron sync complete:"
    echo "  Synced: $synced"
    echo "  Skipped: $skipped"
    echo "  Errors: $errors"

    log "Cron sync complete: synced=$synced, skipped=$skipped, errors=$errors"

    [[ $errors -gt 0 ]] && exit 1
    exit 0
}

main
