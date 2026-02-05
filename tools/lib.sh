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
    REMOTE_OPENCLAW=$(grep "^  openclaw:" "$config_file" | awk '{print $2}' | tr -d '"')
    REMOTE_AGENT_ID=$(grep "^  agent_id:" "$config_file" | awk '{print $2}' | tr -d '"')

    # Local paths (relative to ROOT_DIR)
    LOCAL_MIRROR=$(grep "^  mirror:" "$config_file" | awk '{print $2}' | tr -d '"')
    LOCAL_SESSIONS=$(grep "^  sessions:" "$config_file" | awk '{print $2}' | tr -d '"')
    LOCAL_LOGS=$(grep "^  logs:" "$config_file" | awk '{print $2}' | tr -d '"')
    LOCAL_INTAKE=$(grep "^  intake:" "$config_file" | awk '{print $2}' | tr -d '"')
    LOCAL_REFERENCE=$(grep "^  reference:" "$config_file" | awk '{print $2}' | tr -d '"')
    LOCAL_EXPORTS=$(grep "^  exports:" "$config_file" | awk '{print $2}' | tr -d '"')

    # Make local paths absolute
    MIRROR_DIR="$ROOT_DIR/${LOCAL_MIRROR:-mirror}"
    SESSIONS_DIR="$ROOT_DIR/${LOCAL_SESSIONS:-sessions}"
    LOG_DIR="$ROOT_DIR/${LOCAL_LOGS:-logs}"
    INTAKE_DIR="$ROOT_DIR/${LOCAL_INTAKE:-intake}"
    REFERENCE_DIR="$ROOT_DIR/${LOCAL_REFERENCE:-reference}"
    EXPORTS_DIR="$ROOT_DIR/${LOCAL_EXPORTS:-exports}"

    # Clone repo code option (default: false)
    CLONE_REPO_CODE=$(grep "^clone_repo_code:" "$config_file" | awk '{print $2}' | tr -d '"')
    CLONE_REPO_CODE="${CLONE_REPO_CODE:-false}"

    # Derived remote paths
    REMOTE_SESSIONS="$REMOTE_OPENCLAW/agents/$REMOTE_AGENT_ID/sessions"

    # SSH multiplexing options for faster connections (used for ssh transport)
    SSH_OPTS="-o ControlMaster=auto -o ControlPath=/tmp/ssh-%r@%h:%p -o ControlPersist=60"

    # Bot transport configuration
    # Options: sudo (same machine), tailscale-ssh, ssh (default)
    # Read from config.yaml, can be overridden by environment variable BOT_TRANSPORT
    CONFIG_TRANSPORT=$(grep "^transport:" "$config_file" | awk '{print $2}' | tr -d '"')
    BOT_TRANSPORT="${BOT_TRANSPORT:-${CONFIG_TRANSPORT:-ssh}}"
    BOT_USER="${BOT_USER:-bruba}"
    BOT_HOST="${BOT_HOST:-$SSH_HOST}"
}

# Get list of configured agents (excludes agents with null workspace or empty prompts)
# Usage: mapfile -t AGENTS < <(get_agents)
get_agents() {
    local config_file="$ROOT_DIR/config.yaml"

    python3 -c "
import yaml
import sys
try:
    with open('$config_file') as f:
        config = yaml.safe_load(f)
    agents = config.get('agents', {})
    for name in agents.keys():
        print(name)
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null
}

