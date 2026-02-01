#!/bin/bash
# Assemble prompts from config-driven section order
#
# Usage:
#   ./tools/assemble-prompts.sh              # Assemble all prompt files
#   ./tools/assemble-prompts.sh --verbose    # Show detailed output
#   ./tools/assemble-prompts.sh --dry-run    # Show what would be assembled
#   ./tools/assemble-prompts.sh --force      # Skip conflict check
#
# Assembly reads *_sections from config.yaml (bot profile) and resolves each entry:
#   1. base      → full template file (templates/prompts/{NAME}.md)
#   2. bot:name  → bot-managed section from mirror (<!-- BOT-MANAGED: name -->)
#   3. name      → component snippet (components/{name}/prompts/{NAME}.snippet.md)
#   4. name      → template section (templates/prompts/sections/{name}.md)
#
# Logs: logs/assemble.log

set -e

# Load shared functions
source "$(dirname "$0")/lib.sh"

# Parse arguments
FORCE=false
for arg in "$@"; do
    case $arg in
        --force|-f)
            FORCE=true
            ;;
    esac
done

if ! parse_common_args "$@"; then
    echo "Usage: $0 [--dry-run] [--verbose] [--force]"
    echo ""
    echo "Assemble all prompt files from config-driven section order."
    echo ""
    echo "Options:"
    echo "  --dry-run, -n   Show what would be assembled without doing it"
    echo "  --verbose, -v   Show detailed output"
    echo "  --quiet, -q     Summary output only (default)"
    echo "  --force, -f     Skip conflict check (overwrites bot changes)"
    exit 0
fi

# Load config
load_config

# Set up logging
LOG_FILE="$LOG_DIR/assemble.log"
mkdir -p "$LOG_DIR"
rotate_log "$LOG_FILE"

# Check for conflicts (unless --force or --dry-run)
if [[ "$FORCE" != "true" && "$DRY_RUN" != "true" ]]; then
    SCRIPT_DIR="$(dirname "$0")"
    if [[ -d "$MIRROR_DIR/prompts" ]]; then
        if ! "$SCRIPT_DIR/detect-conflicts.sh" --quiet >/dev/null 2>&1; then
            echo ""
            echo "CONFLICTS DETECTED - Assembly blocked"
            echo ""
            echo "Bot has made changes that would be overwritten."
            echo "Run './tools/detect-conflicts.sh' to see details."
            echo ""
            echo "Options:"
            echo "  1. Resolve conflicts (see /prompt-sync skill)"
            echo "  2. Use --force to overwrite bot changes"
            echo ""
            exit 1
        fi
    fi
fi

log "=== Assembling Prompts ==="

# Create output directory
# Output goes to exports/bot/core-prompts/ which syncs to ~/clawd/ (not memory/)
PROMPTS_OUTPUT="$EXPORTS_DIR/bot/core-prompts"
if [[ "$DRY_RUN" != "true" ]]; then
    mkdir -p "$PROMPTS_OUTPUT"
fi

# List of prompt files to assemble (lowercase name -> uppercase filename)
# Only managing: AGENTS.md, TOOLS.md, HEARTBEAT.md
# Other files (USER, IDENTITY, SOUL, MEMORY, BOOTSTRAP) are bot-managed directly
PROMPT_FILES=(agents tools heartbeat)

# Global counters
TOTAL_FILES=0
TOTAL_SECTIONS=0
TOTAL_MISSING=0

# Parse sections list from config.yaml for a given prompt file
# Usage: get_sections "agents" -> outputs section names one per line
get_sections() {
    local prompt_name="$1"
    local config_key="${prompt_name}_sections"
    local exports_file="$ROOT_DIR/config.yaml"
    local helper="$ROOT_DIR/tools/helpers/parse-yaml.py"

    if [[ ! -f "$exports_file" ]]; then
        echo "ERROR: config.yaml not found" >&2
        return 1
    fi

    # Use Python helper to get JSON array from exports.bot.{prompt_name}_sections
    if [[ -f "$helper" ]]; then
        local json
        json=$("$helper" "$exports_file" "exports.bot.${config_key}" 2>/dev/null) || true
        if [[ -n "$json" && "$json" != "null" && "$json" != "[]" ]]; then
            echo "$json" | tr -d '[]"' | tr ',' '\n' | sed 's/^ *//' | grep -v '^$'
            return
        fi
    fi

    # Fallback: grep-based parsing
    local in_bot=false
    local in_sections=false
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*bot: ]]; then
            in_bot=true
            continue
        fi
        if [[ "$in_bot" == true ]]; then
            # Exit bot section if we hit another top-level profile
            if [[ "$line" =~ ^[[:space:]]{2}[a-z]+: && ! "$line" =~ ^[[:space:]]{4} ]]; then
                if [[ ! "$line" =~ ${config_key} ]]; then
                    in_sections=false
                fi
            fi
            if [[ "$line" =~ ${config_key}: ]]; then
                in_sections=true
                continue
            fi
            if [[ "$in_sections" == true ]]; then
                # Exit if we hit a non-list line at same or lower indent
                if [[ "$line" =~ ^[[:space:]]{4}[a-z] && ! "$line" =~ ^[[:space:]]*- ]]; then
                    break
                fi
                if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+([a-zA-Z0-9_:-]+) ]]; then
                    echo "${BASH_REMATCH[1]}"
                fi
            fi
        fi
    done < "$exports_file"
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
    local mirror_file="$MIRROR_DIR/prompts/${prompt_upper}.md"

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

# Assemble a single prompt file
# Usage: assemble_prompt_file "agents"
assemble_prompt_file() {
    local prompt_name="$1"
    local prompt_upper
    prompt_upper=$(echo "$prompt_name" | tr '[:lower:]' '[:upper:]')
    local output_file="$PROMPTS_OUTPUT/${prompt_upper}.md"

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

# Assemble all prompt files
echo "Assembling prompts..."
for prompt_name in "${PROMPT_FILES[@]}"; do
    assemble_prompt_file "$prompt_name"
done

# Summary
log ""
log "=== Summary ==="
if [[ "$DRY_RUN" == "true" ]]; then
    log "Dry run complete"
else
    log "Assembled: $TOTAL_FILES files, $TOTAL_SECTIONS total sections"
    log "Output: $PROMPTS_OUTPUT/"
fi

echo ""
echo "Assembled: $TOTAL_FILES prompt files"

if [[ $TOTAL_MISSING -gt 0 ]]; then
    echo "WARNING: $TOTAL_MISSING sections missing"
    exit 1
fi
