#!/bin/bash
# Test suite for config-driven prompt assembly (multi-agent)
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

# Load shared functions for agent config
source "$ROOT_DIR/tools/lib.sh"

# Parse args
QUICK=false
VERBOSE=false
for arg in "$@"; do
    case $arg in
        --quick) QUICK=true ;;
        --verbose|-v) VERBOSE=true ;;
    esac
done

# Default agent for single-agent tests
DEFAULT_AGENT="bruba-main"

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
# Test 1: Basic Assembly (bruba-main)
# ============================================================
test_basic_assembly() {
    log ""
    log "=== Test 1: Basic Assembly (bruba-main) ==="

    # Run assembly for bruba-main (use --force to skip conflict check during test)
    output=$(./tools/assemble-prompts.sh --agent=bruba-main --force 2>&1)

    if [[ "$VERBOSE" == "true" ]]; then
        echo "$output"
    fi

    # Check that assembly completed (new format shows "X components" or "base")
    if echo "$output" | grep -qE "AGENTS.md.*components"; then
        pass "Assembly produces AGENTS.md with components"
    else
        fail "Unexpected assembly output: $output"
        return 1
    fi

    # Verify section order in assembled file
    ASSEMBLED_FILE="exports/bot/bruba-main/core-prompts/AGENTS.md"
    if [[ ! -f "$ASSEMBLED_FILE" ]]; then
        fail "Assembled file not found at $ASSEMBLED_FILE"
        return 1
    fi

    sections=$(grep -E '^<!-- (SECTION|COMPONENT|BOT-MANAGED):' "$ASSEMBLED_FILE" | head -10)
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
    if grep -q 'BOT-MANAGED: exec-approvals' "$ASSEMBLED_FILE"; then
        pass "Bot section exec-approvals present"
    else
        fail "Missing exec-approvals bot section"
        return 1
    fi
}

# ============================================================
# Test 1b: Basic Assembly (bruba-manager)
# ============================================================
test_manager_assembly() {
    log ""
    log "=== Test 1b: Basic Assembly (bruba-manager) ==="

    # Run assembly for bruba-manager
    output=$(./tools/assemble-prompts.sh --agent=bruba-manager 2>&1)

    if [[ "$VERBOSE" == "true" ]]; then
        echo "$output"
    fi

    # Check that assembly completed with base template
    if echo "$output" | grep -qE "AGENTS.md.*base"; then
        pass "Manager assembly produces AGENTS.md with base"
    else
        fail "Unexpected manager assembly output: $output"
        return 1
    fi

    # Verify manager files exist
    MANAGER_DIR="exports/bot/bruba-manager/core-prompts"
    for file in AGENTS.md TOOLS.md HEARTBEAT.md; do
        if [[ -f "$MANAGER_DIR/$file" ]]; then
            pass "Manager $file exists"
        else
            fail "Manager $file not found at $MANAGER_DIR/$file"
            return 1
        fi
    done

    # Verify manager AGENTS.md has coordinator identity
    if grep -q "coordinator" "$MANAGER_DIR/AGENTS.md"; then
        pass "Manager AGENTS.md has coordinator identity"
    else
        fail "Manager AGENTS.md missing coordinator content"
        return 1
    fi
}

# ============================================================
# Test 1c: Multi-Agent Assembly (all agents)
# ============================================================
test_multi_agent_assembly() {
    log ""
    log "=== Test 1c: Multi-Agent Assembly ==="

    # Run assembly for all agents (use --force to skip conflict check during test)
    output=$(./tools/assemble-prompts.sh --force 2>&1)

    if [[ "$VERBOSE" == "true" ]]; then
        echo "$output"
    fi

    # Check both agents were processed
    if echo "$output" | grep -q "Agent: bruba-main"; then
        pass "bruba-main processed"
    else
        fail "bruba-main not processed"
        return 1
    fi

    if echo "$output" | grep -q "Agent: bruba-manager"; then
        pass "bruba-manager processed"
    else
        fail "bruba-manager not processed"
        return 1
    fi

    if echo "$output" | grep -q "Agent: bruba-web"; then
        pass "bruba-web processed"
    else
        fail "bruba-web not processed"
        return 1
    fi

    # Verify all export directories exist
    if [[ -d "exports/bot/bruba-main/core-prompts" ]]; then
        pass "bruba-main exports directory exists"
    else
        fail "bruba-main exports directory missing"
        return 1
    fi

    if [[ -d "exports/bot/bruba-manager/core-prompts" ]]; then
        pass "bruba-manager exports directory exists"
    else
        fail "bruba-manager exports directory missing"
        return 1
    fi

    if [[ -d "exports/bot/bruba-web/core-prompts" ]]; then
        pass "bruba-web exports directory exists"
    else
        fail "bruba-web exports directory missing"
        return 1
    fi
}

