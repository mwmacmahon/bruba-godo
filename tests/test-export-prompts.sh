#!/bin/bash
# Test export prompt functionality
#
# Tests:
# 1. Prompt files exist in components/distill/prompts/
# 2. Export CLI can scan and process prompts
# 3. Prompts get renamed correctly (Export.md → Prompt - Export.md)
# 4. config.yaml has correct profiles
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

# Export-Claude.md was merged into Export.md
if [[ ! -f "components/distill/prompts/Export-Claude.md" ]]; then
    pass "Export-Claude.md correctly merged (file removed)"
else
    fail "Export-Claude.md should have been merged into Export.md"
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

# Test 2: Check config.yaml profiles
echo "--- Test 2: config.yaml Profiles ---"

if grep -q "^  bot:" config.yaml; then
    pass "bot profile exists"
else
    fail "bot profile not found in config.yaml"
fi

if grep -q "^  claude:" config.yaml; then
    pass "claude profile exists"
else
    fail "claude profile not found in config.yaml"
fi

if grep -q "type: \[prompt\]" config.yaml; then
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

# Export-Claude.md no longer exists (merged into Export.md)
if [[ ! -f "$TEMP_EXPORTS/Prompt - Export-Claude.md" ]]; then
    pass "Export-Claude.md correctly merged (not copied separately)"
else
    fail "Export-Claude.md should have been merged into Export.md"
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

# Bot profile should get Export.md and Transcription.md in prompts/ subdirectory
if [[ -f "exports/bot/prompts/Prompt - Export.md" ]]; then
    pass "Export.md exported to bot profile (prompts/)"
else
    fail "Export.md not exported to bot profile prompts/"
fi

if [[ -f "exports/bot/prompts/Prompt - Transcription.md" ]]; then
    pass "Transcription.md exported to bot profile (prompts/)"
else
    fail "Transcription.md not exported to bot profile prompts/"
fi

# Check frontmatter preserved
if head -1 "exports/bot/prompts/Prompt - Export.md" | grep -q "^---"; then
    pass "Frontmatter preserved in exported prompt"
else
    fail "Frontmatter missing from exported prompt"
fi

# Check Export.md has file access conditional (merged content)
if grep -q "file write access" "exports/bot/prompts/Prompt - Export.md"; then
    pass "Export.md has Claude Code conditional (merged)"
else
    fail "Export.md missing Claude Code conditional"
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

# Claude profile gets the unified Export.md in prompts/ subdirectory
if [[ -f "exports/claude/prompts/Prompt - Export.md" ]]; then
    pass "Export.md exported to claude profile (prompts/)"
else
    fail "Export.md not exported to claude profile prompts/"
fi

# Claude profile should also get Transcription.md now (unified prompts)
if [[ -f "exports/claude/prompts/Prompt - Transcription.md" ]]; then
    pass "Transcription.md exported to claude profile (prompts/)"
else
    fail "Transcription.md not exported to claude profile prompts/"
fi

# Verify the Export.md has the unified content with file access conditional
if grep -q "file write access" "exports/claude/prompts/Prompt - Export.md"; then
    pass "Claude profile has unified Export prompt with file access conditional"
else
    fail "Claude profile Export.md missing file access conditional"
fi

echo ""

# Test 7: Stage 2 - Silent Transcript Mode Content
echo "--- Test 7: Silent Transcript Mode Content ---"

# Check Transcription.md has Bruba Silent Mode section
if grep -q "## Bruba Silent Mode" "components/distill/prompts/Transcription.md"; then
    pass "Transcription.md has Bruba Silent Mode section"
else
    fail "Transcription.md missing Bruba Silent Mode section"
fi

# Check exported Transcription.md has silent mode section
if grep -q "## Bruba Silent Mode" "exports/bot/prompts/Prompt - Transcription.md"; then
    pass "Exported Transcription.md has Bruba Silent Mode section"
else
    fail "Exported Transcription.md missing Bruba Silent Mode section"
fi

# Check silent mode has key instructions (updated for expanded version)
SILENT_MODE_CONTENT=$(grep -A 50 "## Bruba Silent Mode" "exports/bot/prompts/Prompt - Transcription.md" 2>/dev/null || true)

if echo "$SILENT_MODE_CONTENT" | grep -q "Decision Tree"; then
    pass "Silent mode has Decision Tree section"
else
    fail "Silent mode missing Decision Tree section"
fi

if echo "$SILENT_MODE_CONTENT" | grep -q "What to Track Internally"; then
    pass "Silent mode has internal tracking guidance"
else
    fail "Silent mode missing internal tracking guidance"
fi

if echo "$SILENT_MODE_CONTENT" | grep -q "What to Print"; then
    pass "Silent mode has 'What to Print' section"
else
    fail "Silent mode missing 'What to Print' section"
fi

if echo "$SILENT_MODE_CONTENT" | grep -q "Example Workflow"; then
    pass "Silent mode has Example Workflow"
else
    fail "Silent mode missing Example Workflow"
fi

echo ""

# Test 8: Voice Snippet Silent Mode Flow (simplified 6-step)
echo "--- Test 8: Voice Snippet Silent Mode Flow ---"

VOICE_SNIPPET="components/voice/prompts/AGENTS.snippet.md"

if [[ -f "$VOICE_SNIPPET" ]]; then
    pass "Voice AGENTS.snippet.md exists"
else
    fail "Voice AGENTS.snippet.md not found"
fi

# Check voice snippet has simplified 6-step flow
if grep -q "Transcribe:" "$VOICE_SNIPPET"; then
    pass "Voice snippet has 'Transcribe' step"
else
    fail "Voice snippet missing 'Transcribe' step"
fi

if grep -q "Apply fixes silently" "$VOICE_SNIPPET"; then
    pass "Voice snippet has 'Apply fixes silently' step"
else
    fail "Voice snippet missing 'Apply fixes silently' step"
fi

if grep -q "Surface uncertainties" "$VOICE_SNIPPET"; then
    pass "Voice snippet has 'Surface uncertainties' step"
else
    fail "Voice snippet missing 'Surface uncertainties' step"
fi

if grep -q "Respond" "$VOICE_SNIPPET"; then
    pass "Voice snippet has 'Respond' step"
else
    fail "Voice snippet missing 'Respond' step"
fi

if grep -q "Voice reply:" "$VOICE_SNIPPET"; then
    pass "Voice snippet has 'Voice reply' step"
else
    fail "Voice snippet missing 'Voice reply' step"
fi

if grep -q "Text version" "$VOICE_SNIPPET"; then
    pass "Voice snippet has 'Text version' step"
else
    fail "Voice snippet missing 'Text version' step"
fi

echo ""

# Test 9: AGENTS.snippet Export Pipeline Note
echo "--- Test 9: AGENTS.snippet Export Pipeline Note ---"

DISTILL_SNIPPET="components/distill/prompts/AGENTS.snippet.md"

if grep -q "export pipeline" "$DISTILL_SNIPPET"; then
    pass "Distill snippet mentions export pipeline"
else
    fail "Distill snippet missing export pipeline reference"
fi

if grep -q "components/distill/prompts/" "$DISTILL_SNIPPET"; then
    pass "Distill snippet references source location"
else
    fail "Distill snippet missing source location reference"
fi

# Updated: exports now go to exports/bot/prompts/ (with subdirectory)
if grep -q "exports/bot/" "$DISTILL_SNIPPET"; then
    pass "Distill snippet references export output location"
else
    fail "Distill snippet missing export output reference"
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
