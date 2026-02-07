#!/bin/bash
# Claude Sync component setup
#
# Deploys claude-sync infrastructure to the bot machine.
#
# Usage:
#   ./components/claude-sync/setup.sh              # Full deploy
#   ./components/claude-sync/setup.sh --login       # Launch visible browser for auth
#   ./components/claude-sync/setup.sh --inspect     # Launch visible browser for selector discovery
#
# Prerequisites:
#   - Bot access (./tools/bot works)
#   - Python 3.8+ on bot

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$ROOT_DIR/tools/lib.sh"

SYNC_DIR="/Users/bruba/claude-sync"
DEPLOY_DIR="$SCRIPT_DIR/bot-deploy"

# Parse arguments
MODE="deploy"
for arg in "$@"; do
    case $arg in
        --login)
            MODE="login"
            ;;
        --inspect)
            MODE="inspect"
            ;;
        --help|-h)
            echo "Usage: ./components/claude-sync/setup.sh [--login] [--inspect]"
            echo ""
            echo "Modes:"
            echo "  (default)    Deploy claude-sync infrastructure to bot"
            echo "  --login      Launch visible browser for manual claude.ai login"
            echo "  --inspect    Launch visible browser for CSS selector discovery"
            echo ""
            exit 0
            ;;
    esac
done

# Load config for bot access
load_config

echo "=== Claude Sync Setup ==="
echo ""

# --- Login mode: launch visible browser for auth ---
if [[ "$MODE" == "login" ]]; then
    echo "Launching visible browser for claude.ai login..."
    echo ""
    echo "Instructions:"
    echo "  1. A browser window will open on the bot"
    echo "  2. Navigate to https://claude.ai and log in"
    echo "  3. Once logged in, close the browser window"
    echo "  4. Auth cookies will be saved in the persistent profile"
    echo ""

    bot_exec "cd $SYNC_DIR && source .venv/bin/activate && python -c \"
from playwright.sync_api import sync_playwright
import time

with sync_playwright() as p:
    ctx = p.chromium.launch_persistent_context(
        '$SYNC_DIR/profile',
        headless=False,
        args=['--no-first-run', '--no-default-browser-check'],
        viewport={'width': 1280, 'height': 900},
    )
    page = ctx.pages[0] if ctx.pages else ctx.new_page()
    page.goto('https://claude.ai')
    print('Browser opened. Log in to claude.ai, then close the window.')
    try:
        while len(ctx.pages) > 0:
            time.sleep(1)
    except Exception:
        pass
    ctx.close()
print('Login session saved.')
\""

    echo ""
    echo "Login complete. Run validate.sh to verify."
    exit 0
fi

# --- Inspect mode: launch visible browser for selector discovery ---
if [[ "$MODE" == "inspect" ]]; then
    echo "Launching visible browser for selector inspection..."
    echo ""
    echo "Instructions:"
    echo "  1. A browser window will open on the bot"
    echo "  2. Right-click elements → Inspect to find CSS selectors"
    echo "  3. Update selectors.json with discovered values"
    echo "  4. Close the browser when done"
    echo ""

    bot_exec "cd $SYNC_DIR && source .venv/bin/activate && python -c \"
from playwright.sync_api import sync_playwright
import time

with sync_playwright() as p:
    ctx = p.chromium.launch_persistent_context(
        '$SYNC_DIR/profile',
        headless=False,
        args=['--no-first-run', '--no-default-browser-check', '--auto-open-devtools-for-tabs'],
        viewport={'width': 1280, 'height': 900},
    )
    page = ctx.pages[0] if ctx.pages else ctx.new_page()
    page.goto('https://claude.ai')
    print('Browser opened with DevTools. Inspect elements to find selectors.')
    print('Close the browser window when done.')
    try:
        while len(ctx.pages) > 0:
            time.sleep(1)
    except Exception:
        pass
    ctx.close()
print('Inspect session ended.')
\""

    echo ""
    echo "Update selectors.json with any new selectors, then redeploy:"
    echo "  ./components/claude-sync/setup.sh"
    exit 0
fi

# --- Deploy mode ---

# Step 1: Check bot access
echo "Checking bot access..."
if bot_exec "echo ok" >/dev/null 2>&1; then
    echo "  ✓ Bot access works"
else
    echo "  ✗ Cannot reach bot. Check transport config."
    exit 1
fi

# Step 2: Check Python on bot
echo ""
echo "Checking Python on bot..."
BOT_PYTHON=$(bot_exec "python3 --version 2>&1" || true)
if echo "$BOT_PYTHON" | grep -qE "Python 3\.[89]|Python 3\.1[0-9]"; then
    echo "  ✓ $BOT_PYTHON"
else
    echo "  ✗ Python 3.8+ required on bot. Found: $BOT_PYTHON"
    exit 1
fi

# Step 3: Create directory structure on bot
echo ""
echo "Creating directories..."
bot_exec "mkdir -p $SYNC_DIR/{profile,results}"
echo "  ✓ Created $SYNC_DIR/"
echo "  ✓ Created $SYNC_DIR/profile/"
echo "  ✓ Created $SYNC_DIR/results/"

# Step 4: Deploy bot-deploy files
echo ""
echo "Deploying files..."

for file in claude-research.py common.py selectors.json requirements.txt; do
    local_path="$DEPLOY_DIR/$file"
    if [[ ! -f "$local_path" ]]; then
        echo "  ✗ Missing: $local_path"
        exit 1
    fi

    # Use the bot tool's transport to copy
    case "$BOT_TRANSPORT" in
        sudo)
            sudo cp "$local_path" "$SYNC_DIR/$file"
            sudo chown "$BOT_USER:staff" "$SYNC_DIR/$file"
            ;;
        tailscale-ssh)
            scp -q "$local_path" "${BOT_HOST}:${SYNC_DIR}/$file"
            ;;
        ssh)
            scp -q $SSH_OPTS "$local_path" "${SSH_HOST}:${SYNC_DIR}/$file"
            ;;
    esac
    echo "  ✓ Deployed $file"
done

# Step 5: Create venv and install dependencies
echo ""
echo "Setting up Python environment..."
bot_exec "cd $SYNC_DIR && python3 -m venv .venv 2>&1" || {
    echo "  ✗ Failed to create venv"
    exit 1
}
echo "  ✓ Created venv"

bot_exec "cd $SYNC_DIR && source .venv/bin/activate && pip install -q -r requirements.txt 2>&1" || {
    echo "  ✗ Failed to install requirements"
    exit 1
}
echo "  ✓ Installed requirements"

# Step 6: Install Chromium via Playwright
echo ""
echo "Installing Chromium (this may take a moment)..."
bot_exec "cd $SYNC_DIR && source .venv/bin/activate && playwright install chromium 2>&1" || {
    echo "  ✗ Failed to install Chromium"
    exit 1
}
echo "  ✓ Chromium installed"

# Step 7: Run validation
echo ""
echo "Running validation..."
"$SCRIPT_DIR/validate.sh" --quick

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "  1. Login to claude.ai:  ./components/claude-sync/setup.sh --login"
echo "  2. Discover selectors:  ./components/claude-sync/setup.sh --inspect"
echo "  3. Update selectors:    Edit components/claude-sync/bot-deploy/selectors.json"
echo "  4. Redeploy selectors:  ./components/claude-sync/setup.sh"
echo "  5. Test:                ./tools/bot $SHARED_TOOLS/claude-research.sh --help"
echo ""
