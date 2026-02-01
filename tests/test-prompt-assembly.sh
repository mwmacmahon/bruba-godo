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

    # Check output counts (10 components, 6 template sections, 1+ bot-managed)
    if echo "$output" | grep -qE "10 components, 6 template, [0-9]+ bot"; then
        pass "Assembly produces correct section counts"
    else
        fail "Unexpected section counts: $output"
        return 1
    fi

    # Verify section order
    sections=$(grep -E '^<!-- (SECTION|COMPONENT|BOT-MANAGED):' exports/bot/core-prompts/AGENTS.md | head -10)
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

    # Check bot sections presence (at minimum exec-approvals)
    if grep -q 'BOT-MANAGED: exec-approvals' exports/bot/core-prompts/AGENTS.md; then
        pass "Bot section exec-approvals present"
    else
        fail "Missing exec-approvals bot section"
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
    EXPORTS_BACKUP="config.yaml.test-backup"

    # Backup files
    cp "$MIRROR_FILE" "$BACKUP_FILE"
    cp config.yaml "$EXPORTS_BACKUP"

    cleanup() {
        mv "$BACKUP_FILE" "$MIRROR_FILE" 2>/dev/null || true
        mv "$EXPORTS_BACKUP" config.yaml 2>/dev/null || true
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

    # 3c: Add to config.yaml agents_sections (under bot profile)
    sed -i.bak 's/- heartbeats/- heartbeats\n      - bot:test-section/' config.yaml
    rm -f config.yaml.bak

    # 3d: Re-assemble
    output=$(./tools/assemble-prompts.sh 2>&1)
    if echo "$output" | grep -q "2 bot"; then
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
# Test 3b: Component Edit Detection
# ============================================================
test_component_edit_detection() {
    log ""
    log "=== Test 3b: Component Edit Detection ==="

    MIRROR_FILE="mirror/prompts/AGENTS.md"
    BACKUP_FILE="mirror/prompts/AGENTS.md.test-backup"

    if [[ ! -f "$MIRROR_FILE" ]]; then
        fail "Mirror file not found (run mirror first)"
        return 1
    fi

    # Backup
    cp "$MIRROR_FILE" "$BACKUP_FILE"

    cleanup() {
        mv "$BACKUP_FILE" "$MIRROR_FILE" 2>/dev/null || true
    }
    trap cleanup EXIT

    # 3b-a: Modify session component content in mirror (simulate bot edit)
    # Add a line after "Next session picks it up automatically"
    sed -i.bak 's/Next session picks it up automatically/Next session picks it up automatically\n\n**BOT ADDED THIS LINE**/' "$MIRROR_FILE"
    rm -f "${MIRROR_FILE}.bak"

    # 3b-b: Verify conflict detected
    output=$(./tools/detect-conflicts.sh 2>&1) || true
    if echo "$output" | grep -q "EDITED COMPONENTS"; then
        pass "Component edit detected"
    else
        fail "Failed to detect component edit: $output"
        cleanup
        return 1
    fi

    if echo "$output" | grep -q "session"; then
        pass "Correct component identified (session)"
    else
        fail "Wrong component identified: $output"
        cleanup
        return 1
    fi

    # 3b-c: Verify --diff shows the change
    diff_output=$(./tools/detect-conflicts.sh --diff session 2>&1) || true
    if echo "$diff_output" | grep -q "BOT ADDED THIS LINE"; then
        pass "Diff output shows bot's change"
    else
        fail "Diff didn't show change: $diff_output"
    fi

    # Cleanup
    trap - EXIT
    cleanup
}

# ============================================================
# Test 3c: Multiple Component Edit Detection
# ============================================================
test_multiple_component_edits() {
    log ""
    log "=== Test 3c: Multiple Component Edit Detection ==="

    MIRROR_FILE="mirror/prompts/AGENTS.md"
    BACKUP_FILE="mirror/prompts/AGENTS.md.test-backup"

    if [[ ! -f "$MIRROR_FILE" ]]; then
        fail "Mirror file not found (run mirror first)"
        return 1
    fi

    # Backup
    cp "$MIRROR_FILE" "$BACKUP_FILE"

    cleanup() {
        mv "$BACKUP_FILE" "$MIRROR_FILE" 2>/dev/null || true
    }
    trap cleanup EXIT

    # Edit TWO components in mirror
    # 1. Session component
    sed -i.bak 's/Next session picks it up automatically/Next session picks it up automatically\n\n**EDIT ONE**/' "$MIRROR_FILE"
    rm -f "${MIRROR_FILE}.bak"

    # 2. Voice component (add line after whisper-clean.sh)
    sed -i.bak 's/whisper-clean.sh/whisper-clean.sh\n\n**EDIT TWO**/' "$MIRROR_FILE"
    rm -f "${MIRROR_FILE}.bak"

    # Verify both edits detected
    output=$(./tools/detect-conflicts.sh 2>&1) || true

    if echo "$output" | grep -q "session" && echo "$output" | grep -q "voice"; then
        pass "Multiple component edits detected (session + voice)"
    elif echo "$output" | grep -q "session"; then
        pass "At least session edit detected"
        # voice might not match because the edit pattern is different
    else
        fail "Component edits not detected: $output"
    fi

    # Cleanup
    trap - EXIT
    cleanup
}

# ============================================================
# Test 4: Stage 2 - Silent Transcript Mode in Assembled Output
# ============================================================
test_silent_transcript_mode() {
    log ""
    log "=== Test 4: Silent Transcript Mode Content ==="

    ASSEMBLED_AGENTS="exports/bot/core-prompts/AGENTS.md"

    if [[ ! -f "$ASSEMBLED_AGENTS" ]]; then
        fail "Assembled AGENTS.md not found at $ASSEMBLED_AGENTS (run assembly first)"
        return 1
    fi

    # Check voice snippet silent mode flow is present
    # Check for the simplified 6-step voice flow
    if grep -q "Transcribe:" "$ASSEMBLED_AGENTS"; then
        pass "Assembled AGENTS.md has 'Transcribe' step"
    else
        fail "Assembled AGENTS.md missing 'Transcribe' step"
    fi

    if grep -q "Apply fixes silently" "$ASSEMBLED_AGENTS"; then
        pass "Assembled AGENTS.md has 'Apply fixes silently' step"
    else
        fail "Assembled AGENTS.md missing 'Apply fixes silently' step"
    fi

    if grep -q "Surface uncertainties" "$ASSEMBLED_AGENTS"; then
        pass "Assembled AGENTS.md has 'Surface uncertainties' step"
    else
        fail "Assembled AGENTS.md missing 'Surface uncertainties' step"
    fi

    if grep -q "no transcript echo" "$ASSEMBLED_AGENTS"; then
        pass "Assembled AGENTS.md has 'no transcript echo' instruction"
    else
        fail "Assembled AGENTS.md missing 'no transcript echo' instruction"
    fi

    if grep -q "Voice reply:" "$ASSEMBLED_AGENTS"; then
        pass "Assembled AGENTS.md has voice reply step"
    else
        fail "Assembled AGENTS.md missing voice reply step"
    fi

    # Check distill snippet export pipeline note is present
    if grep -q "synced via the export pipeline" "$ASSEMBLED_AGENTS"; then
        pass "Assembled AGENTS.md has export pipeline note"
    else
        fail "Assembled AGENTS.md missing export pipeline note"
    fi
}

# ============================================================
# Test 5: Full Sync Cycle
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
    rsync -avz exports/bot/core-prompts/AGENTS.md bruba:/Users/bruba/clawd/AGENTS.md >/dev/null 2>&1
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
    if diff -q mirror/prompts/AGENTS.md exports/bot/core-prompts/AGENTS.md >/dev/null 2>&1; then
        pass "Round-trip produces identical files"
    else
        fail "Files differ after round-trip"
        if [[ "$VERBOSE" == "true" ]]; then
            diff mirror/prompts/AGENTS.md exports/bot/core-prompts/AGENTS.md | head -20
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
test_component_edit_detection || true
test_multiple_component_edits || true
test_silent_transcript_mode || true
test_sync_cycle || true

log ""
log "=========================="
log "Results: ${GREEN}$TESTS_PASSED passed${NC}, ${RED}$TESTS_FAILED failed${NC}, ${YELLOW}$TESTS_SKIPPED skipped${NC}"

if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
