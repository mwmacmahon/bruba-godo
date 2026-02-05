#!/bin/bash
# Detect conflicts between mirror and config/components for all prompt files
#
# Usage:
#   ./tools/detect-conflicts.sh                         # Check all agents
#   ./tools/detect-conflicts.sh --agent=bruba-main      # Check specific agent
#   ./tools/detect-conflicts.sh --verbose               # Show details
#   ./tools/detect-conflicts.sh --show-section NAME [FILE]  # Show a bot section
#   ./tools/detect-conflicts.sh --diff NAME [FILE]      # Show diff for a component
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
SHOW_FILE=""
AGENT_FILTER=""

if ! parse_common_args "$@"; then
    echo "Usage: $0 [--verbose] [--agent=NAME] [--show-section NAME [FILE]] [--diff NAME [FILE]]"
    echo ""
    echo "Detect conflicts between mirror and config/components for all prompt files."
    echo ""
    echo "Options:"
    echo "  --verbose, -v            Show detailed output"
    echo "  --agent=NAME             Check specific agent only"
    echo "  --show-section NAME      Show content of a bot section (default: AGENTS.md)"
    echo "  --diff NAME              Show diff for a component (default: AGENTS.md)"
    echo ""
    echo "FILE can be: agents, tools, memory, identity, soul, user, bootstrap, heartbeat"
    exit 0
fi

# Handle --agent, --show-section and --diff from command line
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
    case "${args[$i]}" in
        --agent=*)
            AGENT_FILTER="${args[$i]#*=}"
            ;;
        --show-section)
            SHOW_SECTION="${args[$((i+1))]:-}"
            SHOW_FILE="${args[$((i+2))]:-agents}"
            ;;
        --diff)
            SHOW_DIFF="${args[$((i+1))]:-}"
            SHOW_FILE="${args[$((i+2))]:-agents}"
            ;;
    esac
done

# Load config
load_config

EXPORTS_FILE="$ROOT_DIR/config.yaml"

# List of prompt files to check
PROMPT_FILES=(agents tools heartbeat)

