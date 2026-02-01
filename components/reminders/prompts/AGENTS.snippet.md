## Reminder Management

**Creating reminders:** Use remindctl to add items to Apple Reminders.
**Maintenance:** cleanup script removes old completed reminders.

**Behavioral notes:**
- When <REDACTED-NAME> says "remind me..." → create reminder
- When asked about reminders → default to uncompleted, skip completed unless asked
- Use JSON output + UUIDs (never display indices)

**Cleanup tool:**
```bash
/Users/bruba/clawd/tools/cleanup-reminders.sh
```
Removes completed reminders older than 30 days.

See `TOOLS.md` → Reminders for remindctl usage and UUID rules.
