#!/usr/bin/env bash
# sync-cronjobs.sh - Sync cron job definitions to OpenClaw
#
# Reads YAML files from cronjobs/ and registers them with the bot.
# Only syncs jobs with status: active
#
# Usage:
#   ./tools/sync-cronjobs.sh [--verbose] [--dry-run] [--update] [--check]
#
# Options:
#   --update    Update existing jobs if schedule differs from local YAML
#   --check     Check for drift without making changes (exits 1 if differences found)

set -euo pipefail

# Load shared functions
source "$(dirname "$0")/lib.sh"

# Parse arguments
UPDATE=false
CHECK=false
for arg in "$@"; do
    case "$arg" in
        --update) UPDATE=true ;;
        --check) CHECK=true ;;
    esac
done
parse_common_args "$@"

# Setup
load_config

CRONJOBS_DIR="$ROOT_DIR/cronjobs"
LOG_FILE="$LOG_DIR/sync-cronjobs.log"

mkdir -p "$LOG_DIR"

# Get existing cron jobs from bot (using --json for reliable parsing)
get_existing_jobs() {
    ./tools/bot openclaw cron list --json 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for job in data.get('jobs', []):
        print(job.get('name', ''))
except:
    pass
" || echo ""
}

# Get schedule for a specific job (returns "cron|timezone" or empty)
get_job_schedule() {
    local name="$1"
    ./tools/bot openclaw cron list --json 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for job in data.get('jobs', []):
        if job.get('name', '') == '$name':
            cron = job.get('cron', '')
            tz = job.get('timezone', 'UTC')
            print(f'{cron}|{tz}')
            break
except:
    pass
" || echo ""
}

