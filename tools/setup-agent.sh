#!/bin/bash
# Setup a new agent on the bot machine
#
# Usage:
#   ./tools/setup-agent.sh                    # Interactive mode
#   ./tools/setup-agent.sh --agent-id mybot   # With options
#   ./tools/setup-agent.sh --dry-run          # Preview without changes
#
# Prerequisites:
#   - SSH access to bot machine
#   - Clawdbot installed on bot machine
#   - Python 3 for variable substitution
#
# This script:
#   1. Creates remote directories (workspace, memory, tools)
#   2. Copies and customizes prompt templates
#   3. Adds agent to clawdbot.json
#   4. Creates exec-approvals namespace
#   5. Verifies installation

set -e

# Load shared functions
source "$(dirname "$0")/lib.sh"

# Defaults
AGENT_ID=""
AGENT_NAME=""
USER_NAME=""
WORKSPACE=""
DRY_RUN=false
VERBOSE=false
SKIP_PROMPTS=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --agent-id)
            AGENT_ID="$2"
            shift 2
            ;;
        --agent-name)
            AGENT_NAME="$2"
            shift 2
            ;;
        --user-name)
            USER_NAME="$2"
            shift 2
            ;;
        --workspace)
            WORKSPACE="$2"
            shift 2
            ;;
        --dry-run|-n)
            DRY_RUN=true
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --skip-prompts)
            SKIP_PROMPTS=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Set up a new agent on the bot machine."
            echo ""
            echo "Options:"
            echo "  --agent-id ID       Agent identifier (e.g., my-agent)"
            echo "  --agent-name NAME   Display name (e.g., 'My Agent')"
            echo "  --user-name NAME    Your name (for USER.md template)"
            echo "  --workspace PATH    Workspace path (default: ~/clawd)"
            echo "  --dry-run, -n       Show what would be done without doing it"
            echo "  --verbose, -v       Detailed output"
            echo "  --skip-prompts      Don't prompt for missing values"
            echo "  --help, -h          Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Load config
load_config

# Check prerequisites
echo "=== Checking Prerequisites ==="

if ! require_commands ssh python3; then
    exit 1
fi

# Check SSH connectivity
echo -n "Testing SSH connection to $SSH_HOST... "
if ssh -o ConnectTimeout=5 "$SSH_HOST" "echo ok" >/dev/null 2>&1; then
    echo "✓"
else
    echo "✗"
    echo "ERROR: Cannot connect to $SSH_HOST" >&2
    exit 1
fi

# Check clawdbot is installed
echo -n "Checking clawdbot installation... "
if ssh "$SSH_HOST" "which clawdbot" >/dev/null 2>&1; then
    CLAWDBOT_VERSION=$(ssh "$SSH_HOST" "clawdbot --version" 2>/dev/null || echo "unknown")
    echo "✓ (v$CLAWDBOT_VERSION)"
else
    echo "✗"
    echo "ERROR: clawdbot not found on $SSH_HOST" >&2
    echo "Install clawdbot first: https://github.com/moltbot/clawdbot" >&2
    exit 1
fi

# Get remote home directory
REMOTE_HOME_ACTUAL=$(ssh "$SSH_HOST" "echo \$HOME")
CLAWDBOT_DIR="$REMOTE_HOME_ACTUAL/.clawdbot"

echo ""
echo "=== Agent Configuration ==="

# Interactive prompts for missing values
if [[ -z "$AGENT_ID" && "$SKIP_PROMPTS" != "true" ]]; then
    read -p "Agent ID (e.g., my-agent): " AGENT_ID
fi
AGENT_ID="${AGENT_ID:-my-agent}"

if [[ -z "$AGENT_NAME" && "$SKIP_PROMPTS" != "true" ]]; then
    read -p "Agent display name (e.g., My Agent) [$AGENT_ID]: " AGENT_NAME
fi
AGENT_NAME="${AGENT_NAME:-$AGENT_ID}"

if [[ -z "$USER_NAME" && "$SKIP_PROMPTS" != "true" ]]; then
    read -p "Your name (for USER.md template): " USER_NAME
