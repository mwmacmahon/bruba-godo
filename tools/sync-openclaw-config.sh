#!/bin/bash
# Sync config.yaml settings to bot's openclaw.json
#
# Usage:
#   ./tools/sync-openclaw-config.sh              # Sync all managed settings
#   ./tools/sync-openclaw-config.sh --check      # Check status only (no changes)
#   ./tools/sync-openclaw-config.sh --dry-run    # Show what would change
#   ./tools/sync-openclaw-config.sh --section=X  # Only sync specific section
#   ./tools/sync-openclaw-config.sh --agent=X    # Only sync specific agent
#
# Syncs:
#   - Global defaults: model, compaction, context_pruning, sandbox, max_concurrent
#   - Per-agent: model, heartbeat, memory_search, tools (allow/deny)
#   - Subagents: model, max_concurrent, archive_after_minutes, tools
#   - Voice: STT (tools.media.audio), TTS (messages.tts)
#
# Preserves unmanaged sections: auth, wizard, channels, gateway, env.vars (API keys), plugins, skills
#
# Logs: logs/sync-config.log

set -e

# Load shared functions
source "$(dirname "$0")/lib.sh"

# Parse arguments
CHECK_ONLY=false
AGENT_FILTER=""
SECTION_FILTER=""
args=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --check)
            CHECK_ONLY=true
            shift
            ;;
        --agent=*)
            AGENT_FILTER="${1#*=}"
            shift
            ;;
        --section=*)
            SECTION_FILTER="${1#*=}"
            shift
            ;;
        *)
            args+=("$1")
            shift
            ;;
    esac
done

if ! parse_common_args "${args[@]}"; then
    echo "Usage: $0 [--check] [--section=NAME] [--agent=NAME] [--dry-run] [--verbose]"
    echo ""
    echo "Sync config.yaml settings to bot's openclaw.json."
    echo ""
    echo "Options:"
    echo "  --check           Check status only (list discrepancies)"
    echo "  --section=NAME    Only sync specific section (defaults, agents, subagents)"
    echo "  --agent=NAME      Only sync specific agent"
    echo "  --dry-run, -n     Show what would change without doing it"
    echo "  --verbose, -v     Show detailed output"
    echo ""
    echo "Sections:"
    echo "  defaults   Global agent defaults (model, compaction, etc.)"
    echo "  agents     Per-agent settings (model, heartbeat, tools)"
    echo "  subagents  Subagent settings"
    echo "  voice      Voice settings (STT + TTS)"
    exit 0
fi

# Load config
load_config

# Check prerequisites
require_commands jq python3

# Set up logging
LOG_FILE="$LOG_DIR/sync-config.log"
mkdir -p "$LOG_DIR"

log "=== Syncing OpenClaw Config ==="

# Get current openclaw.json from bot
get_current_config() {
    bot_exec "cat $REMOTE_OPENCLAW/openclaw.json" 2>/dev/null
}

# Save config to bot
save_config() {
    local new_config="$1"
    local backup_name="openclaw.json.backup.$(date +%Y%m%d-%H%M%S)"

    # Create backup
    bot_exec "cp $REMOTE_OPENCLAW/openclaw.json $REMOTE_OPENCLAW/$backup_name"
    log "Backup created: $backup_name"

    # Write new config
    echo "$new_config" | bot_exec "cat > $REMOTE_OPENCLAW/openclaw.json"

    # Validate
    if ! bot_exec "jq empty $REMOTE_OPENCLAW/openclaw.json" 2>/dev/null; then
        log "ERROR: Invalid JSON, restoring backup..."
        bot_exec "cp $REMOTE_OPENCLAW/$backup_name $REMOTE_OPENCLAW/openclaw.json"
        return 1
    fi

    log "Config saved successfully"
}

