#!/bin/bash
# sync-memory.sh - Sync workspace snapshots and repos to agent memory directories
#
# This script:
# 1. Snapshots each agent's workspace/ into memory/workspace-snapshot/ (so working files become searchable)
# 2. Syncs bruba-godo repo to all agents' memory/repos/
# 3. Reindexes memory for all agents
#
# Run this as part of the push workflow or standalone.

set -e

# Load config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

AGENTS="bruba-main bruba-guru bruba-manager"
BOT_BASE="/Users/bruba/agents"
SSH_HOST="${SSH_HOST:-bruba}"

echo "=== Sync Memory ==="
echo "Agents: $AGENTS"
echo ""

# Phase 1: Snapshot workspace into memory/workspace-snapshot for each agent
for agent in $AGENTS; do
  AGENT_DIR="$BOT_BASE/$agent"

  # Check if this agent has a workspace-snapshot directory
  if ssh "$SSH_HOST" "test -d $AGENT_DIR/memory/workspace-snapshot"; then
    echo "[$agent] Snapshotting workspace..."
    ssh "$SSH_HOST" "rsync -av --delete \
      --exclude='.DS_Store' \
      --exclude='*.tmp' \
      $AGENT_DIR/workspace/ \
      $AGENT_DIR/memory/workspace-snapshot/" | sed 's/^/  /'
  else
    echo "[$agent] No workspace-snapshot directory, skipping"
  fi
done

echo ""

# Phase 2: Sync bruba-godo repo to all agents' memory/repos/
echo "=== Syncing bruba-godo repo ==="
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

for agent in $AGENTS; do
  AGENT_DIR="$BOT_BASE/$agent"
  echo "[$agent] Syncing bruba-godo repo..."
  rsync -av --delete \
    --exclude='.git' \
    --exclude='node_modules' \
    --exclude='sessions/' \
    --exclude='logs/' \
    --exclude='mirror/' \
    --exclude='exports/' \
    --exclude='intake/' \
    --exclude='reference/' \
    --exclude='.claude/' \
    "$REPO_DIR/" \
    "$SSH_HOST:$AGENT_DIR/memory/repos/bruba-godo/" | sed 's/^/  /'
done

echo ""

# Phase 3: Reindex memory
echo "=== Reindexing memory ==="
ssh "$SSH_HOST" 'openclaw memory index --verbose' | sed 's/^/  /'

echo ""
echo "=== Done ==="
