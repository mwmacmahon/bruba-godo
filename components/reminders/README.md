# Reminders Component

**Status:** Partial

Scheduled reminders and notifications.

## Overview

This component will enable:
- **Timed reminders:** "Remind me in 30 minutes"
- **Scheduled notifications:** "Every Monday at 9am"
- **Location-based reminders:** "When I get home" (requires location integration)

## Prerequisites (Expected)

- A reminder backend (system reminders, cron, or dedicated service)
- Notification method (Signal, push notifications, etc.)

## Setup

```bash
# Sync reminder tools to bot
./tools/push.sh --tools-only

# Or as part of regular push
./tools/push.sh
```

Tools are synced to `~/clawd/tools/` with executable permissions.

## Notes

**What exists:**
- `prompts/AGENTS.snippet.md` — Reminder handling instructions for the bot
- `prompts/TOOLS.snippet.md` — Tool documentation for reminder commands
- `tools/` — Reminder scripts (cleanup-reminders.sh)
- `allowlist.json` — Exec-approvals entries

**TODO:**
- `setup.sh` — Interactive setup script
- `validate.sh` — Configuration validation
