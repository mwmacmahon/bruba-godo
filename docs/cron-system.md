---
type: doc
scope: reference
title: "Cron System"
description: "Cron job architecture, inbox handoff, and heartbeat coordination"
---

# Cron System

Cron-based proactive monitoring for the Bruba multi-agent system. Cron jobs detect conditions cheaply; Manager's heartbeat coordinates delivery.

> **Related docs:**
> - [Architecture Reference](architecture-masterdoc.md) — Part 5: Heartbeat vs Cron
> - [Operations Guide](operations-guide.md) — Starting/stopping, health checks
> - [Troubleshooting](troubleshooting.md) — Heartbeat and agent communication issues

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    DETECTION LAYER (Isolated Cron Jobs)             │
│  • Fresh session per run (no context carryover)                     │
│  • Haiku model (cheap)                                              │
│  • Write findings to inbox/ files                                   │
│  • Exit immediately after writing                                   │
│                                                                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │
│  │reminder-check│  │staleness     │  │calendar-prep │              │
│  │ 9am,2pm,6pm  │  │ Mon 10am     │  │ 7am weekdays │              │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘              │
│         │                 │                 │                       │
│         ▼                 ▼                 ▼                       │
│     inbox/reminder-   inbox/staleness-  inbox/calendar-             │
│     check.json        check.json        prep.json                   │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              │ (files sit until next heartbeat)
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                 COORDINATION LAYER (Manager Heartbeat)              │
│  • Runs every 15 min (Haiku model)                                  │
│  • Reads inbox/ files                                               │
│  • Cross-references state/ for history                              │
│  • Decides: alert user? poke Main? ignore?                          │
│  • Delivers to Signal                                               │
│  • Deletes processed inbox files                                    │
│  • Updates state/ files                                             │
└─────────────────────────────────────────────────────────────────────┘
```

### Why File-Based Handoff?

OpenClaw has a built-in `isolation.postToMainPrefix` feature, but it's affected by Bug #3589.

| Approach | Pros | Cons |
|----------|------|------|
| Direct heartbeat checks | Simple | Context bloat; every check adds tokens |
| `isolation.postToMainPrefix` | Built-in | Bug #3589 causes prompt bleeding |
| **File-based inbox** | Explicit control; no bloat; inspectable | Manual file management |

---

## Cron Jobs

| Job | Agent | Schedule | Status | Purpose |
|-----|-------|----------|--------|---------|
| **nightly-reset-prep** | bruba-manager | 3:55am daily | Active | Tell agents to write continuation packets |
| **nightly-reset-execute** | bruba-manager | 4:02am daily | Active | Send /reset to main and guru |
| **nightly-reset-wake** | bruba-manager | 4:07am daily | Active | Initialize fresh sessions |
| reminder-check | bruba-manager | 9am, 2pm, 6pm | Active | Detect overdue reminders |
| staleness-check | bruba-manager | Monday 10am | Proposed | Flag stale projects (14+ days) |
| calendar-prep | bruba-manager | 7am weekdays | Proposed | Surface prep-worthy meetings |
| morning-briefing | bruba-manager | 7:15am weekdays | Proposed | Daily summary to Signal |

---

## Manager Coordination Pattern (Nightly Reset)

**Important:** All nightly reset jobs route through bruba-manager, not directly to bruba-main.

**Why:** OpenClaw has a bug/limitation where `systemEvent` + `main session` = always disabled. The working pattern is `agentTurn` + `isolated session`, which fits manager's role as proactive coordinator.

```
3:55 AM  nightly-reset-prep
         └─→ Manager uses sessions_send to tell main/guru: "Write continuation packet"

4:02 AM  nightly-reset-execute
         └─→ Manager uses sessions_send to send "/reset" to main/guru

4:07 AM  nightly-reset-wake
         └─→ Manager uses sessions_send to ping main/guru/web: "Good morning"
