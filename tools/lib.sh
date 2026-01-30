#!/bin/bash
# Shared functions for bruba-godo tools
#
# Usage: source this file at the top of scripts
#   source "$(dirname "$0")/lib.sh"

# Find repo root
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$LIB_DIR")"

# Load config values from config.yaml
load_config() {
    local config_file="$ROOT_DIR/config.yaml"

    if [[ ! -f "$config_file" ]]; then
        echo "ERROR: config.yaml not found at $config_file" >&2
        return 1
    fi

    # SSH
    SSH_HOST=$(grep "^  host:" "$config_file" | awk '{print $2}' | tr -d '"')
    SSH_HOST="${SSH_HOST:-bruba}"

    # Remote paths
    REMOTE_HOME=$(grep "^  home:" "$config_file" | awk '{print $2}' | tr -d '"')
    REMOTE_WORKSPACE=$(grep "^  workspace:" "$config_file" | awk '{print $2}' | tr -d '"')
    REMOTE_CLAWDBOT=$(grep "^  clawdbot:" "$config_file" | awk '{print $2}' | tr -d '"')
    REMOTE_AGENT_ID=$(grep "^  agent_id:" "$config_file" | awk '{print $2}' | tr -d '"')

    # Local paths (relative to ROOT_DIR)
    LOCAL_MIRROR=$(grep "^  mirror:" "$config_file" | awk '{print $2}' | tr -d '"')
    LOCAL_SESSIONS=$(grep "^  sessions:" "$config_file" | awk '{print $2}' | tr -d '"')
    LOCAL_LOGS=$(grep "^  logs:" "$config_file" | awk '{print $2}' | tr -d '"')
    LOCAL_INTAKE=$(grep "^  intake:" "$config_file" | awk '{print $2}' | tr -d '"')
    LOCAL_REFERENCE=$(grep "^  reference:" "$config_file" | awk '{print $2}' | tr -d '"')
    LOCAL_BUNDLES=$(grep "^  bundles:" "$config_file" | awk '{print $2}' | tr -d '"')

    # Make local paths absolute
    MIRROR_DIR="$ROOT_DIR/${LOCAL_MIRROR:-mirror}"
    SESSIONS_DIR="$ROOT_DIR/${LOCAL_SESSIONS:-sessions}"
    LOG_DIR="$ROOT_DIR/${LOCAL_LOGS:-logs}"
    INTAKE_DIR="$ROOT_DIR/${LOCAL_INTAKE:-intake}"
    REFERENCE_DIR="$ROOT_DIR/${LOCAL_REFERENCE:-reference}"
    BUNDLES_DIR="$ROOT_DIR/${LOCAL_BUNDLES:-bundles}"

    # Derived remote paths
    REMOTE_SESSIONS="$REMOTE_CLAWDBOT/agents/$REMOTE_AGENT_ID/sessions"
}

# Cross-platform sed in-place
# Usage: sed_inplace 's/foo/bar/' file.txt
sed_inplace() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# Check if a command exists
# Usage: command_exists python3
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Require commands to exist, exit if missing
# Usage: require_commands python3 rsync jq
require_commands() {
    local missing=()
    for cmd in "$@"; do
        if ! command_exists "$cmd"; then
            missing+=("$cmd")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "ERROR: Missing required commands: ${missing[*]}" >&2
        return 1
    fi
}

# Logging function
# Usage: log "message" [quiet]
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" >> "$LOG_FILE"
    if [[ "${QUIET:-false}" != "true" ]]; then
        echo "$1"
    fi
}

# Rotate log if over max size, keep N old versions
# Usage: rotate_log "/path/to/file.log" [max_size_kb] [keep]
rotate_log() {
    local log_file="$1"
    local max_size_kb="${2:-5120}"  # 5MB default
    local keep="${3:-3}"

    [[ ! -f "$log_file" ]] && return

    local size_kb
    size_kb=$(du -k "$log_file" 2>/dev/null | cut -f1)
    [[ $size_kb -lt $max_size_kb ]] && return

    # Rotate: .3 deleted, .2 -> .3, .1 -> .2, current -> .1
    for ((i=keep; i>=1; i--)); do
        local old="${log_file}.${i}"
        local new="${log_file}.$((i+1))"
        if [[ -f "$old" ]]; then
            if [[ $i -eq $keep ]]; then
                rm -f "$old"
            else
                mv "$old" "$new"
            fi
        fi
    done
    mv "$log_file" "${log_file}.1"
}

# Run command on remote bot
# Usage: bot_cmd "command"
bot_cmd() {
    ssh "$SSH_HOST" "$*"
}

# Copy file from remote bot
# Usage: bot_scp "remote_path" "local_path"
bot_scp() {
    scp -q "$SSH_HOST:$1" "$2"
}

# Parse common arguments
# Sets: QUIET, DRY_RUN, VERBOSE
parse_common_args() {
    QUIET=true
    DRY_RUN=false
    VERBOSE=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run|-n)
                DRY_RUN=true
                shift
                ;;
            --verbose|-v)
                QUIET=false
                VERBOSE=true
                shift
                ;;
            --quiet|-q)
                QUIET=true
                VERBOSE=false
                shift
                ;;
            --help|-h)
                return 1  # Signal to show help
                ;;
            *)
                # Unknown arg, let caller handle
                break
                ;;
        esac
    done
    REMAINING_ARGS=("$@")
}