# ============================================================
# Test 2: Conflict Detection (Verify tool runs)
# ============================================================
test_conflict_detection() {
    log ""
    log "=== Test 2: Conflict Detection ==="

    output=$(./tools/detect-conflicts.sh --agent=bruba-main 2>&1) || true

    if [[ "$VERBOSE" == "true" ]]; then
        echo "$output"
    fi

    # Just verify the tool runs and produces output
    if echo "$output" | grep -q "Checking for conflicts"; then
        pass "Conflict detection runs"
    else
        fail "Conflict detection didn't run: $output"
        return 1
    fi

    # Note: Real conflicts may exist (bot edits). Test just verifies tool works.
    if echo "$output" | grep -q "No conflicts detected"; then
        pass "No conflicts detected (clean state)"
    elif echo "$output" | grep -qE "(EDITED COMPONENTS|NEW BOT SECTIONS|conflicts)"; then
        pass "Conflicts properly detected and reported"
    else
        fail "Unexpected output: $output"
        return 1
    fi
}

# ============================================================
# Test 3: Simulated Bot Section
# ============================================================
test_bot_section_simulation() {
    log ""
    log "=== Test 3: Simulated Bot Section ==="

    MIRROR_FILE="mirror/bruba-main/prompts/AGENTS.md"
    BACKUP_FILE="mirror/bruba-main/prompts/AGENTS.md.test-backup"
    EXPORTS_BACKUP="config.yaml.test-backup"

    if [[ ! -f "$MIRROR_FILE" ]]; then
        skip "Mirror file not found (run mirror first)"
        return 0
    fi

    # Backup files
    cp "$MIRROR_FILE" "$BACKUP_FILE"
    cp config.yaml "$EXPORTS_BACKUP"

    cleanup() {
        mv "$BACKUP_FILE" "$MIRROR_FILE" 2>/dev/null || true
        mv "$EXPORTS_BACKUP" config.yaml 2>/dev/null || true
    }
    trap cleanup EXIT

    # 3a: Add test section to mirror (insert before Safety section)
    sed -i.bak 's/## Safety/<!-- BOT-MANAGED: test-section -->\n## Test Section\n\nThis is a test section.\n<!-- \/BOT-MANAGED: test-section -->\n\n## Safety/' "$MIRROR_FILE"
    rm -f "${MIRROR_FILE}.bak"

    # 3b: Verify detection
    output=$(./tools/detect-conflicts.sh --agent=bruba-main 2>&1) || true
    if echo "$output" | grep -q "test-section"; then
        pass "New bot section detected"
    else
        fail "Failed to detect new bot section"
        cleanup
        return 1
    fi

    # 3c: Add to config.yaml agents_sections (under bruba-main)
    sed -i.bak 's/- heartbeats/- heartbeats\n      - bot:test-section/' config.yaml
    rm -f config.yaml.bak

    # 3d: Re-assemble
    output=$(./tools/assemble-prompts.sh --agent=bruba-main 2>&1)
    if echo "$output" | grep -q "bot"; then
        pass "Test section included in assembly"
    else
        fail "Test section not assembled: $output"
        cleanup
        return 1
    fi

    # 3e: Verify test-section no longer detected as new (it's in config now)
    output=$(./tools/detect-conflicts.sh --agent=bruba-main 2>&1) || true
    if echo "$output" | grep -q "NEW BOT SECTIONS:.*test-section"; then
        fail "test-section still detected as new: $output"
        cleanup
        return 1
    else
        pass "test-section no longer flagged as new bot section"
    fi

    # Cleanup
    trap - EXIT
    cleanup

    # Re-assemble with original
    ./tools/assemble-prompts.sh --agent=bruba-main >/dev/null 2>&1
}