# Get all bot jobs with their schedules (returns "name|cron|timezone" per line)
get_all_bot_jobs() {
    ./tools/bot openclaw cron list --json 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for job in data.get('jobs', []):
        name = job.get('name', '')
        cron = job.get('cron', '')
        tz = job.get('timezone', 'UTC')
        if name:
            print(f'{name}|{cron}|{tz}')
except:
    pass
" || echo ""
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

    # Main sessions use --system-event + --wake now (agent has no heartbeat)
    # Isolated sessions use --message (default wake mode is fine)
    local payload_flag="--message"
    local wake_flag=""
    if [[ "$session" == "main" ]]; then
        payload_flag="--system-event"
        wake_flag="--wake now"
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
        $wake_flag \
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

# Update an existing cron job's schedule
update_job() {
    local name="$1"
    local cron="$2"
    local timezone="$3"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] Would update: $name to '$cron' @ $timezone"
        return 0
    fi

    # Get job ID from name
    local job_id
    job_id=$(./tools/bot openclaw cron list --json 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for job in data.get('jobs', []):
        if job.get('name', '') == '$name':
            print(job.get('id', ''))
            break
except:
    pass
" || echo "")

    if [[ -z "$job_id" ]]; then
        echo "ERROR: Could not find job ID for $name" >&2
        return 1
    fi

    # Update the job using openclaw cron edit
    local result
    if result=$(./tools/bot "openclaw cron edit $job_id --cron '$cron' --tz '$timezone'" 2>&1); then
        [[ "$VERBOSE" == "true" ]] && echo "$result"
        return 0
    else
        echo "ERROR: $result" >&2
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

    # Get existing jobs from bot
    local existing
    existing=$(get_existing_jobs)
    [[ "$VERBOSE" == "true" ]] && echo "Existing jobs: $existing"

    # Build list of local job names (active only)
    local local_jobs=()
    declare -A local_schedules

    for file in "$CRONJOBS_DIR"/*.yaml; do
        [[ ! -f "$file" ]] && continue
        [[ "$(basename "$file")" == "README.yaml" ]] && continue

        local job_data
        job_data=$(parse_cron_yaml "$file")

        local name status cron timezone
        name=$(echo "$job_data" | python3 -c "import json,sys; print(json.load(sys.stdin).get('name',''))")
        status=$(echo "$job_data" | python3 -c "import json,sys; print(json.load(sys.stdin).get('status','proposed'))")
        cron=$(echo "$job_data" | python3 -c "import json,sys; print(json.load(sys.stdin).get('cron',''))")
        timezone=$(echo "$job_data" | python3 -c "import json,sys; print(json.load(sys.stdin).get('timezone','UTC'))")

        if [[ "$status" == "active" && -n "$name" ]]; then
            local_jobs+=("$name")
            local_schedules["$name"]="$cron|$timezone"
        fi
    done

    # Check mode: compare local vs bot and report differences
    if [[ "$CHECK" == "true" ]]; then
        local has_differences=false

        echo "Checking cron job sync status..."
        echo ""

        # Get all bot jobs with schedules
        local bot_jobs_data
        bot_jobs_data=$(get_all_bot_jobs)

        # Build bot job map
        declare -A bot_schedules
        while IFS='|' read -r bot_name bot_cron bot_tz; do
            [[ -z "$bot_name" ]] && continue
            bot_schedules["$bot_name"]="$bot_cron|$bot_tz"
        done <<< "$bot_jobs_data"

        # Check for schedule mismatches (jobs in both local and bot)
        for name in "${local_jobs[@]}"; do
            if [[ -n "${bot_schedules[$name]:-}" ]]; then
                local local_sched="${local_schedules[$name]}"
                local bot_sched="${bot_schedules[$name]}"
                if [[ "$local_sched" != "$bot_sched" ]]; then
                    local local_cron local_tz bot_cron bot_tz
                    IFS='|' read -r local_cron local_tz <<< "$local_sched"
                    IFS='|' read -r bot_cron bot_tz <<< "$bot_sched"
                    echo "Schedule mismatch: $name"
                    echo "  Local: $local_cron @ $local_tz"
                    echo "  Bot:   $bot_cron @ $bot_tz"
                    has_differences=true
                fi
            fi
        done

        # Check for YAML-only jobs (exist locally but not on bot)
        for name in "${local_jobs[@]}"; do
            if [[ -z "${bot_schedules[$name]:-}" ]]; then
                echo "Missing from bot: $name"
                has_differences=true
            fi
        done

        # Check for bot-only jobs (exist on bot but not in YAML)
        for bot_name in "${!bot_schedules[@]}"; do
            local found=false
            for name in "${local_jobs[@]}"; do
                if [[ "$name" == "$bot_name" ]]; then
                    found=true
                    break
                fi
            done
            if [[ "$found" == "false" ]]; then
                echo "Bot-only job: $bot_name"
                has_differences=true
            fi
        done

        echo ""
        if [[ "$has_differences" == "true" ]]; then
            echo "Differences found. Use --update to sync schedules, or run without flags to add missing jobs."
            exit 1
        else
            echo "All jobs in sync."
            exit 0
        fi
    fi

    # Normal sync mode
    local synced=0
    local updated=0
    local skipped=0
    local warned=0
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

        # Handle existing jobs
        if echo "$existing" | grep -q "^$name\$"; then
            # Check if schedule differs
            local current_schedule
            current_schedule=$(get_job_schedule "$name")
            local local_schedule="$cron|$timezone"

            if [[ "$current_schedule" != "$local_schedule" ]]; then
                if [[ "$UPDATE" == "true" ]]; then
                    echo "Updating: $name (schedule changed)"
                    [[ "$VERBOSE" == "true" ]] && echo "  $current_schedule -> $local_schedule"
                    if update_job "$name" "$cron" "$timezone"; then
                        log "Updated cron job: $name"
                        ((updated++))
                    else
                        echo "ERROR: Failed to update $name" >&2
                        ((errors++))
                    fi
                else
                    # Warn about schedule difference (not silently skip)
                    local current_cron current_tz
                    IFS='|' read -r current_cron current_tz <<< "$current_schedule"
                    echo "WARNING: Schedule mismatch for $name (use --update to sync)"
                    echo "  Local: $cron @ $timezone"
                    echo "  Bot:   $current_cron @ $current_tz"
                    ((warned++))
                    ((skipped++))
                fi
            else
                [[ "$VERBOSE" == "true" ]] && echo "Skipping $name (schedule unchanged)"
                ((skipped++))
            fi
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

    # Check for bot-only jobs (informational)
    local bot_jobs_data
    bot_jobs_data=$(get_all_bot_jobs)
    while IFS='|' read -r bot_name bot_cron bot_tz; do
        [[ -z "$bot_name" ]] && continue
        local found=false
        for name in "${local_jobs[@]}"; do
            if [[ "$name" == "$bot_name" ]]; then
                found=true
                break
            fi
        done
        if [[ "$found" == "false" ]]; then
            echo "INFO: Bot-only job (not in local YAML): $bot_name"
        fi
    done <<< "$bot_jobs_data"

    # Summary
    echo ""
    echo "Cron sync complete:"
    echo "  Created: $synced"
    echo "  Updated: $updated"
    echo "  Skipped: $skipped"
    [[ $warned -gt 0 ]] && echo "  Warnings: $warned (schedule mismatches)"
    echo "  Errors: $errors"

    log "Cron sync complete: created=$synced, updated=$updated, skipped=$skipped, errors=$errors"

    [[ $errors -gt 0 ]] && exit 1
    exit 0
}

main
