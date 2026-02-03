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

# Load config for SSH settings
load_config 2>/dev/null || true

AGENTS="bruba-main bruba-guru bruba-manager"
BOT_BASE="/Users/bruba/agents"
SSH_HOST="${SSH_HOST:-bruba}"
SSH_OPTS="${SSH_OPTS:--o ControlMaster=auto -o ControlPath=/tmp/ssh-%r@%h:%p -o ControlPersist=60}"

echo "=== Sync Memory ==="
echo "Agents: $AGENTS"
echo ""

# Phase 1: Snapshot workspace into memory/workspace-snapshot for each agent
for agent in $AGENTS; do
  AGENT_DIR="$BOT_BASE/$agent"

  # Check if this agent has a workspace-snapshot directory
  if ssh $SSH_OPTS "$SSH_HOST" "test -d $AGENT_DIR/memory/workspace-snapshot"; then
    echo "[$agent] Snapshotting workspace..."
    ssh $SSH_OPTS "$SSH_HOST" "rsync -av --delete \
      --exclude='.DS_Store' \
      --exclude='*.tmp' \
      $AGENT_DIR/workspace/ \
      $AGENT_DIR/memory/workspace-snapshot/" | sed 's/^/  /'
  else
    echo "[$agent] No workspace-snapshot directory, skipping"
  fi
done

echo ""

# Phase 2: Sync bruba-godo repo to all agents' memory/repos/ (in parallel)
echo "=== Syncing bruba-godo repo (parallel) ==="
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Launch rsync jobs in parallel
pids=()
for agent in $AGENTS; do
  AGENT_DIR="$BOT_BASE/$agent"
  echo "[$agent] Starting repo sync..."
  (
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
      "$SSH_HOST:$AGENT_DIR/memory/repos/bruba-godo/" >/dev/null 2>&1
    echo "[$agent] Repo sync complete"
  ) &
  pids+=($!)
done

# Wait for all parallel jobs to complete
for pid in "${pids[@]}"; do
  wait "$pid" 2>/dev/null || echo "Warning: A sync job failed"
done
echo "All repo syncs complete"

echo ""

# Phase 3: Reindex memory
echo "=== Reindexing memory ==="
ssh $SSH_OPTS "$SSH_HOST" 'openclaw memory index --verbose' | sed 's/^/  /'

echo ""
echo "=== Done ==="
