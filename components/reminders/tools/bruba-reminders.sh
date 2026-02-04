#!/bin/bash
#
# bruba-reminders.sh - Wrapper for remindctl for AI agent use
#
# Purpose: Provides common reminder operations without requiring pipes,
#          suitable for OpenClaw exec allowlist without approval prompts.
#
# Usage: bruba-reminders.sh <command> [args...]
#
# Commands:
#   list [list_name] [--json] [--all] [--notes] [--overdue] [--today] [--week]
#   add "title" [--list "ListName"] [--due "date"] [--priority low|medium|high] [--notes "text"]
#   edit <uuid> [--title "new"] [--due "date"] [--priority low|medium|high] [--notes "text"]
#   complete <uuid> [uuid2 uuid3 ...]
#   delete <uuid> [uuid2 uuid3 ...]
#   search "query" [--all] [--notes] [--json]
#   count [--overdue] [--today] [--list "ListName"]
#   lookup "title_pattern" [--list "ListName"]
#   lists [--json]
#   status
#   help
#
# Version: 1.0.0
# Updated: 2026-02-04

set -e

# Configuration
REMINDCTL="/opt/homebrew/bin/remindctl"
JQ="/opt/homebrew/bin/jq"

# Fallback paths if homebrew location doesn't exist
[[ ! -x "$REMINDCTL" ]] && REMINDCTL="$(which remindctl 2>/dev/null || echo "")"
[[ ! -x "$JQ" ]] && JQ="$(which jq 2>/dev/null || echo "")"

# Colors for terminal output (disabled if not tty)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# Error handling
error() {
    echo -e "${RED}ERROR:${NC} $1" >&2
    exit 1
}

warn() {
    echo -e "${YELLOW}WARNING:${NC} $1" >&2
}

# Check dependencies
check_deps() {
    if [[ -z "$REMINDCTL" || ! -x "$REMINDCTL" ]]; then
        error "remindctl not found. Install: brew install steipete/tap/remindctl"
    fi
    if [[ -z "$JQ" || ! -x "$JQ" ]]; then
        error "jq not found. Install: brew install jq"
    fi
}

# Priority mapping (remindctl uses low/medium/high, JSON uses 0/1/5/9)
priority_to_text() {
    case "$1" in
        0) echo "none" ;;
        1) echo "low" ;;
        5) echo "medium" ;;
        9) echo "high" ;;
        *) echo "none" ;;
    esac
}

priority_to_num() {
    case "$1" in
        none) echo "0" ;;
        low) echo "1" ;;
        medium) echo "5" ;;
        high) echo "9" ;;
        *) echo "0" ;;
    esac
}

# Format a single reminder to compact output
# Input: JSON object
# Output: [UUID_PREFIX] title (due: date, priority: level, list: name)
format_compact() {
    local json="$1"
    local include_notes="$2"

    local id=$(echo "$json" | "$JQ" -r '.id // ""' | cut -c1-4)
    local title=$(echo "$json" | "$JQ" -r '.title // "Untitled"')
    local due=$(echo "$json" | "$JQ" -r '.dueDate // ""')
    local priority_num=$(echo "$json" | "$JQ" -r '.priority // 0')
    local list=$(echo "$json" | "$JQ" -r '.listName // "Unknown"')
    local notes=$(echo "$json" | "$JQ" -r '.notes // ""')
    local completed=$(echo "$json" | "$JQ" -r '.isCompleted // false')

    # Format due date (strip time if midnight)
    if [[ -n "$due" && "$due" != "null" ]]; then
        # Extract just the date part
        due=$(echo "$due" | cut -c1-10)
    else
        due=""
    fi

    # Build output line
    local output="[${id}] ${title}"

    # Add metadata
    local meta=""
    [[ -n "$due" ]] && meta="due: $due"

    local priority_text=$(priority_to_text "$priority_num")
    [[ "$priority_text" != "none" ]] && {
        [[ -n "$meta" ]] && meta="$meta, "
        meta="${meta}priority: $priority_text"
    }

    [[ -n "$list" && "$list" != "null" ]] && {
        [[ -n "$meta" ]] && meta="$meta, "
        meta="${meta}list: $list"
    }

    [[ "$completed" == "true" ]] && {
        [[ -n "$meta" ]] && meta="$meta, "
        meta="${meta}✓ completed"
    }

    [[ -n "$meta" ]] && output="$output ($meta)"

    echo "$output"

    # Optionally include notes (indented)
    if [[ "$include_notes" == "true" && -n "$notes" && "$notes" != "null" ]]; then
        echo "$notes" | sed 's/^/    /'
    fi
}

