#!/bin/bash
# Provision a new bot on a remote machine
#
# This is the high-level orchestration script for setting up a complete bot.
# It handles prerequisites, workspace creation, agent setup, and verification.
#
# Usage:
#   ./tools/provision-bot.sh                     # Interactive mode
#   ./tools/provision-bot.sh --dry-run           # Preview without changes
#   ./tools/provision-bot.sh --bot-name mybot    # With options
#
# Prerequisites:
#   - SSH access to remote machine (see docs/setup-operator-ssh.md)
#   - Clawdbot installed on remote machine
#   - jq available locally (for JSON manipulation)
#
# This script orchestrates:
#   1. Prerequisites checks (SSH, clawdbot, jq)
#   2. Gathering configuration interactively or from flags
#   3. Creating workspace structure on remote
#   4. Calling setup-agent.sh for template setup
#   5. Security hardening (permissions)
#   6. Verification and next steps

set -e

# Load shared functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# Defaults
BOT_NAME=""
AGENT_ID=""
USER_NAME=""
WORKSPACE=""
DRY_RUN=false
NON_INTERACTIVE=false
SKIP_VERIFY=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --bot-name)
            BOT_NAME="$2"
            shift 2
            ;;
        --agent-id)
            AGENT_ID="$2"
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
        --non-interactive)
            NON_INTERACTIVE=true
            shift
            ;;
        --skip-verify)
            SKIP_VERIFY=true
            shift
            ;;
        --help|-h)
            cat << 'EOF'
Usage: provision-bot.sh [options]

Provision a new bot on a remote machine.

Options:
  --bot-name NAME       Bot display name (e.g., "My Bot")
  --agent-id ID         Agent identifier (e.g., my-bot, used in paths)
  --user-name NAME      Your name (for USER.md template)
  --workspace PATH      Remote workspace path (default: ~/clawd)
  --dry-run, -n         Show what would be done without doing it
  --non-interactive     Don't prompt for values (use defaults)
  --skip-verify         Skip final verification steps
  --help, -h            Show this help

Prerequisites:
  1. SSH access configured (see docs/setup-operator-ssh.md)
  2. Clawdbot installed on remote: npm install -g clawdbot
  3. jq available locally: brew install jq (or apt install jq)

Examples:
  # Interactive setup
  ./tools/provision-bot.sh

  # Quick setup with all options
  ./tools/provision-bot.sh \
    --bot-name "Kitchen Bot" \
    --agent-id kitchen-bot \
    --user-name "Alex" \
    --workspace /Users/kitchenbot/clawd

  # Preview what would happen
  ./tools/provision-bot.sh --dry-run

This script calls setup-agent.sh internally for template substitution.
EOF
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

echo "=========================================="
echo "  Bot Provisioning"
echo "=========================================="
echo ""

# =============================================================================
# Phase 1: Prerequisites
# =============================================================================

echo "Phase 1: Checking Prerequisites"
echo "---"

# Check local tools
echo -n "  Local jq... "
if command_exists jq; then
    echo "OK ($(jq --version))"
else
    echo "MISSING"
    echo ""
    echo "ERROR: jq is required for JSON manipulation." >&2
    echo "Install with: brew install jq (macOS) or apt install jq (Linux)" >&2
    exit 1
fi

# Check SSH connectivity
echo -n "  SSH to $SSH_HOST... "
if ssh -o ConnectTimeout=5 -o BatchMode=yes "$SSH_HOST" "echo ok" >/dev/null 2>&1; then
    echo "OK"
else
    echo "FAILED"
    echo ""
    echo "ERROR: Cannot connect to $SSH_HOST" >&2
    echo "Check your SSH config. See docs/setup-operator-ssh.md for help." >&2
    exit 1
fi

# Check clawdbot on remote
echo -n "  Remote clawdbot... "
CLAWDBOT_VERSION=$(ssh "$SSH_HOST" "clawdbot --version 2>/dev/null" || echo "")
if [[ -n "$CLAWDBOT_VERSION" ]]; then
    echo "OK (v$CLAWDBOT_VERSION)"
else
    echo "MISSING"
    echo ""
    echo "ERROR: clawdbot not found on $SSH_HOST" >&2
    echo "Install with: npm install -g clawdbot" >&2
    exit 1
