#!/bin/bash
# Assemble prompts from config-driven section order
#
# Usage:
#   ./tools/assemble-prompts.sh              # Assemble AGENTS.md
#   ./tools/assemble-prompts.sh --verbose    # Show detailed output
#   ./tools/assemble-prompts.sh --dry-run    # Show what would be assembled
#   ./tools/assemble-prompts.sh --force      # Skip conflict check
#
# Assembly reads agents_sections from exports.yaml (bot profile) and resolves each entry:
#   1. bot:name  → bot-managed section from mirror (<!-- BOT-MANAGED: name -->)
#   2. name      → component snippet (components/{name}/prompts/AGENTS.snippet.md)
#   3. name      → template section (templates/prompts/sections/{name}.md)
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
    echo "Assemble AGENTS.md from config-driven section order."
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
    if [[ -f "$MIRROR_DIR/prompts/AGENTS.md" ]]; then
        if ! "$SCRIPT_DIR/detect-conflicts.sh" --quiet >/dev/null 2>&1; then
            echo ""
            echo "⚠️  CONFLICTS DETECTED - Assembly blocked"
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

# Counters
SECTIONS_ADDED=0
COMPONENTS_ADDED=0
TEMPLATE_SECTIONS_ADDED=0
BOT_SECTIONS_ADDED=0
SECTIONS_SKIPPED=0
SECTIONS_MISSING=0

# Parse agents_sections from exports.yaml (under bot profile)
get_agents_sections() {
    local exports_file="$ROOT_DIR/exports.yaml"
    local helper="$ROOT_DIR/tools/helpers/parse-yaml.py"

    if [[ ! -f "$exports_file" ]]; then
        echo "ERROR: exports.yaml not found" >&2
        return 1
    fi

    # Use Python helper to get JSON array from exports.bot.agents_sections
    if [[ -f "$helper" ]]; then
        local json
        json=$("$helper" "$exports_file" exports.bot.agents_sections 2>/dev/null) || true
        if [[ -n "$json" && "$json" != "null" && "$json" != "[]" ]]; then
            echo "$json" | tr -d '[]"' | tr ',' '\n' | sed 's/^ *//' | grep -v '^$'
            return
        fi
    fi

    # Fallback: grep-based parsing (look for agents_sections under bot profile)
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
                if [[ ! "$line" =~ agents_sections ]]; then
                    break
                fi
            fi
            if [[ "$line" =~ agents_sections: ]]; then
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

# Resolve a section entry to its content
# Usage: resolve_section "entry" >> output_file
resolve_section() {
    local entry="$1"
    local mirror_file="$MIRROR_DIR/prompts/AGENTS.md"

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

    # Check if component exists
    local component_file="$ROOT_DIR/components/$entry/prompts/AGENTS.snippet.md"
    if [[ -f "$component_file" ]]; then
        echo "<!-- COMPONENT: $entry -->"
        cat "$component_file"
        echo "<!-- /COMPONENT: $entry -->"
        return 0
    fi

    # Check if template section exists
    local section_file="$ROOT_DIR/templates/prompts/sections/$entry.md"
    if [[ -f "$section_file" ]]; then
        echo "<!-- SECTION: $entry -->"
        cat "$section_file"
        echo "<!-- /SECTION: $entry -->"
        return 0
    fi

    return 1  # Not found
}

# Get section type for logging
get_section_type() {
    local entry="$1"

    if [[ "$entry" =~ ^bot: ]]; then
        echo "bot"
    elif [[ -f "$ROOT_DIR/components/$entry/prompts/AGENTS.snippet.md" ]]; then
        echo "component"
    elif [[ -f "$ROOT_DIR/templates/prompts/sections/$entry.md" ]]; then
        echo "section"
    else
        echo "missing"
    fi
}

# Main assembly
log ""
log "Assembling: AGENTS.md"

output_file="$PROMPTS_OUTPUT/AGENTS.md"

# Build list of sections
SECTIONS=()
while IFS= read -r section; do
    [[ -n "$section" ]] && SECTIONS+=("$section")
done < <(get_agents_sections)

if [[ ${#SECTIONS[@]} -eq 0 ]]; then
    log "ERROR: No sections found in exports.yaml agents_sections"
    echo "ERROR: No sections found in exports.yaml (exports.bot.agents_sections)" >&2
    exit 1
fi

log "Found ${#SECTIONS[@]} sections in config"

# Process each section
if [[ "$DRY_RUN" != "true" ]]; then
    > "$output_file"  # Clear output file
fi

for entry in "${SECTIONS[@]}"; do
    section_type=$(get_section_type "$entry")

    case "$section_type" in
        bot)
            bot_name="${entry#bot:}"
            if [[ "$DRY_RUN" == "true" ]]; then
                log "  Would add bot section: $bot_name"
            else
                if content=$(resolve_section "$entry"); then
                    printf '%s\n' "$content" >> "$output_file"
                    log "  + Bot: $bot_name"
                    BOT_SECTIONS_ADDED=$((BOT_SECTIONS_ADDED + 1))
                else
                    log "  ! Missing bot section: $bot_name (not in mirror)"
                    SECTIONS_MISSING=$((SECTIONS_MISSING + 1))
                fi
            fi
            ;;
        component)
            if [[ "$DRY_RUN" == "true" ]]; then
                log "  Would add component: $entry"
            else
                resolve_section "$entry" >> "$output_file"
                echo "" >> "$output_file"
                log "  + Component: $entry"
                COMPONENTS_ADDED=$((COMPONENTS_ADDED + 1))
            fi
            ;;
        section)
            if [[ "$DRY_RUN" == "true" ]]; then
                log "  Would add section: $entry"
            else
                resolve_section "$entry" >> "$output_file"
                echo "" >> "$output_file"
                log "  + Section: $entry"
                TEMPLATE_SECTIONS_ADDED=$((TEMPLATE_SECTIONS_ADDED + 1))
            fi
            ;;
        missing)
            log "  ! Missing: $entry (not found as component or section)"
            SECTIONS_MISSING=$((SECTIONS_MISSING + 1))
            ;;
    esac

    SECTIONS_ADDED=$((SECTIONS_ADDED + 1))
done

# Summary
log ""
log "=== Summary ==="
if [[ "$DRY_RUN" == "true" ]]; then
    log "Would assemble: ${#SECTIONS[@]} sections"
else
    log "Assembled: AGENTS.md"
    log "  Components: $COMPONENTS_ADDED"
    log "  Template sections: $TEMPLATE_SECTIONS_ADDED"
    log "  Bot-managed: $BOT_SECTIONS_ADDED"
    if [[ $SECTIONS_MISSING -gt 0 ]]; then
        log "  Missing: $SECTIONS_MISSING"
    fi
    log "Output: $output_file"
fi

TOTAL=$((COMPONENTS_ADDED + TEMPLATE_SECTIONS_ADDED + BOT_SECTIONS_ADDED))
echo "Assembled: AGENTS.md ($TOTAL sections: $COMPONENTS_ADDED components, $TEMPLATE_SECTIONS_ADDED template, $BOT_SECTIONS_ADDED bot)"

if [[ $SECTIONS_MISSING -gt 0 ]]; then
    echo "WARNING: $SECTIONS_MISSING sections missing"
    exit 1
fi