# Compare two JSON values
# Returns 0 if equal, 1 if different
json_equal() {
    local a="$1"
    local b="$2"
    # Normalize: parse as JSON, sort arrays, and compact
    local a_norm b_norm
    # Try to parse as JSON first, fall back to wrapping as string
    a_norm=$(echo "$a" | jq -cS 'if type == "array" then sort else . end' 2>/dev/null) || a_norm=$(echo "$a" | jq -cRS '.' 2>/dev/null) || a_norm="$a"
    b_norm=$(echo "$b" | jq -cS 'if type == "array" then sort else . end' 2>/dev/null) || b_norm=$(echo "$b" | jq -cRS '.' 2>/dev/null) || b_norm="$b"
    [[ "$a_norm" == "$b_norm" ]]
}

# Convert heartbeat: false to { "every": "0m" } for comparison
# OpenClaw uses every: "0m" to mean disabled
normalize_heartbeat() {
    local hb="$1"
    if [[ "$hb" == "false" ]]; then
        echo '{"every":"0m"}'
    else
        echo "$hb"
    fi
}

# Track changes
CHANGES_FOUND=0
CHANGES_APPLIED=0

# Show diff between current and desired
show_diff() {
    local path="$1"
    local current="$2"
    local desired="$3"

    echo "  $path:"
    echo "    current: $(echo "$current" | jq -c '.' 2>/dev/null || echo "$current")"
    echo "    desired: $(echo "$desired" | jq -c '.' 2>/dev/null || echo "$desired")"
}

# Main execution
log "Fetching current config from bot..."
CURRENT_CONFIG=$(get_current_config)

if [[ -z "$CURRENT_CONFIG" ]]; then
    echo "ERROR: Could not read openclaw.json from bot" >&2
    exit 1
fi

# Check if config.yaml has openclaw section
if ! has_openclaw_config; then
    echo "No openclaw section in config.yaml - nothing to sync"
    echo ""
    echo "Add an openclaw: section to config.yaml to manage settings."
    echo "See config.yaml.example for available options."
    exit 0
fi

NEW_CONFIG="$CURRENT_CONFIG"

