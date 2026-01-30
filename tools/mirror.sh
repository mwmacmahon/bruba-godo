#!/bin/bash
# Mirror bot's files locally for backup/reference
# Bot is source of truth - we just keep a copy
#
# Usage:
#   ./tools/mirror.sh           # Mirror all files (quiet)
#   ./tools/mirror.sh --verbose # Show detailed output
#   ./tools/mirror.sh --dry-run # Show what would be mirrored
#
# Output structure:
#   mirror/
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
if ! parse_common_args "$@"; then
    echo "Usage: $0 [--dry-run] [--verbose]"
    echo ""
    echo "Mirror bot's files to local backup."
    echo "Bot is source of truth - we just keep a copy."
    echo ""
    echo "Options:"
    echo "  --dry-run, -n   Show what would be mirrored without doing it"
    echo "  --verbose, -v   Show detailed output"
    echo "  --quiet, -q     Summary output only (default)"
    exit 0
fi

# Load config
load_config

# Set up logging
LOG_FILE="$LOG_DIR/mirror.log"
mkdir -p "$LOG_DIR"
rotate_log "$LOG_FILE"

log "=== Mirroring Bot Files ==="
log "Mirror dir: $MIRROR_DIR"

# Create directories
if [[ "$DRY_RUN" != "true" ]]; then
    mkdir -p "$MIRROR_DIR"/{prompts,memory,config,tools}
fi

MIRRORED=0

# Core prompt files
log ""
log "Prompts ($REMOTE_WORKSPACE/*.md):"
CORE_FILES="AGENTS.md MEMORY.md USER.md IDENTITY.md SOUL.md TOOLS.md HEARTBEAT.md BOOTSTRAP.md"
for file in $CORE_FILES; do
    if bot_cmd "test -f $REMOTE_WORKSPACE/$file" 2>/dev/null; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log "  Would mirror: prompts/$file"
        else
            bot_scp "$REMOTE_WORKSPACE/$file" "$MIRROR_DIR/prompts/$file"
            log "  + prompts/$file"
        fi
        MIRRORED=$((MIRRORED + 1))
    fi
done

# Memory files (date-prefixed only)
log ""
log "Memory ($REMOTE_WORKSPACE/memory/):"
MEMORY_COUNT=0
while IFS= read -r remote_file; do
    [[ -z "$remote_file" ]] && continue
    filename=$(basename "$remote_file")

    # Only pull files starting with YYYY-MM-DD
    if [[ "$filename" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log "  Would mirror: memory/$filename"
        else
            bot_scp "$remote_file" "$MIRROR_DIR/memory/$filename"
            log "  + memory/$filename"
        fi
        MIRRORED=$((MIRRORED + 1))
        MEMORY_COUNT=$((MEMORY_COUNT + 1))
    fi
done < <(bot_cmd "ls $REMOTE_WORKSPACE/memory/*.md 2>/dev/null" || true)

if [[ $MEMORY_COUNT -eq 0 ]]; then
    log "  (no memory files)"
fi

# Config files
log ""
log "Config ($REMOTE_CLAWDBOT/*.json):"
for config_file in clawdbot.json exec-approvals.json; do
    if bot_cmd "test -f $REMOTE_CLAWDBOT/$config_file" 2>/dev/null; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log "  Would mirror: config/$config_file"
        else
            if [[ "$config_file" == "clawdbot.json" ]]; then
                # Redact sensitive tokens
                bot_cmd "cat $REMOTE_CLAWDBOT/$config_file" 2>/dev/null | \
                    sed 's/"botToken"[[:space:]]*:[[:space:]]*"[^"]*"/"botToken": "[REDACTED]"/g' | \
                    sed 's/"token"[[:space:]]*:[[:space:]]*"[^"]*"/"token": "[REDACTED]"/g' \
                    > "$MIRROR_DIR/config/$config_file"
                log "  + config/$config_file (tokens redacted)"
            else
                bot_scp "$REMOTE_CLAWDBOT/$config_file" "$MIRROR_DIR/config/$config_file"
                log "  + config/$config_file"
            fi
        fi
        MIRRORED=$((MIRRORED + 1))
    fi
done

# Tool scripts
log ""
log "Tools ($REMOTE_WORKSPACE/tools/):"
TOOLS_COUNT=0
while IFS= read -r remote_file; do
    [[ -z "$remote_file" ]] && continue
    filename=$(basename "$remote_file")
    if [[ "$DRY_RUN" == "true" ]]; then
        log "  Would mirror: tools/$filename"
    else
        bot_scp "$remote_file" "$MIRROR_DIR/tools/$filename"
        log "  + tools/$filename"
    fi
    MIRRORED=$((MIRRORED + 1))
    TOOLS_COUNT=$((TOOLS_COUNT + 1))
done < <(bot_cmd "ls $REMOTE_WORKSPACE/tools/*.sh 2>/dev/null" || true)

if [[ $TOOLS_COUNT -eq 0 ]]; then
    log "  (no tools)"
fi

log ""
log "=== Summary ==="
if [[ "$DRY_RUN" == "true" ]]; then
    log "Would mirror: $MIRRORED files"
else
    log "Mirrored: $MIRRORED files"
fi

# Always print summary
echo "Mirror: $MIRRORED files"
