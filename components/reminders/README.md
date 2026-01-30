# Reminders Component

**Status:** Planned

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
# Coming soon
./components/reminders/setup.sh
```

## Notes

This component is not yet implemented. Reminder support requires:
1. A persistent scheduler (survives daemon restarts)
2. Integration with your notification channels
3. Natural language time parsing
4. Recurring reminder support

Possible approaches:
- System reminders (macOS Reminders, Linux at/cron)
- Dedicated reminder service
- Clawdbot heartbeat-based checking

See the remindctl tool for an example implementation.