# ============================================================================
# COMMAND: list
# List reminders with various filters
# ============================================================================
cmd_list() {
    local list_name=""
    local output_json=false
    local include_all=false
    local include_notes=false
    local filter_overdue=false
    local filter_today=false
    local filter_week=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json) output_json=true; shift ;;
            --all) include_all=true; shift ;;
            --notes) include_notes=true; shift ;;
            --overdue) filter_overdue=true; shift ;;
            --today) filter_today=true; shift ;;
            --week) filter_week=true; shift ;;
            -*) error "Unknown option: $1" ;;
            *) list_name="$1"; shift ;;
        esac
    done

    # Build remindctl command based on filters
    local cmd_args=""
    if [[ "$filter_overdue" == "true" ]]; then
        cmd_args="overdue"
    elif [[ "$filter_today" == "true" ]]; then
        cmd_args="today"
    elif [[ "$filter_week" == "true" ]]; then
        cmd_args="week"
    elif [[ -n "$list_name" ]]; then
        cmd_args="list \"$list_name\""
    else
        cmd_args="all"
    fi

    # Get JSON output
    local raw_json
    raw_json=$(eval "$REMINDCTL $cmd_args --json" 2>/dev/null) || error "remindctl failed"

    # Handle empty output
    if [[ -z "$raw_json" || "$raw_json" == "[]" || "$raw_json" == "null" ]]; then
        if [[ "$output_json" == "true" ]]; then
            echo "[]"
        else
            echo "No reminders found."
        fi
        return 0
    fi

    # Filter out completed unless --all
    local filtered_json
    if [[ "$include_all" == "true" ]]; then
        filtered_json="$raw_json"
    else
        filtered_json=$(echo "$raw_json" | "$JQ" '[.[] | select(.isCompleted != true)]')
    fi

    # Output
    if [[ "$output_json" == "true" ]]; then
        if [[ "$include_notes" == "true" ]]; then
            echo "$filtered_json" | "$JQ" '.'
        else
            # Strip notes from JSON output
            echo "$filtered_json" | "$JQ" '[.[] | del(.notes)]'
        fi
    else
        # Compact output
        local count=$(echo "$filtered_json" | "$JQ" 'length')
        if [[ "$count" == "0" ]]; then
            echo "No reminders found."
            return 0
        fi

        echo "$filtered_json" | "$JQ" -c '.[]' | while read -r item; do
            format_compact "$item" "$include_notes"
        done
    fi
}

# ============================================================================
# COMMAND: add
# Create a new reminder
# ============================================================================
cmd_add() {
    local title=""
    local list_name=""
    local due=""
    local priority=""
    local notes=""

    # First positional arg is title
    [[ $# -gt 0 && ! "$1" =~ ^-- ]] && { title="$1"; shift; }

    # Parse named arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --list) list_name="$2"; shift 2 ;;
            --due) due="$2"; shift 2 ;;
            --priority) priority="$2"; shift 2 ;;
            --notes) notes="$2"; shift 2 ;;
            -*) error "Unknown option: $1" ;;
            *)
                # Handle positional title if not set
                [[ -z "$title" ]] && { title="$1"; shift; } || error "Unexpected argument: $1"
                ;;
        esac
    done

    [[ -z "$title" ]] && error "Title is required. Usage: add \"title\" [--list ...] [--due ...] [--priority ...] [--notes ...]"

    # Build remindctl command
    local cmd_args="add --title \"$title\""
    [[ -n "$list_name" ]] && cmd_args="$cmd_args --list \"$list_name\""
    [[ -n "$due" ]] && cmd_args="$cmd_args --due \"$due\""
    [[ -n "$priority" ]] && cmd_args="$cmd_args --priority $priority"
    [[ -n "$notes" ]] && cmd_args="$cmd_args --notes \"$notes\""

    # Execute
    eval "$REMINDCTL $cmd_args" || error "Failed to add reminder"
    echo -e "${GREEN}✓${NC} Created reminder: $title"
}

