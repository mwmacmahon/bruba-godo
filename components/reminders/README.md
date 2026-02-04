# Reminders Component

**Status:** Ready

Apple Reminders integration via remindctl wrapper.

## Overview

This component provides:
- **CRUD operations:** Add, edit, complete, delete reminders
- **Smart filtering:** Overdue, today, this week, by list
- **Search:** Find reminders by title or notes
- **Token efficiency:** Compact output by default, JSON when needed
- **UUID handling:** All operations use UUIDs (display indices are broken)

**Multi-agent deployment:** Each agent gets its own copy of `bruba-reminders.sh` in `${WORKSPACE}/tools/`. The `${WORKSPACE}` template variable is substituted during prompt assembly with the agent's workspace path.

## Prerequisites

On the bot machine:
```bash
brew install steipete/tap/remindctl
brew install jq
remindctl authorize  # Grant Reminders access
```

## Files

```
components/reminders/
├── README.md                    # This file
├── allowlist.json               # Exec-approvals entries (uses ${WORKSPACE})
├── prompts/
│   ├── AGENTS.snippet.md        # Bot behavior instructions
│   └── TOOLS.snippet.md         # Tool documentation
└── tools/
    ├── bruba-reminders.sh       # Main wrapper (→ ${WORKSPACE}/tools/)
    ├── cleanup-reminders.sh     # Maintenance script (→ ${WORKSPACE}/tools/)
    └── helpers/
        └── cleanup-reminders.py # Cleanup implementation
```

## Setup

1. **Deploy tools to bot:**
```bash
# Copy script to each agent's tools directory
./tools/bot 'cp components/reminders/tools/bruba-reminders.sh /Users/bruba/agents/bruba-main/tools/'
./tools/bot 'chmod +x /Users/bruba/agents/bruba-main/tools/bruba-reminders.sh'

# Repeat for bruba-manager (or other agents)
./tools/bot 'mkdir -p /Users/bruba/agents/bruba-manager/tools'
./tools/bot 'cp /Users/bruba/agents/bruba-main/tools/bruba-reminders.sh /Users/bruba/agents/bruba-manager/tools/'
```

2. **Verify on bot:**
```bash
./tools/bot '/Users/bruba/agents/bruba-main/tools/bruba-reminders.sh status'
./tools/bot '/Users/bruba/agents/bruba-manager/tools/bruba-reminders.sh status'
```

3. **Enable component in config.yaml:**
```yaml
exports:
  bot:
    agents_sections:
      - reminders  # Add to section list
    tools_sections:
      - reminders  # Add to section list
```

4. **Regenerate prompts:**
```bash
./tools/assemble-prompts.sh
```

## Usage

### Quick Reference

```bash
# List operations
bruba-reminders.sh list                          # All uncompleted
bruba-reminders.sh list Planning                 # Specific list
bruba-reminders.sh list --overdue                # Overdue only
bruba-reminders.sh list --today                  # Today's items
bruba-reminders.sh list --week                   # This week
bruba-reminders.sh list --json                   # JSON output
bruba-reminders.sh list --all                    # Include completed
bruba-reminders.sh list --notes                  # Include notes

# Create
bruba-reminders.sh add "Task title"
bruba-reminders.sh add "Task" --list "Work" --due tomorrow --priority high

# Edit (UUID required)
bruba-reminders.sh edit 4DF7 --title "New title"
bruba-reminders.sh edit 4DF7 --due "2026-02-15" --priority medium

# Complete/Delete (UUID required)
bruba-reminders.sh complete 4DF7
bruba-reminders.sh complete 4DF7 A8B2 C3E9
bruba-reminders.sh delete 4DF7

# Search
bruba-reminders.sh search "keyword"
bruba-reminders.sh search "keyword" --notes --json

# Utility
bruba-reminders.sh count --overdue
bruba-reminders.sh lookup "task title"
bruba-reminders.sh lists
bruba-reminders.sh status
```

### Output Format

Default compact output:
```
[4DF7] Task title (due: 2026-02-10, priority: high, list: Work)
[A8B2] Another task (due: 2026-02-05, list: Personal)
```

### UUID Rule

**NEVER use display indices** — they are globally broken in remindctl.

Always use UUIDs:
- Compact output shows `[4DF7]` prefix
- Use `lookup "title"` to find UUID from title
- 4+ character prefix is sufficient

## Known Limitations

| Operation | Status | Notes |
|-----------|--------|-------|
| Add reminder | ✅ Works | |
| Edit title/priority/due/notes | ✅ Works | UUID only |
| Complete | ✅ Works | UUID only |
| Delete | ✅ Works | UUID only |
| Move to different list | ❌ Fails | Apple error -3002 |
| Clear due date | ❌ Fails | Delete and recreate |
| Remove recurrence | ❌ Fails | Delete and recreate |

## Allowlist

The `allowlist.json` provides exec-approval entries:
```json
{
  "entries": [
    {"pattern": "${WORKSPACE}/tools/cleanup-reminders.sh", "id": "cleanup-reminders"},
    {"pattern": "${WORKSPACE}/tools/bruba-reminders.sh", "id": "bruba-reminders"},
    {"pattern": "${WORKSPACE}/tools/bruba-reminders.sh *", "id": "bruba-reminders-args"}
  ]
}
```

## Maintenance

Cleanup old completed reminders:
```bash
${WORKSPACE}/tools/cleanup-reminders.sh           # Dry run
${WORKSPACE}/tools/cleanup-reminders.sh --execute # Actually delete
```

Retention: 7 days for Groceries, 365 days for all others.

Backups saved to: `~/clawd/output/reminders_archive/<list_name>/<timestamp>.json`

---

## macOS Reminders Permission Context

**Only these contexts can access Apple Reminders:**
- OpenClaw daemon (runs as bruba user in native session)
- Native Terminal.app on the bot machine (logged in as bruba)

**These contexts CANNOT access Reminders:**
- SSH sessions (different security context)
- VSCode integrated terminal (different security context)
- `./tools/bot` from operator machine (uses sudo)
- Any non-GUI process spawned remotely

This is a macOS security feature. Reminders access is granted per-application
and requires a GUI session for initial authorization.

If testing via SSH shows "access denied" but OpenClaw works fine, this is expected.