# === SYNC GLOBAL DEFAULTS ===
if [[ -z "$SECTION_FILTER" || "$SECTION_FILTER" == "defaults" ]]; then
    log "Checking global defaults..."
    echo "Checking global defaults..."

    # Model defaults
    DESIRED_MODEL=$(get_openclaw_config model)
    if [[ -n "$DESIRED_MODEL" && "$DESIRED_MODEL" != "null" ]]; then
        CURRENT_MODEL=$(echo "$CURRENT_CONFIG" | jq -c '.agents.defaults.model // null')
        if ! json_equal "$CURRENT_MODEL" "$DESIRED_MODEL"; then
            show_diff "agents.defaults.model" "$CURRENT_MODEL" "$DESIRED_MODEL"
            CHANGES_FOUND=1
            if [[ "$CHECK_ONLY" != "true" && "$DRY_RUN" != "true" ]]; then
                NEW_CONFIG=$(echo "$NEW_CONFIG" | jq ".agents.defaults.model = $DESIRED_MODEL")
                CHANGES_APPLIED=1
            fi
        fi
    fi

    # Compaction
    DESIRED_COMPACTION=$(get_openclaw_config compaction)
    if [[ -n "$DESIRED_COMPACTION" && "$DESIRED_COMPACTION" != "null" ]]; then
        CURRENT_COMPACTION=$(echo "$CURRENT_CONFIG" | jq -c '.agents.defaults.compaction // null')
        if ! json_equal "$CURRENT_COMPACTION" "$DESIRED_COMPACTION"; then
            show_diff "agents.defaults.compaction" "$CURRENT_COMPACTION" "$DESIRED_COMPACTION"
            CHANGES_FOUND=1
            if [[ "$CHECK_ONLY" != "true" && "$DRY_RUN" != "true" ]]; then
                NEW_CONFIG=$(echo "$NEW_CONFIG" | jq ".agents.defaults.compaction = $DESIRED_COMPACTION")
                CHANGES_APPLIED=1
            fi
        fi
    fi

    # Context pruning
    DESIRED_CTX=$(get_openclaw_config context_pruning)
    if [[ -n "$DESIRED_CTX" && "$DESIRED_CTX" != "null" ]]; then
        CURRENT_CTX=$(echo "$CURRENT_CONFIG" | jq -c '.agents.defaults.contextPruning // null')
        if ! json_equal "$CURRENT_CTX" "$DESIRED_CTX"; then
            show_diff "agents.defaults.contextPruning" "$CURRENT_CTX" "$DESIRED_CTX"
            CHANGES_FOUND=1
            if [[ "$CHECK_ONLY" != "true" && "$DRY_RUN" != "true" ]]; then
                NEW_CONFIG=$(echo "$NEW_CONFIG" | jq ".agents.defaults.contextPruning = $DESIRED_CTX")
                CHANGES_APPLIED=1
            fi
        fi
    fi

    # Memory search
    DESIRED_MEM=$(get_openclaw_config memory_search)
    if [[ -n "$DESIRED_MEM" && "$DESIRED_MEM" != "null" ]]; then
        CURRENT_MEM=$(echo "$CURRENT_CONFIG" | jq -c '.agents.defaults.memorySearch // null')
        if ! json_equal "$CURRENT_MEM" "$DESIRED_MEM"; then
            show_diff "agents.defaults.memorySearch" "$CURRENT_MEM" "$DESIRED_MEM"
            CHANGES_FOUND=1
            if [[ "$CHECK_ONLY" != "true" && "$DRY_RUN" != "true" ]]; then
                NEW_CONFIG=$(echo "$NEW_CONFIG" | jq ".agents.defaults.memorySearch = $DESIRED_MEM")
                CHANGES_APPLIED=1
            fi
        fi
    fi

    # Sandbox
    DESIRED_SANDBOX=$(get_openclaw_config sandbox)
    if [[ -n "$DESIRED_SANDBOX" && "$DESIRED_SANDBOX" != "null" ]]; then
        CURRENT_SANDBOX=$(echo "$CURRENT_CONFIG" | jq -c '.agents.defaults.sandbox // null')
        if ! json_equal "$CURRENT_SANDBOX" "$DESIRED_SANDBOX"; then
            show_diff "agents.defaults.sandbox" "$CURRENT_SANDBOX" "$DESIRED_SANDBOX"
            CHANGES_FOUND=1
            if [[ "$CHECK_ONLY" != "true" && "$DRY_RUN" != "true" ]]; then
                NEW_CONFIG=$(echo "$NEW_CONFIG" | jq ".agents.defaults.sandbox = $DESIRED_SANDBOX")
                CHANGES_APPLIED=1
            fi
        fi
    fi

    # Max concurrent
    DESIRED_MC=$("$ROOT_DIR/tools/helpers/parse-yaml.py" "$ROOT_DIR/config.yaml" "openclaw.max_concurrent" 2>/dev/null || echo "")
    if [[ -n "$DESIRED_MC" && "$DESIRED_MC" != "null" ]]; then
        CURRENT_MC=$(echo "$CURRENT_CONFIG" | jq -r '.agents.defaults.maxConcurrent // null')
        if [[ "$CURRENT_MC" != "$DESIRED_MC" ]]; then
            show_diff "agents.defaults.maxConcurrent" "$CURRENT_MC" "$DESIRED_MC"
            CHANGES_FOUND=1
            if [[ "$CHECK_ONLY" != "true" && "$DRY_RUN" != "true" ]]; then
                NEW_CONFIG=$(echo "$NEW_CONFIG" | jq ".agents.defaults.maxConcurrent = $DESIRED_MC")
                CHANGES_APPLIED=1
            fi
        fi
    fi

    # Subagents defaults
    SUBAGENT_CONFIG=$(get_subagents_config)
    if [[ -n "$SUBAGENT_CONFIG" && "$SUBAGENT_CONFIG" != "null" ]]; then
        # Max concurrent
        DESIRED_SUB_MC=$(echo "$SUBAGENT_CONFIG" | jq -r '.max_concurrent // null')
        if [[ "$DESIRED_SUB_MC" != "null" ]]; then
            CURRENT_SUB_MC=$(echo "$CURRENT_CONFIG" | jq -r '.agents.defaults.subagents.maxConcurrent // null')
            if [[ "$CURRENT_SUB_MC" != "$DESIRED_SUB_MC" ]]; then
                show_diff "agents.defaults.subagents.maxConcurrent" "$CURRENT_SUB_MC" "$DESIRED_SUB_MC"
                CHANGES_FOUND=1
                if [[ "$CHECK_ONLY" != "true" && "$DRY_RUN" != "true" ]]; then
                    NEW_CONFIG=$(echo "$NEW_CONFIG" | jq ".agents.defaults.subagents.maxConcurrent = $DESIRED_SUB_MC")
                    CHANGES_APPLIED=1
                fi
            fi
        fi

        # Archive after minutes
        DESIRED_SUB_AAM=$(echo "$SUBAGENT_CONFIG" | jq -r '.archive_after_minutes // null')
        if [[ "$DESIRED_SUB_AAM" != "null" ]]; then
            CURRENT_SUB_AAM=$(echo "$CURRENT_CONFIG" | jq -r '.agents.defaults.subagents.archiveAfterMinutes // null')
            if [[ "$CURRENT_SUB_AAM" != "$DESIRED_SUB_AAM" ]]; then
                show_diff "agents.defaults.subagents.archiveAfterMinutes" "$CURRENT_SUB_AAM" "$DESIRED_SUB_AAM"
                CHANGES_FOUND=1
                if [[ "$CHECK_ONLY" != "true" && "$DRY_RUN" != "true" ]]; then
                    NEW_CONFIG=$(echo "$NEW_CONFIG" | jq ".agents.defaults.subagents.archiveAfterMinutes = $DESIRED_SUB_AAM")
                    CHANGES_APPLIED=1
                fi
            fi
        fi

        # Model
        DESIRED_SUB_MODEL=$(echo "$SUBAGENT_CONFIG" | jq -r '.model // null')
        if [[ "$DESIRED_SUB_MODEL" != "null" ]]; then
            CURRENT_SUB_MODEL=$(echo "$CURRENT_CONFIG" | jq -r '.agents.defaults.subagents.model // null')
            if [[ "$CURRENT_SUB_MODEL" != "$DESIRED_SUB_MODEL" ]]; then
                show_diff "agents.defaults.subagents.model" "$CURRENT_SUB_MODEL" "$DESIRED_SUB_MODEL"
                CHANGES_FOUND=1
                if [[ "$CHECK_ONLY" != "true" && "$DRY_RUN" != "true" ]]; then
                    NEW_CONFIG=$(echo "$NEW_CONFIG" | jq ".agents.defaults.subagents.model = \"$DESIRED_SUB_MODEL\"")
                    CHANGES_APPLIED=1
                fi
            fi
        fi
    fi