```

**Benefits:**
- Main stays reactive (user conversations only)
- Each step can fail independently
- Manager already has sessions_send capability
- Uses `NO_REPLY` to avoid Signal spam

---

## Adding a Cron Job

```bash
openclaw cron add \
  --name "reminder-check" \
  --cron "0 9,14,18 * * *" \
  --tz "America/New_York" \
  --session isolated \
  --model "anthropic/claude-haiku-4-5" \
  --agent bruba-manager \
  --message 'Run: remindctl overdue

If overdue items exist, write JSON to inbox/reminder-check.json:
{
  "timestamp": "[ISO8601]",
  "source": "reminder-check",
  "overdue": [{"id": "[id]", "title": "[title]", "list": "[list]", "days_overdue": [N]}]
}

If NO overdue items, do NOT create the file. Exit silently.'
```

## Managing Cron Jobs

```bash
openclaw cron list                           # List all jobs
openclaw cron status --name reminder-check   # Check specific job
openclaw cron trigger --name reminder-check  # Manual test run
openclaw cron disable --name reminder-check  # Pause job
openclaw cron enable --name reminder-check   # Resume job
openclaw cron remove --name reminder-check   # Delete job
```

---

## State Files

Manager maintains persistent state in `state/`:

**state/nag-history.json** — Reminder escalation tracking
```json
{
  "reminders": {
    "ABC123": {
      "title": "Call dentist",
      "list": "Immediate",
      "firstSeen": "2026-01-28T09:00:00Z",
      "nagCount": 2,
      "lastNagged": "2026-02-01T14:00:00Z",
      "status": "active"
    }
  },
  "lastUpdated": "2026-02-02T09:00:00Z"
}
```

**Nag escalation rules:**
| Nag Count | Days Overdue | Tone |
|-----------|--------------|------|
| 1 | Any | Polite: "Reminder: [title] is overdue" |
| 2 | 3+ | Firmer: "[title] overdue for [N] days" |
| 3 | 7+ | Action: "[title] overdue [N] days — remove it?" |
| 4+ | Any | Stop nagging |

**state/staleness-history.json** — Project staleness tracking (same pattern, mention once/week max)

**state/pending-tasks.json** — Track async tasks sent to bruba-web
```json
{
  "tasks": [
    {
      "id": "task-abc123",
      "target": "bruba-web",
      "topic": "quantum computing trends",
      "sentAt": "2026-02-02T10:00:00Z",
      "expectedFile": "/Users/bruba/agents/bruba-web/results/2026-02-02-quantum.md",
      "status": "pending"
    }
  ],
  "lastUpdated": "2026-02-02T10:00:00Z"
}
```

---

## Heartbeat Processing Flow

```
ON HEARTBEAT:

1. PROCESS INBOX FILES
   for each file in inbox/:
     - reminder-check.json → apply nag rules, queue alerts
     - staleness-check.json → apply staleness rules, queue alerts
     - calendar-prep.json → queue prep notes
     - delete file after processing

2. CHECK PENDING ASYNC TASKS
   read state/pending-tasks.json
   for each task:
     if /Users/bruba/agents/bruba-web/results/[expectedFile] exists:
       → mark complete, read summary, queue for delivery
     elif sentAt > 15 min ago:
       → flag as potentially stuck
   update state/pending-tasks.json

3. COMPILE ALERTS
   alerts = []
   add reminder nags (max 3)
   add staleness warnings (max 1)
   add calendar prep notes (max 2)
   add completed research summaries

   if len(alerts) > 5: truncate to most important

4. DELIVER OR SUPPRESS
   if alerts is empty:
     respond "HEARTBEAT_OK"  # suppresses output
   else:
     send consolidated message to Signal

5. UPDATE STATE
   write nag-history.json, staleness-history.json
```

---

## Cost Estimates

| Component | Model | Frequency | Est. Monthly |
|-----------|-------|-----------|--------------|
| reminder-check | Haiku | 3x daily | ~$0.20 |
| staleness-check | Haiku | 1x weekly | ~$0.02 |
| calendar-prep | Haiku | 5x weekly | ~$0.05 |
| morning-briefing | Sonnet | 5x weekly | ~$0.50 |
| Manager heartbeat | Haiku | 60x daily | ~$3.00 |
| **Total (all enabled)** | | | **~$4/mo** |
