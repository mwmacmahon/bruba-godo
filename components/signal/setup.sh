#!/bin/bash
# Set up Signal channel for the bot
#
# Usage:
#   ./components/signal/setup.sh              # Interactive mode
#   ./components/signal/setup.sh --dry-run    # Preview without changes
#
# Prerequisites:
#   - Bot already provisioned
#   - signal-cli installed on remote machine

set -e

# Find repo root and load shared functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$ROOT_DIR/tools/lib.sh"

# Defaults
DRY_RUN=false
PHONE_NUMBER=""
LINK_MODE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run|-n)
            DRY_RUN=true
            shift
            ;;
        --phone)
            PHONE_NUMBER="$2"
            shift 2
            ;;
        --link)
            LINK_MODE=true
            shift
            ;;
        --help|-h)
            cat << 'EOF'
Usage: setup.sh [options]

Set up Signal channel for the bot.

Options:
  --phone NUMBER     Bot's phone number (E.164 format: +1234567890)
  --link             Link to existing Signal account (generates QR code)
  --dry-run, -n      Show what would be done without doing it
  --help, -h         Show this help

Examples:
  # Interactive setup
  ./components/signal/setup.sh

  # Register new number
  ./components/signal/setup.sh --phone +15551234567

  # Link to existing Signal account
  ./components/signal/setup.sh --link
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
echo "  Signal Channel Setup"
echo "=========================================="
echo ""

# =============================================================================
# Phase 1: Prerequisites
# =============================================================================

echo "Phase 1: Checking Prerequisites"
echo "---"

# Check SSH
echo -n "  SSH to $SSH_HOST... "
if ssh -o ConnectTimeout=5 -o BatchMode=yes "$SSH_HOST" "echo ok" >/dev/null 2>&1; then
    echo "OK"
else
    echo "FAILED"
    echo "ERROR: Cannot connect to $SSH_HOST" >&2
    exit 1
fi

# Check signal-cli on remote
echo -n "  Remote signal-cli... "
SIGNAL_VERSION=$(ssh "$SSH_HOST" "signal-cli --version 2>/dev/null | head -1" || echo "")
if [[ -n "$SIGNAL_VERSION" ]]; then
    echo "OK ($SIGNAL_VERSION)"
else
    echo "NOT FOUND"
    echo ""
    echo "ERROR: signal-cli not installed on $SSH_HOST" >&2
    echo ""
    echo "Install with:" >&2
    echo "  macOS:  brew install signal-cli" >&2
    echo "  Linux:  Download from https://github.com/AsamK/signal-cli/releases" >&2
    exit 1
fi

# Check clawdbot config exists
CLAWDBOT_DIR=$(ssh "$SSH_HOST" "echo \$HOME/.clawdbot")
echo -n "  Clawdbot config... "
if ssh "$SSH_HOST" "test -f '$CLAWDBOT_DIR/clawdbot.json'"; then
    echo "OK"
else
    echo "NOT FOUND"
    echo ""
    echo "ERROR: clawdbot.json not found. Run provision-bot.sh first." >&2
    exit 1
fi

echo ""

# =============================================================================
# Phase 2: Configuration
# =============================================================================

echo "Phase 2: Configuration"
echo "---"

# Check if Signal is already configured
CURRENT_SIGNAL=$(ssh "$SSH_HOST" "cat '$CLAWDBOT_DIR/clawdbot.json' | grep -o '\"signal\"' 2>/dev/null" || echo "")
if [[ -n "$CURRENT_SIGNAL" ]]; then
    echo "  Signal appears to be already configured in clawdbot.json"
    read -p "  Continue and update configuration? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy] ]]; then
        echo "Aborted."
        exit 0
    fi
fi

# Get phone number
if [[ -z "$PHONE_NUMBER" && "$LINK_MODE" != "true" ]]; then
    echo ""
    echo "  How would you like to set up Signal?"
    echo ""
    echo "    1. Register a new phone number (need to receive SMS)"
    echo "    2. Link to existing Signal account (scan QR code)"
    echo ""
    read -p "  Choice [1/2]: " choice

    case $choice in
        1)
            read -p "  Enter phone number (E.164 format, e.g., +15551234567): " PHONE_NUMBER
            if [[ ! "$PHONE_NUMBER" =~ ^\+[0-9]+$ ]]; then
                echo "ERROR: Invalid phone number format. Use E.164: +CountryCodeNumber" >&2
                exit 1
            fi
            ;;
        2)
            LINK_MODE=true
            ;;
        *)
            echo "Invalid choice" >&2
            exit 1
            ;;
    esac
fi

echo ""

# =============================================================================
# Phase 3: Signal Setup
# =============================================================================

echo "Phase 3: Signal Account Setup"
echo "---"

