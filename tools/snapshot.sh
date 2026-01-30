#!/bin/bash
#
# snapshot.sh - Create a full backup of bot configuration and memory
#
# Creates a timestamped archive of:
#   - ~/.clawdbot/ (config, exec-approvals, etc.)
#   - ~/clawd/ (workspace, memory)
#
# Usage:
#   ./tools/snapshot.sh                   # Create snapshot
#   ./tools/snapshot.sh --output /path    # Custom output directory
#   ./tools/snapshot.sh --dry-run         # Show what would be backed up
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Source shared library
source "$SCRIPT_DIR/lib.sh"

# Defaults
OUTPUT_DIR="$REPO_ROOT/snapshots"
DRY_RUN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Create a timestamped backup of bot configuration and memory."
            echo ""
            echo "Options:"
            echo "  --output DIR    Output directory (default: snapshots/)"
            echo "  --dry-run       Show what would be backed up"
            echo "  --verbose, -v   Verbose output"
            echo "  --help, -h      Show this help"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Load config
load_config

# Get remote paths
REMOTE_HOME=$(get_config ".remote.home" "/Users/bruba")
REMOTE_CLAWDBOT=$(get_config ".remote.clawdbot" "$REMOTE_HOME/.clawdbot")
REMOTE_WORKSPACE=$(get_config ".remote.workspace" "$REMOTE_HOME/clawd")

# Generate snapshot name
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SNAPSHOT_NAME="snapshot-$TIMESTAMP"

if $DRY_RUN; then
    log_info "Dry run - would back up:"
    echo "  Config: $REMOTE_CLAWDBOT/"
    echo "    - clawdbot.json"
    echo "    - exec-approvals.json"
    echo "    - .env"
    echo "  Workspace: $REMOTE_WORKSPACE/"
    echo "    - *.md (core files)"
    echo "    - memory/ (memory files)"
    echo "    - tools/ (custom tools)"
    echo ""
    echo "  Output: $OUTPUT_DIR/$SNAPSHOT_NAME.tar.gz"
    exit 0
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Create temp directory for staging
TEMP_DIR=$(mktemp -d)
STAGING_DIR="$TEMP_DIR/$SNAPSHOT_NAME"
mkdir -p "$STAGING_DIR/config"
mkdir -p "$STAGING_DIR/workspace"

log_info "Creating snapshot: $SNAPSHOT_NAME"

# Copy config files
log_info "Backing up config..."
run_remote "cat $REMOTE_CLAWDBOT/clawdbot.json" > "$STAGING_DIR/config/clawdbot.json" 2>/dev/null || true
run_remote "cat $REMOTE_CLAWDBOT/exec-approvals.json" > "$STAGING_DIR/config/exec-approvals.json" 2>/dev/null || true
run_remote "cat $REMOTE_CLAWDBOT/.env" > "$STAGING_DIR/config/.env" 2>/dev/null || true

# Copy workspace core files
log_info "Backing up workspace..."
for file in AGENTS.md BOOTSTRAP.md HEARTBEAT.md IDENTITY.md MEMORY.md SOUL.md TOOLS.md USER.md; do
    run_remote "cat $REMOTE_WORKSPACE/$file" > "$STAGING_DIR/workspace/$file" 2>/dev/null || true
done

# Copy memory directory
log_info "Backing up memory..."
mkdir -p "$STAGING_DIR/workspace/memory"
rsync -az --quiet \
    -e "ssh" \
    "$(get_ssh_host):$REMOTE_WORKSPACE/memory/" \
    "$STAGING_DIR/workspace/memory/" 2>/dev/null || true

# Copy tools directory
log_info "Backing up tools..."
mkdir -p "$STAGING_DIR/workspace/tools"
rsync -az --quiet \
    -e "ssh" \
    "$(get_ssh_host):$REMOTE_WORKSPACE/tools/" \
    "$STAGING_DIR/workspace/tools/" 2>/dev/null || true

# Create metadata file
cat > "$STAGING_DIR/SNAPSHOT.md" << EOF
# Snapshot Metadata

**Created:** $(date -u +"%Y-%m-%dT%H:%M:%SZ")
**Host:** $(get_ssh_host)
**Agent ID:** $(get_config ".remote.agent_id" "unknown")

## Contents

- \`config/\` - Clawdbot configuration
  - clawdbot.json - Main config
  - exec-approvals.json - Exec allowlist
  - .env - API keys
- \`workspace/\` - Bot workspace
  - Core prompt files (AGENTS.md, SOUL.md, etc.)
  - memory/ - Memory files
  - tools/ - Custom tools

## Restore

To restore this snapshot:

\`\`\`bash
# Extract
tar -xzf $SNAPSHOT_NAME.tar.gz

# Copy config (careful - will overwrite!)
scp -r $SNAPSHOT_NAME/config/* bruba:~/.clawdbot/

# Copy workspace
scp -r $SNAPSHOT_NAME/workspace/* bruba:~/clawd/

# Restart daemon
ssh bruba 'clawdbot daemon restart'
\`\`\`
EOF

# Create archive
log_info "Creating archive..."
cd "$TEMP_DIR"
tar -czf "$OUTPUT_DIR/$SNAPSHOT_NAME.tar.gz" "$SNAPSHOT_NAME"

# Cleanup
rm -rf "$TEMP_DIR"

# Show result
ARCHIVE_SIZE=$(du -h "$OUTPUT_DIR/$SNAPSHOT_NAME.tar.gz" | cut -f1)
log_success "Snapshot created: $OUTPUT_DIR/$SNAPSHOT_NAME.tar.gz ($ARCHIVE_SIZE)"
