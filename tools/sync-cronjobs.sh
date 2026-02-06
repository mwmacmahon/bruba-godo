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

# Cache bot job data (avoid repeated API calls)
BOT_JOBS_CACHE=""
get_bot_jobs_cache() {
    if [[ -z "$BOT_JOBS_CACHE" ]]; then
        BOT_JOBS_CACHE=$(./tools/bot 'openclaw cron list --json' 2>/dev/null || echo '{"jobs":[]}')
    fi
    echo "$BOT_JOBS_CACHE"
}

# Get existing cron job names from bot
get_existing_jobs() {
    get_bot_jobs_cache | python3 -c "
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
    get_bot_jobs_cache | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for job in data.get('jobs', []):
        if job.get('name', '') == '$name':
            sched = job.get('schedule', {})
            cron = sched.get('expr', '')
            tz = sched.get('tz', 'UTC')
            print(f'{cron}|{tz}')
            break
except:
    pass
" || echo ""
}

# Get all bot jobs with their schedules (returns "name|cron|timezone" per line)
get_all_bot_jobs() {
    get_bot_jobs_cache | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for job in data.get('jobs', []):
        name = job.get('name', '')
        sched = job.get('schedule', {})
        cron = sched.get('expr', '')
        tz = sched.get('tz', 'UTC')
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
    echo "$message" | bot_exec "cat > '$tmp_file'"

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
    if result=$(bot_exec "openclaw cron add \
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
        bot_exec "rm -f '$tmp_file'" 2>/dev/null || true
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
    job_id=$(get_bot_jobs_cache | python3 -c "
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

# Check mode: compare local YAML vs bot and report differences
run_check() {
    echo "Checking cron job sync status..."
    echo ""

    # Use Python to do all comparison in one pass (avoids bash associative arrays)
    local result
    result=$(python3 -c "
import yaml, json, sys, os, glob

# Parse all local YAML files
local_jobs = {}
for f in sorted(glob.glob('$CRONJOBS_DIR/*.yaml')):
    if os.path.basename(f) == 'README.yaml':
        continue
    try:
        with open(f) as fh:
            data = yaml.safe_load(fh)
        if data.get('status') == 'active' and data.get('name'):
            name = data['name']
            local_jobs[name] = {
                'cron': data.get('schedule', {}).get('cron', ''),
                'tz': data.get('schedule', {}).get('timezone', 'UTC')
            }
    except:
        pass

# Parse bot JSON from stdin
bot_jobs = {}
try:
    data = json.load(sys.stdin)
    for job in data.get('jobs', []):
        name = job.get('name', '')
        if name:
            sched = job.get('schedule', {})
            bot_jobs[name] = {
                'cron': sched.get('expr', ''),
                'tz': sched.get('tz', 'UTC')
            }
except:
    pass

has_diff = False

# Schedule mismatches
for name in sorted(local_jobs):
    if name in bot_jobs:
        l = local_jobs[name]
        b = bot_jobs[name]
        if l['cron'] != b['cron'] or l['tz'] != b['tz']:
            print(f'Schedule mismatch: {name}')
            print(f\"  Local: {l['cron']} @ {l['tz']}\")
            print(f\"  Bot:   {b['cron']} @ {b['tz']}\")
            has_diff = True

# Missing from bot
for name in sorted(local_jobs):
    if name not in bot_jobs:
        print(f'Missing from bot: {name}')
        has_diff = True

# Bot-only
for name in sorted(bot_jobs):
    if name not in local_jobs:
        print(f'Bot-only job: {name}')
        has_diff = True

sys.exit(1 if has_diff else 0)
" < <(get_bot_jobs_cache) 2>&1)

    local exit_code=$?
    echo "$result"
    echo ""

    if [[ $exit_code -ne 0 ]]; then
        echo "Differences found. Use --update to sync schedules, or run without flags to add missing jobs."
        exit 1
    else
        echo "All jobs in sync."
        exit 0
    fi
}

main() {
    log "Starting cron job sync..."

    # Check for cronjobs directory
    if [[ ! -d "$CRONJOBS_DIR" ]]; then
        echo "ERROR: cronjobs/ directory not found" >&2
        exit 1
    fi

    # Check mode
    if [[ "$CHECK" == "true" ]]; then
        run_check
    fi

    # Get existing jobs from bot
    local existing
    existing=$(get_existing_jobs)
    [[ "$VERBOSE" == "true" ]] && echo "Existing jobs on bot: $(echo "$existing" | tr '\n' ', ')"

    # Normal sync mode
    local synced=0
    local updated=0
    local skipped=0
    local warned=0
    local errors=0

    # Track local active job names for bot-only detection
    local local_job_names=""

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
            ((skipped++)) || true
            continue
        fi

        local_job_names="${local_job_names}${name}\n"

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
                        ((updated++)) || true
                    else
                        echo "ERROR: Failed to update $name" >&2
                        ((errors++)) || true
                    fi
                else
                    # Warn about schedule difference (not silently skip)
                    local current_cron current_tz
                    IFS='|' read -r current_cron current_tz <<< "$current_schedule"
                    echo "WARNING: Schedule mismatch for $name (use --update to sync)"
                    echo "  Local: $cron @ $timezone"
                    echo "  Bot:   $current_cron @ $current_tz"
                    ((warned++)) || true
                    ((skipped++)) || true
                fi
            else
                [[ "$VERBOSE" == "true" ]] && echo "Skipping $name (schedule unchanged)"
                ((skipped++)) || true
            fi
            continue
        fi

        # Validate required fields
        if [[ -z "$name" || -z "$cron" || -z "$message" ]]; then
            echo "ERROR: Invalid job definition in $filename" >&2
            ((errors++)) || true
            continue
        fi

        # Register the job
        echo "Registering: $name"
        if register_job "$name" "$cron" "$timezone" "$agent" "$session" "$message" "$description"; then
            log "Registered cron job: $name"
            ((synced++)) || true
        else
            echo "ERROR: Failed to register $name" >&2
            ((errors++)) || true
        fi
    done

    # Check for bot-only jobs (informational)
    local bot_jobs_data
    bot_jobs_data=$(get_all_bot_jobs)
    while IFS='|' read -r bot_name bot_cron bot_tz; do
        [[ -z "$bot_name" ]] && continue
        if ! echo -e "$local_job_names" | grep -q "^${bot_name}\$"; then
            echo "INFO: Bot-only job (not in local YAML): $bot_name"
        fi
    done <<< "$bot_jobs_data"

    # Summary
    echo ""
    echo "Cron sync complete:"
    echo "  Created: $synced"
    echo "  Updated: $updated"
    echo "  Skipped: $skipped"
    [[ $warned -gt 0 ]] && echo "  Warnings: $warned (schedule mismatches)" || true
    echo "  Errors: $errors"

    log "Cron sync complete: created=$synced, updated=$updated, skipped=$skipped, errors=$errors"

    [[ $errors -gt 0 ]] && exit 1
    exit 0
}

main
