#!/bin/bash
# Push content exports to bot memory
#
# Usage:
#   ./tools/push.sh                     # Push for all agents
#   ./tools/push.sh --agent=bruba-main  # Push for specific agent
#   ./tools/push.sh --dry-run           # Show what would be synced
#   ./tools/push.sh --verbose           # Detailed output
#   ./tools/push.sh --no-index          # Skip memory reindex
#
# Reads config.yaml for filter configuration, syncs exports/bot/{agent}/ to bot workspaces
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
TOOLS_ONLY=false
UPDATE_ALLOWLIST=false
SYNC_TOOLS=false
AGENT_FILTER=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-index)
            NO_INDEX=true
            shift
            ;;
        --tools-only)
            TOOLS_ONLY=true
            shift
            ;;
        --update-allowlist)
            UPDATE_ALLOWLIST=true
            shift
            ;;
        --sync-tools)
            SYNC_TOOLS=true
            shift
            ;;
        --agent=*)
            AGENT_FILTER="${1#*=}"
            shift
            ;;
        *)
            break
            ;;
    esac
done

if ! parse_common_args "$@"; then
    echo "Usage: $0 [--dry-run] [--verbose] [--no-index] [--tools-only] [--update-allowlist] [--sync-tools] [--agent=NAME]"
    echo ""
    echo "Push content bundles to bot memory."
    echo ""
    echo "Options:"
    echo "  --dry-run, -n       Show what would be synced without doing it"
    echo "  --verbose, -v       Show detailed output"
    echo "  --quiet, -q         Summary output only (default)"
    echo "  --no-index          Skip memory reindex after sync"
    echo "  --tools-only        Sync only component tools (skip content)"
    echo "  --update-allowlist  Update exec-approvals with component tool entries"
    echo "  --sync-tools        Sync agent tool configs from config.yaml to openclaw.json"
    echo "  --agent=NAME        Push for specific agent only"
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

