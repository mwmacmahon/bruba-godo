#!/bin/bash
# Assemble prompts from config-driven section order
#
# Usage:
#   ./tools/assemble-prompts.sh                     # Assemble for all agents
#   ./tools/assemble-prompts.sh --agent=bruba-main  # Single agent
#   ./tools/assemble-prompts.sh --verbose           # Show detailed output
#   ./tools/assemble-prompts.sh --dry-run           # Show what would be assembled
#   ./tools/assemble-prompts.sh --force             # Skip conflict check
#
# Assembly reads *_sections from config.yaml and resolves each entry:
#   1. base         → full template file (templates/prompts/{NAME}.md)
#   2. manager-base → manager template (templates/prompts/manager/{NAME}.md)
#   3. bot:name     → bot-managed section from mirror (<!-- BOT-MANAGED: name -->)
#   4. name         → component snippet (components/{name}/prompts/{NAME}.snippet.md)
#   5. name         → template section (templates/prompts/sections/{name}.md)
#
# Logs: logs/assemble.log

set -e

# Load shared functions
source "$(dirname "$0")/lib.sh"

# Parse arguments
FORCE=false
AGENT_FILTER=""
for arg in "$@"; do
    case $arg in
        --force|-f)
            FORCE=true
            ;;
        --agent=*)
            AGENT_FILTER="${arg#*=}"
            ;;
    esac
done

if ! parse_common_args "$@"; then
    echo "Usage: $0 [--dry-run] [--verbose] [--force] [--agent=NAME]"
    echo ""
    echo "Assemble all prompt files from config-driven section order."
    echo ""
    echo "Options:"
    echo "  --dry-run, -n      Show what would be assembled without doing it"
    echo "  --verbose, -v      Show detailed output"
    echo "  --quiet, -q        Summary output only (default)"
    echo "  --force, -f        Skip conflict check (overwrites bot changes)"
    echo "  --agent=NAME       Assemble for specific agent only"
    exit 0
fi

# Load config
load_config

# Set up logging
LOG_FILE="$LOG_DIR/assemble.log"
mkdir -p "$LOG_DIR"
rotate_log "$LOG_FILE"

# List of prompt files to assemble (lowercase name -> uppercase filename)
# Only managing: AGENTS.md, TOOLS.md, HEARTBEAT.md
# Other files (USER, IDENTITY, SOUL, MEMORY, BOOTSTRAP) are managed directly on bot
PROMPT_FILES=(agents tools heartbeat)

# Global counters
TOTAL_FILES=0
TOTAL_SECTIONS=0
TOTAL_MISSING=0

# Parse sections list from config.yaml for a given prompt file and agent
# Usage: get_sections "agents" -> outputs section names one per line
get_sections() {
    local prompt_name="$1"
    local config_key="${prompt_name}_sections"
    local config_file="$ROOT_DIR/config.yaml"

    if [[ ! -f "$config_file" ]]; then
        echo "ERROR: config.yaml not found" >&2
        return 1
    fi

    # Use Python to reliably parse nested YAML
    python3 -c "
import yaml
import sys
try:
    with open('$config_file') as f:
        config = yaml.safe_load(f)

    agent_name = '$AGENT_NAME'
    sections_key = '${config_key}'

    # Get sections from agents.{agent_name}.{prompt_name}_sections
    agent_config = config.get('agents', {}).get(agent_name, {})
    sections = agent_config.get(sections_key, [])
    for s in sections:
        print(s)
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null
}

# Extract a specific BOT-MANAGED section from mirror
# Usage: get_bot_section "name" "mirror_file"
get_bot_section() {
    local name="$1"
    local mirror_file="$2"

    [[ ! -f "$mirror_file" ]] && return 1

    local in_section=false
    local content=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^\<!--\ BOT-MANAGED:\ ${name}\ --\>$ ]]; then
            in_section=true
            content="$line"$'\n'
        elif [[ "$in_section" == true ]]; then
            content+="$line"$'\n'
            if [[ "$line" =~ ^\<!--\ /BOT-MANAGED:\ ${name}\ --\>$ ]]; then
                printf '%s' "$content"
                return 0
            fi
        fi
    done < "$mirror_file"

    return 1
}

