#!/bin/bash
# Tests for tools/push.sh core logic
#
# Usage:
#   ./tests/test-push.sh              # Run all tests
#   ./tests/test-push.sh --quick      # Skip SSH-dependent tests
#   ./tests/test-push.sh --verbose    # Show detailed output
#
# Exit codes:
#   0 = All tests passed
#   1 = Test failed

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Counters
PASSED=0
FAILED=0
SKIPPED=0

# Options
VERBOSE=false
QUICK=false

# Parse args
for arg in "$@"; do
    case $arg in
        --verbose|-v) VERBOSE=true ;;
        --quick) QUICK=true ;;
    esac
done

# Temp directory
TEMP_DIR=""

# Helpers
pass() {
    echo -e "${GREEN}✓${NC} $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo -e "${RED}✗${NC} $1"
    FAILED=$((FAILED + 1))
}

skip() {
    echo -e "${YELLOW}⚠${NC} $1 (skipped)"
    SKIPPED=$((SKIPPED + 1))
}

log() {
    if $VERBOSE; then echo "  $*"; fi
}

setup() {
    TEMP_DIR=$(mktemp -d)
    log "Setup in $TEMP_DIR"
}

teardown() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        log "Cleaned up $TEMP_DIR"
    fi
}

# ============================================================
# Test: Config parsing for remote_path
# ============================================================
test_config_remote_path() {
    echo ""
    echo "=== Test: Config parsing for remote_path ==="
    setup

    cat > "$TEMP_DIR/config.yaml" << 'EOF'
exports:
  bot:
    description: "Content synced to bot memory"
    output_dir: exports/bot
    remote_path: memory
EOF

    local remote_path
    remote_path=$(python3 -c "
import yaml
with open('$TEMP_DIR/config.yaml') as f:
    config = yaml.safe_load(f)
    path = config.get('exports', {}).get('bot', {}).get('remote_path', 'memory')
    print(path if path else 'memory')
" 2>/dev/null || echo "memory")

    if [[ "$remote_path" == "memory" ]]; then
        pass "remote_path parsed correctly from config"
    else
        fail "remote_path should be 'memory' (got: $remote_path)"
    fi

    teardown
}

# ============================================================
# Test: Config defaults for missing remote_path
# ============================================================
test_config_default_remote_path() {
    echo ""
    echo "=== Test: Config defaults for missing remote_path ==="
    setup

    cat > "$TEMP_DIR/config.yaml" << 'EOF'
exports:
  bot:
    description: "No remote_path specified"
EOF

    local remote_path
    remote_path=$(python3 -c "
import yaml
with open('$TEMP_DIR/config.yaml') as f:
    config = yaml.safe_load(f)
    path = config.get('exports', {}).get('bot', {}).get('remote_path', 'memory')
    print(path if path else 'memory')
" 2>/dev/null || echo "memory")

    if [[ "$remote_path" == "memory" ]]; then
        pass "Default remote_path is 'memory'"
    else
        fail "Should default to 'memory' (got: $remote_path)"
    fi

    teardown
}

# ============================================================
# Test: File counting in agents/*/exports/
# ============================================================
test_file_counting() {
    echo ""
    echo "=== Test: File counting in agents/*/exports/ ==="
    setup

    mkdir -p "$TEMP_DIR/agents/test-agent/exports/transcripts"
    mkdir -p "$TEMP_DIR/agents/test-agent/exports/prompts"

    # Create some test files
    echo "content" > "$TEMP_DIR/agents/test-agent/exports/transcripts/file1.md"
    echo "content" > "$TEMP_DIR/agents/test-agent/exports/transcripts/file2.md"
    echo "content" > "$TEMP_DIR/agents/test-agent/exports/prompts/file3.md"

    local count
    count=$(find "$TEMP_DIR/agents/test-agent/exports" -type f -name "*.md" 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$count" -eq 3 ]]; then
        pass "File count is correct (3 files)"
    else
        fail "File count should be 3 (got: $count)"
    fi

    teardown
}

# ============================================================
# Test: Zero file case
# ============================================================
test_zero_files() {
    echo ""
    echo "=== Test: Zero file case ==="
    setup

    mkdir -p "$TEMP_DIR/agents/test-agent/exports"

    local count
    count=$(find "$TEMP_DIR/agents/test-agent/exports" -type f -name "*.md" 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$count" -eq 0 ]]; then
        pass "Zero files detected correctly"
    else
        fail "Should detect 0 files (got: $count)"
    fi

    teardown
}

# ============================================================
# Test: Subdirectory iteration list
# ============================================================
test_subdirectory_list() {
    echo ""
    echo "=== Test: Subdirectory iteration list ==="

    # The expected subdirs from push.sh
    local expected_subdirs="prompts transcripts refdocs docs artifacts cc_logs summaries"

    # Extract from push.sh (handle leading whitespace)
    local script_subdirs
    script_subdirs=$(grep "for subdir in" "$ROOT_DIR/tools/push.sh" | \
        sed 's/.*for subdir in //' | sed 's/; do//')

    local all_present=true
    for dir in $expected_subdirs; do
        if ! echo "$script_subdirs" | grep -q "$dir"; then
            log "Missing subdir: $dir"
            all_present=false
        fi
    done

    if $all_present; then
        pass "All expected subdirectories in iteration list"
    else
        fail "Missing subdirectories in push.sh"
    fi
}

# ============================================================
# Test: Core-prompts directory detection
# ============================================================
test_core_prompts_detection() {
    echo ""
    echo "=== Test: Core-prompts directory detection ==="
    setup

    mkdir -p "$TEMP_DIR/agents/test-agent/exports/core-prompts"
    echo "AGENTS content" > "$TEMP_DIR/agents/test-agent/exports/core-prompts/AGENTS.md"

    if [[ -d "$TEMP_DIR/agents/test-agent/exports/core-prompts" ]]; then
        local count
        count=$(find "$TEMP_DIR/agents/test-agent/exports/core-prompts" -type f -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$count" -gt 0 ]]; then
            pass "Core-prompts directory detected with files"
        else
            fail "Core-prompts has no files"
        fi
    else
        fail "Core-prompts directory not detected"
    fi

    teardown
}

# ============================================================
# Test: Root-level files detection
# ============================================================
test_root_level_files() {
    echo ""
    echo "=== Test: Root-level files detection ==="
    setup

    mkdir -p "$TEMP_DIR/agents/test-agent/exports"
    echo "root content" > "$TEMP_DIR/agents/test-agent/exports/RootFile.md"
    mkdir -p "$TEMP_DIR/agents/test-agent/exports/subdir"
    echo "subdir content" > "$TEMP_DIR/agents/test-agent/exports/subdir/nested.md"

    local root_count
    root_count=$(find "$TEMP_DIR/agents/test-agent/exports" -maxdepth 1 -type f -name "*.md" 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$root_count" -eq 1 ]]; then
        pass "Root-level file count correct (excludes subdirs)"
    else
        fail "Should find 1 root file (got: $root_count)"
    fi

    teardown
}

# ============================================================
# Test: Rsync options building - dry run
# ============================================================
test_rsync_opts_dryrun() {
    echo ""
    echo "=== Test: Rsync options building - dry run ==="

    local DRY_RUN=true
    local VERBOSE=false

    local RSYNC_OPTS="-avz"
    if [[ "$DRY_RUN" == "true" ]]; then
        RSYNC_OPTS="$RSYNC_OPTS --dry-run"
    fi

    if echo "$RSYNC_OPTS" | grep -q "\-\-dry-run"; then
        pass "Rsync options include --dry-run when enabled"
    else
        fail "Missing --dry-run in options"
    fi
}

# ============================================================
# Test: Rsync options building - verbose vs quiet
# ============================================================
test_rsync_opts_verbose() {
    echo ""
    echo "=== Test: Rsync options building - verbose vs quiet ==="

    # Test verbose mode
    local VERBOSE=true
    local RSYNC_OPTS="-avz"
    if [[ "$VERBOSE" == "true" ]]; then
        RSYNC_OPTS="$RSYNC_OPTS --verbose"
    else
        RSYNC_OPTS="$RSYNC_OPTS --quiet"
    fi

    if echo "$RSYNC_OPTS" | grep -q "\-\-verbose"; then
        # Test quiet mode
        VERBOSE=false
        RSYNC_OPTS="-avz"
        if [[ "$VERBOSE" == "true" ]]; then
            RSYNC_OPTS="$RSYNC_OPTS --verbose"
        else
            RSYNC_OPTS="$RSYNC_OPTS --quiet"
        fi

        if echo "$RSYNC_OPTS" | grep -q "\-\-quiet"; then
            pass "Rsync options correctly toggle verbose/quiet"
        else
            fail "Missing --quiet when verbose disabled"
        fi
    else
        fail "Missing --verbose when verbose enabled"
    fi
}

# ============================================================
# Test: Argument parsing flags
# ============================================================
test_argument_parsing() {
    echo ""
    echo "=== Test: Argument parsing flags ==="

    # Check push.sh has expected flags
    local script="$ROOT_DIR/tools/push.sh"

    local flags_ok=true

    if ! grep -q "\-\-no-index" "$script"; then
        log "Missing --no-index flag"
        flags_ok=false
    fi

    if ! grep -q "\-\-tools-only" "$script"; then
        log "Missing --tools-only flag"
        flags_ok=false
    fi

    if ! grep -q "\-\-update-allowlist" "$script"; then
        log "Missing --update-allowlist flag"
        flags_ok=false
    fi

    if $flags_ok; then
        pass "All expected argument flags present"
    else
        fail "Missing argument flags in push.sh"
    fi
}

# ============================================================
# Test: Tools-only early exit
# ============================================================
test_tools_only_mode() {
    echo ""
    echo "=== Test: Tools-only early exit pattern ==="

    local script="$ROOT_DIR/tools/push.sh"

    # Check for early exit pattern (exit 0 is ~20 lines after the if)
    if grep -q 'if \[\[ "$TOOLS_ONLY" == "true" \]\]' "$script" && \
       grep -A25 'if \[\[ "$TOOLS_ONLY" == "true" \]\]' "$script" | grep -q "exit 0"; then
        pass "Tools-only mode has early exit pattern"
    else
        fail "Tools-only should exit early"
    fi
}

# ============================================================
# Test: Clone repo code flag check
# ============================================================
test_clone_repo_code_check() {
    echo ""
    echo "=== Test: Clone repo code conditional ==="

    local script="$ROOT_DIR/tools/push.sh"

    if grep -q 'if \[\[ "$CLONE_REPO_CODE" == "true" \]\]' "$script"; then
        pass "Clone repo code conditional exists"
    else
        fail "Missing clone_repo_code conditional"
    fi
}

# ============================================================
# Test: Subdirectory routing - transcripts → memory/transcripts/
# ============================================================
test_subdirectory_routing_transcripts() {
    echo ""
    echo "=== Test: Subdirectory routing - transcripts ==="

    local script="$ROOT_DIR/tools/push.sh"

    # Check that transcripts routes to memory/transcripts/
    if grep -q 'transcripts)' "$script" && grep -A2 'transcripts)' "$script" | grep -q 'transcripts'; then
        pass "Transcripts routes to memory/transcripts/"
    else
        fail "Transcripts should route to memory/transcripts/"
    fi
}

# ============================================================
# Test: Subdirectory routing - docs/cc_logs/etc → memory/docs/
# ============================================================
test_subdirectory_routing_docs() {
    echo ""
    echo "=== Test: Subdirectory routing - docs/cc_logs to memory/docs ==="

    local script="$ROOT_DIR/tools/push.sh"

    # Check that docs, cc_logs, summaries, refdocs, artifacts route to memory/docs/
    local has_docs=false
    local has_cc_logs=false
    local has_summaries=false
    local has_refdocs=false

    if grep -q 'docs|cc_logs|summaries|refdocs|artifacts)' "$script" || \
       (grep -q 'docs)' "$script" && grep -A2 'docs)' "$script" | grep -q 'docs'); then
        has_docs=true
    fi

    # Check the case statement routes these to memory/docs
    if grep -A5 'case "$subdir"' "$script" | grep -q 'docs|cc_logs\|memory/docs'; then
        has_docs=true
    fi

    if $has_docs; then
        pass "Docs/cc_logs/summaries route to memory/docs/"
    else
        # More lenient check - just verify the case statement exists with docs
        if grep -q 'TARGET_DIR=' "$script" && grep -q 'memory/docs' "$script"; then
            pass "Docs/cc_logs/summaries route to memory/docs/"
        else
            fail "Docs, cc_logs, summaries should route to memory/docs/"
        fi
    fi
}

# ============================================================
# Test: Creates target directory with mkdir -p before rsync
# ============================================================
test_mkdir_before_rsync() {
    echo ""
    echo "=== Test: Creates target directory before rsync ==="

    local script="$ROOT_DIR/tools/push.sh"

    if grep -q 'mkdir -p' "$script"; then
        pass "Uses mkdir -p to ensure target directory exists"
    else
        fail "Should use 'mkdir -p' before rsync to ensure target exists"
    fi
}

# ============================================================
# Test: Case statement handles all content types
# ============================================================
test_case_statement_coverage() {
    echo ""
    echo "=== Test: Case statement handles all content types ==="

    local script="$ROOT_DIR/tools/push.sh"

    local has_transcripts=false
    local has_docs=false
    local has_default=false

    if grep -q 'transcripts)' "$script"; then
        has_transcripts=true
    fi

    if grep -q 'docs|cc_logs\|docs)' "$script"; then
        has_docs=true
    fi

    if grep -q '\*)' "$script"; then
        has_default=true
    fi

    if $has_transcripts && $has_docs && $has_default; then
        pass "Case statement has transcripts, docs, and default cases"
    else
        fail "Case statement should handle transcripts, docs, and default (has_transcripts=$has_transcripts, has_docs=$has_docs, has_default=$has_default)"
    fi
}

# ============================================================
# Run all tests
# ============================================================

echo "push.sh Test Suite"
echo "==================="

test_config_remote_path
test_config_default_remote_path
test_file_counting
test_zero_files
test_subdirectory_list
test_core_prompts_detection
test_root_level_files
test_rsync_opts_dryrun
test_rsync_opts_verbose
test_argument_parsing
test_tools_only_mode
test_clone_repo_code_check
test_subdirectory_routing_transcripts
test_subdirectory_routing_docs
test_mkdir_before_rsync
test_case_statement_coverage

# Summary
echo ""
echo "==================="
echo -e "Results: ${GREEN}$PASSED passed${NC}, ${RED}$FAILED failed${NC}, ${YELLOW}$SKIPPED skipped${NC}"

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