fi

# === SYNC PER-AGENT SETTINGS ===
if [[ -z "$SECTION_FILTER" || "$SECTION_FILTER" == "agents" ]]; then
    log "Checking agent settings..."
    echo "Checking agent settings..."

    # Get list of agents to process
    if [[ -n "$AGENT_FILTER" ]]; then
        AGENTS_TO_SYNC=("$AGENT_FILTER")
    else
        AGENTS_TO_SYNC=()
        while IFS= read -r agent; do
            [[ -n "$agent" ]] && AGENTS_TO_SYNC+=("$agent")
        done < <(get_agents)
    fi

    for agent in "${AGENTS_TO_SYNC[@]}"; do
        load_agent_config "$agent"

        # Skip agents with no workspace (like bruba-helper)
        [[ -z "$AGENT_WORKSPACE" || "$AGENT_WORKSPACE" == "null" ]] && continue

        [[ "$VERBOSE" == "true" ]] && echo "  Checking $agent..."

        # Get current agent config from openclaw.json
        AGENT_INDEX=$(echo "$CURRENT_CONFIG" | jq -r ".agents.list | to_entries[] | select(.value.id == \"$agent\") | .key")
        if [[ -z "$AGENT_INDEX" ]]; then
            [[ "$VERBOSE" == "true" ]] && echo "    Agent not found in openclaw.json, skipping"
            continue
        fi

        # Model
        DESIRED_MODEL=$(get_agent_model "$agent")
        if [[ -n "$DESIRED_MODEL" && "$DESIRED_MODEL" != "null" ]]; then
            CURRENT_MODEL=$(echo "$CURRENT_CONFIG" | jq -r ".agents.list[$AGENT_INDEX].model // null")
            # For string models, compare directly; for objects, use json_equal
            model_changed=false
            if echo "$DESIRED_MODEL" | jq -e 'type == "object"' >/dev/null 2>&1; then
                # Object model - compare as JSON
                CURRENT_MODEL_JSON=$(echo "$CURRENT_CONFIG" | jq -c ".agents.list[$AGENT_INDEX].model // null")
                if ! json_equal "$CURRENT_MODEL_JSON" "$DESIRED_MODEL"; then
                    model_changed=true
                    show_diff "agents.$agent.model" "$CURRENT_MODEL_JSON" "$DESIRED_MODEL"
                fi
            else
                # String model - compare directly
                if [[ "$CURRENT_MODEL" != "$DESIRED_MODEL" ]]; then
                    model_changed=true
                    show_diff "agents.$agent.model" "$CURRENT_MODEL" "$DESIRED_MODEL"
                fi
            fi
            if [[ "$model_changed" == "true" ]]; then
                CHANGES_FOUND=1
                if [[ "$CHECK_ONLY" != "true" && "$DRY_RUN" != "true" ]]; then
                    # Check if desired is a string or object
                    if echo "$DESIRED_MODEL" | jq -e 'type == "object"' >/dev/null 2>&1; then
                        NEW_CONFIG=$(echo "$NEW_CONFIG" | jq ".agents.list[$AGENT_INDEX].model = $DESIRED_MODEL")
                    else
                        NEW_CONFIG=$(echo "$NEW_CONFIG" | jq ".agents.list[$AGENT_INDEX].model = \"$DESIRED_MODEL\"")
                    fi
                    CHANGES_APPLIED=1
                fi
            fi
        fi

        # Heartbeat
        # Get raw heartbeat value (might be false, object, or missing)
        DESIRED_HB_RAW=$("$ROOT_DIR/tools/helpers/parse-yaml.py" "$ROOT_DIR/config.yaml" "agents.$agent.heartbeat" 2>/dev/null || echo "")
        if [[ -n "$DESIRED_HB_RAW" ]]; then
            CURRENT_HB=$(echo "$CURRENT_CONFIG" | jq -c ".agents.list[$AGENT_INDEX].heartbeat // null")
            # Python yaml returns "False" for false
            if [[ "$DESIRED_HB_RAW" == "false" || "$DESIRED_HB_RAW" == "False" ]]; then
                # false means disabled - equivalent to null, {"every":"0m"}, or {"every":"0"}
                CURRENT_EVERY=$(echo "$CURRENT_HB" | jq -r '.every // ""' 2>/dev/null)
                # null, 0m, or 0 all mean disabled - no change needed
                if [[ "$CURRENT_HB" != "null" && "$CURRENT_EVERY" != "0m" && "$CURRENT_EVERY" != "0" && -n "$CURRENT_EVERY" ]]; then
                    show_diff "agents.$agent.heartbeat" "$CURRENT_HB" '{"every":"0m"}'
                    CHANGES_FOUND=1
                    if [[ "$CHECK_ONLY" != "true" && "$DRY_RUN" != "true" ]]; then
                        NEW_CONFIG=$(echo "$NEW_CONFIG" | jq ".agents.list[$AGENT_INDEX].heartbeat = {\"every\":\"0m\"}")
                        CHANGES_APPLIED=1
                    fi
                fi
            else
                # It's an object - use full comparison
                DESIRED_HB=$(get_agent_heartbeat "$agent")
                if [[ -n "$DESIRED_HB" && "$DESIRED_HB" != "null" ]]; then
                    if ! json_equal "$CURRENT_HB" "$DESIRED_HB"; then
                        show_diff "agents.$agent.heartbeat" "$CURRENT_HB" "$DESIRED_HB"
                        CHANGES_FOUND=1
                        if [[ "$CHECK_ONLY" != "true" && "$DRY_RUN" != "true" ]]; then
                            NEW_CONFIG=$(echo "$NEW_CONFIG" | jq ".agents.list[$AGENT_INDEX].heartbeat = $DESIRED_HB")
                            CHANGES_APPLIED=1
                        fi
                    fi
                fi
            fi
        fi

        # Tools allow
        DESIRED_ALLOW=$(get_agent_tools_allow "$agent")
        if [[ -n "$DESIRED_ALLOW" && "$DESIRED_ALLOW" != "null" && "$DESIRED_ALLOW" != "[]" ]]; then
            CURRENT_ALLOW=$(echo "$CURRENT_CONFIG" | jq -c ".agents.list[$AGENT_INDEX].tools.allow // []")
            if ! json_equal "$CURRENT_ALLOW" "$DESIRED_ALLOW"; then
                show_diff "agents.$agent.tools.allow" "$CURRENT_ALLOW" "$DESIRED_ALLOW"
                CHANGES_FOUND=1
                if [[ "$CHECK_ONLY" != "true" && "$DRY_RUN" != "true" ]]; then
                    NEW_CONFIG=$(echo "$NEW_CONFIG" | jq ".agents.list[$AGENT_INDEX].tools.allow = $DESIRED_ALLOW")
                    CHANGES_APPLIED=1
                fi
            fi
        fi

        # Tools deny
        DESIRED_DENY=$(get_agent_tools_deny "$agent")
        if [[ -n "$DESIRED_DENY" && "$DESIRED_DENY" != "null" && "$DESIRED_DENY" != "[]" ]]; then
            CURRENT_DENY=$(echo "$CURRENT_CONFIG" | jq -c ".agents.list[$AGENT_INDEX].tools.deny // []")
            if ! json_equal "$CURRENT_DENY" "$DESIRED_DENY"; then
                show_diff "agents.$agent.tools.deny" "$CURRENT_DENY" "$DESIRED_DENY"
                CHANGES_FOUND=1
                if [[ "$CHECK_ONLY" != "true" && "$DRY_RUN" != "true" ]]; then
                    NEW_CONFIG=$(echo "$NEW_CONFIG" | jq ".agents.list[$AGENT_INDEX].tools.deny = $DESIRED_DENY")
                    CHANGES_APPLIED=1
                fi
            fi
        fi
    done