# ============================================================================
# COMMAND: edit
# Edit an existing reminder (UUID required)
# ============================================================================
cmd_edit() {
    local uuid=""
    local title=""
    local due=""
    local priority=""
    local notes=""

    # First positional arg is UUID
    [[ $# -gt 0 && ! "$1" =~ ^-- ]] && { uuid="$1"; shift; }

    # Parse named arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --title) title="$2"; shift 2 ;;
            --due) due="$2"; shift 2 ;;
            --priority) priority="$2"; shift 2 ;;
            --notes) notes="$2"; shift 2 ;;
            -*) error "Unknown option: $1" ;;
            *)
                [[ -z "$uuid" ]] && { uuid="$1"; shift; } || error "Unexpected argument: $1"
                ;;
        esac
    done

    [[ -z "$uuid" ]] && error "UUID is required. Usage: edit <uuid> [--title ...] [--due ...] [--priority ...] [--notes ...]"

    # Validate UUID exists (optional but helpful)
    # Skip for now as it adds latency

    # Build remindctl command
    local cmd_args="edit \"$uuid\""
    [[ -n "$title" ]] && cmd_args="$cmd_args --title \"$title\""
    [[ -n "$due" ]] && cmd_args="$cmd_args --due \"$due\""
    [[ -n "$priority" ]] && cmd_args="$cmd_args --priority $priority"
    [[ -n "$notes" ]] && cmd_args="$cmd_args --notes \"$notes\""

    # Check if any edit options provided
    if [[ -z "$title" && -z "$due" && -z "$priority" && -z "$notes" ]]; then
        error "No edit options provided. Use --title, --due, --priority, or --notes"
    fi

    # Execute
    eval "$REMINDCTL $cmd_args" || error "Failed to edit reminder. Is the UUID correct?"
    echo -e "${GREEN}✓${NC} Updated reminder: $uuid"
}

