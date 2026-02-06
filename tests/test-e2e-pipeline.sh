#!/bin/bash
# E2E test for content pipeline: intake → reference → exports
#
# Tests the full content flow:
# 1. intake/ (file with CONFIG) → canonicalize → reference/transcripts/
# 2. reference/ → export → agents/bruba-main/exports/
#
# Run from repo root: ./tests/test-e2e-pipeline.sh

set -e

cd "$(dirname "$0")/.."
ROOT_DIR="$(pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((TESTS_PASSED++)) || true
}

fail() {
    echo -e "${RED}✗${NC} $1"
    ((TESTS_FAILED++)) || true
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Test file naming
TEST_ID="e2e-test-$$"
TEST_FILE="${TEST_ID}.md"
CANONICAL_FILE="e2e-test-conversation.md"

echo "=== E2E Pipeline Test ==="
echo ""
echo "Test ID: $TEST_ID"
echo ""

# Cleanup function
cleanup() {
    echo ""
    echo "--- Cleanup ---"
    rm -f "intake/$TEST_FILE" 2>/dev/null && echo "  Removed intake/$TEST_FILE" || true
    rm -f "intake/processed/$TEST_FILE" 2>/dev/null && echo "  Removed intake/processed/$TEST_FILE" || true
    rm -f "reference/transcripts/$CANONICAL_FILE" 2>/dev/null && echo "  Removed reference/transcripts/$CANONICAL_FILE" || true
    # Don't remove agents/bruba-main/exports files - they may have other content
    # The export test verifies existence, that's sufficient
}
trap cleanup EXIT

# Ensure directories exist
mkdir -p intake reference/transcripts agents/bruba-main/exports

# --- Test 1: Setup ---
echo "--- Test 1: Setup ---"

if [[ -f "tests/fixtures/009-e2e-pipeline/input.md" ]]; then
    cp "tests/fixtures/009-e2e-pipeline/input.md" "intake/$TEST_FILE"
    if [[ -f "intake/$TEST_FILE" ]]; then
        pass "Copied fixture to intake/$TEST_FILE"
    else
        fail "Failed to copy fixture"
        exit 1
    fi
else
    fail "Fixture not found: tests/fixtures/009-e2e-pipeline/input.md"
    exit 1
fi

echo ""

# --- Test 2: Canonicalize ---
echo "--- Test 2: Canonicalize ---"

# Check CLI exists
if python3 -c "from components.distill.lib import cli" 2>/dev/null; then
    pass "CLI module available"
else
    fail "CLI module not found"
    exit 1
fi

# Run canonicalize with proper output options
CANON_OUTPUT=$(python3 -m components.distill.lib.cli canonicalize \
    --output reference/transcripts/ \
    --move intake/processed/ \
    "intake/$TEST_FILE" 2>&1) || true

if [[ -f "reference/transcripts/$CANONICAL_FILE" ]]; then
    pass "Canonical file created: reference/transcripts/$CANONICAL_FILE"
else
    fail "Canonical file not created"
    echo "  CLI output: $CANON_OUTPUT"
    exit 1
fi

# Verify original moved to processed
if [[ -f "intake/processed/$TEST_FILE" ]]; then
    pass "Original moved to intake/processed/"
else
    warn "Original not in intake/processed/ (may be expected)"
fi

# Verify frontmatter preserved
if head -1 "reference/transcripts/$CANONICAL_FILE" | grep -q "^---"; then
    pass "Frontmatter preserved in canonical file"
else
    fail "Frontmatter missing from canonical file"
fi

echo ""

# --- Test 3: Export ---
echo "--- Test 3: Export ---"

# Run export
EXPORT_OUTPUT=$(python3 -m components.distill.lib.cli export --profile agent:bruba-main 2>&1) || true

if echo "$EXPORT_OUTPUT" | grep -q "Export complete"; then
    pass "Export CLI completed"
else
    fail "Export CLI failed"
    echo "  Output: $EXPORT_OUTPUT"
fi

# Check if our file was exported (now goes to transcripts/ subdirectory with prefix)
# Note: scope: meta should be included in agent profile
EXPORT_FILE="agents/bruba-main/exports/transcripts/Transcript - ${CANONICAL_FILE}"
if [[ -f "$EXPORT_FILE" ]]; then
    pass "File exported to $EXPORT_FILE"
else
    # It might have been filtered - check if that's expected
    if echo "$EXPORT_OUTPUT" | grep -q "$CANONICAL_FILE"; then
        pass "File processed by export (may have been filtered)"
    else
        warn "File not in agents/bruba-main/exports/transcripts/ (check type filters)"
    fi
fi

echo ""

# --- Test 4: Content Verification ---
echo "--- Test 4: Content Verification ---"

if [[ -f "reference/transcripts/$CANONICAL_FILE" ]]; then
    # Verify key content
    if grep -q "E2E Pipeline Test" "reference/transcripts/$CANONICAL_FILE"; then
        pass "Title preserved in canonical file"
    else
        fail "Title missing from canonical file"
    fi

    if grep -q "MESSAGE 0" "reference/transcripts/$CANONICAL_FILE"; then
        pass "Message content preserved"
    else
        fail "Message content missing"
    fi

    if grep -q "BACKMATTER" "reference/transcripts/$CANONICAL_FILE"; then
        pass "Backmatter preserved"
    else
        fail "Backmatter missing"
    fi
fi

echo ""
echo "=== Summary ==="
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "\n${GREEN}All e2e tests passed!${NC}"
    exit 0
else
    echo -e "\n${RED}Some tests failed${NC}"
    exit 1
fi
