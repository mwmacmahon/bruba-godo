#!/bin/bash
# Generate cronjob YAML files from templates + config
#
# Usage:
#   ./tools/generate-cronjobs.sh              # Generate all cronjob files
#   ./tools/generate-cronjobs.sh --verbose    # Show details
#   ./tools/generate-cronjobs.sh --dry-run    # Show what would be generated
#
# Reads reset_cycle/wake_cycle flags from config.yaml, generates message blocks,
# writes final YAML to cronjobs/ directory.
#
# Templates: templates/cronjobs/
# Output: cronjobs/ (generated files overwrite in place)
# Non-templated cronjobs (reminder-check, staleness-check, etc.) are untouched.

set -e

# Load shared functions
source "$(dirname "$0")/lib.sh"

# Parse arguments
if ! parse_common_args "$@"; then
    echo "Usage: $0 [--dry-run] [--verbose]"
    echo ""
    echo "Generate cronjob YAML files from templates and config."
    echo ""
    echo "Options:"
    echo "  --dry-run, -n    Show what would be generated without writing"
    echo "  --verbose, -v    Show detailed output"
    exit 0
fi

# Load config
load_config

TEMPLATES_DIR="$ROOT_DIR/templates/cronjobs"
OUTPUT_DIR="$ROOT_DIR/cronjobs"

# Verify templates exist
if [[ ! -d "$TEMPLATES_DIR" ]]; then
    echo "ERROR: Templates directory not found: $TEMPLATES_DIR" >&2
    exit 1
fi

# Get agent lists from config
RESET_AGENTS=()
while IFS= read -r agent; do
    [[ -n "$agent" ]] && RESET_AGENTS+=("$agent")
done < <(get_reset_agents)

WAKE_AGENTS=()
while IFS= read -r agent; do
    [[ -n "$agent" ]] && WAKE_AGENTS+=("$agent")
done < <(get_wake_agents)

