#!/bin/bash
# Test export prompt functionality
#
# Tests:
# 1. Prompt files exist in components/distill/prompts/
# 2. Export CLI can scan and process prompts
# 3. Prompts get renamed correctly (Export.md → Prompt - Export.md)
# 4. exports.yaml has correct profiles
#
# Run from repo root: ./tests/test-export-prompts.sh

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

echo "=== Export Prompt Tests ==="
echo ""

# Test 1: Check prompt files exist
echo "--- Test 1: Prompt Files Exist ---"

if [[ -f "components/distill/prompts/Export.md" ]]; then
    pass "Export.md exists"
else
    fail "Export.md not found"
fi

if [[ -f "components/distill/prompts/Export-Claude.md" ]]; then
    pass "Export-Claude.md exists"
else
    fail "Export-Claude.md not found"
fi

if [[ -f "components/distill/prompts/Transcription.md" ]]; then
    pass "Transcription.md exists"
else
    fail "Transcription.md not found"
fi

if [[ -f "components/distill/prompts/AGENTS.snippet.md" ]]; then
    pass "AGENTS.snippet.md exists (should be excluded from export)"
else
    warn "AGENTS.snippet.md not found"
fi

echo ""

# Test 2: Check exports.yaml profiles
echo "--- Test 2: exports.yaml Profiles ---"

if grep -q "^  bot:" exports.yaml; then
    pass "bot profile exists"
else
    fail "bot profile not found in exports.yaml"
fi

if grep -q "^  claude:" exports.yaml; then
    pass "claude profile exists"
else
    fail "claude profile not found in exports.yaml"
fi

if grep -q "type: \[prompt\]" exports.yaml; then
    pass "type: [prompt] filter exists"
else
    warn "type: [prompt] filter not found (may need to add)"
fi

echo ""

# Test 3: Test prompt copying logic (simulated)
echo "--- Test 3: Prompt Copy Logic ---"

# Create temp export directory
TEMP_EXPORTS=$(mktemp -d)
trap "rm -rf $TEMP_EXPORTS" EXIT

# Simulate the push.sh prompt copying logic
PROMPT_COUNT=0
for prompt_file in components/*/prompts/*.md; do
    [[ -e "$prompt_file" ]] || continue
    filename=$(basename "$prompt_file")

    # Skip AGENTS.snippet.md
    if [[ "$filename" == "AGENTS.snippet.md" ]]; then
        continue
    fi

    dest_name="Prompt - ${filename}"
    cp "$prompt_file" "$TEMP_EXPORTS/$dest_name"
    ((PROMPT_COUNT++)) || true
done

if [[ $PROMPT_COUNT -gt 0 ]]; then
    pass "Copied $PROMPT_COUNT prompt(s) to temp directory"
else
    fail "No prompts copied"
fi

if [[ -f "$TEMP_EXPORTS/Prompt - Export.md" ]]; then
    pass "Export.md renamed to 'Prompt - Export.md'"
else
    fail "Prompt - Export.md not created"
fi

if [[ -f "$TEMP_EXPORTS/Prompt - Export-Claude.md" ]]; then
    pass "Export-Claude.md renamed to 'Prompt - Export-Claude.md'"
else
    fail "Prompt - Export-Claude.md not created"
fi

if [[ -f "$TEMP_EXPORTS/Prompt - Transcription.md" ]]; then
    pass "Transcription.md renamed to 'Prompt - Transcription.md'"
else
    fail "Prompt - Transcription.md not created"
fi

if [[ ! -f "$TEMP_EXPORTS/Prompt - AGENTS.snippet.md" ]]; then
    pass "AGENTS.snippet.md correctly excluded"
else
    fail "AGENTS.snippet.md should have been excluded"
fi

echo ""

# Test 4: Check Export CLI exists and has export command
echo "--- Test 4: Export CLI ---"

if python3 -c "from components.distill.lib import cli" 2>/dev/null; then
    pass "CLI module imports successfully"
else
    fail "CLI module import failed"
fi

CLI_HELP=$(python3 -m components.distill.lib.cli --help 2>&1 || true)
if echo "$CLI_HELP" | grep -q "export"; then
    pass "CLI has export command"
else
    fail "CLI missing export command"
fi

echo ""

# Test 5: Run export CLI with profile targeting
echo "--- Test 5: Profile-Targeted Export ---"

# Clean exports for fresh test
rm -rf exports/bot exports/claude

# Run export with bot profile
BOT_OUTPUT=$(python3 -m components.distill.lib.cli --verbose export --profile bot 2>&1 || true)

if echo "$BOT_OUTPUT" | grep -q "prompts)"; then
    pass "Export CLI found prompt files"
else
    fail "Export CLI didn't find prompts: $BOT_OUTPUT"
fi

if echo "$BOT_OUTPUT" | grep -q "Profile: bot"; then
    pass "Export CLI runs for bot profile"
else
    fail "Export CLI failed to run bot profile"
fi

# Bot profile should get Export.md and Transcription.md (profile: bot)
if [[ -f "exports/bot/Prompt - Export.md" ]]; then
    pass "Export.md exported to bot profile"
else
    fail "Export.md not exported to bot profile"
fi

if [[ -f "exports/bot/Prompt - Transcription.md" ]]; then
    pass "Transcription.md exported to bot profile"
else
    fail "Transcription.md not exported to bot profile"
fi

# Bot profile should NOT get Export-Claude.md (profile: claude)
if [[ ! -f "exports/bot/Prompt - Export-Claude.md" ]]; then
    pass "Export-Claude.md correctly excluded from bot profile"
else
    fail "Export-Claude.md should not be in bot profile"
fi

# Check frontmatter preserved
if head -1 "exports/bot/Prompt - Export.md" | grep -q "^---"; then
    pass "Frontmatter preserved in exported prompt"
else
    fail "Frontmatter missing from exported prompt"
fi

# Test 6: Claude profile targeting
echo ""
echo "--- Test 6: Claude Profile Targeting ---"

CLAUDE_OUTPUT=$(python3 -m components.distill.lib.cli --verbose export --profile claude 2>&1 || true)

if echo "$CLAUDE_OUTPUT" | grep -q "Profile: claude"; then
    pass "Export CLI runs for claude profile"
else
    fail "Export CLI failed to run claude profile"
fi

# Claude profile should get Export-Claude.md as "Prompt - Export.md"
if [[ -f "exports/claude/Prompt - Export.md" ]]; then
    pass "Export-Claude.md exported to claude profile as Prompt - Export.md"
else
    fail "Export-Claude.md not exported to claude profile"
fi

# Claude profile should NOT get bot-targeted prompts
if [[ ! -f "exports/claude/Prompt - Transcription.md" ]]; then
    pass "Transcription.md correctly excluded from claude profile"
else
    fail "Transcription.md should not be in claude profile"
fi

# Verify the Export.md in claude/ is the Claude-specific version
if grep -q "Claude Code" "exports/claude/Prompt - Export.md"; then
    pass "Claude profile has Claude-specific Export prompt"
else
    fail "Claude profile should have Claude Code variant of Export"
fi

echo ""
echo "=== Summary ==="
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "\n${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "\n${RED}Some tests failed${NC}"
    exit 1
fi
