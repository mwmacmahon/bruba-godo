#!/bin/bash
# Test suite for component tools automation (Phase B-E of component audit)
#
# Tests:
#   - Component tool discovery
#   - Allowlist.json validation
#   - validate-components.sh correctness
#   - update-allowlist.sh functionality
#
# Usage:
#   ./tests/test-component-tools.sh              # Run all tests
#   ./tests/test-component-tools.sh --quick      # Skip SSH-dependent tests
#   ./tests/test-component-tools.sh --verbose    # Show detailed output
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
NC='\033[0m'

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
# Test 1: Component Tools Discovery
# ============================================================
test_component_tools_discovery() {
    log ""
    log "=== Test 1: Component Tools Discovery ==="

    # Expected components with tools/
    local expected_components=("voice" "web-search" "reminders")
    local found=0

    for component in "${expected_components[@]}"; do
        if [[ -d "$ROOT_DIR/components/$component/tools" ]]; then
            pass "Found tools/ in $component"
            found=$((found + 1))
        else
            fail "Missing tools/ in $component"
        fi
    done

    if [[ $found -eq ${#expected_components[@]} ]]; then
        pass "All expected component tools directories exist"
    fi
}

# ============================================================
# Test 2: Allowlist.json Validation
# ============================================================
test_allowlist_json_validity() {
    log ""
    log "=== Test 2: Allowlist.json Validation ==="

    local components_with_tools=0
    local components_with_allowlist=0

    for component_dir in "$ROOT_DIR/components"/*/; do
        local component=$(basename "$component_dir")

        # Check if has tools/
        if [[ -d "$component_dir/tools" ]]; then
            components_with_tools=$((components_with_tools + 1))

            # Must have allowlist.json
            if [[ -f "$component_dir/allowlist.json" ]]; then
                components_with_allowlist=$((components_with_allowlist + 1))

                # Validate JSON syntax
                if jq empty "$component_dir/allowlist.json" 2>/dev/null; then
                    pass "$component/allowlist.json is valid JSON"
                else
                    fail "$component/allowlist.json has invalid JSON"
                    continue
                fi

                # Validate structure (must have entries array)
                if jq -e '.entries | type == "array"' "$component_dir/allowlist.json" >/dev/null 2>&1; then
                    pass "$component/allowlist.json has entries array"
                else
                    fail "$component/allowlist.json missing entries array"
                    continue
                fi

                # Validate each entry has pattern and id
                local invalid_entries
                invalid_entries=$(jq '[.entries[] | select(.pattern == null or .id == null)] | length' "$component_dir/allowlist.json")
                if [[ "$invalid_entries" -eq 0 ]]; then
                    pass "$component/allowlist.json entries have pattern+id"
                else
                    fail "$component/allowlist.json has $invalid_entries entries missing pattern/id"
                fi

                # Validate ${WORKSPACE} placeholder usage
                local uses_workspace
                uses_workspace=$(jq '[.entries[].pattern | select(contains("${WORKSPACE}"))] | length' "$component_dir/allowlist.json")
                local total_entries
                total_entries=$(jq '.entries | length' "$component_dir/allowlist.json")
                if [[ "$uses_workspace" -eq "$total_entries" ]]; then
                    pass "$component/allowlist.json uses \${WORKSPACE} placeholder"
                else
                    fail "$component/allowlist.json has entries without \${WORKSPACE}"
                fi
            else
                fail "$component has tools/ but no allowlist.json"
            fi
        fi
    done

    if [[ $components_with_tools -eq $components_with_allowlist ]]; then
        pass "All components with tools have allowlist.json ($components_with_tools)"
    fi
}

# ============================================================
# Test 3: Validate-Components Script
# ============================================================
test_validate_components_script() {
    log ""
    log "=== Test 3: Validate-Components Script ==="

    # Script exists and is executable
    if [[ -x "$ROOT_DIR/tools/validate-components.sh" ]]; then
        pass "validate-components.sh exists and is executable"
    else
        fail "validate-components.sh not found or not executable"
        return 1
    fi

    # Run validation
    local output
    output=$(./tools/validate-components.sh 2>&1) || true

    if [[ "$VERBOSE" == "true" ]]; then
        echo "$output"
    fi

    # Should report counts
    if echo "$output" | grep -qE "[0-9]+ passed"; then
        pass "validate-components.sh reports check counts"
    else
        fail "validate-components.sh output format unexpected"
    fi

    # Should have no errors on current state
    if echo "$output" | grep -q "0 errors"; then
        pass "validate-components.sh reports no errors"
    else
        # Extract error count
        local errors
        errors=$(echo "$output" | grep -oE "[0-9]+ errors" | head -1)
        fail "validate-components.sh found errors: $errors"
    fi
}

# ============================================================
# Test 4: Update-Allowlist Check Mode
# ============================================================
test_update_allowlist_check() {
    log ""
    log "=== Test 4: Update-Allowlist Check Mode ==="

    if [[ "$QUICK" == "true" ]]; then
        skip "update-allowlist.sh --check (requires SSH)"
        return 0
    fi

    # Check SSH connectivity
    if ! ./tools/bot echo "ping" >/dev/null 2>&1; then
        skip "update-allowlist.sh --check (no SSH connectivity)"
        return 0
    fi

    # Script exists
    if [[ ! -x "$ROOT_DIR/tools/update-allowlist.sh" ]]; then
        fail "update-allowlist.sh not found or not executable"
        return 1
    fi

    # Run check mode
    local output
    output=$(./tools/update-allowlist.sh --check 2>&1) || true

    if [[ "$VERBOSE" == "true" ]]; then
        echo "$output"
    fi

    # Should produce status output
    if echo "$output" | grep -qE "(in sync|entries to add|orphan entries)"; then
        pass "update-allowlist.sh --check produces status"
    else
        fail "update-allowlist.sh --check output unexpected: $output"
    fi
}

# ============================================================
# Test 5: Update-Allowlist Dry Run
# ============================================================
test_update_allowlist_dryrun() {
    log ""
    log "=== Test 5: Update-Allowlist Dry Run ==="

    if [[ "$QUICK" == "true" ]]; then
        skip "update-allowlist.sh --dry-run (requires SSH)"
        return 0
    fi

    if ! ./tools/bot echo "ping" >/dev/null 2>&1; then
        skip "update-allowlist.sh --dry-run (no SSH connectivity)"
        return 0
    fi

    local output
    output=$(./tools/update-allowlist.sh --dry-run 2>&1) || true

    if [[ "$VERBOSE" == "true" ]]; then
        echo "$output"
    fi

    # Should say DRY RUN or "in sync"
    if echo "$output" | grep -qE "(\[DRY RUN\]|in sync)"; then
        pass "update-allowlist.sh --dry-run works"
    else
        fail "update-allowlist.sh --dry-run output unexpected"
    fi
}

# ============================================================
# Test 6: Allowlist Entry Expansion
# ============================================================
test_allowlist_expansion() {
    log ""
    log "=== Test 6: Allowlist Entry Expansion ==="

    # Test that ${WORKSPACE} gets expanded correctly
    # Source lib.sh in subshell to avoid polluting our functions
    REMOTE_WORKSPACE=$(
        source "$ROOT_DIR/tools/lib.sh" 2>/dev/null
        load_config 2>/dev/null
        echo "$REMOTE_WORKSPACE"
    )

    if [[ -z "$REMOTE_WORKSPACE" ]]; then
        fail "REMOTE_WORKSPACE not set from config"
        return 1
    fi
    pass "REMOTE_WORKSPACE loaded: $REMOTE_WORKSPACE"

    # Test expansion on a sample entry
    local sample='{"entries":[{"pattern":"${WORKSPACE}/tools/test.sh","id":"test"}]}'
    local expanded
    expanded=$(echo "$sample" | sed "s|\${WORKSPACE}|$REMOTE_WORKSPACE|g")

    if echo "$expanded" | grep -q "$REMOTE_WORKSPACE/tools/test.sh"; then
        pass "\${WORKSPACE} expansion works"
    else
        fail "\${WORKSPACE} expansion failed: $expanded"
    fi
}

# ============================================================
# Test 7: AGENTS.snippet.md Wiring
# ============================================================
test_snippet_wiring() {
    log ""
    log "=== Test 7: AGENTS.snippet.md Wiring ==="

    # Components with tools should have AGENTS.snippet.md
    local components_with_tools=("voice" "web-search" "reminders")

    for component in "${components_with_tools[@]}"; do
        local snippet="$ROOT_DIR/components/$component/prompts/AGENTS.snippet.md"
        if [[ -f "$snippet" ]]; then
            pass "$component has AGENTS.snippet.md"
        else
            fail "$component missing AGENTS.snippet.md"
        fi
    done

    # Check they're in config.yaml agents_sections
    if [[ -f "$ROOT_DIR/config.yaml" ]]; then
        for component in "${components_with_tools[@]}"; do
            if grep -qE "^\s*- $component\s*$" "$ROOT_DIR/config.yaml"; then
                pass "$component in config.yaml agents_sections"
            else
                fail "$component not in config.yaml agents_sections"
            fi
        done
    else
        skip "config.yaml not found (using example?)"
    fi
}

# ============================================================
# Test 8: Push Script Tool Sync
# ============================================================
test_push_script_tools_option() {
    log ""
    log "=== Test 8: Push Script --tools-only Option ==="

    # Check push.sh has the option
    if grep -q "\-\-tools-only" "$ROOT_DIR/tools/push.sh"; then
        pass "push.sh has --tools-only option"
    else
        fail "push.sh missing --tools-only option"
        return 1
    fi

    # Check sync_component_tools function exists
    if grep -q "sync_component_tools" "$ROOT_DIR/tools/push.sh"; then
        pass "push.sh has sync_component_tools function"
    else
        fail "push.sh missing sync_component_tools function"
    fi

    # Check --update-allowlist option
    if grep -q "\-\-update-allowlist" "$ROOT_DIR/tools/push.sh"; then
        pass "push.sh has --update-allowlist option"
    else
        fail "push.sh missing --update-allowlist option"
    fi
}

# ============================================================
# Test 9: Orphan Detection Logic
# ============================================================
test_orphan_detection() {
    log ""
    log "=== Test 9: Orphan Detection Logic ==="

    # Check update-allowlist.sh has orphan detection
    if grep -q "find_orphan_entries" "$ROOT_DIR/tools/update-allowlist.sh"; then
        pass "update-allowlist.sh has find_orphan_entries function"
    else
        fail "update-allowlist.sh missing find_orphan_entries function"
    fi

    # Check --add-only and --remove-only flags
    if grep -q "\-\-add-only" "$ROOT_DIR/tools/update-allowlist.sh"; then
        pass "update-allowlist.sh has --add-only flag"
    else
        fail "update-allowlist.sh missing --add-only flag"
    fi

    if grep -q "\-\-remove-only" "$ROOT_DIR/tools/update-allowlist.sh"; then
        pass "update-allowlist.sh has --remove-only flag"
    else
        fail "update-allowlist.sh missing --remove-only flag"
    fi
}

# ============================================================
# Test 10: Sync Skill Allowlist Step
# ============================================================
test_sync_skill_allowlist_step() {
    log ""
    log "=== Test 10: Sync Skill Allowlist Step ==="

    local sync_skill="$ROOT_DIR/.claude/commands/sync.md"

    if [[ ! -f "$sync_skill" ]]; then
        fail "sync.md skill not found"
        return 1
    fi

    # Check for allowlist validation step
    if grep -q "Validate Allowlist" "$sync_skill"; then
        pass "sync.md has 'Validate Allowlist' step"
    else
        fail "sync.md missing 'Validate Allowlist' step"
    fi

    # Check for update-allowlist.sh --check
    if grep -q "update-allowlist.sh --check" "$sync_skill"; then
        pass "sync.md references update-allowlist.sh --check"
    else
        fail "sync.md missing update-allowlist.sh --check reference"
    fi
}

# ============================================================
# Main
# ============================================================
log "Component Tools Test Suite"
log "==========================="
log "(Testing Phase B-E component audit changes)"
log ""

test_component_tools_discovery || true
test_allowlist_json_validity || true
test_validate_components_script || true
test_update_allowlist_check || true
test_update_allowlist_dryrun || true
test_allowlist_expansion || true
test_snippet_wiring || true
test_push_script_tools_option || true
test_orphan_detection || true
test_sync_skill_allowlist_step || true

echo ""
echo "==========================="
echo -e "Results: ${GREEN}$TESTS_PASSED passed${NC}, ${RED}$TESTS_FAILED failed${NC}, ${YELLOW}$TESTS_SKIPPED skipped${NC}"

if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