# Resolve a section entry to its content for a specific prompt file
# Usage: resolve_section "entry" "prompt_name" >> output_file
# prompt_name: lowercase (e.g., "agents", "tools")
resolve_section() {
    local entry="$1"
    local prompt_name="$2"
    local prompt_upper
    prompt_upper=$(echo "$prompt_name" | tr '[:lower:]' '[:upper:]')
    local mirror_file="$AGENT_MIRROR_DIR/prompts/${prompt_upper}.md"

    # Handle 'base' - include full template
    if [[ "$entry" == "base" ]]; then
        local template_file="$ROOT_DIR/templates/prompts/${prompt_upper}.md"
        if [[ -f "$template_file" ]]; then
            cat "$template_file"
            return 0
        else
            return 1
        fi
    fi

    # Handle 'manager-base' - include manager-specific template
    if [[ "$entry" == "manager-base" ]]; then
        local template_file="$ROOT_DIR/templates/prompts/manager/${prompt_upper}.md"
        if [[ -f "$template_file" ]]; then
            cat "$template_file"
            return 0
        else
            return 1
        fi
    fi

    # Check if bot-managed (bot:name)
    if [[ "$entry" =~ ^bot:(.+)$ ]]; then
        local bot_name="${BASH_REMATCH[1]}"
        local content
        if content=$(get_bot_section "$bot_name" "$mirror_file"); then
            printf '%s' "$content"
            return 0
        else
            return 1  # Bot section not found in mirror
        fi
    fi

    # Check if component exists for this prompt file
    local component_file="$ROOT_DIR/components/$entry/prompts/${prompt_upper}.snippet.md"
    if [[ -f "$component_file" ]]; then
        echo "<!-- COMPONENT: $entry -->"
        cat "$component_file"
        echo "<!-- /COMPONENT: $entry -->"
        return 0
    fi

    # Check if template section exists (only for AGENTS.md for now)
    if [[ "$prompt_name" == "agents" ]]; then
        local section_file="$ROOT_DIR/templates/prompts/sections/$entry.md"
        if [[ -f "$section_file" ]]; then
            echo "<!-- SECTION: $entry -->"
            cat "$section_file"
            echo "<!-- /SECTION: $entry -->"
            return 0
        fi
    fi

    return 1  # Not found
}

# Get section type for logging
# Usage: get_section_type "entry" "prompt_name"
get_section_type() {
    local entry="$1"
    local prompt_name="$2"
    local prompt_upper
    prompt_upper=$(echo "$prompt_name" | tr '[:lower:]' '[:upper:]')

    if [[ "$entry" == "base" ]]; then
        if [[ -f "$ROOT_DIR/templates/prompts/${prompt_upper}.md" ]]; then
            echo "base"
        else
            echo "missing"
        fi
    elif [[ "$entry" == "manager-base" ]]; then
        if [[ -f "$ROOT_DIR/templates/prompts/manager/${prompt_upper}.md" ]]; then
            echo "manager-base"
        else
            echo "missing"
        fi
    elif [[ "$entry" =~ ^bot: ]]; then
        echo "bot"
    elif [[ -f "$ROOT_DIR/components/$entry/prompts/${prompt_upper}.snippet.md" ]]; then
        echo "component"
    elif [[ "$prompt_name" == "agents" && -f "$ROOT_DIR/templates/prompts/sections/$entry.md" ]]; then
        echo "section"
    else
        echo "missing"
    fi
}

# Check for conflicts for a specific agent (unless --force or --dry-run)
check_conflicts() {
    local agent="$1"
    if [[ "$FORCE" != "true" && "$DRY_RUN" != "true" ]]; then
        local mirror_prompts="$MIRROR_DIR/$agent/prompts"
        if [[ -d "$mirror_prompts" ]]; then
            SCRIPT_DIR="$(dirname "$0")"
            if ! "$SCRIPT_DIR/detect-conflicts.sh" --agent="$agent" --quiet >/dev/null 2>&1; then
                echo ""
                echo "CONFLICTS DETECTED for $agent - Assembly blocked"
                echo ""
                echo "Bot has made changes that would be overwritten."
                echo "Run './tools/detect-conflicts.sh --agent=$agent' to see details."
                echo ""
                echo "Options:"
                echo "  1. Resolve conflicts (see /prompt-sync skill)"
                echo "  2. Use --force to overwrite bot changes"
                echo ""
                return 1
            fi
        fi
    fi
    return 0
}