fi

# === SYNC SUBAGENT TOOLS ===
if [[ -z "$SECTION_FILTER" || "$SECTION_FILTER" == "subagents" ]]; then
    log "Checking subagent settings..."
    echo "Checking subagent settings..."

    SUBAGENT_CONFIG=$(get_subagents_config)
    if [[ -n "$SUBAGENT_CONFIG" && "$SUBAGENT_CONFIG" != "null" ]]; then
        # Tools allow
        DESIRED_ALLOW=$(echo "$SUBAGENT_CONFIG" | jq -c '.tools_allow // []')
        if [[ "$DESIRED_ALLOW" != "[]" ]]; then
            CURRENT_ALLOW=$(echo "$CURRENT_CONFIG" | jq -c '.tools.subagents.tools.allow // []')
            if ! json_equal "$CURRENT_ALLOW" "$DESIRED_ALLOW"; then
                show_diff "tools.subagents.tools.allow" "$CURRENT_ALLOW" "$DESIRED_ALLOW"
                CHANGES_FOUND=1
                if [[ "$CHECK_ONLY" != "true" && "$DRY_RUN" != "true" ]]; then
                    NEW_CONFIG=$(echo "$NEW_CONFIG" | jq ".tools.subagents.tools.allow = $DESIRED_ALLOW")
                    CHANGES_APPLIED=1
                fi
            fi
        fi

        # Tools deny
        DESIRED_DENY=$(echo "$SUBAGENT_CONFIG" | jq -c '.tools_deny // []')
        if [[ "$DESIRED_DENY" != "[]" ]]; then
            CURRENT_DENY=$(echo "$CURRENT_CONFIG" | jq -c '.tools.subagents.tools.deny // []')
            if ! json_equal "$CURRENT_DENY" "$DESIRED_DENY"; then
                show_diff "tools.subagents.tools.deny" "$CURRENT_DENY" "$DESIRED_DENY"
                CHANGES_FOUND=1
                if [[ "$CHECK_ONLY" != "true" && "$DRY_RUN" != "true" ]]; then
                    NEW_CONFIG=$(echo "$NEW_CONFIG" | jq ".tools.subagents.tools.deny = $DESIRED_DENY")
                    CHANGES_APPLIED=1
                fi
            fi
        fi
    fi