# Apply variable substitutions to content (must match assemble-prompts.sh)
# Usage: apply_substitutions "$content" "$workspace"
apply_substitutions() {
    local content="$1"
    local workspace="$2"
    local result
    result=$(echo "$content" | sed \
        -e "s|\${WORKSPACE}|$workspace|g" \
        -e "s|\${AGENT_NAME}|$AGENT_NAME|g" \
        -e "s|\${SHARED_TOOLS}|$SHARED_TOOLS|g" \
        -e "s|\${HUMAN_NAME}|$AGENT_HUMAN_NAME|g" \
        -e "s|\${SIGNAL_UUID}|$AGENT_SIGNAL_UUID|g" \
        -e "s|\${PEER_AGENT}|$AGENT_PEER_AGENT|g" \
        -e "s|\${PEER_HUMAN_NAME}|$AGENT_PEER_HUMAN_NAME|g")
    # Apply custom per-agent variables
    if [[ -n "$AGENT_CUSTOM_VARIABLES" && "$AGENT_CUSTOM_VARIABLES" != "{}" ]]; then
        result=$(echo "$result" | VARS="$AGENT_CUSTOM_VARIABLES" python3 -c "
import json, os, sys
variables = json.loads(os.environ['VARS'])
content = sys.stdin.read()
for k, v in variables.items():
    content = content.replace('\${' + k + '}', str(v))
sys.stdout.write(content)
")
    fi
    echo "$result"
}

# Get config sections for a specific prompt file and agent
get_config_sections() {
    local prompt_name="$1"
    local agent="$2"
    local config_key="${prompt_name}_sections"

    # Use Python to reliably parse nested YAML
    python3 -c "
import yaml
import sys
try:
    with open('$EXPORTS_FILE') as f:
        config = yaml.safe_load(f)

    # Get sections from agents.{agent}.{prompt_name}_sections
    agent_config = config.get('agents', {}).get('$agent', {})
    sections = agent_config.get('${config_key}', [])
    for s in sections:
        print(s)
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null
}

# Get bot sections from config (entries with bot: prefix)
get_config_bot_sections() {
    local prompt_name="$1"
    local agent="$2"
    get_config_sections "$prompt_name" "$agent" | grep "^bot:" | sed 's/^bot://' || true
}

# Get bot sections from a mirror file
get_mirror_bot_sections() {
    local mirror_file="$1"
    [[ ! -f "$mirror_file" ]] && return
    grep -oE '<!-- BOT-MANAGED: [^>]+ -->' "$mirror_file" 2>/dev/null | \
        sed 's/<!-- BOT-MANAGED: //' | sed 's/ -->//' || true
}

# Get COMPONENT sections from a mirror file
get_mirror_component_sections() {
    local mirror_file="$1"
    [[ ! -f "$mirror_file" ]] && return
    grep -oE '<!-- COMPONENT: [^>]+ -->' "$mirror_file" 2>/dev/null | \
        sed 's/<!-- COMPONENT: //' | sed 's/ -->//' || true
}

# Get section content from mirror by name
get_mirror_section_content() {
    local name="$1"
    local mirror_file="$2"
    local in_section=false
    local content=""

    [[ ! -f "$mirror_file" ]] && return 1

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
    done < "$mirror_file"

    return 1
}

# Find position of a section in mirror (what section comes before it)
find_section_position() {
    local name="$1"
    local mirror_file="$2"
    local prev_section=""

    [[ ! -f "$mirror_file" ]] && echo "unknown" && return

    while IFS= read -r line || [[ -n "$line" ]]; do
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
            prev_section="after-heading:${BASH_REMATCH[1]}"
        fi
    done < "$mirror_file"

    echo "unknown"
}

# Get component content from mirror
get_component_content_from_mirror() {
    local name="$1"
    local mirror_file="$2"
    local in_component=false
    local content=""

    [[ ! -f "$mirror_file" ]] && return 1

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
    done < "$mirror_file"

    return 1
}

# Handle --show-section (uses default agent or filter)
if [[ -n "$SHOW_SECTION" ]]; then
    AGENT="${AGENT_FILTER:-bruba-main}"
    load_agent_config "$AGENT"
    SHOW_FILE="${SHOW_FILE:-agents}"
    prompt_upper=$(echo "$SHOW_FILE" | tr '[:lower:]' '[:upper:]')
    mirror_file="$AGENT_MIRROR_DIR/prompts/${prompt_upper}.md"

    echo "=== Bot Section: $SHOW_SECTION (${prompt_upper}.md, $AGENT) ==="
    if content=$(get_mirror_section_content "$SHOW_SECTION" "$mirror_file"); then
        echo "$content"
    else
        echo "Section not found in mirror"
        exit 1
    fi
    exit 0
fi

# Handle --diff
if [[ -n "$SHOW_DIFF" ]]; then
    AGENT="${AGENT_FILTER:-bruba-main}"
    load_agent_config "$AGENT"
    SHOW_FILE="${SHOW_FILE:-agents}"
    prompt_upper=$(echo "$SHOW_FILE" | tr '[:lower:]' '[:upper:]')
    mirror_file="$AGENT_MIRROR_DIR/prompts/${prompt_upper}.md"

    # Parse component:variant syntax
    component="${SHOW_DIFF%%:*}"
    variant=""
    [[ "$SHOW_DIFF" == *:* ]] && variant="${SHOW_DIFF#*:}"

    # Resolve to exactly one file (no fallback)
    if [[ -n "$variant" ]]; then
        component_file="$ROOT_DIR/components/$component/prompts/${prompt_upper}.${variant}.snippet.md"
    else
        component_file="$ROOT_DIR/components/$component/prompts/${prompt_upper}.snippet.md"
    fi

    if [[ ! -f "$component_file" ]]; then
        echo "Component not found: $SHOW_DIFF ($(basename "$component_file"))"
        exit 1
    fi

    # Extract component content from mirror
    temp_mirror=$(mktemp)
    if get_component_content_from_mirror "$SHOW_DIFF" "$mirror_file" > "$temp_mirror"; then
        echo "=== Diff: $SHOW_DIFF (${prompt_upper}.md, $AGENT) ==="
        echo "--- component (source)"
        echo "+++ mirror (bot's version)"
        diff -u "$component_file" "$temp_mirror" || true
    else
        echo "Component $SHOW_DIFF not found in mirror ${prompt_upper}.md"
    fi
    rm -f "$temp_mirror"
    exit 0
fi

# Build list of agents to check
if [[ -n "$AGENT_FILTER" ]]; then
    AGENTS=("$AGENT_FILTER")
else
    # Read agents into array (bash 3.x compatible)
    AGENTS=()
    while IFS= read -r agent; do
        [[ -n "$agent" ]] && AGENTS+=("$agent")
    done < <(get_agents)
fi

# Main conflict detection
echo "Checking for conflicts..."
echo ""

TOTAL_CONFLICTS=0

# Process each agent
for agent in "${AGENTS[@]}"; do
    load_agent_config "$agent"

    # Skip agents with no workspace
    if [[ -z "$AGENT_WORKSPACE" || "$AGENT_WORKSPACE" == "null" ]]; then
        continue
    fi

    AGENT_CONFLICTS=0

    # Check each prompt file
    for prompt_name in "${PROMPT_FILES[@]}"; do
        prompt_upper=$(echo "$prompt_name" | tr '[:lower:]' '[:upper:]')
        mirror_file="$AGENT_MIRROR_DIR/prompts/${prompt_upper}.md"

        # Skip if no mirror file exists
        if [[ ! -f "$mirror_file" ]]; then
            continue
        fi

        # Skip if no sections configured for this file
        sections=$(get_config_sections "$prompt_name" "$agent")
        if [[ -z "$sections" ]]; then
            continue
        fi

        FILE_CONFLICTS=0
        NEW_BOT_SECTIONS=()
        NEW_COMPONENT_SECTIONS=()
        EDITED_COMPONENTS=()

        # 1. Find new bot sections (in mirror but not in config)
        CONFIG_BOT_SECTIONS=$(get_config_bot_sections "$prompt_name" "$agent")
        MIRROR_BOT_SECTIONS=$(get_mirror_bot_sections "$mirror_file")

        for section in $MIRROR_BOT_SECTIONS; do
            if ! echo "$CONFIG_BOT_SECTIONS" | grep -q "^${section}$"; then
                NEW_BOT_SECTIONS+=("$section")
                FILE_CONFLICTS=$((FILE_CONFLICTS + 1))
            fi
        done

        # 2. Find new COMPONENT sections (in mirror but not in config)
        CONFIG_ALL_SECTIONS=$(get_config_sections "$prompt_name" "$agent" | sed 's/^bot://')
        MIRROR_COMPONENT_SECTIONS=$(get_mirror_component_sections "$mirror_file")

        for section in $MIRROR_COMPONENT_SECTIONS; do
            if ! echo "$CONFIG_ALL_SECTIONS" | grep -q "^${section}$"; then
                NEW_COMPONENT_SECTIONS+=("$section")
                FILE_CONFLICTS=$((FILE_CONFLICTS + 1))
            fi
        done

        # 3. Check if components were edited by bot (only for agents using components)
        if [[ "$agent" == "bruba-main" ]]; then
            for entry in $(get_config_sections "$prompt_name" "$agent" | grep -v "^bot:" | grep -v "^base$" | grep -v "^manager-base$"); do
                # Parse component:variant syntax
                component="${entry%%:*}"
                variant=""
                [[ "$entry" == *:* ]] && variant="${entry#*:}"

                # Resolve to exactly one file (no fallback)
                if [[ -n "$variant" ]]; then
                    component_file="$ROOT_DIR/components/$component/prompts/${prompt_upper}.${variant}.snippet.md"
                else
                    component_file="$ROOT_DIR/components/$component/prompts/${prompt_upper}.snippet.md"
                fi

                if [[ ! -f "$component_file" ]]; then
                    continue
                fi

                # Get content from mirror (using full entry for marker matching)
                mirror_content=$(get_component_content_from_mirror "$entry" "$mirror_file" 2>/dev/null) || continue

                # Get source content with substitutions applied (to match what was pushed)
                source_content=$(apply_substitutions "$(cat "$component_file")" "$AGENT_WORKSPACE")

                # Compare
                if ! diff -q <(printf '%s\n' "$mirror_content") <(printf '%s\n' "$source_content") >/dev/null 2>&1; then
                    EDITED_COMPONENTS+=("$entry")
                    FILE_CONFLICTS=$((FILE_CONFLICTS + 1))
                fi
            done
        fi

        # Report conflicts for this file
        if [[ $FILE_CONFLICTS -gt 0 ]]; then
            echo "=== $agent: ${prompt_upper}.md: $FILE_CONFLICTS conflicts ==="
            echo ""

            # Report new bot sections
            if [[ ${#NEW_BOT_SECTIONS[@]} -gt 0 ]]; then
                echo "NEW BOT SECTIONS:"
                for section in "${NEW_BOT_SECTIONS[@]}"; do
                    position=$(find_section_position "$section" "$mirror_file")
                    echo ""
                    echo "  Section: $section"
                    echo "  Position: after '$position'"
                    echo "  Preview:"
                    if content=$(get_mirror_section_content "$section" "$mirror_file"); then
                        echo "$content" | head -5 | sed 's/^/    /'
                        lines=$(echo "$content" | wc -l)
                        if [[ $lines -gt 5 ]]; then
                            echo "    ... ($((lines - 5)) more lines)"
                        fi
                    fi
                    echo ""
                    echo "  To keep: Add 'bot:$section' to ${prompt_name}_sections in config.yaml"
                    echo "  To discard: Section will be removed on next push"
                done
                echo ""
            fi

            # Report new component sections
            if [[ ${#NEW_COMPONENT_SECTIONS[@]} -gt 0 ]]; then
                echo "NEW COMPONENT SECTIONS:"
                for section in "${NEW_COMPONENT_SECTIONS[@]}"; do
                    position=$(find_section_position "$section" "$mirror_file")
                    echo ""
                    echo "  Component: $section"
                    echo "  Position: after '$position'"
                    echo ""
                    echo "  To keep as component: Create components/$section/prompts/${prompt_upper}.snippet.md"
                    echo "                        Add '$section' to ${prompt_name}_sections in config.yaml"
                    echo "  To keep as bot-managed: Add 'bot:$section' to ${prompt_name}_sections"
                    echo "  To discard: Section will be removed on next push"
                done
                echo ""
            fi

            # Report edited components
            if [[ ${#EDITED_COMPONENTS[@]} -gt 0 ]]; then
                echo "EDITED COMPONENTS:"
                for component in "${EDITED_COMPONENTS[@]}"; do
                    echo ""
                    echo "  Component: $component"
                    echo "  Source: components/$component/prompts/${prompt_upper}.snippet.md"
                    echo ""
                    echo "  Options:"
                    echo "    1. Keep bot's version: copy changes to source component"
                    echo "    2. Discard bot's changes: next push will overwrite"
                    echo "    3. Convert to bot-managed: rename to BOT-MANAGED section"
                    echo ""
                    echo "  Run: ./tools/detect-conflicts.sh --agent=$agent --diff $component $prompt_name"
                done
                echo ""
            fi

            AGENT_CONFLICTS=$((AGENT_CONFLICTS + FILE_CONFLICTS))
        fi
    done

    TOTAL_CONFLICTS=$((TOTAL_CONFLICTS + AGENT_CONFLICTS))
done

# Final summary
if [[ $TOTAL_CONFLICTS -eq 0 ]]; then
    echo "No conflicts detected"
    exit 0
fi

echo ""
echo "Total conflicts: $TOTAL_CONFLICTS"
echo ""
echo "Run with --show-section NAME [FILE] to see full content"
echo "Run with --diff NAME [FILE] to compare component to mirror"
echo "Use --agent=NAME to filter by agent"
echo ""
echo "REMEMBER: Always ask user before accepting or discarding bot changes."

exit 1
