## Reminder Management

**Primary tool:** `${SHARED_TOOLS}/bruba-reminders.sh`

This wrapper handles Apple Reminders without requiring pipes or approval prompts.

**Creating reminders:**
```bash
bruba-reminders.sh add "Task title" --list "ListName" --due tomorrow --priority high
```

**Viewing reminders:**
```bash
bruba-reminders.sh list                # All uncompleted
bruba-reminders.sh list --overdue      # Overdue items
bruba-reminders.sh list Work           # Specific list
```

**Behavioral notes:**
- When <REDACTED-NAME> says "remind me..." → create reminder with `add`
- When asked about reminders → use default compact output (excludes completed)
- For counts → use `count` command (token-efficient)
- Use JSON output (`--json`) only when you need to parse specific fields

**⚠️ UUID Rule:** Always use UUIDs for edit/complete/delete. Display indices are broken.
- Output shows `[4DF7]` prefix — use that for edits
- Use `lookup "title"` to find UUID from title

**Common lists:** Reminders, Scheduled, Backlog, Work, Work Scheduled, Planning, Personal, Groceries

See `TOOLS.md` → Reminders for full command reference.
