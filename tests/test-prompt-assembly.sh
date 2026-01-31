#!/bin/bash
# Test suite for config-driven prompt assembly
#
# Usage:
#   ./tests/test-prompt-assembly.sh              # Run all tests
#   ./tests/test-prompt-assembly.sh --quick      # Skip sync cycle (no SSH needed)
#   ./tests/test-prompt-assembly.sh --verbose    # Show detailed output
#
# Exit codes:
#   0 = All tests passed
#   1 = Test failed
#   2 = Setup error

set -e

cd "$(dirname "$0")/.."
ROOT_DIR="$(pwd)"

# Parse args
QUICK=false
VERBOSE=false
for arg in "$@"; do
    case $arg in
        --quick) QUICK=true ;;
        --verbose|-v) VERBOSE=true ;;
    esac
done

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

log() {
    echo "$@"
}

pass() {
    echo -e "${GREEN}PASS${NC}: $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail() {
    echo -e "${RED}FAIL${NC}: $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

skip() {
    echo -e "${YELLOW}SKIP${NC}: $1"
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
}

# ============================================================
# Test 1: Basic Assembly
# ============================================================
test_basic_assembly() {
    log ""
    log "=== Test 1: Basic Assembly ==="

    # Run assembly
    output=$(./tools/assemble-prompts.sh 2>&1)

    if [[ "$VERBOSE" == "true" ]]; then
        echo "$output"
    fi

    # Check output counts
    if echo "$output" | grep -q "10 components, 6 template, 2 bot"; then
        pass "Assembly produces correct section counts"
    else
        fail "Unexpected section counts: $output"
        return 1
    fi

    # Verify section order
    sections=$(grep -E '^<!-- (SECTION|COMPONENT|BOT-MANAGED):' assembled/prompts/AGENTS.md | head -10)
    expected_start="<!-- SECTION: header -->
<!-- COMPONENT: http-api -->
<!-- SECTION: first-run -->
<!-- COMPONENT: session -->"

    if echo "$sections" | head -4 | diff -q - <(echo "$expected_start") >/dev/null; then
        pass "Section order matches config"
    else
        fail "Section order mismatch"
        if [[ "$VERBOSE" == "true" ]]; then
            echo "Expected start:"
            echo "$expected_start"
            echo "Got:"
            echo "$sections" | head -4
        fi
        return 1
    fi

    # Check bot sections presence
    if grep -q 'BOT-MANAGED: exec-approvals' assembled/prompts/AGENTS.md && \
       grep -q 'BOT-MANAGED: packets' assembled/prompts/AGENTS.md; then
        pass "Bot sections (exec-approvals, packets) present"
    else
        fail "Missing bot sections"
        return 1
    fi
}

# ============================================================
# Test 2: Conflict Detection (No False Positives)
# ============================================================
test_conflict_detection() {
    log ""
    log "=== Test 2: Conflict Detection ==="

    output=$(./tools/detect-conflicts.sh 2>&1) || true

    if [[ "$VERBOSE" == "true" ]]; then
        echo "$output"
    fi

    if echo "$output" | grep -q "No conflicts detected"; then
        pass "No false positives on current state"
    else
        fail "Unexpected conflicts detected: $output"
        return 1
    fi
}

# ============================================================
# Test 3: Simulated Bot Section
# ============================================================
test_bot_section_simulation() {
    log ""
    log "=== Test 3: Simulated Bot Section ==="

    MIRROR_FILE="mirror/prompts/AGENTS.md"
    BACKUP_FILE="mirror/prompts/AGENTS.md.test-backup"
    CONFIG_BACKUP="config.yaml.test-backup"

    # Backup files
    cp "$MIRROR_FILE" "$BACKUP_FILE"
    cp config.yaml "$CONFIG_BACKUP"

    cleanup() {
        mv "$BACKUP_FILE" "$MIRROR_FILE" 2>/dev/null || true
        mv "$CONFIG_BACKUP" config.yaml 2>/dev/null || true
    }
    trap cleanup EXIT

    # 3a: Add test section to mirror
    sed -i.bak 's/## Make It Yours/<!-- BOT-MANAGED: test-section -->\n## Test Section\n\nThis is a test section.\n<!-- \/BOT-MANAGED: test-section -->\n\n## Make It Yours/' "$MIRROR_FILE"
    rm -f "${MIRROR_FILE}.bak"

    # 3b: Verify detection
    output=$(./tools/detect-conflicts.sh 2>&1) || true
    if echo "$output" | grep -q "test-section"; then
        pass "New bot section detected"
    else
        fail "Failed to detect new bot section"
        cleanup
        return 1
    fi

    # 3c: Add to config
    sed -i.bak 's/- heartbeats/- heartbeats\n  - bot:test-section/' config.yaml
    rm -f config.yaml.bak

    # 3d: Re-assemble
    output=$(./tools/assemble-prompts.sh 2>&1)
    if echo "$output" | grep -q "3 bot"; then
        pass "Test section included in assembly"
    else
        fail "Test section not assembled: $output"
        cleanup
        return 1
    fi

    # 3e: Verify no conflicts now
    output=$(./tools/detect-conflicts.sh 2>&1) || true
    if echo "$output" | grep -q "No conflicts detected"; then
        pass "No conflicts after adding to config"
    else
        fail "Still detecting conflicts: $output"
        cleanup
        return 1
    fi

    # Cleanup
    trap - EXIT
    cleanup

    # Re-assemble with original
    ./tools/assemble-prompts.sh >/dev/null 2>&1
}

# ============================================================
# Test 4: Full Sync Cycle
# ============================================================
test_sync_cycle() {
    log ""
    log "=== Test 4: Full Sync Cycle ==="

    if [[ "$QUICK" == "true" ]]; then
        skip "Sync cycle (--quick mode)"
        return 0
    fi

    # Check SSH connectivity
    if ! ./tools/bot echo "ping" >/dev/null 2>&1; then
        skip "Sync cycle (no SSH connectivity)"
        return 0
    fi

    # 4a: Push assembled to remote
    rsync -avz assembled/prompts/AGENTS.md bruba:/Users/bruba/clawd/AGENTS.md >/dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        pass "Push to remote succeeded"
    else
        fail "Push to remote failed"
        return 1
    fi

    # 4b: Mirror back
    ./tools/mirror.sh >/dev/null 2>&1
    pass "Mirror back succeeded"

    # 4c: Verify no conflicts
    output=$(./tools/detect-conflicts.sh 2>&1) || true
    if echo "$output" | grep -q "No conflicts detected"; then
        pass "No conflicts after round-trip"
    else
        fail "Conflicts after round-trip: $output"
        return 1
    fi

    # 4d: Re-assemble and compare
    ./tools/assemble-prompts.sh >/dev/null 2>&1
    if diff -q mirror/prompts/AGENTS.md assembled/prompts/AGENTS.md >/dev/null 2>&1; then
        pass "Round-trip produces identical files"
    else
        fail "Files differ after round-trip"
        if [[ "$VERBOSE" == "true" ]]; then
            diff mirror/prompts/AGENTS.md assembled/prompts/AGENTS.md | head -20
        fi
        return 1
    fi
}

# ============================================================
# Main
# ============================================================
log "Prompt Assembly Test Suite"
log "=========================="

test_basic_assembly || true
test_conflict_detection || true
test_bot_section_simulation || true
test_sync_cycle || true

log ""
log "=========================="
log "Results: ${GREEN}$TESTS_PASSED passed${NC}, ${RED}$TESTS_FAILED failed${NC}, ${YELLOW}$TESTS_SKIPPED skipped${NC}"

if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
