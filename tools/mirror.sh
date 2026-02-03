#!/bin/bash
# Mirror bot's files locally for backup/reference
# Bot is source of truth - we just keep a copy
#
# Usage:
#   ./tools/mirror.sh                   # Mirror all agents (quiet)
#   ./tools/mirror.sh --agent=bruba-main # Mirror specific agent
#   ./tools/mirror.sh --verbose          # Show detailed output
#   ./tools/mirror.sh --dry-run          # Show what would be mirrored
#
# Output structure:
#   mirror/{agent}/
#     prompts/    - AGENTS.md, MEMORY.md, etc.
#     memory/     - Date-prefixed memory entries
#     config/     - Config files (tokens redacted)
#     tools/      - Bot's tool scripts
#
# Logs: logs/mirror.log

set -e

# Load shared functions
source "$(dirname "$0")/lib.sh"

# Parse arguments
AGENT_FILTER=""
for arg in "$@"; do
    case $arg in
        --agent=*)
            AGENT_FILTER="${arg#*=}"
            ;;
    esac
done

if ! parse_common_args "$@"; then
    echo "Usage: $0 [--dry-run] [--verbose] [--agent=NAME]"
    echo ""
    echo "Mirror bot's files to local backup."
    echo "Bot is source of truth - we just keep a copy."
    echo ""
    echo "Options:"
    echo "  --dry-run, -n      Show what would be mirrored without doing it"
    echo "  --verbose, -v      Show detailed output"
    echo "  --quiet, -q        Summary output only (default)"
    echo "  --agent=NAME       Mirror specific agent only"
    exit 0
fi

# Load config
load_config

# Set up logging
LOG_FILE="$LOG_DIR/mirror.log"
mkdir -p "$LOG_DIR"
rotate_log "$LOG_FILE"

log "=== Mirroring Bot Files ==="

# Build list of agents to process
if [[ -n "$AGENT_FILTER" ]]; then
    AGENTS=("$AGENT_FILTER")
else
    # Read agents into array (bash 3.x compatible)
    AGENTS=()
    while IFS= read -r agent; do
        [[ -n "$agent" ]] && AGENTS+=("$agent")
    done < <(get_agents)
fi

TOTAL_MIRRORED=0

