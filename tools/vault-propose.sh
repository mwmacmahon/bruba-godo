#!/usr/bin/env bash
set -euo pipefail

# vault-propose.sh — Propose vault content for promotion to the public repo
#
# Scans the vault for files that could be promoted (filtered through vault.deny),
# lets you select which ones to include, then creates a PR branch in godo.
#
# No private branch involved — content goes directly from vault to a PR.
#
# Usage:
#   vault-propose.sh              # Interactive: show promotable files, create PR
#   vault-propose.sh --list       # Just list promotable files

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"
load_vault_config

LIST_ONLY=false
[[ "${1:-}" == "--list" ]] && LIST_ONLY=true

if [[ "$VAULT_ENABLED" != "true" ]]; then
    echo "Vault mode not enabled. Set vault.enabled: true in config.yaml"
    exit 1
fi

if [[ ! -d "$VAULT_PATH/.git" ]]; then
    echo "Error: Vault not found at $VAULT_PATH"
    exit 1
fi

DENY_FILE="$VAULT_PATH/vault.deny"

echo "=== Vault Propose ==="
echo "Scanning vault for promotable content..."
echo ""

# Build deny patterns from vault.deny
DENY_PATTERNS=()
if [[ -f "$DENY_FILE" ]]; then
    while IFS= read -r pattern; do
        [[ -z "$pattern" || "$pattern" == \#* ]] && continue
        DENY_PATTERNS+=("$pattern")
    done < "$DENY_FILE"
fi

# Find files in vault that are in vaulted dirs, not denied
PROMOTABLE=()
cd "$VAULT_PATH"

for dir in "${VAULT_DIRS[@]}"; do
    [[ ! -d "$VAULT_PATH/$dir" ]] && continue

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue

        # Check against deny patterns
        local_denied=false
        for pattern in "${DENY_PATTERNS[@]}"; do
            # Simple prefix/glob matching
            clean="${pattern%/}"
            if [[ "$file" == $clean* || "$file" == $pattern ]]; then
                local_denied=true
                break
            fi
        done

        if [[ "$local_denied" == "false" ]]; then
            # Check if file is already tracked in godo (skip if so)
            if ! git -C "$ROOT_DIR" ls-files --error-unmatch "$file" &>/dev/null 2>&1; then
                PROMOTABLE+=("$file")
            fi
        fi
    done < <(cd "$VAULT_PATH" && find "$dir" -type f -not -name '.git' -not -path '*/.git/*' -not -name '.DS_Store' -not -name '.gitkeep' 2>/dev/null)
done

if [[ ${#PROMOTABLE[@]} -eq 0 ]]; then
    echo "No promotable files found."
    echo "(All vault content is either denied by vault.deny or already tracked in godo.)"
    exit 0
fi

echo "Promotable files (${#PROMOTABLE[@]}):"
for i in "${!PROMOTABLE[@]}"; do
    echo "  [$((i+1))] ${PROMOTABLE[$i]}"
done

if [[ "$LIST_ONLY" == "true" ]]; then
    exit 0
fi

echo ""
read -p "Create PR with all these files? [y/N] " -r
[[ ! "$REPLY" =~ ^[Yy]$ ]] && exit 0

# Create PR branch in godo
BRANCH_NAME="vault/propose-$(date +%Y%m%d-%H%M%S)"
cd "$ROOT_DIR"

git checkout -b "$BRANCH_NAME" main

# Copy files from vault to godo (real copies, not symlinks)
for file in "${PROMOTABLE[@]}"; do
    mkdir -p "$(dirname "$file")"
    cp "$VAULT_PATH/$file" "$file"
    git add -f "$file"
done

git commit -m "content: vault proposal $(date +%Y-%m-%d)"

echo ""
read -p "Push and create PR? [y/N] " -r
if [[ "$REPLY" =~ ^[Yy]$ ]]; then
    git push origin "$BRANCH_NAME"
    gh pr create \
        --title "Content from vault $(date +%Y-%m-%d)" \
        --body "$(cat <<'EOF'
## Vault Content Proposal

Content promoted from the vault repo, filtered through `vault.deny`.

**Review:** Check each file for sensitive content before merging.
**After merge:** Update `.gitignore` with `!` exceptions for promoted paths.
EOF
)"
    echo ""
    echo "PR created."
else
    echo ""
    echo "Branch created locally: $BRANCH_NAME"
    echo "Push manually with: git push origin $BRANCH_NAME"
fi

git checkout main