if [[ "$LINK_MODE" == "true" ]]; then
    # Link mode - generate QR code
    echo "  Generating QR code for linking..."
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [dry-run] Would run: signal-cli link -n 'Bot'"
        echo "  [dry-run] Would generate QR code at qr.io"
    else
        # Generate link URI
        echo "  Running signal-cli link on remote..."
        LINK_URI=$(ssh "$SSH_HOST" "signal-cli link -n 'ClawdBot' 2>&1 | grep -o 'sgnl://.*'" || echo "")

        if [[ -z "$LINK_URI" ]]; then
            echo "  ERROR: Could not generate link URI" >&2
            echo "  Try running manually: ssh $SSH_HOST 'signal-cli link -n Bot'" >&2
            exit 1
        fi

        echo ""
        echo "  ================================================"
        echo "  Scan this QR code with Signal on your phone:"
        echo ""
        echo "  Go to: https://qr.io/"
        echo "  Paste this URI:"
        echo ""
        echo "  $LINK_URI"
        echo ""
        echo "  ================================================"
        echo ""
        echo "  Steps:"
        echo "    1. Open Signal on your phone"
        echo "    2. Go to Settings → Linked Devices → Link New Device"
        echo "    3. Scan the QR code generated at qr.io"
        echo ""
        read -p "  Press Enter after scanning the QR code..."

        # Get the linked number
        echo ""
        echo "  Checking linked account..."
        PHONE_NUMBER=$(ssh "$SSH_HOST" "signal-cli -o json listAccounts 2>/dev/null | head -1" | grep -o '"+[0-9]*"' | tr -d '"' || echo "")

        if [[ -z "$PHONE_NUMBER" ]]; then
            echo "  Could not detect phone number. Please enter it manually."
            read -p "  Phone number: " PHONE_NUMBER
        else
            echo "  Detected phone number: $PHONE_NUMBER"
        fi
    fi
else
    # Register mode
    echo "  Registering new number: $PHONE_NUMBER"
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [dry-run] Would run: signal-cli -u $PHONE_NUMBER register"
        echo "  [dry-run] Would prompt for verification code"
    else
        # Register
        echo "  Sending verification SMS to $PHONE_NUMBER..."
        ssh "$SSH_HOST" "signal-cli -u '$PHONE_NUMBER' register" || {
            echo "ERROR: Registration failed" >&2
            exit 1
        }

        echo ""
        read -p "  Enter verification code from SMS: " VERIFY_CODE

        echo "  Verifying..."
        ssh "$SSH_HOST" "signal-cli -u '$PHONE_NUMBER' verify '$VERIFY_CODE'" || {
            echo "ERROR: Verification failed" >&2
            exit 1
        }

        echo "  Registration successful!"
    fi
fi

echo ""

# =============================================================================
# Phase 4: Update Clawdbot Config
# =============================================================================

echo "Phase 4: Updating Clawdbot Configuration"
echo "---"

if [[ "$DRY_RUN" == "true" ]]; then
    echo "  [dry-run] Would update clawdbot.json with:"
    echo "    channels.signal.enabled = true"
    echo "    channels.signal.phoneNumber = $PHONE_NUMBER"
    echo "    http.port = 8088"
else
    # Update config using jq
    echo "  Updating clawdbot.json..."

    ssh "$SSH_HOST" "
        cd '$CLAWDBOT_DIR'

        # Backup
        cp clawdbot.json clawdbot.json.backup

        # Update with jq
        jq '.channels.signal.enabled = true |
            .channels.signal.phoneNumber = \"$PHONE_NUMBER\" |
            .http.port = 8088' clawdbot.json > clawdbot.json.tmp

        mv clawdbot.json.tmp clawdbot.json
    " && echo "  Config updated successfully"
fi

echo ""

# =============================================================================
# Phase 5: Restart Daemon
# =============================================================================

echo "Phase 5: Restarting Daemon"
echo "---"

if [[ "$DRY_RUN" == "true" ]]; then
    echo "  [dry-run] Would restart clawdbot daemon"
else
    echo "  Restarting clawdbot..."
    ssh "$SSH_HOST" "clawdbot daemon restart 2>&1" | sed 's/^/  /'

    # Wait for startup
    sleep 2

    echo ""
    echo "  Checking status..."
    ssh "$SSH_HOST" "clawdbot daemon status 2>&1" | sed 's/^/  /'
fi

echo ""

# =============================================================================
# Phase 6: Verification
# =============================================================================

echo "Phase 6: Verification"
echo "---"

if [[ "$DRY_RUN" != "true" ]]; then
    # Check Signal channel is enabled
    echo -n "  Signal channel... "
    if ssh "$SSH_HOST" "cat '$CLAWDBOT_DIR/clawdbot.json' | grep -q '\"signal\".*\"enabled\".*true'"; then
        echo "ENABLED"
    else
        echo "CHECK FAILED"
    fi

    # Check http port
    echo -n "  HTTP port... "
    HTTP_PORT=$(ssh "$SSH_HOST" "cat '$CLAWDBOT_DIR/clawdbot.json' | grep -o '\"port\".*[0-9]*' | grep -o '[0-9]*' | head -1" || echo "unknown")
    echo "$HTTP_PORT"
fi

echo ""

# =============================================================================
# Summary
# =============================================================================

echo "=========================================="
echo "  Signal Setup Complete"
echo "=========================================="
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
    echo "This was a dry run. No changes were made."
else
    echo "Signal channel is now enabled!"
    echo ""
    echo "To message your bot:"
    echo "  1. Open Signal on your phone"
    echo "  2. Start a new message to: $PHONE_NUMBER"
    echo "  3. Say hello!"
    echo ""
    echo "Notes:"
    echo "  - Bot must be running (clawdbot daemon start)"
    echo "  - First message may take a moment to respond"
    echo "  - Voice messages work if whisper is configured"
fi
