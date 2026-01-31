#!/bin/bash
# Detect conflicts between mirror and config/components
#
# Usage:
#   ./tools/detect-conflicts.sh              # Check for conflicts
#   ./tools/detect-conflicts.sh --verbose    # Show details
#   ./tools/detect-conflicts.sh --show-section NAME  # Show a bot section
#   ./tools/detect-conflicts.sh --diff NAME  # Show diff for a component
#
# Conflicts detected:
#   1. New BOT-MANAGED sections in mirror not in config
#   2. Component content differs from mirror (bot edited it)
#
# Exit codes:
#   0 = No conflicts
#   1 = Conflicts detected
#   2 = Error

set -e

# Load shared functions
source "$(dirname "$0")/lib.sh"

# Parse arguments
SHOW_SECTION=""
SHOW_DIFF=""

if ! parse_common_args "$@"; then
    echo "Usage: $0 [--verbose] [--show-section NAME] [--diff NAME]"
    echo ""
    echo "Detect conflicts between mirror and config/components."
    echo ""
    echo "Options:"
    echo "  --verbose, -v         Show detailed output"
    echo "  --show-section NAME   Show content of a bot section"
    echo "  --diff NAME           Show diff for a component"
    exit 0
fi

# Check for additional args
for arg in "${REMAINING_ARGS[@]}"; do
    case $arg in
        --show-section)
            shift
            SHOW_SECTION="${REMAINING_ARGS[1]:-}"
            ;;
        --diff)
            shift
            SHOW_DIFF="${REMAINING_ARGS[1]:-}"
            ;;
    esac
done

# Handle --show-section and --diff from command line more robustly
while [[ $# -gt 0 ]]; do
    case $1 in
        --show-section)
            SHOW_SECTION="$2"
            shift 2
            ;;
        --diff)
            SHOW_DIFF="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

# Re-parse for show-section and diff (simpler approach)
for i in "${!BASH_ARGV[@]}"; do
    if [[ "${BASH_ARGV[$i]}" == "--show-section" ]]; then
        SHOW_SECTION="${BASH_ARGV[$((i-1))]}"
    fi
    if [[ "${BASH_ARGV[$i]}" == "--diff" ]]; then
        SHOW_DIFF="${BASH_ARGV[$((i-1))]}"
    fi
done

# Load config
load_config

MIRROR_FILE="$MIRROR_DIR/prompts/AGENTS.md"
EXPORTS_FILE="$ROOT_DIR/exports.yaml"

# Get bot sections from exports.yaml (under bot profile agents_sections)
get_config_bot_sections() {
    grep -E "^\s*-\s+bot:" "$EXPORTS_FILE" 2>/dev/null | sed 's/.*bot://' | sed 's/#.*//' | tr -d ' ' || true
}

# Get bot sections from mirror
get_mirror_bot_sections() {
    grep -oE '<!-- BOT-MANAGED: [^>]+ -->' "$MIRROR_FILE" 2>/dev/null | sed 's/<!-- BOT-MANAGED: //' | sed 's/ -->//' || true
}

# Get COMPONENT sections from mirror
get_mirror_component_sections() {
    grep -oE '<!-- COMPONENT: [^>]+ -->' "$MIRROR_FILE" 2>/dev/null | \
        sed 's/<!-- COMPONENT: //' | sed 's/ -->//' || true
}

# Get all sections from config (components + templates + bot:)
get_config_all_sections() {
    local sections_started=false
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*agents_sections: ]]; then
            sections_started=true
            continue
        fi
        if [[ "$sections_started" == true ]]; then
            if [[ "$line" =~ ^[[:space:]]*[a-z_]+: ]] && [[ ! "$line" =~ ^[[:space:]]*- ]]; then
                break
            fi
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+([a-z0-9_:-]+) ]]; then
                echo "${BASH_REMATCH[1]}" | sed 's/^bot://'
            fi
        fi
    done < "$EXPORTS_FILE"
}

# Get section content from mirror by name
get_mirror_section_content() {
    local name="$1"
    local in_section=false
    local content=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^\<!--\ BOT-MANAGED:\ ${name}\ --\>$ ]]; then
            in_section=true
            continue
        elif [[ "$in_section" == true ]]; then
            if [[ "$line" =~ ^\<!--\ /BOT-MANAGED:\ ${name}\ --\>$ ]]; then
                printf '%s' "$content"
                return 0
            fi
            content+="$line"$'\n'
        fi
    done < "$MIRROR_FILE"

    return 1
}

