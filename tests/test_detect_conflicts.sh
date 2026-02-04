#!/bin/bash
# Tests for detect-conflicts.sh
#
# Run with:
#   ./tests/test_detect_conflicts.sh
#   ./tests/test_detect_conflicts.sh -v  # verbose

# Don't use set -e as we need to capture exit codes from failing commands

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
TEMP_DIR=""
VERBOSE=false

[[ "$1" == "-v" ]] && VERBOSE=true

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

PASSED=0
FAILED=0

log() {
    if $VERBOSE; then echo "$@"; fi
}

setup() {
    TEMP_DIR=$(mktemp -d)

    # Create minimal directory structure
    mkdir -p "$TEMP_DIR/mirror/prompts"
    mkdir -p "$TEMP_DIR/components/existing-component/prompts"
    mkdir -p "$TEMP_DIR/templates/prompts/sections"
    mkdir -p "$TEMP_DIR/tools"

    # Copy tools with modified lib.sh that respects TEST_ROOT_DIR
    cp "$ROOT_DIR/tools/detect-conflicts.sh" "$TEMP_DIR/tools/"

    # Create modified lib.sh that uses TEST_ROOT_DIR if set
    cat > "$TEMP_DIR/tools/lib.sh" << 'LIBEOF'
#!/bin/bash
# Test version of lib.sh - uses TEST_ROOT_DIR if set
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${TEST_ROOT_DIR:-$(dirname "$LIB_DIR")}"

load_config() {
    local config_file="$ROOT_DIR/config.yaml"
    if [[ ! -f "$config_file" ]]; then
        echo "ERROR: config.yaml not found at $config_file" >&2
        return 1
    fi
    SSH_HOST="test"
    REMOTE_HOME="/test"
    REMOTE_WORKSPACE="/test/clawd"
    MIRROR_DIR="$ROOT_DIR/mirror"
    EXPORTS_DIR="$ROOT_DIR/exports"
}

parse_common_args() {
    VERBOSE=false
    DRY_RUN=false
    REMAINING_ARGS=("$@")
    return 0
}
LIBEOF

    # Create minimal config.yaml
    cat > "$TEMP_DIR/config.yaml" << 'EOF'
ssh:
  host: test
remote:
  home: /test
  workspace: /test/clawd
local:
  mirror: mirror
EOF

    # Add agents_sections to config.yaml
    cat >> "$TEMP_DIR/config.yaml" << 'EOF'
exports:
  bot:
    agents_sections:
      - header
      - existing-component
      - bot:exec-approvals
EOF

    # Create template section
    cat > "$TEMP_DIR/templates/prompts/sections/header.md" << 'EOF'
# Header Section
EOF

    # Create existing component
    cat > "$TEMP_DIR/components/existing-component/prompts/AGENTS.snippet.md" << 'EOF'
## Existing Component
This is the existing component content.
EOF

    log "Setup complete in $TEMP_DIR"
}

teardown() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        log "Cleaned up $TEMP_DIR"
    fi
}

run_detect_conflicts() {
    # Run detect-conflicts.sh from temp directory with temp tools
    cd "$TEMP_DIR"
    TEST_ROOT_DIR="$TEMP_DIR" bash "$TEMP_DIR/tools/detect-conflicts.sh" 2>&1
}

assert_exit_code() {
    local expected=$1
    local actual=$2
    local test_name=$3

    if [[ "$actual" -eq "$expected" ]]; then
        echo -e "${GREEN}✓${NC} $test_name"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}✗${NC} $test_name (expected exit $expected, got $actual)"
        FAILED=$((FAILED + 1))
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"

    if echo "$haystack" | grep -q "$needle"; then
        echo -e "${GREEN}✓${NC} $test_name"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}✗${NC} $test_name"
        echo "    Expected to find: $needle"
        $VERBOSE && echo "    In output: $haystack"
        FAILED=$((FAILED + 1))
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"

    if ! echo "$haystack" | grep -q "$needle"; then
        echo -e "${GREEN}✓${NC} $test_name"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}✗${NC} $test_name"
        echo "    Expected NOT to find: $needle"
        FAILED=$((FAILED + 1))
    fi
}

# =============================================================================
# Test: No conflicts when mirror matches config
# =============================================================================
test_no_conflicts_when_matching() {
    echo ""
    echo "=== Test: No conflicts when mirror matches config ==="
    setup

    # Create mirror AGENTS.md that matches config
    cat > "$TEMP_DIR/mirror/prompts/AGENTS.md" << 'EOF'
<!-- SECTION: header -->
# Header Section
<!-- /SECTION: header -->

<!-- COMPONENT: existing-component -->
## Existing Component
This is the existing component content.
<!-- /COMPONENT: existing-component -->

<!-- BOT-MANAGED: exec-approvals -->
Bot managed content here
<!-- /BOT-MANAGED: exec-approvals -->
EOF

    cd "$TEMP_DIR"
    output=$(TEST_ROOT_DIR="$TEMP_DIR" bash "$TEMP_DIR/tools/detect-conflicts.sh" 2>&1)
    exit_code=$?

    log "Output: $output"

    assert_exit_code 0 $exit_code "Should exit 0 when no conflicts"
    assert_contains "$output" "No conflicts detected" "Should report no conflicts"

    teardown
}