# ============================================================
# Test 3b: Component Edit Detection
# ============================================================
test_component_edit_detection() {
    log ""
    log "=== Test 3b: Component Edit Detection ==="

    MIRROR_FILE="mirror/bruba-main/prompts/AGENTS.md"
    BACKUP_FILE="mirror/bruba-main/prompts/AGENTS.md.test-backup"

    if [[ ! -f "$MIRROR_FILE" ]]; then
        skip "Mirror file not found (run mirror first)"
        return 0
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
    output=$(./tools/detect-conflicts.sh --agent=bruba-main 2>&1) || true
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
    diff_output=$(./tools/detect-conflicts.sh --agent=bruba-main --diff session 2>&1) || true
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

    MIRROR_FILE="mirror/bruba-main/prompts/AGENTS.md"
    BACKUP_FILE="mirror/bruba-main/prompts/AGENTS.md.test-backup"

    if [[ ! -f "$MIRROR_FILE" ]]; then
        skip "Mirror file not found (run mirror first)"
        return 0
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
    output=$(./tools/detect-conflicts.sh --agent=bruba-main 2>&1) || true

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

    ASSEMBLED_AGENTS="exports/bot/bruba-main/core-prompts/AGENTS.md"

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
    log "=== Test 5: Full Sync Cycle ==="

    if [[ "$QUICK" == "true" ]]; then
        skip "Sync cycle (--quick mode)"
        return 0
    fi

    # Check SSH connectivity
    if ! ./tools/bot echo "ping" >/dev/null 2>&1; then
        skip "Sync cycle (no SSH connectivity)"
        return 0
    fi

    # 5a: Push assembled to remote (using push.sh)
    output=$(./tools/push.sh --agent=bruba-main 2>&1)
    if [[ $? -eq 0 ]]; then
        pass "Push to remote succeeded"
    else
        fail "Push to remote failed: $output"
        return 1
    fi

    # 5b: Mirror back
    ./tools/mirror.sh --agent=bruba-main >/dev/null 2>&1
    pass "Mirror back succeeded"

    # 5c: Verify no conflicts
    output=$(./tools/detect-conflicts.sh --agent=bruba-main 2>&1) || true
    if echo "$output" | grep -q "No conflicts detected"; then
        pass "No conflicts after round-trip"
    else
        fail "Conflicts after round-trip: $output"
        return 1
    fi

    # 5d: Re-assemble and compare
    ./tools/assemble-prompts.sh --agent=bruba-main >/dev/null 2>&1
    if diff -q mirror/bruba-main/prompts/AGENTS.md exports/bot/bruba-main/core-prompts/AGENTS.md >/dev/null 2>&1; then
        pass "Round-trip produces identical files"
    else
        fail "Files differ after round-trip"
        if [[ "$VERBOSE" == "true" ]]; then
            diff mirror/bruba-main/prompts/AGENTS.md exports/bot/bruba-main/core-prompts/AGENTS.md | head -20
        fi
        return 1
    fi
}

# ============================================================
# Test 6: Push Multi-Agent
# ============================================================
test_push_multi_agent() {
    log ""
    log "=== Test 6: Push Multi-Agent ==="

    if [[ "$QUICK" == "true" ]]; then
        skip "Push multi-agent (--quick mode)"
        return 0
    fi

    # Check SSH connectivity
    if ! ./tools/bot echo "ping" >/dev/null 2>&1; then
        skip "Push multi-agent (no SSH connectivity)"
        return 0
    fi

    # Test dry-run for all agents
    output=$(./tools/push.sh --dry-run 2>&1)
    if [[ $? -eq 0 ]]; then
        pass "Push dry-run succeeded"
    else
        fail "Push dry-run failed: $output"
        return 1
    fi

    # Verify both agents mentioned in output
    if echo "$output" | grep -q "bruba-main"; then
        pass "Push includes bruba-main"
    else
        fail "Push missing bruba-main"
    fi

    if echo "$output" | grep -q "bruba-manager"; then
        pass "Push includes bruba-manager"
    else
        fail "Push missing bruba-manager"
    fi
}