fi
USER_NAME="${USER_NAME:-User}"

if [[ -z "$WORKSPACE" && "$SKIP_PROMPTS" != "true" ]]; then
    read -p "Workspace path [$REMOTE_HOME_ACTUAL/clawd]: " WORKSPACE
fi
WORKSPACE="${WORKSPACE:-$REMOTE_HOME_ACTUAL/clawd}"

# Show configuration
echo ""
echo "Configuration:"
echo "  Agent ID:   $AGENT_ID"
echo "  Agent Name: $AGENT_NAME"
echo "  User Name:  $USER_NAME"
echo "  Workspace:  $WORKSPACE"
echo "  Clawdbot:   $CLAWDBOT_DIR"
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY RUN] Would perform the following actions:"
    echo ""
fi

# Confirm
if [[ "$SKIP_PROMPTS" != "true" && "$DRY_RUN" != "true" ]]; then
    read -p "Proceed with setup? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy] ]]; then
        echo "Aborted."
        exit 0
    fi
fi

echo ""
echo "=== Creating Directories ==="

AGENT_DIR="$CLAWDBOT_DIR/agents/$AGENT_ID"
DIRS_TO_CREATE=(
    "$WORKSPACE"
    "$WORKSPACE/memory"
    "$WORKSPACE/memory/archive"
    "$WORKSPACE/tools"
    "$WORKSPACE/tools/helpers"
    "$WORKSPACE/output"
    "$AGENT_DIR"
    "$AGENT_DIR/workspace"
    "$AGENT_DIR/workspace/code"
    "$AGENT_DIR/workspace/output"
    "$AGENT_DIR/sessions"
)

for dir in "${DIRS_TO_CREATE[@]}"; do
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  Would create: $dir"
    else
        ssh "$SSH_HOST" "mkdir -p '$dir'"
        [[ "$VERBOSE" == "true" ]] && echo "  Created: $dir"
    fi
done
echo "  ✓ Directories created"

echo ""
echo "=== Copying Prompt Templates ==="

TEMPLATE_DIR="$ROOT_DIR/templates/prompts"
SETUP_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
FIRST_DATE=$(date +"%Y-%m-%d")

# Function to substitute variables in templates
substitute_vars() {
    local content="$1"
    content="${content//\$\{BOT_NAME\}/$AGENT_NAME}"
    content="${content//\$\{USER_NAME\}/$USER_NAME}"
    content="${content//\$\{AGENT_ID\}/$AGENT_ID}"
    content="${content//\$\{WORKSPACE\}/$WORKSPACE}"
    content="${content//\$\{CLAWDBOT_DIR\}/$CLAWDBOT_DIR}"
    content="${content//\$\{SETUP_DATE\}/$SETUP_DATE}"
    content="${content//\$\{FIRST_CONVERSATION_DATE\}/$FIRST_DATE}"
    content="${content//\$\{CLAWDBOT_VERSION\}/$CLAWDBOT_VERSION}"
    echo "$content"
}

PROMPT_FILES=(IDENTITY.md SOUL.md USER.md AGENTS.md TOOLS.md MEMORY.md BOOTSTRAP.md HEARTBEAT.md)