# Load config for a specific agent
# Usage: load_agent_config "bruba-main"
# Sets: AGENT_NAME, AGENT_WORKSPACE, AGENT_PROMPTS, AGENT_REMOTE_PATH, AGENT_MIRROR_DIR, AGENT_EXPORT_DIR
load_agent_config() {
    local agent="${1:-bruba-main}"
    local config_file="$ROOT_DIR/config.yaml"

    AGENT_NAME="$agent"

    # Use Python to reliably parse nested YAML
    local agent_data
    agent_data=$(python3 -c "
import yaml
import json
import sys
try:
    with open('$config_file') as f:
        config = yaml.safe_load(f)
    agent = config.get('agents', {}).get('$agent', {})
    print(json.dumps({
        'workspace': agent.get('workspace'),
        'prompts': agent.get('prompts', []),
        'remote_path': agent.get('remote_path', 'memory')
    }))
except Exception as e:
    print(json.dumps({'workspace': None, 'prompts': [], 'remote_path': 'memory'}))
" 2>/dev/null)

    AGENT_WORKSPACE=$(echo "$agent_data" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('workspace') or '')" 2>/dev/null)
    AGENT_PROMPTS=$(echo "$agent_data" | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps(d.get('prompts', [])))" 2>/dev/null)
    AGENT_REMOTE_PATH=$(echo "$agent_data" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('remote_path') or 'memory')" 2>/dev/null)

    # Derived paths
    AGENT_MIRROR_DIR="$MIRROR_DIR/$agent"
    AGENT_EXPORT_DIR="$EXPORTS_DIR/bot/$agent"
}

# Get tools_allow list for an agent from config.yaml
# Usage: get_agent_tools_allow "bruba-main"
# Returns: JSON array of allowed tools
get_agent_tools_allow() {
    local agent="$1"
    local config_file="$ROOT_DIR/config.yaml"
    local helper="$ROOT_DIR/tools/helpers/parse-yaml.py"

    "$helper" "$config_file" "agents.$agent.tools_allow" 2>/dev/null || true
}

# Get tools_deny list for an agent from config.yaml
# Usage: get_agent_tools_deny "bruba-main"
# Returns: JSON array of denied tools
get_agent_tools_deny() {
    local agent="$1"
    local config_file="$ROOT_DIR/config.yaml"
    local helper="$ROOT_DIR/tools/helpers/parse-yaml.py"

    "$helper" "$config_file" "agents.$agent.tools_deny" 2>/dev/null || true
}

# Get subagents config from config.yaml
# Usage: get_subagents_config
# Returns: JSON object with subagent settings
get_subagents_config() {
    local config_file="$ROOT_DIR/config.yaml"
    local helper="$ROOT_DIR/tools/helpers/parse-yaml.py"

    "$helper" "$config_file" "subagents" 2>/dev/null
}

# Get openclaw global config from config.yaml
# Usage: get_openclaw_config [section]
# Returns: JSON object with openclaw settings (with camelCase keys)
# Examples:
#   get_openclaw_config              # All openclaw settings
#   get_openclaw_config compaction   # Just compaction section
get_openclaw_config() {
    local section="${1:-}"
    local config_file="$ROOT_DIR/config.yaml"
    local helper="$ROOT_DIR/tools/helpers/parse-yaml.py"

    if [[ -n "$section" ]]; then
        "$helper" "$config_file" --to-json "openclaw.$section" 2>/dev/null || true
    else
        "$helper" "$config_file" --to-json "openclaw" 2>/dev/null || true
    fi
}

# Get agent model config from config.yaml
# Usage: get_agent_model "bruba-main"
# Returns: JSON (string or object with primary/fallbacks)
get_agent_model() {
    local agent="$1"
    local config_file="$ROOT_DIR/config.yaml"
    local helper="$ROOT_DIR/tools/helpers/parse-yaml.py"

    "$helper" "$config_file" "agents.$agent.model" 2>/dev/null || true
}

# Get agent heartbeat config from config.yaml
# Usage: get_agent_heartbeat "bruba-manager"
# Returns: JSON object with heartbeat settings (camelCase keys)
get_agent_heartbeat() {
    local agent="$1"
    local config_file="$ROOT_DIR/config.yaml"
    local helper="$ROOT_DIR/tools/helpers/parse-yaml.py"

    "$helper" "$config_file" --to-json "agents.$agent.heartbeat" 2>/dev/null || true
}

# Check if openclaw section exists in config.yaml
# Usage: has_openclaw_config
# Returns: 0 if exists, 1 if not
has_openclaw_config() {
    local config_file="$ROOT_DIR/config.yaml"
    local helper="$ROOT_DIR/tools/helpers/parse-yaml.py"

    "$helper" "$config_file" "openclaw" >/dev/null 2>&1
}

# Get voice config from config.yaml
# Usage: get_voice_config [section]
# Returns: JSON object with voice settings (with camelCase keys)
# Examples:
#   get_voice_config              # All voice settings
#   get_voice_config stt          # Just STT section
#   get_voice_config tts          # Just TTS section
get_voice_config() {
    local section="${1:-}"
    local config_file="$ROOT_DIR/config.yaml"
    local helper="$ROOT_DIR/tools/helpers/parse-yaml.py"

    if [[ -n "$section" ]]; then
        "$helper" "$config_file" --to-json "openclaw.voice.$section" 2>/dev/null || true
    else
        "$helper" "$config_file" --to-json "openclaw.voice" 2>/dev/null || true
    fi
}

# Get bindings config from config.yaml
# Usage: get_bindings_config
# Returns: JSON array of bindings for openclaw.json
get_bindings_config() {
    local config_file="$ROOT_DIR/config.yaml"
    local helper="$ROOT_DIR/tools/helpers/parse-yaml.py"

    # Get bindings as JSON, transforming agent->agentId and restructuring match
    python3 -c "
import yaml
import json
import sys

with open('$config_file') as f:
    config = yaml.safe_load(f)

bindings = config.get('bindings', [])
if not bindings:
    print('[]')
    sys.exit(0)

result = []
for b in bindings:
    entry = {
        'agentId': b.get('agent'),
        'match': {'channel': b.get('channel')}
    }
    # Add peer if present
    if 'peer' in b:
        entry['match']['peer'] = b['peer']
    result.append(entry)

print(json.dumps(result))
" 2>/dev/null || echo "[]"
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

# Run command as bot user (supports multiple transports)
# Usage: bot_exec "command"
# Transport is controlled by BOT_TRANSPORT env var or config
bot_exec() {
    local cmd="$*"

    case "$BOT_TRANSPORT" in
        sudo)
            # Same machine, different user
            # Use login shell (-i) to get proper ~ expansion for target user
            sudo -u "$BOT_USER" -i bash -c "$cmd"
            ;;
        tailscale-ssh)
            # Tailscale SSH (faster, no key management)
            tailscale ssh "$BOT_USER@$BOT_HOST" "$cmd"
            ;;
        ssh|*)
            # Default: regular SSH with multiplexing
            ssh $SSH_OPTS "$BOT_USER@$BOT_HOST" "$cmd"
            ;;
    esac
}

# Legacy alias for compatibility
bot_cmd() {
    bot_exec "$@"
}

# Copy file from bot user's filesystem
# Usage: bot_scp "remote_path" "local_path"
bot_scp() {
    local remote_path="$1"
    local local_path="$2"

    case "$BOT_TRANSPORT" in
        sudo)
            # Same machine - just copy with sudo
            sudo -u "$BOT_USER" cat "$remote_path" > "$local_path"
            ;;
        tailscale-ssh)
            # Use rsync over tailscale ssh
            rsync -e "tailscale ssh" -q "$BOT_USER@$BOT_HOST:$remote_path" "$local_path"
            ;;
        ssh|*)
            # Default: regular scp
            scp $SSH_OPTS -q "$BOT_USER@$BOT_HOST:$remote_path" "$local_path"
            ;;
    esac
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