# Assemble a single prompt file for current agent
# Usage: assemble_prompt_file "agents"
assemble_prompt_file() {
    local prompt_name="$1"
    local prompt_upper
    prompt_upper=$(echo "$prompt_name" | tr '[:lower:]' '[:upper:]')
    local output_file="$AGENT_EXPORT_DIR/core-prompts/${prompt_upper}.md"

    # Get sections for this prompt file
    local sections=()
    while IFS= read -r section; do
        [[ -n "$section" ]] && sections+=("$section")
    done < <(get_sections "$prompt_name")

    if [[ ${#sections[@]} -eq 0 ]]; then
        log "  Skipped: ${prompt_upper}.md (no ${prompt_name}_sections in config)"
        return 0
    fi

    log ""
    log "Assembling: ${prompt_upper}.md"

    # Counters for this file
    local base_added=0
    local components_added=0
    local template_sections_added=0
    local bot_sections_added=0
    local sections_missing=0

    # Clear output file
    if [[ "$DRY_RUN" != "true" ]]; then
        > "$output_file"
    fi

    # Process each section
    for entry in "${sections[@]}"; do
        local section_type
        section_type=$(get_section_type "$entry" "$prompt_name")

        case "$section_type" in
            base)
                if [[ "$DRY_RUN" == "true" ]]; then
                    log "  Would add base template"
                else
                    resolve_section "$entry" "$prompt_name" >> "$output_file"
                    echo "" >> "$output_file"
                    log "  + Base: templates/prompts/${prompt_upper}.md"
                    base_added=1
                fi
                ;;
            manager-base)
                if [[ "$DRY_RUN" == "true" ]]; then
                    log "  Would add manager-base template"
                else
                    resolve_section "$entry" "$prompt_name" >> "$output_file"
                    echo "" >> "$output_file"
                    log "  + Manager-Base: templates/prompts/manager/${prompt_upper}.md"
                    base_added=1
                fi
                ;;
            bot)
                local bot_name="${entry#bot:}"
                if [[ "$DRY_RUN" == "true" ]]; then
                    log "  Would add bot section: $bot_name"
                else
                    if content=$(resolve_section "$entry" "$prompt_name"); then
                        printf '%s\n' "$content" >> "$output_file"
                        log "  + Bot: $bot_name"
                        bot_sections_added=$((bot_sections_added + 1))
                    else
                        log "  ! Missing bot section: $bot_name (not in mirror)"
                        sections_missing=$((sections_missing + 1))
                    fi
                fi
                ;;
            component)
                if [[ "$DRY_RUN" == "true" ]]; then
                    log "  Would add component: $entry"
                else
                    resolve_section "$entry" "$prompt_name" >> "$output_file"
                    echo "" >> "$output_file"
                    log "  + Component: $entry"
                    components_added=$((components_added + 1))
                fi
                ;;
            section)
                if [[ "$DRY_RUN" == "true" ]]; then
                    log "  Would add section: $entry"
                else
                    resolve_section "$entry" "$prompt_name" >> "$output_file"
                    echo "" >> "$output_file"
                    log "  + Section: $entry"
                    template_sections_added=$((template_sections_added + 1))
                fi
                ;;
            missing)
                log "  ! Missing: $entry (not found as component or section for ${prompt_upper})"
                sections_missing=$((sections_missing + 1))
                ;;
        esac
    done

    # Calculate total for this file
    local file_total=$((base_added + components_added + template_sections_added + bot_sections_added))

    if [[ "$DRY_RUN" != "true" && $file_total -gt 0 ]]; then
        TOTAL_FILES=$((TOTAL_FILES + 1))
        TOTAL_SECTIONS=$((TOTAL_SECTIONS + file_total))

        # Build summary parts
        local parts=()
        [[ $base_added -gt 0 ]] && parts+=("base")
        [[ $components_added -gt 0 ]] && parts+=("$components_added components")
        [[ $template_sections_added -gt 0 ]] && parts+=("$template_sections_added sections")
        [[ $bot_sections_added -gt 0 ]] && parts+=("$bot_sections_added bot")

        local summary
        summary=$(IFS=', '; echo "${parts[*]}")
        echo "  ${prompt_upper}.md ($summary)"
    fi

    if [[ $sections_missing -gt 0 ]]; then
        TOTAL_MISSING=$((TOTAL_MISSING + sections_missing))
    fi
}

# Build list of agents to process
if [[ -n "$AGENT_FILTER" ]]; then
    AGENTS=("$AGENT_FILTER")
else
    # Read agents into array (bash 3.x compatible)
    AGENTS=()
    while IFS= read -r agent; do
        [[ -n "$agent" ]] && AGENTS+=("$agent")
    done < <(get_agents)
fi

log "=== Assembling Prompts ==="
echo "Assembling prompts..."

# Process each agent
for agent in "${AGENTS[@]}"; do
    load_agent_config "$agent"

    # Skip agents with no prompts configured
    if [[ "$AGENT_PROMPTS" == "[]" || -z "$AGENT_PROMPTS" ]]; then
        log "Skipping $agent (no prompts configured)"
        continue
    fi

    # Skip agents with null workspace (like helpers)
    if [[ -z "$AGENT_WORKSPACE" || "$AGENT_WORKSPACE" == "null" ]]; then
        log "Skipping $agent (no workspace)"
        continue
    fi

    # Check for conflicts
    if ! check_conflicts "$agent"; then
        exit 1
    fi

    log ""
    log "=== Agent: $agent ==="
    echo ""
    echo "Agent: $agent"

    # Create output directory
    if [[ "$DRY_RUN" != "true" ]]; then
        mkdir -p "$AGENT_EXPORT_DIR/core-prompts"
    fi

    # Assemble each prompt file
    for prompt_name in "${PROMPT_FILES[@]}"; do
        assemble_prompt_file "$prompt_name"
    done
done

# Summary
log ""
log "=== Summary ==="
if [[ "$DRY_RUN" == "true" ]]; then
    log "Dry run complete"
else
    log "Assembled: $TOTAL_FILES files, $TOTAL_SECTIONS total sections"
fi

echo ""
echo "Assembled: $TOTAL_FILES prompt files"

if [[ $TOTAL_MISSING -gt 0 ]]; then
    echo "WARNING: $TOTAL_MISSING sections missing"
    exit 1
fi
