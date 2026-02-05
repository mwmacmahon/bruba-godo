#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GODO="$(dirname "$SCRIPT_DIR")"
BRANCH_NAME="vault/propose-$(date +%Y%m%d-%H%M%S)"

echo "=== Vault Propose: private → main ==="
cd "$GODO"

DIFF_FILES=$(git diff --name-only main...private 2>/dev/null \
  | grep -v '^\.' || echo "")

if [ -z "$DIFF_FILES" ]; then
  echo "No content differences between private and main."
  exit 0
fi

echo "Content on private branch not on main:"
echo "$DIFF_FILES" | sed 's/^/  /'
echo ""
read -p "Create PR with these files? [y/N] " -r
[[ ! "$REPLY" =~ ^[Yy]$ ]] && exit 0

git checkout -b "$BRANCH_NAME" main
git merge private --no-edit --squash
git add -f .
git commit -m "content: vault proposal $(date +%Y-%m-%d)"

git push origin "$BRANCH_NAME"
gh pr create \
  --title "Content from vault $(date +%Y-%m-%d)" \
  --body "$(cat <<'EOF'
## Vault Content Proposal

Content from the private branch, filtered through `vault.deny`.
Two gates passed:
1. Allowed past `vault.deny` blacklist (vault → private)
2. Reviewed in this PR (private → main/GitHub)

**After merge:** update `.gitignore` with `!` exceptions for new paths.
EOF
)"

git checkout main
echo ""
echo "PR created. After merge, update .gitignore with ! exceptions."
