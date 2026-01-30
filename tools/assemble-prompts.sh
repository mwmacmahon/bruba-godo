#!/bin/bash
# Assemble final prompts from templates, components, and user snippets
#
# Usage:
#   ./tools/assemble-prompts.sh              # Assemble all prompts
#   ./tools/assemble-prompts.sh --verbose    # Show detailed output
#   ./tools/assemble-prompts.sh --dry-run    # Show what would be assembled
#
# Assembly order for each prompt (e.g., AGENTS.md):
#   1. templates/prompts/AGENTS.md           (base template)
#   2. + components/*/prompts/AGENTS.snippet.md  (all enabled components)
#   3. + user/prompts/AGENTS.snippet.md      (user customizations)
#   = assembled/prompts/AGENTS.md            (final output)
#
# Logs: logs/assemble.log

set -e

# Load shared functions
source "$(dirname "$0")/lib.sh"

# Parse arguments
if ! parse_common_args "$@"; then
    echo "Usage: $0 [--dry-run] [--verbose]"
    echo ""
    echo "Assemble final prompts from templates, components, and user snippets."
    echo ""
    echo "Options:"
    echo "  --dry-run, -n   Show what would be assembled without doing it"
    echo "  --verbose, -v   Show detailed output"
    echo "  --quiet, -q     Summary output only (default)"
    exit 0
fi

# Load config
load_config

# Set up logging
LOG_FILE="$LOG_DIR/assemble.log"
mkdir -p "$LOG_DIR"
rotate_log "$LOG_FILE"

log "=== Assembling Prompts ==="

# Create output directory
PROMPTS_OUTPUT="$ASSEMBLED_DIR/prompts"
if [[ "$DRY_RUN" != "true" ]]; then
    mkdir -p "$PROMPTS_OUTPUT"
fi

# Core prompt files to assemble
PROMPT_FILES="AGENTS.md TOOLS.md MEMORY.md IDENTITY.md SOUL.md USER.md HEARTBEAT.md BOOTSTRAP.md"

ASSEMBLED=0
COMPONENTS_ADDED=0

for prompt in $PROMPT_FILES; do
    base_file="$ROOT_DIR/templates/prompts/$prompt"
    output_file="$PROMPTS_OUTPUT/$prompt"
    snippet_name="${prompt%.md}.snippet.md"

    # Skip if base template doesn't exist
    if [[ ! -f "$base_file" ]]; then
        log "  Skip: $prompt (no base template)"
        continue
    fi

    log ""
    log "Assembling: $prompt"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "  Would use base: templates/prompts/$prompt"
    else
        # Start with base template
        cp "$base_file" "$output_file"
        log "  + Base: templates/prompts/$prompt"
    fi

    # Add component snippets
    for component_dir in "$ROOT_DIR"/components/*/; do
        component_name=$(basename "$component_dir")
        snippet_file="$component_dir/prompts/$snippet_name"

        if [[ -f "$snippet_file" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log "  Would add: components/$component_name/prompts/$snippet_name"
            else
                # Append snippet with separator
                echo "" >> "$output_file"
                echo "<!-- COMPONENT: $component_name -->" >> "$output_file"
                cat "$snippet_file" >> "$output_file"
                echo "<!-- /COMPONENT: $component_name -->" >> "$output_file"
                log "  + Component: $component_name"
            fi
            COMPONENTS_ADDED=$((COMPONENTS_ADDED + 1))
        fi
    done

    # Add user snippet if exists
    user_snippet="$ROOT_DIR/user/prompts/$snippet_name"
    if [[ -f "$user_snippet" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log "  Would add: user/prompts/$snippet_name"
        else
            echo "" >> "$output_file"
            echo "<!-- USER CUSTOMIZATION -->" >> "$output_file"
            cat "$user_snippet" >> "$output_file"
            echo "<!-- /USER CUSTOMIZATION -->" >> "$output_file"
            log "  + User: user/prompts/$snippet_name"
        fi
    fi

    ASSEMBLED=$((ASSEMBLED + 1))
done

log ""
log "=== Summary ==="
if [[ "$DRY_RUN" == "true" ]]; then
    log "Would assemble: $ASSEMBLED prompts"
    log "Component snippets found: $COMPONENTS_ADDED"
else
    log "Assembled: $ASSEMBLED prompts"
    log "Component snippets added: $COMPONENTS_ADDED"
    log "Output: $PROMPTS_OUTPUT/"
fi

echo "Assembled: $ASSEMBLED prompts ($COMPONENTS_ADDED component snippets)"