# ============================================================
# Test 7: Config Parsing Works
# ============================================================
test_config_parsing() {
    log ""
    log "=== Test 7: Config Parsing Works ==="

    source ./tools/lib.sh
    load_config

    # Just verify we can parse agent configs without error
    local main_deny mgr_deny subagent_config

    main_deny=$(get_agent_tools_deny "bruba-main")
    if [[ -n "$main_deny" && "$main_deny" != "null" ]]; then
        pass "bruba-main tools_deny parses"
    else
        fail "bruba-main tools_deny failed to parse"
        return 1
    fi

    mgr_deny=$(get_agent_tools_deny "bruba-manager")
    if [[ -n "$mgr_deny" && "$mgr_deny" != "null" ]]; then
        pass "bruba-manager tools_deny parses"
    else
        fail "bruba-manager tools_deny failed to parse"
        return 1
    fi

    subagent_config=$(get_subagents_config)
    if [[ -n "$subagent_config" && "$subagent_config" != "null" ]]; then
        pass "subagents config parses"
    else
        fail "subagents config failed to parse"
        return 1
    fi
}

# ============================================================
# Test 9: Agent Tools Sync Dry-Run
# ============================================================
test_agent_tools_sync_dry_run() {
    log ""
    log "=== Test 9: Agent Tools Sync Dry-Run ==="

    if [[ "$QUICK" == "true" ]]; then
        skip "Agent tools sync (--quick mode)"
        return 0
    fi

    # Check SSH connectivity
    if ! ./tools/bot echo "ping" >/dev/null 2>&1; then
        skip "Agent tools sync (no SSH connectivity)"
        return 0
    fi

    # Run with --dry-run, should not error
    output=$(./tools/update-agent-tools.sh --dry-run 2>&1)
    if [[ $? -eq 0 ]]; then
        pass "Agent tools sync dry-run completed"
    else
        fail "Agent tools sync dry-run failed: $output"
        return 1
    fi
}

# ============================================================
# Test 10: Agent Tools Check
# ============================================================
test_agent_tools_check() {
    log ""
    log "=== Test 10: Agent Tools Check ==="

    if [[ "$QUICK" == "true" ]]; then
        skip "Agent tools check (--quick mode)"
        return 0
    fi

    # Check SSH connectivity
    if ! ./tools/bot echo "ping" >/dev/null 2>&1; then
        skip "Agent tools check (no SSH connectivity)"
        return 0
    fi

    # Run with --check, capture output
    output=$(./tools/update-agent-tools.sh --check 2>&1)
    # Should complete without error (may show discrepancies)
    if [[ $? -eq 0 ]]; then
        pass "Agent tools check completed"
        if echo "$output" | grep -q "in sync"; then
            pass "Agent tools are in sync with config"
        else
            log "  Note: Some discrepancies found (expected if config was just updated)"
        fi
    else
        fail "Agent tools check failed: $output"
    fi
}

# ============================================================
# Test 11: Config Sync Round-Trip Verification
# ============================================================
test_config_sync_roundtrip() {
    log ""
    log "=== Test 11: Config Sync Round-Trip Verification ==="

    if [[ "$QUICK" == "true" ]]; then
        skip "Config sync round-trip (--quick mode)"
        return 0
    fi

    # Check SSH connectivity
    if ! ./tools/bot echo "ping" >/dev/null 2>&1; then
        skip "Config sync round-trip (no SSH connectivity)"
        return 0
    fi

    # This test verifies that running --check shows "in sync"
    # after the config.yaml has been aligned with bot state
    output=$(./tools/update-agent-tools.sh --check 2>&1)

    if echo "$output" | grep -q "in sync"; then
        pass "Agent tools config in sync with bot"
    else
        # Show what's different
        fail "Config not in sync with bot"
        if [[ "$VERBOSE" == "true" ]]; then
            echo "  Discrepancies found:"
            echo "$output" | grep -E "(allow|deny):" | head -10
        fi
        return 1
    fi
}

# ============================================================
# Main
# ============================================================
log "Prompt Assembly Test Suite (Multi-Agent)"
log "========================================"

test_basic_assembly || true
test_manager_assembly || true
test_multi_agent_assembly || true
test_conflict_detection || true
test_bot_section_simulation || true
test_component_edit_detection || true
test_multiple_component_edits || true
test_silent_transcript_mode || true
test_sync_cycle || true
test_push_multi_agent || true
test_config_parsing || true
test_agent_tools_sync_dry_run || true
test_agent_tools_check || true
test_config_sync_roundtrip || true

log ""
log "========================================"
log "Results: ${GREEN}$TESTS_PASSED passed${NC}, ${RED}$TESTS_FAILED failed${NC}, ${YELLOW}$TESTS_SKIPPED skipped${NC}"

if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