# =============================================================================
# Test: Detects new BOT-MANAGED section
# =============================================================================
test_detects_new_bot_section() {
    echo ""
    echo "=== Test: Detects new BOT-MANAGED section ==="
    setup

    # Create mirror with a new BOT-MANAGED section not in config
    cat > "$TEMP_DIR/mirror/prompts/AGENTS.md" << 'EOF'
<!-- SECTION: header -->
# Header
<!-- /SECTION: header -->

<!-- COMPONENT: existing-component -->
## Existing
<!-- /COMPONENT: existing-component -->

<!-- BOT-MANAGED: exec-approvals -->
Existing bot section
<!-- /BOT-MANAGED: exec-approvals -->

<!-- BOT-MANAGED: new-bot-section -->
This is a NEW bot section not in config
<!-- /BOT-MANAGED: new-bot-section -->
EOF

    cd "$TEMP_DIR"
    output=$(TEST_ROOT_DIR="$TEMP_DIR" bash "$TEMP_DIR/tools/detect-conflicts.sh" 2>&1)
    exit_code=$?

    log "Output: $output"

    assert_exit_code 1 $exit_code "Should exit 1 when conflicts found"
    assert_contains "$output" "Conflicts detected" "Should report conflicts"
    assert_contains "$output" "new-bot-section" "Should identify the new section"
    assert_contains "$output" "NEW BOT SECTIONS" "Should categorize as bot section"

    teardown
}

# =============================================================================
# Test: Detects new COMPONENT section (THE BUG WE FIXED)
# =============================================================================
test_detects_new_component_section() {
    echo ""
    echo "=== Test: Detects new COMPONENT section (regression test) ==="
    setup

    # Create mirror with a new COMPONENT section not in config
    # This is the exact scenario that was failing before the fix
    cat > "$TEMP_DIR/mirror/prompts/AGENTS.md" << 'EOF'
<!-- SECTION: header -->
# Header
<!-- /SECTION: header -->

<!-- COMPONENT: existing-component -->
## Existing
<!-- /COMPONENT: existing-component -->

<!-- BOT-MANAGED: exec-approvals -->
Bot section
<!-- /BOT-MANAGED: exec-approvals -->

<!-- COMPONENT: claude-code -->
## Claude Code Collaboration
Bot added this component section!
<!-- /COMPONENT: claude-code -->
EOF

    cd "$TEMP_DIR"
    output=$(TEST_ROOT_DIR="$TEMP_DIR" bash "$TEMP_DIR/tools/detect-conflicts.sh" 2>&1)
    exit_code=$?

    log "Output: $output"

    # THIS WAS THE BUG: script said "no conflicts" when claude-code was added
    assert_exit_code 1 $exit_code "Should exit 1 when new COMPONENT found"
    assert_contains "$output" "Conflicts detected" "Should report conflicts"
    assert_contains "$output" "claude-code" "Should identify claude-code"
    assert_contains "$output" "NEW COMPONENT SECTIONS" "Should categorize as component section"

    teardown
}

# =============================================================================
# Test: Detects edited component content
# =============================================================================
test_detects_edited_component() {
    echo ""
    echo "=== Test: Detects edited component content ==="
    setup

    # Create mirror where existing component has been modified
    cat > "$TEMP_DIR/mirror/prompts/AGENTS.md" << 'EOF'
<!-- SECTION: header -->
# Header
<!-- /SECTION: header -->

<!-- COMPONENT: existing-component -->
## Existing Component
This content was MODIFIED by the bot!
Extra lines added.
<!-- /COMPONENT: existing-component -->

<!-- BOT-MANAGED: exec-approvals -->
Bot section
<!-- /BOT-MANAGED: exec-approvals -->
EOF

    cd "$TEMP_DIR"
    output=$(TEST_ROOT_DIR="$TEMP_DIR" bash "$TEMP_DIR/tools/detect-conflicts.sh" 2>&1)
    exit_code=$?

    log "Output: $output"

    assert_exit_code 1 $exit_code "Should exit 1 when component edited"
    assert_contains "$output" "Conflicts detected" "Should report conflicts"
    assert_contains "$output" "existing-component" "Should identify edited component"
    assert_contains "$output" "EDITED COMPONENTS" "Should categorize as edited"

    teardown
}