# Process each agent
for agent in "${AGENTS[@]}"; do
    load_agent_config "$agent"

    # Skip agents with no workspace
    if [[ -z "$AGENT_WORKSPACE" || "$AGENT_WORKSPACE" == "null" ]]; then
        log "Skipping $agent (no workspace)"
        continue
    fi

    log ""
    log "=== Agent: $agent ==="
    log "Workspace: $AGENT_WORKSPACE"
    log "Mirror dir: $AGENT_MIRROR_DIR"

    AGENT_MIRRORED=0

    # Create directories
    if [[ "$DRY_RUN" != "true" ]]; then
        mkdir -p "$AGENT_MIRROR_DIR"/{prompts,memory,config,tools}
    fi

    # Core prompt files - single SSH call to list all existing .md files
    log ""
    log "Prompts ($AGENT_WORKSPACE/*.md):"
    CORE_FILES="AGENTS.md MEMORY.md USER.md IDENTITY.md SOUL.md TOOLS.md HEARTBEAT.md BOOTSTRAP.md"
    EXISTING_PROMPTS=$(bot_cmd "cd $AGENT_WORKSPACE && ls $CORE_FILES 2>/dev/null" || true)
    for file in $EXISTING_PROMPTS; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log "  Would mirror: prompts/$file"
        else
            bot_scp "$AGENT_WORKSPACE/$file" "$AGENT_MIRROR_DIR/prompts/$file"
            log "  + prompts/$file"
        fi
        AGENT_MIRRORED=$((AGENT_MIRRORED + 1))
    done

    # Memory files (date-prefixed only) - single find call (returns empty if dir doesn't exist)
    log ""
    log "Memory ($AGENT_WORKSPACE/memory/):"
    MEMORY_COUNT=0
    while IFS= read -r remote_file; do
        [[ -z "$remote_file" ]] && continue
        filename=$(basename "$remote_file")

        # Only pull files starting with YYYY-MM-DD
        if [[ "$filename" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log "  Would mirror: memory/$filename"
            else
                bot_scp "$remote_file" "$AGENT_MIRROR_DIR/memory/$filename"
                log "  + memory/$filename"
            fi
            AGENT_MIRRORED=$((AGENT_MIRRORED + 1))
            MEMORY_COUNT=$((MEMORY_COUNT + 1))
        fi
    done < <(bot_cmd "find $AGENT_WORKSPACE/memory -maxdepth 1 -name '*.md' 2>/dev/null" || true)

    if [[ $MEMORY_COUNT -eq 0 ]]; then
        log "  (no memory files)"
    fi

    # Config files - only for main agent (has openclaw config)
    if [[ "$agent" == "bruba-main" ]]; then
        log ""
        log "Config ($REMOTE_OPENCLAW/*.json):"
        CONFIG_FILES="openclaw.json exec-approvals.json"
        EXISTING_CONFIGS=$(bot_cmd "cd $REMOTE_OPENCLAW && ls $CONFIG_FILES 2>/dev/null" || true)
        for config_file in $EXISTING_CONFIGS; do
            if [[ "$DRY_RUN" == "true" ]]; then
                log "  Would mirror: config/$config_file"
            else
                if [[ "$config_file" == "openclaw.json" ]]; then
                    # Redact sensitive tokens
                    bot_cmd "cat $REMOTE_OPENCLAW/$config_file" 2>/dev/null | \
                        sed 's/"botToken"[[:space:]]*:[[:space:]]*"[^"]*"/"botToken": "[REDACTED]"/g' | \
                        sed 's/"token"[[:space:]]*:[[:space:]]*"[^"]*"/"token": "[REDACTED]"/g' \
                        > "$AGENT_MIRROR_DIR/config/$config_file"
                    log "  + config/$config_file (tokens redacted)"
                else
                    bot_scp "$REMOTE_OPENCLAW/$config_file" "$AGENT_MIRROR_DIR/config/$config_file"
                    log "  + config/$config_file"
                fi
            fi
            AGENT_MIRRORED=$((AGENT_MIRRORED + 1))
        done
    fi

    # Tool scripts - only for main agent
    if [[ "$agent" == "bruba-main" ]]; then
        log ""
        log "Tools ($AGENT_WORKSPACE/tools/):"
        TOOLS_COUNT=0
        while IFS= read -r remote_file; do
            [[ -z "$remote_file" ]] && continue
            filename=$(basename "$remote_file")
            if [[ "$DRY_RUN" == "true" ]]; then
                log "  Would mirror: tools/$filename"
            else
                bot_scp "$remote_file" "$AGENT_MIRROR_DIR/tools/$filename"
                log "  + tools/$filename"
            fi
            AGENT_MIRRORED=$((AGENT_MIRRORED + 1))
            TOOLS_COUNT=$((TOOLS_COUNT + 1))
        done < <(bot_cmd "find $AGENT_WORKSPACE/tools -maxdepth 1 -name '*.sh' 2>/dev/null" || true)

        if [[ $TOOLS_COUNT -eq 0 ]]; then
            log "  (no tools)"
        fi
    fi

    # State files - for manager (single find call)
    if [[ "$agent" == "bruba-manager" ]]; then
        log ""
        log "State ($AGENT_WORKSPACE/state/):"
        STATE_COUNT=0
        while IFS= read -r remote_file; do
            [[ -z "$remote_file" ]] && continue
            mkdir -p "$AGENT_MIRROR_DIR/state" 2>/dev/null || true
            filename=$(basename "$remote_file")
            if [[ "$DRY_RUN" == "true" ]]; then
                log "  Would mirror: state/$filename"
            else
                bot_scp "$remote_file" "$AGENT_MIRROR_DIR/state/$filename"
                log "  + state/$filename"
            fi
            AGENT_MIRRORED=$((AGENT_MIRRORED + 1))
            STATE_COUNT=$((STATE_COUNT + 1))
        done < <(bot_cmd "find $AGENT_WORKSPACE/state -maxdepth 1 -name '*.json' 2>/dev/null" || true)
        if [[ $STATE_COUNT -eq 0 ]]; then
            log "  (no state files)"
        fi
    fi

    # Results files - for guru (single find call)
    if [[ "$agent" == "bruba-guru" ]]; then
        log ""
        log "Results ($AGENT_WORKSPACE/results/):"
        RESULTS_COUNT=0
        while IFS= read -r remote_file; do
            [[ -z "$remote_file" ]] && continue
            mkdir -p "$AGENT_MIRROR_DIR/results" 2>/dev/null || true
            filename=$(basename "$remote_file")
            if [[ "$DRY_RUN" == "true" ]]; then
                log "  Would mirror: results/$filename"
            else
                bot_scp "$remote_file" "$AGENT_MIRROR_DIR/results/$filename"
                log "  + results/$filename"
            fi
            AGENT_MIRRORED=$((AGENT_MIRRORED + 1))
            RESULTS_COUNT=$((RESULTS_COUNT + 1))
        done < <(bot_cmd "find $AGENT_WORKSPACE/results -maxdepth 1 -name '*.md' 2>/dev/null" || true)
        if [[ $RESULTS_COUNT -eq 0 ]]; then
            log "  (no results files)"
        fi
    fi

    echo "$agent: $AGENT_MIRRORED files"
    TOTAL_MIRRORED=$((TOTAL_MIRRORED + AGENT_MIRRORED))
done

log ""
log "=== Summary ==="
if [[ "$DRY_RUN" == "true" ]]; then
    log "Would mirror: $TOTAL_MIRRORED files"
else
    log "Mirrored: $TOTAL_MIRRORED files"
fi

# Always print summary
echo ""
echo "Mirror: $TOTAL_MIRRORED files"
