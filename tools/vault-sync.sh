#!/usr/bin/env bash
set -euo pipefail

# vault-sync.sh — Commit vault changes
#
# With vault_mode enabled, content lives in the vault via symlinks.
# This script just commits any changes in the vault repo.
#
# Usage:
#   vault-sync.sh              # Commit vault changes
#   vault-sync.sh --dry-run    # Show what would be committed

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"
load_vault_config

DRY_RUN=false
[[ "${1:-}" == "--dry-run" || "${1:-}" == "-n" ]] && DRY_RUN=true

if [[ "$VAULT_ENABLED" != "true" ]]; then
    echo "Vault mode not enabled. Set vault.enabled: true in config.yaml"
    exit 0
fi

# Support env var override for backward compat
VAULT_PATH="${VAULT_PATH_OVERRIDE:-$VAULT_PATH}"

if [[ ! -d "$VAULT_PATH/.git" ]]; then
    echo "Error: Vault not found at $VAULT_PATH"
    exit 1
fi

echo "=== Vault Commit ==="
echo "Vault: $VAULT_PATH"
echo ""

cd "$VAULT_PATH"

# Show status
git status --short

if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    echo "(dry run — no commit made)"
    exit 0
fi

git add -A
if ! git diff --cached --quiet; then
    git commit -m "vault sync $(date +%Y-%m-%d-%H%M)"
    echo ""
    echo "Vault committed."
else
    echo ""
    echo "No changes to commit."
fi
