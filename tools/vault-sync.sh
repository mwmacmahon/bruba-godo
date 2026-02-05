#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GODO="$(dirname "$SCRIPT_DIR")"
VAULT="${VAULT_PATH:-/Users/dadbook/source/bruba-vault}"
CURRENT_BRANCH="$(git -C "$GODO" branch --show-current)"

if [ ! -d "$VAULT/.git" ]; then
  echo "Error: Vault not found at $VAULT"
  exit 1
fi

# ── Phase 1: Delegate to vault's own sync script ──
echo "=== Phase 1: Vault Sync ==="
"$VAULT/sync-from-godo.sh"

# ── Phase 2: Push filtered content to private branch ──
echo ""
echo "=== Phase 2: Update Private Branch ==="

if [ ! -f "$VAULT/vault.deny" ]; then
  echo "Error: $VAULT/vault.deny not found"
  exit 1
fi

# Stash uncommitted changes
cd "$GODO"
STASHED=false
if ! git diff --quiet || ! git diff --cached --quiet; then
  git stash push -m "vault-sync auto-stash"
  STASHED=true
fi

# Create private branch if needed
if ! git rev-parse --verify private &>/dev/null; then
  echo "Creating private branch from main..."
  git branch private main
fi

git checkout private

# Merge code changes from main
if ! git merge main --no-edit 2>/dev/null; then
  echo "Error: merge conflict merging main into private."
  echo "Resolve manually: git checkout private && git merge main"
  git merge --abort
  git checkout "$CURRENT_BRANCH"
  [ "$STASHED" = true ] && git stash pop
  exit 1
fi

# Build rsync exclude list from vault.deny
EXCLUDE_ARGS=()
while IFS= read -r pattern; do
  [[ -z "$pattern" || "$pattern" == \#* ]] && continue
  EXCLUDE_ARGS+=(--exclude="$pattern")
done < "$VAULT/vault.deny"
EXCLUDE_ARGS+=(--exclude=".git" --exclude="vault.deny"
               --exclude=".gitignore" --exclude="sync-from-godo.sh"
               --exclude="sync-to-icloud.sh")

# Sync content dirs that aren't denied
SYNC_DIRS=("sessions" "intake" "reference" "exports" "assembled"
           "mirror" "docs/cc_logs" "docs/meta")

for dir in "${SYNC_DIRS[@]}"; do
  if [ -d "$VAULT/$dir" ]; then
    # Check if dir is fully denied
    DENIED=false
    while IFS= read -r pattern; do
      [[ -z "$pattern" || "$pattern" == \#* ]] && continue
      clean="${pattern%/}"
      if [[ "$dir" == ${clean}* ]]; then
        DENIED=true
        break
      fi
    done < "$VAULT/vault.deny"

    if [ "$DENIED" = false ]; then
      mkdir -p "$GODO/$dir"
      rsync -a --delete "${EXCLUDE_ARGS[@]}" "$VAULT/$dir/" "$GODO/$dir/"
    fi
  fi
done

# Force-add bypasses .gitignore on private branch
git add -f .
if ! git diff --cached --quiet; then
  git commit -m "vault content sync $(date +%Y-%m-%d-%H%M)"
  echo "Private branch updated."
else
  echo "Private branch: no changes."
fi

# Return to original branch
git checkout "$CURRENT_BRANCH"
[ "$STASHED" = true ] && git stash pop

echo ""
echo "Done. Currently on: $CURRENT_BRANCH"
