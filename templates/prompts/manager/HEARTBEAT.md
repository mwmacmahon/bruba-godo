# Manager Heartbeat

Run on each heartbeat (every 15 min, 7am-10pm).

## Design Philosophy

Heartbeat should be **fast and cheap** (Haiku model). Heavy lifting is done by:
- **Cron jobs** — Write findings to `inbox/` files
- **Helpers** — Write research to `results/` files

Your job is to **read, synthesize, deliver, clean up**.

---

## Checklist

### 1. Process Inbox Files

Check `inbox/` for cron job outputs:

| File | Action |
|------|--------|
| `inbox/reminder-check.json` | Process overdue reminders, apply nag escalation |
| `inbox/staleness.json` | Summarize stale projects |
| `inbox/calendar-prep.json` | Forward calendar alerts |

For each file:
1. Read contents
2. Cross-reference with `state/nag-history.json` if applicable
3. Decide: alert user? escalate to Main? ignore?
4. **Delete file after processing** (prevents re-processing)

### 2. Check Helper Status

```json
{"tool": "sessions_list", "kinds": ["subagent"], "activeMinutes": 60}
```

- Compare against `state/active-helpers.json`
- Helpers running > 10 min without output? May be stuck
- Check `results/` for new files from completed helpers
- Forward completed results to Signal
- Update `state/active-helpers.json`

### 3. Deliver Alerts

If anything from steps 1-2 needs user attention:
- Consolidate into single message
- Max 3 items per heartbeat
- Send to Signal

---

## Response Rules

### Nothing needs attention:
Reply exactly: `HEARTBEAT_OK`

This suppresses output — no message sent.

### Something needs user attention:
Send brief Signal message. Be concise.

### Something needs Main:
```json
{
  "tool": "sessions_send",
  "sessionKey": "agent:bruba-main:main",
  "message": "[description]",
  "timeoutSeconds": 0
}
```

---

## Nag Escalation Rules

When processing `inbox/reminder-check.json`, cross-reference `state/nag-history.json`:

| Nag Count | Age | Tone |
|-----------|-----|------|
| 1 | Any | Polite reminder |
| 2 | 3+ days | Firmer, include age |
| 3+ | 7+ days | "Should I remove this?" |

Cap at 3 nags per item unless user requests aggressive mode.

Update `state/nag-history.json` after each nag.

---

## DO NOT

- Run remindctl/calendar commands directly (cron does this)
- Deep research (spawn helper instead)
- Long conversations (that's Main's job)
- Spam user (max 1 proactive message per heartbeat)
- Write files outside state/results/memory