for file in "${PROMPT_FILES[@]}"; do
    if [[ -f "$TEMPLATE_DIR/$file" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  Would copy: $file → $WORKSPACE/$file"
        else
            content=$(cat "$TEMPLATE_DIR/$file")
            substituted=$(substitute_vars "$content")
            echo "$substituted" | ssh "$SSH_HOST" "cat > '$WORKSPACE/$file'"
            [[ "$VERBOSE" == "true" ]] && echo "  Copied: $file"
        fi
    fi
done
echo "  ✓ Prompt templates copied"

echo ""
echo "=== Configuring Clawdbot ==="

# Check if agent already exists
if ssh "$SSH_HOST" "cat '$CLAWDBOT_DIR/clawdbot.json' 2>/dev/null | grep -q '\"id\": \"$AGENT_ID\"'"; then
    echo "  Agent '$AGENT_ID' already exists in clawdbot.json"
    echo "  Skipping agent creation (use clawdbot CLI to modify)"
else
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  Would add agent '$AGENT_ID' to clawdbot.json"
    else
        # Add agent using jq if available, otherwise warn
        if ssh "$SSH_HOST" "which jq" >/dev/null 2>&1; then
            # Create new agent entry
            ssh "$SSH_HOST" "jq '.agents.list += [{
                \"id\": \"$AGENT_ID\",
                \"name\": \"$AGENT_NAME\",
                \"workspace\": \"$WORKSPACE\",
                \"agentDir\": \"$AGENT_DIR\",
                \"model\": \"opus\"
            }]' '$CLAWDBOT_DIR/clawdbot.json' > /tmp/cb.json && mv /tmp/cb.json '$CLAWDBOT_DIR/clawdbot.json'"
            echo "  ✓ Agent added to clawdbot.json"
        else
            echo "  ⚠ jq not found — manually add agent to clawdbot.json"
            echo "    See templates/config/clawdbot.json.template for format"
        fi
    fi
fi

# Setup exec-approvals
if [[ "$DRY_RUN" == "true" ]]; then
    echo "  Would create exec-approvals namespace for '$AGENT_ID'"
else
    if ssh "$SSH_HOST" "test -f '$CLAWDBOT_DIR/exec-approvals.json'"; then
        # Check if namespace exists
        if ssh "$SSH_HOST" "cat '$CLAWDBOT_DIR/exec-approvals.json' | grep -q '\"$AGENT_ID\"'"; then
            echo "  Exec-approvals namespace already exists"
        else
            # Add namespace using jq
            if ssh "$SSH_HOST" "which jq" >/dev/null 2>&1; then
                ssh "$SSH_HOST" "jq '.agents[\"$AGENT_ID\"] = {\"allowlist\": [
                    {\"pattern\": \"/usr/bin/grep\", \"id\": \"grep-$AGENT_ID\"},
                    {\"pattern\": \"/usr/bin/wc\", \"id\": \"wc-$AGENT_ID\"},
                    {\"pattern\": \"/bin/ls\", \"id\": \"ls-$AGENT_ID\"},
                    {\"pattern\": \"/bin/cat\", \"id\": \"cat-$AGENT_ID\"},
                    {\"pattern\": \"/bin/echo\", \"id\": \"echo-$AGENT_ID\"}
                ]}' '$CLAWDBOT_DIR/exec-approvals.json' > /tmp/ea.json && mv /tmp/ea.json '$CLAWDBOT_DIR/exec-approvals.json'"
                echo "  ✓ Exec-approvals namespace created"
            else
                echo "  ⚠ jq not found — manually add exec-approvals namespace"
            fi
        fi
    else
        echo "  ⚠ exec-approvals.json not found — will be created on first exec"
    fi
fi

echo ""
echo "=== Verification ==="

if [[ "$DRY_RUN" == "true" ]]; then
    echo "  Would verify: clawdbot status"
else
    echo -n "  Checking clawdbot status... "
    if ssh "$SSH_HOST" "clawdbot status" >/dev/null 2>&1; then
        echo "✓"
    else
        echo "⚠ (may need daemon restart)"
    fi

    echo -n "  Checking workspace... "
    if ssh "$SSH_HOST" "test -d '$WORKSPACE/memory'"; then
        echo "✓"
    else
        echo "✗"
    fi

    echo -n "  Checking prompts... "
    if ssh "$SSH_HOST" "test -f '$WORKSPACE/AGENTS.md'"; then
        echo "✓"
    else
        echo "✗"
    fi
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "  1. Review and customize prompts in $WORKSPACE/"
echo "  2. Add your ANTHROPIC_API_KEY if not already configured"
echo "  3. Start the daemon: ssh $SSH_HOST 'clawdbot daemon start'"
echo "  4. Test: ssh $SSH_HOST 'clawdbot gateway health'"
echo ""
echo "To remove this agent later:"
echo "  ssh $SSH_HOST 'rm -rf $AGENT_DIR'"
echo "  Then remove from clawdbot.json and exec-approvals.json"
