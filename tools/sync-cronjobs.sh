#!/usr/bin/env bash
# sync-cronjobs.sh - Sync cron job definitions to OpenClaw
#
# Reads YAML files from cronjobs/ and registers them with the bot.
# Only syncs jobs with status: active
#
# Usage:
#   ./tools/sync-cronjobs.sh [--verbose] [--dry-run] [--update] [--check] [--delete] [--force]
#
# Options:
#   --update    Update existing jobs if any fields differ from local YAML
#   --check     Check for drift without making changes (exits 1 if differences found)
#   --delete    With --update: remove bot-only jobs not in local YAML (prompts for confirmation)
#   --force     With --update: skip confirmation prompts

set -euo pipefail

# Load shared functions
source "$(dirname "$0")/lib.sh"

# Parse arguments
UPDATE=false
CHECK=false
DELETE=false
FORCE=false
for arg in "$@"; do
    case "$arg" in
        --update) UPDATE=true ;;
        --check) CHECK=true ;;
        --delete) DELETE=true ;;
        --force) FORCE=true ;;
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

# Get a specific field for a job by name
# Usage: get_job_field <name> <python_expr>
get_job_field() {
    local name="$1"
    local expr="$2"
    get_bot_jobs_cache | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for job in data.get('jobs', []):
        if job.get('name', '') == '$name':
            $expr
            break
except:
    pass
" || echo ""
}

# Get schedule for a specific job (returns "cron|timezone" or empty)
get_job_schedule() {
    get_job_field "$1" "
            sched = job.get('schedule', {})
            cron = sched.get('expr', '')
            tz = sched.get('tz', 'UTC')
            print(f'{cron}|{tz}')"
}

# Get job message from name
get_job_message() {
    get_job_field "$1" "
            payload = job.get('payload', {})
            print(payload.get('message', ''))"
}

# Get job description from name
get_job_description() {
    get_job_field "$1" "print(job.get('description', ''))"
}

# Get job model from name
get_job_model() {
    get_job_field "$1" "
            payload = job.get('payload', {})
            print(payload.get('model', ''))"
}

# Get job agent from name
get_job_agent() {
    get_job_field "$1" "print(job.get('agentId', ''))"
}

# Get job session target from name
get_job_session() {
    get_job_field "$1" "print(job.get('sessionTarget', ''))"
}

# Get job ID from name
get_job_id() {
    get_job_field "$1" "print(job.get('id', ''))"
}

# Get all bot job names
get_all_bot_job_names() {
    get_bot_jobs_cache | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for job in data.get('jobs', []):
        name = job.get('name', '')
        if name:
            print(name)
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

# Normalize a string for comparison (trim trailing whitespace/newlines)
normalize_str() {
    echo "$1" | sed 's/[[:space:]]*$//'
}

# Compare local vs bot values and return list of changed fields
# Sets CHANGED_FIELDS variable
detect_changes() {
    local name="$1"
    local cron="$2"
    local timezone="$3"
    local message="$4"
    local description="$5"
    local model="$6"
    local agent="$7"
    local session="$8"

    CHANGED_FIELDS=""

    # Schedule
    local current_schedule
    current_schedule=$(get_job_schedule "$name")
    local local_schedule="$cron|$timezone"
    [[ "$current_schedule" != "$local_schedule" ]] && CHANGED_FIELDS="${CHANGED_FIELDS}schedule " || true

    # Message (trim trailing whitespace for comparison — YAML block scalars add trailing newline)
    local current_msg
    current_msg=$(get_job_message "$name")
    local trimmed_msg trimmed_current
    trimmed_msg=$(normalize_str "$message")
    trimmed_current=$(normalize_str "$current_msg")
    [[ "$trimmed_current" != "$trimmed_msg" ]] && CHANGED_FIELDS="${CHANGED_FIELDS}message " || true

    # Description
    local current_desc
    current_desc=$(get_job_description "$name")
    [[ "$current_desc" != "$description" ]] && CHANGED_FIELDS="${CHANGED_FIELDS}description " || true

    # Model
    local current_model
    current_model=$(get_job_model "$name")
    [[ -n "$model" && "$current_model" != "$model" ]] && CHANGED_FIELDS="${CHANGED_FIELDS}model " || true

    # Agent
    local current_agent
    current_agent=$(get_job_agent "$name")
    [[ -n "$agent" && "$current_agent" != "$agent" ]] && CHANGED_FIELDS="${CHANGED_FIELDS}agent " || true

    # Session target
    local current_session
    current_session=$(get_job_session "$name")
    [[ -n "$session" && "$current_session" != "$session" ]] && CHANGED_FIELDS="${CHANGED_FIELDS}session " || true
}

# Update an existing cron job
update_job() {
    local name="$1"
    local cron="$2"
    local timezone="$3"
    local message="$4"
    local description="$5"
    local model="$6"

    local job_id
    job_id=$(get_job_id "$name")

    if [[ -z "$job_id" ]]; then
        echo "ERROR: Could not find job ID for $name" >&2
        return 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] Would update: $name ($job_id)"
        return 0
    fi

    # Write message to temp file on bot, build a single edit command
    local tmp_file="/Users/bruba/.openclaw/tmp-cron-msg-$$.txt"
    echo "$message" | bot_exec "cat > '$tmp_file'"

    local result
    if result=$(bot_exec "openclaw cron edit '$job_id' \
        --cron '$cron' \
        --tz '$timezone' \
        --description '$description' \
        --model '$model' \
        --message \"\$(cat '$tmp_file')\" \
        && rm -f '$tmp_file'" 2>&1); then
        [[ "$VERBOSE" == "true" ]] && echo "$result"
        return 0
    else
        echo "ERROR: edit command failed for $name — $result" >&2
        bot_exec "rm -f '$tmp_file'" 2>/dev/null || true
        return 1
    fi
}

