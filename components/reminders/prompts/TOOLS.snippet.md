### Reminders

**Primary Tool:** `${WORKSPACE}/tools/bruba-reminders.sh`

A wrapper around remindctl that handles filtering, JSON parsing, and provides token-efficient output without requiring pipes.

**Quick Reference:**
```bash
bruba-reminders.sh list                          # All uncompleted
bruba-reminders.sh list Planning                 # Specific list
bruba-reminders.sh list --overdue                # Overdue only
bruba-reminders.sh list --today                  # Today's items
bruba-reminders.sh add "Task" --list "Work"      # Add reminder
bruba-reminders.sh edit UUID --title "New"       # Edit by UUID
bruba-reminders.sh complete UUID                 # Mark complete
bruba-reminders.sh search "keyword"              # Search
bruba-reminders.sh count --overdue               # Quick count
bruba-reminders.sh lookup "title"                # Find UUID by title
bruba-reminders.sh lists                         # Show all lists
```

**⚠️ CRITICAL: Never use display indices `[1]`, `[2]`, etc. — they are BROKEN.**
Display indices don't match internal IDs. Using `remindctl edit 8` will edit the WRONG reminder.

**Always use UUIDs:**
1. Default output shows `[UUID_PREFIX]` for each item
2. Use UUID prefix (4+ chars): `bruba-reminders.sh edit 4DF7 --title "New"`
3. Use `lookup` to find UUID from title: `bruba-reminders.sh lookup "task name"`

**Output Modes:**
| Mode | When to Use | Tokens |
|------|-------------|--------|
| Default (compact) | Display to user | ~20-40/item |
| `--json` | Programmatic parsing | ~150-300/item |
| `count` | Quick checks | ~5 total |

**Common Operations:**

```bash
# Add with all options
bruba-reminders.sh add "Review PR" --list "Work" --due tomorrow --priority high --notes "Details"

# Edit existing
bruba-reminders.sh edit 4DF7 --title "Updated" --due "2026-02-15" --priority medium

# Complete multiple
bruba-reminders.sh complete 4DF7 A8B2 C3E9

# Search with notes
bruba-reminders.sh search "deploy" --notes

# Get JSON for specific list
bruba-reminders.sh list Work --json
```

**Date Formats:** `today`, `tomorrow`, `YYYY-MM-DD`, `YYYY-MM-DD HH:mm`

**Priority Levels:** `low`, `medium`, `high`

**Known Limitations (Apple API):**
- Cannot move reminder between lists (error -3002)
- Cannot clear due date (delete and recreate)
- Cannot remove recurrence (delete and recreate)

**Maintenance Tool:**
```bash
${WORKSPACE}/tools/cleanup-reminders.sh
```
Removes completed reminders older than retention period (7 days for Groceries, 365 for others).