if [[ ${#RESET_AGENTS[@]} -eq 0 ]]; then
    echo "WARNING: No agents with reset_cycle: true" >&2
fi
if [[ ${#WAKE_AGENTS[@]} -eq 0 ]]; then
    echo "WARNING: No agents with wake_cycle: true" >&2
fi

[[ "$VERBOSE" == "true" ]] && echo "Reset agents: ${RESET_AGENTS[*]}"
[[ "$VERBOSE" == "true" ]] && echo "Wake agents: ${WAKE_AGENTS[*]}"

# Get continuation type per agent (standard or technical)
get_continuation_type() {
    local agent="$1"
    local config_file="$ROOT_DIR/config.yaml"
    python3 -c "
import yaml
with open('$config_file') as f:
    config = yaml.safe_load(f)
agent = config.get('agents', {}).get('$agent', {})
print(agent.get('continuation_type', 'standard'))
" 2>/dev/null
}

# Get human_name for an agent from config
get_agent_human_name() {
    local agent="$1"
    local config_file="$ROOT_DIR/config.yaml"
    python3 -c "
import yaml
with open('$config_file') as f:
    config = yaml.safe_load(f)
agent = config.get('agents', {}).get('$agent', {})
print(agent.get('identity', {}).get('human_name', ''))
" 2>/dev/null
}

# Prep message for standard agents
STANDARD_PREP_MSG='Session reset in 7 minutes. Write a continuation packet to memory/CONTINUATION.md. Include: Session Summary (what you remember from today, or '\''Nothing recorded'\'' if empty), In Progress (current tasks and status), Open Questions (unresolved items), Next Steps (action items for tomorrow). Write actual content, not placeholders. Create the file now.'

# Prep message for technical agents (guru)
TECHNICAL_PREP_MSG='Session reset in 7 minutes. Write a continuation packet to memory/CONTINUATION.md. Include: Technical Session Summary (topics worked on), In Progress (debugging/analysis status), Open Questions (unresolved technical issues), Handoff Notes (context for next session). Write actual content, not placeholders. Create the file now.'

# Generate a cronjob file from template
# Args: template_name
generate_from_template() {
    local template_name="$1"
    local template_file="$TEMPLATES_DIR/$template_name"
    local output_file="$OUTPUT_DIR/$template_name"

    if [[ ! -f "$template_file" ]]; then
        echo "ERROR: Template not found: $template_file" >&2
        return 1
    fi

    local content
    content=$(cat "$template_file")

    # Generate agent message block based on template type
    local agent_messages=""

    case "$template_name" in
        nightly-reset-prep.yaml)
            local n=1
            for agent in "${RESET_AGENTS[@]}"; do
                local ctype
                ctype=$(get_continuation_type "$agent")
                local msg="$STANDARD_PREP_MSG"
                [[ "$ctype" == "technical" ]] && msg="$TECHNICAL_PREP_MSG"
                agent_messages+="  $n. sessions_send to agent:${agent}:main: \"$msg\""
                agent_messages+=$'\n\n'
                n=$((n + 1))
            done
            ;;

        nightly-reset-execute.yaml)
            local n=1
            for agent in "${RESET_AGENTS[@]}"; do
                agent_messages+="  $n. sessions_send to agent:${agent}:main: \"/reset\""
                agent_messages+=$'\n'
                n=$((n + 1))
            done
            agent_messages+=$'\n'
            ;;

        nightly-reset-wake.yaml)
            local n=1
            for agent in "${WAKE_AGENTS[@]}"; do
                # Reset agents get CONTINUATION.md hint, others get plain wake
                local is_reset=false
                for ra in "${RESET_AGENTS[@]}"; do
                    [[ "$ra" == "$agent" ]] && is_reset=true && break
                done

                if [[ "$is_reset" == "true" ]]; then
                    agent_messages+="  $n. sessions_send to agent:${agent}:main: \"Good morning. Session initialized. Check memory/CONTINUATION.md for context from previous session.\""
                else
                    agent_messages+="  $n. sessions_send to agent:${agent}:main: \"Good morning. Session initialized.\""
                fi
                agent_messages+=$'\n'
                n=$((n + 1))
            done
            agent_messages+=$'\n'
            ;;

        morning-briefing.yaml)
            # This one uses {{HUMAN_NAME}} substitution, not {{AGENT_MESSAGES}}
            local manager_name
            manager_name=$(get_agent_human_name "bruba-manager")
            if [[ -z "$manager_name" ]]; then
                echo "WARNING: bruba-manager has no identity.human_name set" >&2
                manager_name="User"
            fi
            content="${content//\{\{HUMAN_NAME\}\}/$manager_name}"
            ;;
    esac

    # Replace {{AGENT_MESSAGES}} placeholder
    if [[ -n "$agent_messages" ]]; then
        # Strip one trailing newline (template already has separator before next line)
        agent_messages="${agent_messages%$'\n'}"
        # Use Python with env vars for reliable multi-line substitution
        content=$(TMPL="$content" MSGS="$agent_messages" python3 -c "
import os
content = os.environ['TMPL']
messages = os.environ['MSGS']
print(content.replace('{{AGENT_MESSAGES}}', messages), end='')
")
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "=== Would write: $output_file ==="
        [[ "$VERBOSE" == "true" ]] && echo "$content"
    else
        printf '%s\n' "$content" > "$output_file"
        [[ "$VERBOSE" == "true" ]] && echo "Generated: $output_file" || true
    fi
}

# Generate all templated cronjobs
GENERATED=0
for template in nightly-reset-prep.yaml nightly-reset-execute.yaml nightly-reset-wake.yaml morning-briefing.yaml; do
    generate_from_template "$template"
    GENERATED=$((GENERATED + 1))
done

if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    echo "Dry run: $GENERATED cronjob files would be generated"
else
    echo "Generated $GENERATED cronjob files in $OUTPUT_DIR/"
fi