# ============================================================================
# COMMAND: complete
# Mark reminder(s) as complete (UUID required)
# ============================================================================
cmd_complete() {
    [[ $# -eq 0 ]] && error "At least one UUID is required. Usage: complete <uuid> [uuid2 ...]"

    local failed=0
    for uuid in "$@"; do
        if "$REMINDCTL" complete "$uuid" 2>/dev/null; then
            echo -e "${GREEN}✓${NC} Completed: $uuid"
        else
            echo -e "${RED}✗${NC} Failed to complete: $uuid" >&2
            failed=$((failed + 1))
        fi
    done

    [[ $failed -gt 0 ]] && exit 1
    return 0
}

# ============================================================================
# COMMAND: delete
# Delete reminder(s) (UUID required)
# ============================================================================
cmd_delete() {
    [[ $# -eq 0 ]] && error "At least one UUID is required. Usage: delete <uuid> [uuid2 ...]"

    local failed=0
    for uuid in "$@"; do
        if "$REMINDCTL" delete "$uuid" --force 2>/dev/null; then
            echo -e "${GREEN}✓${NC} Deleted: $uuid"
        else
            echo -e "${RED}✗${NC} Failed to delete: $uuid" >&2
            failed=$((failed + 1))
        fi
    done

    [[ $failed -gt 0 ]] && exit 1
    return 0
}

# ============================================================================
# COMMAND: search
# Search reminders by text
# ============================================================================
cmd_search() {
    local query=""
    local output_json=false
    local include_all=false
    local include_notes=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json) output_json=true; shift ;;
            --all) include_all=true; shift ;;
            --notes) include_notes=true; shift ;;
            -*) error "Unknown option: $1" ;;
            *) query="$1"; shift ;;
        esac
    done

    [[ -z "$query" ]] && error "Search query is required. Usage: search \"query\" [--all] [--notes] [--json]"

    # Get all reminders as JSON
    local raw_json
    raw_json=$("$REMINDCTL" all --json 2>/dev/null) || error "remindctl failed"

    # Filter by completion status
    local base_json
    if [[ "$include_all" == "true" ]]; then
        base_json="$raw_json"
    else
        base_json=$(echo "$raw_json" | "$JQ" '[.[] | select(.isCompleted != true)]')
    fi

    # Search in title and notes (case-insensitive)
    local query_lower=$(echo "$query" | tr '[:upper:]' '[:lower:]')
    local filtered_json
    filtered_json=$(echo "$base_json" | "$JQ" --arg q "$query_lower" '
        [.[] | select(
            (.title | ascii_downcase | contains($q)) or
            (.notes // "" | ascii_downcase | contains($q))
        )]
    ')

    # Output
    local count=$(echo "$filtered_json" | "$JQ" 'length')

    if [[ "$output_json" == "true" ]]; then
        if [[ "$include_notes" == "true" ]]; then
            echo "$filtered_json" | "$JQ" '.'
        else
            echo "$filtered_json" | "$JQ" '[.[] | del(.notes)]'
        fi
    else
        if [[ "$count" == "0" ]]; then
            echo "No reminders found matching: $query"
            return 0
        fi

        echo "Found $count reminder(s) matching: $query"
        echo ""
        echo "$filtered_json" | "$JQ" -c '.[]' | while read -r item; do
            format_compact "$item" "$include_notes"
        done
    fi
}

# ============================================================================
# COMMAND: count
# Quick count of reminders (useful for cron jobs)
# ============================================================================
cmd_count() {
    local filter_overdue=false
    local filter_today=false
    local list_name=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --overdue) filter_overdue=true; shift ;;
            --today) filter_today=true; shift ;;
            --list) list_name="$2"; shift 2 ;;
            -*) error "Unknown option: $1" ;;
            *) error "Unexpected argument: $1" ;;
        esac
    done

    # Build remindctl command
    local cmd_args=""
    if [[ "$filter_overdue" == "true" ]]; then
        cmd_args="overdue"
    elif [[ "$filter_today" == "true" ]]; then
        cmd_args="today"
    elif [[ -n "$list_name" ]]; then
        cmd_args="list \"$list_name\""
    else
        cmd_args="all"
    fi

    # Get quiet count
    local count
    count=$(eval "$REMINDCTL $cmd_args --quiet" 2>/dev/null | grep -oE '[0-9]+' | head -1) || count="0"

    echo "$count"
}

# ============================================================================
# COMMAND: lookup
# Get UUID from title match
# ============================================================================
cmd_lookup() {
    local title_pattern=""
    local list_name=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --list) list_name="$2"; shift 2 ;;
            -*) error "Unknown option: $1" ;;
            *) title_pattern="$1"; shift ;;
        esac
    done

    [[ -z "$title_pattern" ]] && error "Title pattern is required. Usage: lookup \"pattern\" [--list ListName]"

    # Get reminders JSON
    local cmd_args="all"
    [[ -n "$list_name" ]] && cmd_args="list \"$list_name\""

    local raw_json
    raw_json=$(eval "$REMINDCTL $cmd_args --json" 2>/dev/null) || error "remindctl failed"

    # Filter uncompleted and search
    local pattern_lower=$(echo "$title_pattern" | tr '[:upper:]' '[:lower:]')
    local matches
    matches=$(echo "$raw_json" | "$JQ" --arg p "$pattern_lower" '
        [.[] | select(.isCompleted != true) | select(.title | ascii_downcase | contains($p))]
        | .[] | {id: .id, title: .title}
    ')

    if [[ -z "$matches" || "$matches" == "null" ]]; then
        echo "No matching reminders found for: $title_pattern"
        return 1
    fi

    # Output matches
    echo "$matches" | "$JQ" -r '"\(.id | .[0:8])  \(.title)"'
}

# ============================================================================
# COMMAND: lists
# Show available reminder lists
# ============================================================================
cmd_lists() {
    local output_json=false

    [[ "$1" == "--json" ]] && output_json=true

    local raw
    raw=$("$REMINDCTL" lists --json 2>/dev/null) || error "remindctl failed"

    if [[ "$output_json" == "true" ]]; then
        echo "$raw" | "$JQ" '.'
    else
        echo "Available Lists:"
        echo ""
        echo "$raw" | "$JQ" -r '.[] | "  \(.title) (\(.reminderCount // 0) items)"'
    fi
}