# Find position of a bot section in mirror (what section comes before it)
find_section_position() {
    local name="$1"
    local prev_section=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Track section markers
        if [[ "$line" =~ ^\<!--\ COMPONENT:\ ([^\ ]+)\ --\>$ ]]; then
            prev_section="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^\<!--\ SECTION:\ ([^\ ]+)\ --\>$ ]]; then
            prev_section="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^\<!--\ BOT-MANAGED:\ ([^\ ]+)\ --\>$ ]]; then
            local found_name="${BASH_REMATCH[1]}"
            if [[ "$found_name" == "$name" ]]; then
                echo "$prev_section"
                return 0
            fi
            prev_section="bot:$found_name"
        elif [[ "$line" =~ ^##\ (.+)$ ]] && [[ -z "$prev_section" ]]; then
            # Fallback: use heading as position hint
            prev_section="after-heading:${BASH_REMATCH[1]}"
        fi
    done < "$MIRROR_FILE"

    echo "unknown"
}

# Handle --show-section
if [[ -n "$SHOW_SECTION" ]]; then
    echo "=== Bot Section: $SHOW_SECTION ==="
    if content=$(get_mirror_section_content "$SHOW_SECTION"); then
        echo "$content"
    else
        echo "Section not found in mirror"
        exit 1
    fi
    exit 0
fi

# Handle --diff (compare component to mirror)
if [[ -n "$SHOW_DIFF" ]]; then
    component_file="$ROOT_DIR/components/$SHOW_DIFF/prompts/AGENTS.snippet.md"
    if [[ ! -f "$component_file" ]]; then
        echo "Component not found: $SHOW_DIFF"
        exit 1
    fi

    # Extract component content from mirror (between COMPONENT markers)
    temp_mirror=$(mktemp)
    in_component=false
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^\<!--\ COMPONENT:\ ${SHOW_DIFF}\ --\>$ ]]; then
            in_component=true
            continue
        elif [[ "$line" =~ ^\<!--\ /COMPONENT:\ ${SHOW_DIFF}\ --\>$ ]]; then
            break
        elif [[ "$in_component" == true ]]; then
            echo "$line" >> "$temp_mirror"
        fi
    done < "$MIRROR_FILE"

    echo "=== Diff: $SHOW_DIFF ==="
    echo "--- component (source)"
    echo "+++ mirror (bot's version)"
    diff -u "$component_file" "$temp_mirror" || true
    rm -f "$temp_mirror"
    exit 0
fi

# Main conflict detection
echo "Checking for conflicts..."
echo ""

CONFLICTS=0
NEW_BOT_SECTIONS=()
NEW_COMPONENT_SECTIONS=()
EDITED_COMPONENTS=()

# Check for missing mirror
if [[ ! -f "$MIRROR_FILE" ]]; then
    echo "No mirror file found. Run ./tools/mirror.sh first."
    exit 2
fi

# 1. Find new bot sections (in mirror but not in config)
CONFIG_BOT_SECTIONS=$(get_config_bot_sections)
MIRROR_BOT_SECTIONS=$(get_mirror_bot_sections)

for section in $MIRROR_BOT_SECTIONS; do
    if ! echo "$CONFIG_BOT_SECTIONS" | grep -q "^${section}$"; then
        NEW_BOT_SECTIONS+=("$section")
        CONFLICTS=$((CONFLICTS + 1))
    fi
done

# 1b. Find new COMPONENT sections (in mirror but not in config)
CONFIG_ALL_SECTIONS=$(get_config_all_sections)
MIRROR_COMPONENT_SECTIONS=$(get_mirror_component_sections)

for section in $MIRROR_COMPONENT_SECTIONS; do
    if ! echo "$CONFIG_ALL_SECTIONS" | grep -q "^${section}$"; then
        NEW_COMPONENT_SECTIONS+=("$section")
        CONFLICTS=$((CONFLICTS + 1))
    fi
done

# 2. Check if components were edited by bot
# Extract each component from mirror and compare to source
get_component_content_from_mirror() {
    local name="$1"
    local in_component=false
    local content=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^\<!--\ COMPONENT:\ ${name}\ --\>$ ]]; then
            in_component=true
            continue
        elif [[ "$in_component" == true ]]; then
            if [[ "$line" =~ ^\<!--\ /COMPONENT:\ ${name}\ --\>$ ]]; then
                printf '%s' "$content"
                return 0
            fi
            content+="$line"$'\n'
        fi
    done < "$MIRROR_FILE"

    return 1
}

