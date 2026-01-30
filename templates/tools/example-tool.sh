#!/bin/bash
# Example tool script
#
# This is a template for creating bot tools. Copy and customize.
#
# Usage:
#   ./example-tool.sh [args]
#
# To make this tool available to the bot:
# 1. Copy to ~/clawd/tools/
# 2. chmod +x ~/clawd/tools/example-tool.sh
# 3. Add to exec-approvals.json allowlist
#
# Notes:
# - Use full paths for any binaries (e.g., /usr/bin/grep not grep)
# - Avoid shell built-ins that might not work in allowlist mode
# - Keep output clean — the bot will read it

set -e

# Your code here
echo "Example tool executed with args: $*"