# Delete a cron job by name
delete_job() {
    local name="$1"
    local job_id
    job_id=$(get_job_id "$name")

    if [[ -z "$job_id" ]]; then
        echo "ERROR: Could not find job ID for $name" >&2
        return 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] Would delete: $name ($job_id)"
        return 0
    fi

    local result
    if result=$(bot_exec "openclaw cron rm '$job_id'" 2>&1); then
        [[ "$VERBOSE" == "true" ]] && echo "$result"
        return 0
    else
        echo "ERROR: delete failed for $name — $result" >&2
        return 1
    fi
}

# Check mode: compare local YAML vs bot and report differences
run_check() {
    echo "Checking cron job sync status..."
    echo ""

    # Use Python to do full comparison in one pass
    local result
    set +e
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
                'tz': data.get('schedule', {}).get('timezone', 'UTC'),
                'description': data.get('description', ''),
                'model': data.get('execution', {}).get('model', ''),
                'agent': data.get('execution', {}).get('agent', ''),
                'session': data.get('execution', {}).get('session', ''),
                'message': data.get('message', '').rstrip(),
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
            payload = job.get('payload', {})
            bot_jobs[name] = {
                'cron': sched.get('expr', ''),
                'tz': sched.get('tz', 'UTC'),
                'description': job.get('description', ''),
                'model': payload.get('model', ''),
                'agent': job.get('agentId', ''),
                'session': job.get('sessionTarget', ''),
                'message': payload.get('message', '').rstrip(),
            }
except:
    pass

has_diff = False

# Compare matching jobs across all fields
field_labels = {
    'cron': 'Schedule',
    'tz': 'Timezone',
    'description': 'Description',
    'model': 'Model',
    'agent': 'Agent',
    'session': 'Session',
    'message': 'Message',
}
for name in sorted(local_jobs):
    if name in bot_jobs:
        l = local_jobs[name]
        b = bot_jobs[name]
        diffs = []
        for key in ['cron', 'tz', 'description', 'model', 'agent', 'session', 'message']:
            lv = l.get(key, '')
            bv = b.get(key, '')
            if lv and lv != bv:
                diffs.append(key)
        if diffs:
            diff_names = ', '.join(field_labels.get(d, d) for d in diffs)
            print(f'DRIFT: {name} — changed: {diff_names}')
            for d in diffs:
                lv = l.get(d, '')
                bv = b.get(d, '')
                label = field_labels.get(d, d)
                if d == 'message':
                    # Just show first line for messages
                    l_first = lv.split(chr(10))[0][:80]
                    b_first = bv.split(chr(10))[0][:80]
                    print(f'  {label}: local=\"{l_first}...\" bot=\"{b_first}...\"')
                else:
                    print(f'  {label}: local=\"{lv}\" bot=\"{bv}\"')
            has_diff = True

# Missing from bot
for name in sorted(local_jobs):
    if name not in bot_jobs:
        print(f'MISSING: {name} (not on bot)')
        has_diff = True

# Bot-only
bot_only = 0
for name in sorted(bot_jobs):
    if name not in local_jobs:
        print(f'ORPHAN: {name} (bot-only, not in local YAML)')
        bot_only += 1
        has_diff = True

sys.exit(1 if has_diff else 0)
" < <(get_bot_jobs_cache) 2>&1)
    local exit_code=$?
    set -e
    echo "$result"
    echo ""

    if [[ $exit_code -ne 0 ]]; then
        echo "Differences found. Use --update to sync, --update --delete to also remove orphans."
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
    local orphans=0
    local deleted=0

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

        local name status description cron timezone agent session message model
        name=$(echo "$job_data" | python3 -c "import json,sys; print(json.load(sys.stdin).get('name',''))")
        status=$(echo "$job_data" | python3 -c "import json,sys; print(json.load(sys.stdin).get('status','proposed'))")
        description=$(echo "$job_data" | python3 -c "import json,sys; print(json.load(sys.stdin).get('description',''))")
        cron=$(echo "$job_data" | python3 -c "import json,sys; print(json.load(sys.stdin).get('cron',''))")
        timezone=$(echo "$job_data" | python3 -c "import json,sys; print(json.load(sys.stdin).get('timezone','UTC'))")
        agent=$(echo "$job_data" | python3 -c "import json,sys; print(json.load(sys.stdin).get('agent','bruba-main'))")
        session=$(echo "$job_data" | python3 -c "import json,sys; print(json.load(sys.stdin).get('session','isolated'))")
        message=$(echo "$job_data" | python3 -c "import json,sys; print(json.load(sys.stdin).get('message',''))")
        model=$(echo "$job_data" | python3 -c "import json,sys; print(json.load(sys.stdin).get('model',''))")

        # Skip non-active jobs
        if [[ "$status" != "active" ]]; then
            [[ "$VERBOSE" == "true" ]] && echo "Skipping $name (status: $status)"
            ((skipped++)) || true
            continue
        fi

        local_job_names="${local_job_names}${name}\n"

        # Handle existing jobs
        if echo "$existing" | grep -q "^$name\$"; then
            # Detect all changes
            detect_changes "$name" "$cron" "$timezone" "$message" "$description" "$model" "$agent" "$session"

            if [[ -n "$CHANGED_FIELDS" ]]; then
                if [[ "$UPDATE" == "true" ]]; then
                    echo "Updating: $name (changed: ${CHANGED_FIELDS% })"
                    if update_job "$name" "$cron" "$timezone" "$message" "$description" "$model"; then
                        log "Updated cron job: $name"
                        ((updated++)) || true
                    else
                        echo "ERROR: Failed to update $name" >&2
                        ((errors++)) || true
                    fi
                else
                    echo "WARNING: Changes detected for $name (use --update to sync)"
                    echo "  Changed: ${CHANGED_FIELDS% }"
                    ((warned++)) || true
                    ((skipped++)) || true
                fi
            else
                [[ "$VERBOSE" == "true" ]] && echo "Skipping $name (no changes)"
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

    # Check for bot-only jobs (orphans)
    local bot_job_names
    bot_job_names=$(get_all_bot_job_names)
    while IFS= read -r bot_name; do
        [[ -z "$bot_name" ]] && continue
        if ! echo -e "$local_job_names" | grep -q "^${bot_name}\$"; then
            ((orphans++)) || true
            if [[ "$DELETE" == "true" && "$UPDATE" == "true" ]]; then
                if [[ "$FORCE" == "true" ]]; then
                    echo "Deleting orphan: $bot_name"
                    if delete_job "$bot_name"; then
                        log "Deleted orphan cron job: $bot_name"
                        ((deleted++)) || true
                    else
                        ((errors++)) || true
                    fi
                else
                    echo -n "Delete orphan '$bot_name'? [y/N] "
                    read -r confirm
                    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                        echo "Deleting: $bot_name"
                        if delete_job "$bot_name"; then
                            log "Deleted orphan cron job: $bot_name"
                            ((deleted++)) || true
                        else
                            ((errors++)) || true
                        fi
                    else
                        echo "Kept: $bot_name"
                    fi
                fi
            else
                echo "INFO: Bot-only job (not in local YAML): $bot_name"
            fi
        fi
    done <<< "$bot_job_names"

    # Summary
    echo ""
    echo "Cron sync complete:"
    echo "  Created: $synced"
    echo "  Updated: $updated"
    echo "  Skipped: $skipped"
    [[ $orphans -gt 0 ]] && echo "  Orphans: $orphans" || true
    [[ $deleted -gt 0 ]] && echo "  Deleted: $deleted" || true
    [[ $warned -gt 0 ]] && echo "  Warnings: $warned (use --update to sync)" || true
    echo "  Errors: $errors"

    log "Cron sync complete: created=$synced, updated=$updated, skipped=$skipped, orphans=$orphans, deleted=$deleted, errors=$errors"

    [[ $errors -gt 0 ]] && exit 1
    exit 0
}

main
