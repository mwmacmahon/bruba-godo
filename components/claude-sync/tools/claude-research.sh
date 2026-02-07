#!/bin/bash
#
# claude-research.sh - Send research questions to Claude.ai Projects
#
# Wrapper around claude-research.py that handles venv activation
# and argument passing. Runs on the bot machine.
#
# Usage:
#   claude-research.sh --project <URL> --question "..." [--output PATH] [--timeout 120]
#   claude-research.sh --help
#
# Exit codes:
#   0 = success (output path printed to stdout)
#   1 = error
#   2 = auth expired (re-login needed)
#
# Version: 1.0.0
# Updated: 2026-02-06

set -e

SYNC_DIR="/Users/bruba/claude-sync"
VENV_DIR="$SYNC_DIR/.venv"
SCRIPT="$SYNC_DIR/claude-research.py"

# Show help
if [[ "$1" == "--help" || "$1" == "-h" || $# -eq 0 ]]; then
    cat << 'EOF'
claude-research.sh - Send research questions to Claude.ai Projects

USAGE:
    claude-research.sh --project <URL> --question "question text" [options]

REQUIRED:
    --project URL       Claude.ai project URL
    --question TEXT      Research question to ask

OPTIONS:
    --output PATH       Output file path (default: auto-generated)
    --timeout SECONDS   Max wait for response (default: 120)
    --visible           Show browser window (for debugging)
    --help              Show this help

EXAMPLES:
    # Basic research query
    claude-research.sh \
      --project "https://claude.ai/project/abc123" \
      --question "What are the key differences between REST and GraphQL?"

    # With custom output and timeout
    claude-research.sh \
      --project "https://claude.ai/project/abc123" \
      --question "Summarize recent Playwright changelog" \
      --output /Users/bruba/claude-sync/results/playwright-changes.md \
      --timeout 180

EXIT CODES:
    0   Success (result path printed to stdout)
    1   Error (check stderr for details)
    2   Auth expired (run setup.sh --login to re-authenticate)
EOF
    exit 0
fi

# Validate sync directory exists
if [[ ! -d "$SYNC_DIR" ]]; then
    echo "ERROR: claude-sync not set up. Directory not found: $SYNC_DIR" >&2
    echo "Run: components/claude-sync/setup.sh" >&2
    exit 1
fi

# Validate venv exists
if [[ ! -f "$VENV_DIR/bin/python" ]]; then
    echo "ERROR: Python venv not found at $VENV_DIR" >&2
    echo "Run: components/claude-sync/setup.sh" >&2
    exit 1
fi

# Validate script exists
if [[ ! -f "$SCRIPT" ]]; then
    echo "ERROR: claude-research.py not found at $SCRIPT" >&2
    echo "Run: components/claude-sync/setup.sh" >&2
    exit 1
fi

# Activate venv and run
source "$VENV_DIR/bin/activate"
exec python "$SCRIPT" "$@"