# Get list of components from exports.yaml agents_sections
get_config_components() {
    # Extract entries that don't have "bot:" prefix and aren't template sections
    local sections_started=false
    while IFS= read -r line; do
        # Look for agents_sections under bot profile
        if [[ "$line" =~ ^[[:space:]]*agents_sections: ]]; then
            sections_started=true
            continue
        fi
        if [[ "$sections_started" == true ]]; then
            # Stop at next non-list item
            if [[ "$line" =~ ^[[:space:]]*[a-z_]+: ]] && [[ ! "$line" =~ ^[[:space:]]*- ]]; then
                break
            fi
            # Extract section name (skip bot: prefix and template sections)
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+([a-z0-9_-]+)[[:space:]]*(#.*)?$ ]]; then
                local name="${BASH_REMATCH[1]}"
                # Check if it's a component (has prompts/AGENTS.snippet.md)
                if [[ -f "$ROOT_DIR/components/$name/prompts/AGENTS.snippet.md" ]]; then
                    echo "$name"
                fi
            fi
        fi
    done < "$EXPORTS_FILE"
}

# Compare each component
for component in $(get_config_components); do
    component_file="$ROOT_DIR/components/$component/prompts/AGENTS.snippet.md"

    if [[ ! -f "$component_file" ]]; then
        continue
    fi

    # Get content from mirror
    mirror_content=$(get_component_content_from_mirror "$component" 2>/dev/null) || continue

    # Get source content
    source_content=$(cat "$component_file")

    # Compare using diff (handles whitespace normalization)
    if ! diff -q <(printf '%s\n' "$mirror_content") <(printf '%s\n' "$source_content") >/dev/null 2>&1; then
        EDITED_COMPONENTS+=("$component")
        CONFLICTS=$((CONFLICTS + 1))
    fi
done

# Report conflicts
if [[ $CONFLICTS -eq 0 ]]; then
    echo "✓ No conflicts detected"
    exit 0
fi

echo "⚠️  Conflicts detected: $CONFLICTS"
echo ""

# Report new bot sections
if [[ ${#NEW_BOT_SECTIONS[@]} -gt 0 ]]; then
    echo "NEW BOT SECTIONS (in mirror, not in config):"
    for section in "${NEW_BOT_SECTIONS[@]}"; do
        position=$(find_section_position "$section")
        echo ""
        echo "  Section: $section"
        echo "  Position: after '$position'"
        echo "  Preview:"
        if content=$(get_mirror_section_content "$section"); then
            echo "$content" | head -5 | sed 's/^/    /'
            lines=$(echo "$content" | wc -l)
            if [[ $lines -gt 5 ]]; then
                echo "    ... ($((lines - 5)) more lines)"
            fi
        fi
        echo ""
        echo "  To keep: Add 'bot:$section' to exports.yaml agents_sections after '$position'"
        echo "  To discard: Section will be removed on next push"
    done
fi

# Report new component sections (bot added COMPONENT markers not in config)
if [[ ${#NEW_COMPONENT_SECTIONS[@]} -gt 0 ]]; then
    echo ""
    echo "NEW COMPONENT SECTIONS (bot added, not in config):"
    for section in "${NEW_COMPONENT_SECTIONS[@]}"; do
        position=$(find_section_position "$section")
        echo ""
        echo "  Component: $section"
        echo "  Position: after '$position'"
        echo ""
        echo "  To keep as component: Create components/$section/prompts/AGENTS.snippet.md"
        echo "                        Add '$section' to exports.yaml agents_sections"
        echo "  To keep as bot-managed: Add 'bot:$section' to exports.yaml agents_sections"
        echo "  To discard: Section will be removed on next push"
    done
fi

# Report edited components
if [[ ${#EDITED_COMPONENTS[@]} -gt 0 ]]; then
    echo ""
    echo "EDITED COMPONENTS (bot modified source component content):"
    for component in "${EDITED_COMPONENTS[@]}"; do
        echo ""
        echo "  Component: $component"
        echo "  Source: components/$component/prompts/AGENTS.snippet.md"
        echo ""
        echo "  Options:"
        echo "    1. Keep bot's version: copy changes to source component"
        echo "    2. Discard bot's changes: next push will overwrite"
        echo "    3. Convert to bot-managed: rename to BOT-MANAGED section"
        echo ""
        echo "  Run: ./tools/detect-conflicts.sh --diff $component"
    done
fi

echo ""
echo "Run with --show-section NAME to see full content"
echo "Run with --diff NAME to compare component to mirror"

exit 1