fi

# === SYNC VOICE SETTINGS ===
if [[ -z "$SECTION_FILTER" || "$SECTION_FILTER" == "voice" ]]; then
    log "Checking voice settings..."
    echo "Checking voice settings..."

    # STT (tools.media.audio)
    DESIRED_STT=$(get_voice_config stt)
    if [[ -n "$DESIRED_STT" && "$DESIRED_STT" != "null" ]]; then
        CURRENT_STT=$(echo "$CURRENT_CONFIG" | jq -c '.tools.media.audio // null')
        if ! json_equal "$CURRENT_STT" "$DESIRED_STT"; then
            show_diff "tools.media.audio" "$CURRENT_STT" "$DESIRED_STT"
            CHANGES_FOUND=1
            if [[ "$CHECK_ONLY" != "true" && "$DRY_RUN" != "true" ]]; then
                NEW_CONFIG=$(echo "$NEW_CONFIG" | jq ".tools.media.audio = $DESIRED_STT")
                CHANGES_APPLIED=1
            fi
        fi
    fi

    # TTS (messages.tts)
    DESIRED_TTS=$(get_voice_config tts)
    if [[ -n "$DESIRED_TTS" && "$DESIRED_TTS" != "null" ]]; then
        CURRENT_TTS=$(echo "$CURRENT_CONFIG" | jq -c '.messages.tts // null')
        if ! json_equal "$CURRENT_TTS" "$DESIRED_TTS"; then
            show_diff "messages.tts" "$CURRENT_TTS" "$DESIRED_TTS"
            CHANGES_FOUND=1
            if [[ "$CHECK_ONLY" != "true" && "$DRY_RUN" != "true" ]]; then
                NEW_CONFIG=$(echo "$NEW_CONFIG" | jq ".messages.tts = $DESIRED_TTS")
                CHANGES_APPLIED=1
            fi
        fi
    fi
fi

# Apply changes if needed
if [[ "$CHANGES_APPLIED" -eq 1 ]]; then
    log "Applying changes..."
    if save_config "$NEW_CONFIG"; then
        log "Changes applied successfully"
    else
        echo "ERROR: Failed to save config" >&2
        exit 1
    fi
fi

log "=== Sync Complete ==="

# Summary
echo ""
if [[ "$CHECK_ONLY" == "true" ]]; then
    if [[ $CHANGES_FOUND -eq 0 ]]; then
        echo "Config: in sync"
    else
        echo "Config: discrepancies found (run without --check to apply)"
    fi
elif [[ "$DRY_RUN" == "true" ]]; then
    if [[ $CHANGES_FOUND -eq 0 ]]; then
        echo "[DRY RUN] Config: in sync"
    else
        echo "[DRY RUN] Would update config (run without --dry-run to apply)"
    fi
else
    if [[ $CHANGES_FOUND -eq 0 ]]; then
        echo "Config: in sync"
    else
        echo "Config: updated"
        echo ""
        echo "IMPORTANT: Restart gateway to apply changes:"
        echo "  ./tools/bot openclaw gateway restart"
    fi
fi