# Sync component tools function (to main agent only - they share tools)
sync_component_tools() {
    local tools_synced=0
    local tool_rsync_opts="-avz --chmod=+x"
    if [[ "$DRY_RUN" == "true" ]]; then
        tool_rsync_opts="$tool_rsync_opts --dry-run"
    fi
    if [[ "$VERBOSE" != "true" ]]; then
        tool_rsync_opts="$tool_rsync_opts --quiet"
    fi

    for component_dir in "$ROOT_DIR/components"/*/tools; do
        if [[ -d "$component_dir" ]]; then
            local component
            component=$(basename "$(dirname "$component_dir")")
            log "  Syncing $component tools..."
            rsync $tool_rsync_opts "$component_dir/" "$SSH_HOST:$REMOTE_WORKSPACE/tools/"
            if [[ "$DRY_RUN" != "true" ]]; then
                tools_synced=$((tools_synced + $(find "$component_dir" -type f | wc -l | tr -d ' ')))
            fi
        fi
    done
    echo "$tools_synced"
}

# Handle --tools-only mode (early exit)
if [[ "$TOOLS_ONLY" == "true" ]]; then
    log "=== Syncing Component Tools Only ==="
    TOOLS_COUNT=$(sync_component_tools)
    log "=== Tool Sync Complete ==="
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "Tools: dry run complete"
    else
        echo "Tools: $TOOLS_COUNT files synced"
    fi

    # Update allowlist if requested
    if [[ "$UPDATE_ALLOWLIST" == "true" ]]; then
        log "Updating exec-approvals allowlist..."
        ALLOWLIST_ARGS=""
        [[ "$DRY_RUN" == "true" ]] && ALLOWLIST_ARGS="--dry-run"
        [[ "$VERBOSE" == "true" ]] && ALLOWLIST_ARGS="$ALLOWLIST_ARGS --verbose"
        "$ROOT_DIR/tools/update-allowlist.sh" $ALLOWLIST_ARGS
    fi

    exit 0
fi

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

# Default remote path for content (can be overridden per-agent)
DEFAULT_REMOTE_PATH="memory"

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

TOTAL_SYNCED=0

# Process each agent
for agent in "${AGENTS[@]}"; do
    load_agent_config "$agent"

    # Skip agents with no workspace
    if [[ -z "$AGENT_WORKSPACE" || "$AGENT_WORKSPACE" == "null" ]]; then
        log "Skipping $agent (no workspace)"
        continue
    fi

    # Skip if no export directory exists
    if [[ ! -d "$AGENT_EXPORT_DIR" ]]; then
        log "Skipping $agent (no exports at $AGENT_EXPORT_DIR)"
        continue
    fi

    log ""
    log "=== Syncing $agent ==="
    echo "Agent: $agent"

    # 1. Sync core-prompts to workspace root (AGENTS.md, TOOLS.md, HEARTBEAT.md)
    if [[ -d "$AGENT_EXPORT_DIR/core-prompts" ]]; then
        CORE_COUNT=$(find "$AGENT_EXPORT_DIR/core-prompts" -type f -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$CORE_COUNT" -gt 0 ]]; then
            log "Syncing core-prompts/ to $SSH_HOST:$AGENT_WORKSPACE/ ($CORE_COUNT files)"
            if [[ "$DRY_RUN" == "true" ]]; then
                log "[DRY RUN] Would sync $CORE_COUNT core prompt files"
                rsync $RSYNC_OPTS "$AGENT_EXPORT_DIR/core-prompts/" "$SSH_HOST:$AGENT_WORKSPACE/"
            else
                rsync $RSYNC_OPTS "$AGENT_EXPORT_DIR/core-prompts/" "$SSH_HOST:$AGENT_WORKSPACE/"
                log "  Synced $CORE_COUNT core prompt files"
                echo "  core-prompts: $CORE_COUNT files"
            fi
            TOTAL_SYNCED=$((TOTAL_SYNCED + CORE_COUNT))
        fi
    fi

    # 2. Only sync content directories for main agent (bruba-main has memory)
    if [[ "$agent" == "bruba-main" ]]; then
        # Generate inventory files
        if [[ -f "$ROOT_DIR/tools/generate-inventory.sh" ]]; then
            log "Generating inventories..."
            "$ROOT_DIR/tools/generate-inventory.sh" | while read -r line; do log "$line"; done
        fi

        # Use agent's remote_path (defaults to 'memory')
        remote_path="${AGENT_REMOTE_PATH:-memory}"

        # Sync content subdirectories to memory/ preserving structure
        # transcripts → memory/transcripts/, docs/cc_logs/summaries → memory/docs/
        for subdir in prompts transcripts refdocs docs artifacts cc_logs summaries; do
            if [[ -d "$AGENT_EXPORT_DIR/$subdir" ]]; then
                SUBDIR_COUNT=$(find "$AGENT_EXPORT_DIR/$subdir" -type f -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
                if [[ "$SUBDIR_COUNT" -gt 0 ]]; then
                    # Determine target directory based on content type
                    case "$subdir" in
                        transcripts)
                            TARGET_DIR="$remote_path/transcripts"
                            ;;
                        docs|cc_logs|summaries|refdocs|artifacts)
                            TARGET_DIR="$remote_path/docs"
                            ;;
                        prompts)
                            TARGET_DIR="$remote_path/docs"
                            ;;
                        *)
                            TARGET_DIR="$remote_path/docs"
                            ;;
                    esac

                    log "Syncing $subdir/ to $SSH_HOST:$AGENT_WORKSPACE/$TARGET_DIR/ ($SUBDIR_COUNT files)"
                    if [[ "$DRY_RUN" == "true" ]]; then
                        log "[DRY RUN] Would sync $SUBDIR_COUNT $subdir files"
                        rsync $RSYNC_OPTS "$AGENT_EXPORT_DIR/$subdir/" "$SSH_HOST:$AGENT_WORKSPACE/$TARGET_DIR/"
                    else
                        # Ensure target directory exists
                        ssh "$SSH_HOST" "mkdir -p $AGENT_WORKSPACE/$TARGET_DIR"
                        rsync $RSYNC_OPTS "$AGENT_EXPORT_DIR/$subdir/" "$SSH_HOST:$AGENT_WORKSPACE/$TARGET_DIR/"
                        log "  Synced $SUBDIR_COUNT $subdir files"
                        echo "  $subdir: $SUBDIR_COUNT files"
                    fi
                    TOTAL_SYNCED=$((TOTAL_SYNCED + SUBDIR_COUNT))
                fi
            fi
        done

        # Sync root-level inventory files
        ROOT_FILES=$(find "$AGENT_EXPORT_DIR" -maxdepth 1 -type f -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$ROOT_FILES" -gt 0 ]]; then
            log "Syncing root-level files to $SSH_HOST:$AGENT_WORKSPACE/$remote_path/ ($ROOT_FILES files)"
            if [[ "$DRY_RUN" == "true" ]]; then
                log "[DRY RUN] Would sync $ROOT_FILES root files"
                rsync $RSYNC_OPTS --include='*.md' --exclude='*/' "$AGENT_EXPORT_DIR/" "$SSH_HOST:$AGENT_WORKSPACE/$remote_path/"
            else
                rsync $RSYNC_OPTS --include='*.md' --exclude='*/' "$AGENT_EXPORT_DIR/" "$SSH_HOST:$AGENT_WORKSPACE/$remote_path/"
                log "  Synced $ROOT_FILES root files"
            fi
            TOTAL_SYNCED=$((TOTAL_SYNCED + ROOT_FILES))
        fi
    fi
done

# 3. Sync repo code if enabled (to main agent only)
if [[ "$CLONE_REPO_CODE" == "true" ]]; then
    log "Syncing repo code to $SSH_HOST:$REMOTE_WORKSPACE/workspace/repo/"

    REPO_RSYNC_OPTS="-avz --delete"
    if [[ "$DRY_RUN" == "true" ]]; then
        REPO_RSYNC_OPTS="$REPO_RSYNC_OPTS --dry-run"
    fi
    if [[ "$VERBOSE" != "true" ]]; then
        REPO_RSYNC_OPTS="$REPO_RSYNC_OPTS --quiet"
    fi

    # Include only specific directories/files, exclude ephemeral content
    rsync $REPO_RSYNC_OPTS \
        --exclude='intake/' \
        --exclude='exports/' \
        --exclude='bundles/' \
        --exclude='.git/' \
        --exclude='__pycache__/' \
        --exclude='*.pyc' \
        --exclude='node_modules/' \
        --exclude='mirror/' \
        --exclude='sessions/' \
        --exclude='logs/' \
        --exclude='reference/' \
        --exclude='user/' \
        --include='docs/***' \
        --include='templates/***' \
        --include='components/***' \
        --include='tools/***' \
        --include='README.md' \
        --include='CLAUDE.md' \
        --exclude='*' \
        "$ROOT_DIR/" "$SSH_HOST:$REMOTE_WORKSPACE/workspace/repo/"

    if [[ "$DRY_RUN" != "true" ]]; then
        CODE_COUNT=$(find "$ROOT_DIR/docs" "$ROOT_DIR/tools" -type f 2>/dev/null | wc -l | tr -d ' ')
        log "  Synced ~$CODE_COUNT repo files"
    fi
fi

# 4. Sync component tools (to main agent only)
log "Syncing component tools..."
TOOLS_COUNT=$(sync_component_tools)
if [[ "$DRY_RUN" != "true" ]]; then
    log "  $TOOLS_COUNT tool files synced"
fi

# 5. Sync agent tool configs if requested
if [[ "$SYNC_TOOLS" == "true" ]]; then
    log "Syncing agent tool configs..."
    TOOLS_ARGS=""
    [[ "$DRY_RUN" == "true" ]] && TOOLS_ARGS="--dry-run"
    [[ "$VERBOSE" == "true" ]] && TOOLS_ARGS="$TOOLS_ARGS --verbose"
    if "$ROOT_DIR/tools/update-agent-tools.sh" $TOOLS_ARGS; then
        log "Agent tool configs synced"
    else
        log "Warning: Agent tool config sync had issues"
    fi
fi

# 6. Update allowlist if requested
if [[ "$UPDATE_ALLOWLIST" == "true" ]]; then
    log "Updating exec-approvals allowlist..."
    ALLOWLIST_ARGS=""
    [[ "$DRY_RUN" == "true" ]] && ALLOWLIST_ARGS="--dry-run"
    [[ "$VERBOSE" == "true" ]] && ALLOWLIST_ARGS="$ALLOWLIST_ARGS --verbose"
    "$ROOT_DIR/tools/update-allowlist.sh" $ALLOWLIST_ARGS
fi

# Trigger reindex for main agent if not dry run
# Use conditional reindex to skip if no content changed
if [[ "$DRY_RUN" != "true" && "$NO_INDEX" != "true" ]]; then
    HASH_FILE="$ROOT_DIR/.last-sync-hash"
    CURRENT_HASH=""

    # Compute hash of exported content
    if [[ -d "$EXPORTS_DIR/bot" ]]; then
        CURRENT_HASH=$(find "$EXPORTS_DIR/bot" -type f -exec md5 -q {} \; 2>/dev/null | sort | md5 -q 2>/dev/null || echo "")
    fi

    PREV_HASH=""
    if [[ -f "$HASH_FILE" ]]; then
        PREV_HASH=$(cat "$HASH_FILE" 2>/dev/null)
    fi

    if [[ -n "$CURRENT_HASH" && "$CURRENT_HASH" != "$PREV_HASH" ]]; then
        log "Triggering memory reindex (content changed)..."
        if bot_cmd "openclaw memory index" 2>/dev/null; then
            log "Memory indexed"
            echo "$CURRENT_HASH" > "$HASH_FILE"
        else
            log "Warning: Memory index failed (may need manual reindex)"
        fi
    else
        log "Skipping reindex (no content changes)"
    fi
fi

log "=== Push Complete ==="
echo ""
echo "Push: $TOTAL_SYNCED files synced"