# =============================================================================
# Test: Multiple conflicts detected
# =============================================================================
test_multiple_conflicts() {
    echo ""
    echo "=== Test: Multiple conflicts detected ==="
    setup

    # Create mirror with multiple issues
    cat > "$TEMP_DIR/mirror/prompts/AGENTS.md" << 'EOF'
<!-- SECTION: header -->
# Header
<!-- /SECTION: header -->

<!-- COMPONENT: existing-component -->
## Modified content
<!-- /COMPONENT: existing-component -->

<!-- BOT-MANAGED: exec-approvals -->
Existing
<!-- /BOT-MANAGED: exec-approvals -->

<!-- BOT-MANAGED: new-notes -->
New bot section
<!-- /BOT-MANAGED: new-notes -->

<!-- COMPONENT: new-feature -->
New component
<!-- /COMPONENT: new-feature -->
EOF

    cd "$TEMP_DIR"
    output=$(TEST_ROOT_DIR="$TEMP_DIR" bash "$TEMP_DIR/tools/detect-conflicts.sh" 2>&1)
    exit_code=$?

    log "Output: $output"

    assert_exit_code 1 $exit_code "Should exit 1 with multiple conflicts"
    assert_contains "$output" "new-notes" "Should find new bot section"
    assert_contains "$output" "new-feature" "Should find new component"
    assert_contains "$output" "existing-component" "Should find edited component"

    teardown
}

# =============================================================================
# Test: Component variant support (component:variant syntax)
# =============================================================================
test_component_variant_support() {
    echo ""
    echo "=== Test: Component variant support (component:variant syntax) ==="
    setup

    # Create variant component file
    mkdir -p "$TEMP_DIR/components/http-api/prompts"
    cat > "$TEMP_DIR/components/http-api/prompts/AGENTS.router.snippet.md" << 'EOF'
## HTTP API Router
Handle routing for Siri requests.
EOF

    # Update config to use variant syntax
    cat > "$TEMP_DIR/config.yaml" << 'EOF'
ssh:
  host: test
remote:
  home: /test
  workspace: /test/clawd
local:
  mirror: mirror
exports:
  bot:
    agents_sections:
      - header
      - http-api:router
      - bot:exec-approvals
EOF

    # Create mirror AGENTS.md with variant component
    cat > "$TEMP_DIR/mirror/prompts/AGENTS.md" << 'EOF'
<!-- SECTION: header -->
# Header Section
<!-- /SECTION: header -->

<!-- COMPONENT: http-api:router -->
## HTTP API Router
Handle routing for Siri requests.
<!-- /COMPONENT: http-api:router -->

<!-- BOT-MANAGED: exec-approvals -->
Bot managed content here
<!-- /BOT-MANAGED: exec-approvals -->
EOF

    cd "$TEMP_DIR"
    output=$(TEST_ROOT_DIR="$TEMP_DIR" bash "$TEMP_DIR/tools/detect-conflicts.sh" 2>&1)
    exit_code=$?

    log "Output: $output"

    assert_exit_code 0 $exit_code "Should exit 0 when variant component matches"
    assert_contains "$output" "No conflicts detected" "Should report no conflicts with variant"

    teardown
}

# =============================================================================
# Test: Detects edited variant component
# =============================================================================
test_detects_edited_variant_component() {
    echo ""
    echo "=== Test: Detects edited variant component ==="
    setup

    # Create variant component file
    mkdir -p "$TEMP_DIR/components/http-api/prompts"
    cat > "$TEMP_DIR/components/http-api/prompts/AGENTS.router.snippet.md" << 'EOF'
## HTTP API Router
Handle routing for Siri requests.
EOF

    # Update config to use variant syntax
    cat > "$TEMP_DIR/config.yaml" << 'EOF'
ssh:
  host: test
remote:
  home: /test
  workspace: /test/clawd
local:
  mirror: mirror
exports:
  bot:
    agents_sections:
      - header
      - http-api:router
      - bot:exec-approvals
EOF

    # Create mirror with MODIFIED variant component
    cat > "$TEMP_DIR/mirror/prompts/AGENTS.md" << 'EOF'
<!-- SECTION: header -->
# Header Section
<!-- /SECTION: header -->

<!-- COMPONENT: http-api:router -->
## HTTP API Router
Handle routing for Siri requests.
BOT ADDED THIS LINE!
<!-- /COMPONENT: http-api:router -->

<!-- BOT-MANAGED: exec-approvals -->
Bot managed content here
<!-- /BOT-MANAGED: exec-approvals -->
EOF

    cd "$TEMP_DIR"
    output=$(TEST_ROOT_DIR="$TEMP_DIR" bash "$TEMP_DIR/tools/detect-conflicts.sh" 2>&1)
    exit_code=$?

    log "Output: $output"

    assert_exit_code 1 $exit_code "Should exit 1 when variant component edited"
    assert_contains "$output" "http-api:router" "Should identify edited variant component"
    assert_contains "$output" "EDITED COMPONENTS" "Should categorize as edited"

    teardown
}

# =============================================================================
# Run all tests
# =============================================================================
echo "Running detect-conflicts.sh tests..."

test_no_conflicts_when_matching
test_detects_new_bot_section
test_detects_new_component_section
test_detects_edited_component
test_multiple_conflicts
test_component_variant_support
test_detects_edited_variant_component

echo ""
echo "================================"
echo -e "${GREEN}Passed: $PASSED${NC}"
[[ $FAILED -gt 0 ]] && echo -e "${RED}Failed: $FAILED${NC}" || echo "Failed: $FAILED"
echo "================================"

exit $([[ $FAILED -eq 0 ]] && echo 0 || echo 1)