# ============================================================================
# COMMAND: status
# Check remindctl status and permissions
# ============================================================================
cmd_status() {
    echo "Checking remindctl status..."
    echo ""

    # Binary check
    if [[ -x "$REMINDCTL" ]]; then
        echo -e "${GREEN}✓${NC} remindctl found: $REMINDCTL"
    else
        echo -e "${RED}✗${NC} remindctl not found"
        return 1
    fi

    # jq check
    if [[ -x "$JQ" ]]; then
        echo -e "${GREEN}✓${NC} jq found: $JQ"
    else
        echo -e "${RED}✗${NC} jq not found"
        return 1
    fi

    # Permission check
    echo ""
    "$REMINDCTL" status 2>&1
}

# ============================================================================
# COMMAND: help
# Show usage
# ============================================================================
cmd_help() {
    cat << 'EOF'
bruba-reminders.sh - Wrapper for remindctl for AI agent use

USAGE:
    bruba-reminders.sh <command> [arguments]

COMMANDS:
    list [list_name] [options]    List reminders
        --json                    Output as JSON
        --all                     Include completed items
        --notes                   Include notes in output
        --overdue                 Filter to overdue only
        --today                   Filter to today only
        --week                    Filter to this week only

    add "title" [options]         Create new reminder
        --list "ListName"         Specify list
        --due "date"              Set due date (today, tomorrow, YYYY-MM-DD)
        --priority level          Set priority (low, medium, high)
        --notes "text"            Add notes

    edit <uuid> [options]         Edit existing reminder (UUID REQUIRED)
        --title "new title"       Change title
        --due "date"              Change due date
        --priority level          Change priority
        --notes "text"            Change notes

    complete <uuid> [uuid2 ...]   Mark reminder(s) as complete

    delete <uuid> [uuid2 ...]     Delete reminder(s)

    search "query" [options]      Search reminders by text
        --json                    Output as JSON
        --all                     Include completed items
        --notes                   Include notes in output

    count [options]               Get count of reminders
        --overdue                 Count overdue only
        --today                   Count today only
        --list "ListName"         Count specific list

    lookup "title_pattern"        Find UUID by title match
        --list "ListName"         Search in specific list

    lists [--json]                Show available lists

    status                        Check remindctl status

    help                          Show this help

EXAMPLES:
    # List overdue items
    bruba-reminders.sh list --overdue

    # Add a reminder to Work list
    bruba-reminders.sh add "Review PR" --list "Work" --due tomorrow --priority high

    # Edit by UUID prefix
    bruba-reminders.sh edit 4DF7 --title "Updated title" --priority medium

    # Complete multiple
    bruba-reminders.sh complete 4DF7 A8B2 C3E9

    # Search for anything mentioning "deploy"
    bruba-reminders.sh search "deploy"

    # Quick overdue count
    bruba-reminders.sh count --overdue

    # Find UUID for a reminder
    bruba-reminders.sh lookup "Review PR" --list "Work"

NOTES:
    - Always use UUIDs for edit/complete/delete (display indices are broken)
    - UUID prefix (4+ chars) works: 4DF7 instead of full 4DF7A83B-1234-...
    - Default output excludes completed items and notes for efficiency
    - Use --json for programmatic parsing
    - Moving items between lists is not supported (Apple API limitation)
EOF
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    check_deps

    local cmd="${1:-help}"
    shift 2>/dev/null || true

    case "$cmd" in
        list)     cmd_list "$@" ;;
        add)      cmd_add "$@" ;;
        edit)     cmd_edit "$@" ;;
        complete) cmd_complete "$@" ;;
        delete)   cmd_delete "$@" ;;
        search)   cmd_search "$@" ;;
        count)    cmd_count "$@" ;;
        lookup)   cmd_lookup "$@" ;;
        lists)    cmd_lists "$@" ;;
        status)   cmd_status ;;
        help|--help|-h) cmd_help ;;
        *)        error "Unknown command: $cmd. Run 'bruba-reminders.sh help' for usage." ;;
    esac
}

main "$@"
