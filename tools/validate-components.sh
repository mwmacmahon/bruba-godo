#!/bin/bash
# Validate component consistency
#
# Usage:
#   ./tools/validate-components.sh           # Run validation
#   ./tools/validate-components.sh --verbose # Detailed output
#
# Checks:
#   - Components with tools/ have allowlist.json
#   - Components with AGENTS.snippet.md are in agents_sections
#   - No orphaned snippets (in dir but not in config)
#
# Exit codes: 0 = OK, 1 = errors found

set -e

# Load shared functions
source "$(dirname "$0")/lib.sh"

# Parse arguments
VERBOSE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--verbose]"
            echo ""
            echo "Validate component consistency."
            echo ""
            echo "Checks:"
            echo "  - Components with tools/ have allowlist.json"
            echo "  - Components with AGENTS.snippet.md are in agents_sections"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

# Load config
load_config

# Get agents_sections from config.yaml
get_agents_sections() {
    python3 -c "
import yaml
with open('$ROOT_DIR/config.yaml') as f:
    config = yaml.safe_load(f)
    sections = config.get('exports', {}).get('bot', {}).get('agents_sections', [])
    for s in sections:
        print(s)
"
}

echo "Validating components..."
echo ""

ERRORS=0
WARNINGS=0
PASSED=0

# Get configured sections
SECTIONS=$(get_agents_sections)

# Check each component
for component_dir in "$ROOT_DIR/components"/*/; do
    component=$(basename "$component_dir")
    issues=()
    features=()

    # Check for snippet
    if [[ -f "$component_dir/prompts/AGENTS.snippet.md" ]]; then
        features+=("snippet")
        # Check if in agents_sections
        if ! echo "$SECTIONS" | grep -q "^${component}$"; then
            issues+=("snippet not in agents_sections")
            ((ERRORS++))
        fi
    fi

    # Check for tools
    if [[ -d "$component_dir/tools" ]] && [[ -n "$(ls -A "$component_dir/tools" 2>/dev/null)" ]]; then
        features+=("tools")
        # Check for allowlist.json
        if [[ -f "$component_dir/allowlist.json" ]]; then
            features+=("allowlist")
        else
            issues+=("has tools/ but no allowlist.json")
            ((ERRORS++))
        fi
    fi

    # Check for setup/validate
    [[ -f "$component_dir/setup.sh" ]] && features+=("setup")
    [[ -f "$component_dir/validate.sh" ]] && features+=("validate")

    # Report
    feature_str=$(IFS=,; echo "${features[*]}")

    if [[ ${#issues[@]} -eq 0 ]]; then
        echo "✓ $component: OK ($feature_str)"
        ((PASSED++))
    else
        echo "✗ $component: ${issues[*]} ($feature_str)"
    fi

    if [[ "$VERBOSE" == "true" && ${#issues[@]} -gt 0 ]]; then
        for issue in "${issues[@]}"; do
            echo "    - $issue"
        done
    fi
done

echo ""
echo "Checks: $PASSED passed, $ERRORS errors"

if [[ $ERRORS -gt 0 ]]; then
    exit 1
fi
exit 0