fi

# Check remote jq
echo -n "  Remote jq... "
if ssh "$SSH_HOST" "which jq" >/dev/null 2>&1; then
    echo "OK"
    REMOTE_HAS_JQ=true
else
    echo "MISSING (optional, setup-agent.sh will warn)"
    REMOTE_HAS_JQ=false
fi

# Get remote home directory
REMOTE_HOME_ACTUAL=$(ssh "$SSH_HOST" "echo \$HOME")
REMOTE_USER=$(ssh "$SSH_HOST" "whoami")
echo "  Remote user: $REMOTE_USER"
echo "  Remote home: $REMOTE_HOME_ACTUAL"

echo ""
echo "  All prerequisites passed!"
echo ""

# =============================================================================
# Phase 2: Gather Configuration
# =============================================================================

echo "Phase 2: Configuration"
echo "---"

if [[ "$NON_INTERACTIVE" != "true" ]]; then
    # Interactive prompts
    if [[ -z "$BOT_NAME" ]]; then
        read -p "  Bot name (display name, e.g., 'Bruba'): " BOT_NAME
    fi
    BOT_NAME="${BOT_NAME:-MyBot}"

    if [[ -z "$AGENT_ID" ]]; then
        # Suggest agent ID from bot name
        suggested_id=$(echo "$BOT_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
        read -p "  Agent ID (for paths, default: $suggested_id): " AGENT_ID
        AGENT_ID="${AGENT_ID:-$suggested_id}"
    fi

    if [[ -z "$USER_NAME" ]]; then
        read -p "  Your name (for USER.md template): " USER_NAME
    fi
    USER_NAME="${USER_NAME:-User}"

    if [[ -z "$WORKSPACE" ]]; then
        read -p "  Workspace path (default: $REMOTE_HOME_ACTUAL/clawd): " WORKSPACE
    fi
else
    # Non-interactive defaults
    BOT_NAME="${BOT_NAME:-MyBot}"
    AGENT_ID="${AGENT_ID:-$(echo "$BOT_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')}"
    USER_NAME="${USER_NAME:-User}"
fi

WORKSPACE="${WORKSPACE:-$REMOTE_HOME_ACTUAL/clawd}"
CLAWDBOT_DIR="$REMOTE_HOME_ACTUAL/.clawdbot"
AGENT_DIR="$CLAWDBOT_DIR/agents/$AGENT_ID"

echo ""
echo "  Configuration:"
echo "    Bot Name:   $BOT_NAME"
echo "    Agent ID:   $AGENT_ID"
echo "    User Name:  $USER_NAME"
echo "    Workspace:  $WORKSPACE"
echo "    Agent Dir:  $AGENT_DIR"
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
    echo "  [DRY RUN MODE - no changes will be made]"
    echo ""
fi

# Confirm before proceeding
if [[ "$NON_INTERACTIVE" != "true" && "$DRY_RUN" != "true" ]]; then
    read -p "  Proceed with provisioning? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy] ]]; then
        echo "Aborted."
        exit 0
    fi
    echo ""
fi

# =============================================================================
# Phase 3: Create Workspace
# =============================================================================

echo "Phase 3: Creating Workspace"
echo "---"

# Directories to create
DIRS_TO_CREATE=(
    "$WORKSPACE"
    "$WORKSPACE/memory"
    "$WORKSPACE/memory/archive"
    "$WORKSPACE/tools"
    "$WORKSPACE/tools/helpers"
    "$WORKSPACE/output"
)

for dir in "${DIRS_TO_CREATE[@]}"; do
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [dry-run] mkdir -p $dir"
    else
        ssh "$SSH_HOST" "mkdir -p '$dir'" && echo "  Created: $dir"
    fi
done

echo ""

# =============================================================================
# Phase 4: Setup Agent (templates, config)
# =============================================================================

echo "Phase 4: Setting Up Agent"
echo "---"

# Build setup-agent.sh arguments
SETUP_ARGS=(
    --agent-id "$AGENT_ID"
    --agent-name "$BOT_NAME"
    --user-name "$USER_NAME"
    --workspace "$WORKSPACE"
    --skip-prompts
)

if [[ "$DRY_RUN" == "true" ]]; then
    SETUP_ARGS+=(--dry-run)
fi

# Call setup-agent.sh
echo "  Running setup-agent.sh..."
"$SCRIPT_DIR/setup-agent.sh" "${SETUP_ARGS[@]}" 2>&1 | sed 's/^/  /'

echo ""

# =============================================================================
# Phase 5: Security Hardening
# =============================================================================

echo "Phase 5: Security Hardening"
echo "---"

# Set proper permissions
if [[ "$DRY_RUN" == "true" ]]; then
    echo "  [dry-run] chmod 700 $WORKSPACE"
    echo "  [dry-run] chmod 700 $CLAWDBOT_DIR"
    echo "  [dry-run] chmod 600 $CLAWDBOT_DIR/*.json"
else
    ssh "$SSH_HOST" "chmod 700 '$WORKSPACE'" && echo "  Set permissions: $WORKSPACE (700)"
    ssh "$SSH_HOST" "chmod 700 '$CLAWDBOT_DIR' 2>/dev/null" && echo "  Set permissions: $CLAWDBOT_DIR (700)" || echo "  Skipped: $CLAWDBOT_DIR (may not exist yet)"
    ssh "$SSH_HOST" "chmod 600 '$CLAWDBOT_DIR'/*.json 2>/dev/null" && echo "  Set permissions: *.json (600)" || echo "  Skipped: *.json (may not exist yet)"
fi

echo ""

# =============================================================================
# Phase 6: Verification
# =============================================================================

if [[ "$SKIP_VERIFY" != "true" && "$DRY_RUN" != "true" ]]; then
    echo "Phase 6: Verification"
    echo "---"

    # Check workspace exists
    echo -n "  Workspace directory... "
    if ssh "$SSH_HOST" "test -d '$WORKSPACE/memory'"; then
        echo "OK"
    else
        echo "MISSING"
    fi

    # Check prompts were copied
    echo -n "  Prompt files... "
    PROMPT_COUNT=$(ssh "$SSH_HOST" "ls -1 '$WORKSPACE'/*.md 2>/dev/null | wc -l" | tr -d ' ')
    if [[ "$PROMPT_COUNT" -gt 0 ]]; then
        echo "OK ($PROMPT_COUNT files)"
    else
        echo "NONE FOUND"
    fi

    # Check clawdbot config
    echo -n "  Clawdbot config... "
    if ssh "$SSH_HOST" "test -f '$CLAWDBOT_DIR/clawdbot.json'"; then
        if ssh "$SSH_HOST" "cat '$CLAWDBOT_DIR/clawdbot.json' | grep -q '\"$AGENT_ID\"'"; then
            echo "OK (agent registered)"
        else
            echo "WARN (agent not in config)"
        fi
    else
        echo "MISSING (will be created on first run)"
    fi

    # Check daemon status
    echo -n "  Daemon status... "
    DAEMON_STATUS=$(ssh "$SSH_HOST" "clawdbot daemon status 2>&1" || echo "not running")
    if echo "$DAEMON_STATUS" | grep -q "running"; then
        echo "RUNNING"
    else
        echo "NOT RUNNING (start with: clawdbot daemon start)"
    fi

    echo ""
fi

# =============================================================================
# Summary
# =============================================================================

echo "=========================================="
echo "  Provisioning Complete"
echo "=========================================="
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
    echo "This was a dry run. No changes were made."
    echo "Run without --dry-run to provision for real."
else
    echo "Next steps:"
    echo ""
    echo "  1. Review and customize prompts:"
    echo "     ssh $SSH_HOST cat $WORKSPACE/IDENTITY.md"
    echo ""
    echo "  2. Add API key (if not already set):"
    echo "     ssh $SSH_HOST 'echo \"export ANTHROPIC_API_KEY=sk-ant-...\" >> ~/.zshrc'"
    echo ""
    echo "  3. Start the daemon:"
    echo "     ssh $SSH_HOST 'clawdbot daemon start'"
    echo ""
    echo "  4. Connect via Signal (optional):"
    echo "     ./components/signal/setup.sh"
    echo ""
    echo "  5. Test from this operator workspace:"
    echo "     ./tools/bot clawdbot status"
    echo ""
fi
