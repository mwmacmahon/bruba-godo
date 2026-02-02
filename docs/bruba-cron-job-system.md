---
version: 1.0.0
updated: 2026-02-02 13:00
type: refdoc
project: planning
tags: [bruba, openclaw, cron, heartbeat, proactive, implementation]
---

# Bruba Cron System Implementation Guide

Implementation guide for setting up proactive monitoring via isolated cron jobs feeding into Manager's heartbeat. Based on OpenClaw best practices research (Feb 2026).

---

## Executive Summary

**Goal:** Proactive monitoring (reminders, staleness, calendar) without bloating Manager's context or triggering Bug #3589.

**Pattern:** Isolated cron jobs (Haiku, cheap) write findings to `inbox/` files. Manager's heartbeat (Haiku) reads, synthesizes, delivers, deletes.

**Implementation scope:**
- ✅ **IMPLEMENT NOW:** reminder-check (core functionality)
- 📋 **PROPOSED:** staleness-check, calendar-prep, morning-briefing (defined but not enabled)

**Why not just have Manager check everything on heartbeat?**
- Heartbeat runs every 15 min with full session context
- Running `remindctl`, checking files, etc. adds tokens to every heartbeat
- Bug #3589 causes heartbeat prompt to bleed into cron system events
- Isolated cron = fresh session each run = no context accumulation

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│  DETECTION LAYER (Isolated Cron Jobs)                                │
│  • Fresh session per run (no context carryover)                      │
│  • Haiku model (cheap)                                               │
│  • Write findings to inbox/ files                                    │
│  • Exit immediately after writing                                    │
│                                                                      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │
│  │reminder-check│  │staleness     │  │calendar-prep │              │
│  │ 9am,2pm,6pm  │  │ Mon 10am     │  │ 7am weekdays │              │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘              │
│         │                 │                 │                        │
│         ▼                 ▼                 ▼                        │
│  inbox/reminder-   inbox/staleness   inbox/calendar-                │
│  check.json        .json             prep.json                       │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              │ (files sit until next heartbeat)
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│  COORDINATION LAYER (Manager Heartbeat)                              │
│  • Runs every 15 min (Haiku model)                                   │
│  • Reads inbox/ files                                                │
│  • Cross-references state/ for history (nag counts, etc.)           │
│  • Decides: alert user? escalate to Main? ignore?                   │
│  • Delivers to Signal                                                │
│  • Deletes processed inbox files                                     │
│  • Updates state/ files                                              │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│  DELIVERY                                                            │
│  • Signal message to user (max 3 items per heartbeat)               │
│  • Or: sessions_send to Main for complex follow-up                  │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Why File-Based Handoff?

OpenClaw has a built-in `isolation.postToMainPrefix` feature that posts cron summaries directly to the main session. However:

| Approach | Pros | Cons |
|----------|------|------|
| `postToMainPrefix` | Built-in, automatic | Affected by Bug #3589; summaries accumulate in session |
| File-based inbox | Explicit control; avoids #3589; inspectable | Manual file management |

**Recommendation:** Use file-based handoff until Bug #3589 is fixed. It's more reliable and easier to debug.

### Bug #3589: Heartbeat Prompt Bleeding

**Status:** OPEN (as of Feb 2026)

When cron jobs fire system events, the heartbeat prompt ("reply HEARTBEAT_OK if nothing needs attention") gets appended to ALL events. This causes:
- Cron job purposes get hijacked
- Agent sees heartbeat prompt and replies `HEARTBEAT_OK`
- Actual cron task is ignored

**File-based handoff sidesteps this entirely** — cron writes to files, no system events involved.

---

## Cron Job Management System

Rather than manually running `openclaw cron add` commands, cron job definitions live in the bruba-godo repository as version-controlled files. A `/cronjobs` command manages which jobs are active.

### Directory Structure

```
bruba-godo/
└── cronjobs/
    ├── README.md              # This documentation
    ├── reminder-check.yaml    # ✅ ACTIVE
    ├── staleness-check.yaml   # 📋 PROPOSED (not enabled)
    ├── calendar-prep.yaml     # 📋 PROPOSED (not enabled)
    └── morning-briefing.yaml  # 📋 PROPOSED (not enabled)
```

### Job Definition Format

Each `.yaml` file defines one cron job:

```yaml
# cronjobs/reminder-check.yaml
name: reminder-check
description: Check for overdue reminders and write to Manager inbox
status: active  # active | proposed | disabled

schedule:
  cron: "0 9,14,18 * * *"
  timezone: America/New_York

execution:
  session: isolated
  model: anthropic/claude-haiku-4-5
  agent: bruba-manager

message: |
  Run this command and parse the output:
  remindctl list --overdue
  
  If there are overdue items, write JSON to inbox/reminder-check.json:
  {
    "timestamp": "[current ISO8601 timestamp]",
    "source": "reminder-check",
    "overdue": [
      {"id": "[reminder-id]", "title": "[title]", "list": "[list-name]", "days_overdue": [number]}
    ]
  }
  
  If there are NO overdue items, do NOT create the file. Just exit silently.

output:
  file: inbox/reminder-check.json
  schema: reminder-check  # references schema in this doc
```

### /cronjobs Command

Main should support a `/cronjobs` command for managing jobs:

```
/cronjobs                     # List all jobs with status
/cronjobs status              # Same as above
/cronjobs enable <name>       # Enable a proposed/disabled job
/cronjobs disable <name>      # Disable an active job
/cronjobs trigger <name>      # Manually trigger a job (for testing)
/cronjobs sync                # Sync bruba-godo definitions to OpenClaw
```

**Example output:**
```
📋 Bruba Cron Jobs

ACTIVE:
  ✅ reminder-check      0 9,14,18 * * *   Check overdue reminders

PROPOSED (not enabled):
  📋 staleness-check     0 10 * * 1        Weekly project staleness
  📋 calendar-prep       0 7 * * 1-5       Morning calendar prep
  📋 morning-briefing    15 7 * * 1-5      Daily briefing to Signal

DISABLED:
  (none)

Use /cronjobs enable <name> to activate a proposed job.
```

### Sync Logic

`/cronjobs sync` should:

1. Read all `.yaml` files from `bruba-godo/cronjobs/`
2. For each file with `status: active`:
   - Check if job exists in OpenClaw (`openclaw cron list`)
   - If not: run `openclaw cron add` with parameters from yaml
   - If exists but differs: update (remove + add)
3. For jobs in OpenClaw not in yaml files: warn (orphaned)
4. For jobs with `status: disabled`: ensure removed from OpenClaw

This keeps the source of truth in version control while OpenClaw is the runtime.

---

## Cron Job Specifications

### 1. Reminder Check ✅ IMPLEMENT NOW

**Purpose:** Detect overdue reminders for nag escalation.

**Status:** ACTIVE — implement this job now.

**Schedule:** 3x daily (9am, 2pm, 6pm) — frequent enough to catch items, not so frequent as to spam.

```bash
openclaw cron add \
  --name "reminder-check" \
  --cron "0 9,14,18 * * *" \
  --tz "America/New_York" \
  --session isolated \
  --model "anthropic/claude-haiku-4-5" \
  --agent bruba-manager \
  --message 'Run this command and parse the output:
remindctl list --overdue

If there are overdue items, write JSON to inbox/reminder-check.json:
{
  "timestamp": "[current ISO8601 timestamp]",
  "source": "reminder-check",
  "overdue": [
    {"id": "[reminder-id]", "title": "[title]", "list": "[list-name]", "days_overdue": [number]}
  ]
}

If there are NO overdue items, do NOT create the file. Just exit silently.

IMPORTANT: Only write the file if there are actual overdue items. Empty arrays waste processing.'
```

**Output schema:**
```json
{
  "timestamp": "2026-02-02T14:00:00Z",
  "source": "reminder-check",
  "overdue": [
    {"id": "ABC123", "title": "Call dentist", "list": "Immediate", "days_overdue": 5},
    {"id": "DEF456", "title": "Submit expenses", "list": "Scheduled", "days_overdue": 2}
  ]
}
```

---

### 2. Project Staleness Check 📋 PROPOSED

**Purpose:** Detect projects that haven't been touched in 14+ days.

**Status:** PROPOSED — define in bruba-godo but do not enable yet.

**Schedule:** Weekly (Monday 10am) — projects don't go stale overnight.

```bash
openclaw cron add \
  --name "staleness-check" \
  --cron "0 10 * * 1" \
  --tz "America/New_York" \
  --session isolated \
  --model "anthropic/claude-haiku-4-5" \
  --agent bruba-manager \
  --message 'Check for stale projects in ~/projects directory.

A project is "stale" if:
- It is a directory (not a file)
- No files inside have been modified in 14+ days
- It does NOT contain a .paused file (explicit pause marker)

Use find or stat to check modification times.

If there are stale projects, write JSON to inbox/staleness.json:
{
  "timestamp": "[current ISO8601 timestamp]",
  "source": "staleness-check", 
  "stale": [
    {"path": "[relative-path]", "name": "[project-name]", "days_stale": [number]}
  ]
}

If nothing is stale, do NOT create the file.

Sort by days_stale descending (oldest first).'
```

**Output schema:**
```json
{
  "timestamp": "2026-02-02T10:00:00Z",
  "source": "staleness-check",
  "stale": [
    {"path": "~/projects/old-experiment", "name": "old-experiment", "days_stale": 45},
    {"path": "~/projects/side-project", "name": "side-project", "days_stale": 21}
  ]
}
```

---

### 3. Calendar Prep Check 📋 PROPOSED

**Purpose:** Alert about upcoming meetings that need preparation.

**Status:** PROPOSED — define in bruba-godo but do not enable yet.

**Schedule:** Weekday mornings (7am Mon-Fri) — catch the day's meetings.

```bash
openclaw cron add \
  --name "calendar-prep" \
  --cron "0 7 * * 1-5" \
  --tz "America/New_York" \
  --session isolated \
  --model "anthropic/claude-haiku-4-5" \
  --agent bruba-manager \
  --message 'Check calendar for today'\''s events that might need preparation.

Use the appropriate calendar command to list today'\''s events.

An event "needs prep" if:
- It is a meeting (not an all-day event or reminder)
- It starts within the next 4 hours
- Title suggests preparation might help (contains: review, discuss, present, demo, interview, 1:1)

If there are events needing prep, write JSON to inbox/calendar-prep.json:
{
  "timestamp": "[current ISO8601 timestamp]",
  "source": "calendar-prep",
  "events": [
    {"title": "[event-title]", "start": "[ISO8601]", "hours_until": [number], "prep_hint": "[why it might need prep]"}
  ]
}

If no events need prep, do NOT create the file.

Keep prep_hint brief (under 10 words).'
```

**Output schema:**
```json
{
  "timestamp": "2026-02-02T07:00:00Z",
  "source": "calendar-prep",
  "events": [
    {"title": "Q1 Review with Leadership", "start": "2026-02-02T10:00:00Z", "hours_until": 3, "prep_hint": "review meeting - check slides"},
    {"title": "1:1 with Alex", "start": "2026-02-02T11:00:00Z", "hours_until": 4, "prep_hint": "1:1 - review action items"}
  ]
}
```

---

### 4. Morning Briefing (Fire-and-Forget) 📋 PROPOSED

**Purpose:** Daily summary delivered directly to Signal.

**Status:** PROPOSED — define in bruba-godo but do not enable yet.

**Schedule:** Weekday mornings (7:15am Mon-Fri) — after calendar-prep so it can reference that data.

**Note:** This one uses `--deliver` to send directly to Signal, bypassing Manager's inbox. It's truly fire-and-forget.

```bash
openclaw cron add \
  --name "morning-briefing" \
  --cron "15 7 * * 1-5" \
  --tz "America/New_York" \
  --session isolated \
  --model "anthropic/claude-sonnet-4-5" \
  --message 'Create a brief morning briefing for <REDACTED-NAME>.

Check:
1. Today'\''s calendar - any important meetings?
2. Weather - only mention if severe (storms, extreme temps)
3. Read inbox/calendar-prep.json if it exists - any prep needed?
4. Read inbox/reminder-check.json if it exists - any critical overdue items?

Format as 3-5 bullet points maximum. Be concise.

Example:
• 10am: Q1 Review - might want to check slides
• 2 overdue reminders (dentist 5 days, expenses 2 days)
• Clear weather, high 45°F

Do NOT read state/nag-history.json - that'\''s for Manager'\''s heartbeat processing, not briefings.' \
  --deliver \
  --channel signal
```

**Note:** Morning briefing runs at 7:15am, 15 minutes after calendar-prep (7:00am), so the inbox files exist when it runs. This is intentional sequencing.

---

## State File Specifications

These files live in Manager's `state/` directory and persist across heartbeats.

### state/active-helpers.json

Tracks spawned helpers. Manager updates this when spawning and when helpers complete.

```json
{
  "helpers": [
    {
      "runId": "run_abc123",
      "childSessionKey": "agent:bruba-manager:subagent:xyz789",
      "label": "quantum-research",
      "task": "Research quantum computing trends for 2026",
      "spawnedAt": "2026-02-02T10:00:00Z",
      "status": "running",
      "expectedFile": "results/2026-02-02-quantum.md"
    }
  ],
  "lastUpdated": "2026-02-02T10:00:00Z"
}
```

**Status values:** `running`, `completed`, `failed`, `stuck`, `archived`

**Manager heartbeat actions:**
1. Check `sessions_list` for actual subagent status
2. Compare against this file
3. If helper completed: check for `expectedFile`, update status, forward results
4. If helper running > 15 min: mark as potentially stuck
5. Clean up archived entries older than 24 hours

---

### state/nag-history.json

Tracks reminder nag escalation. Manager reads this when processing `inbox/reminder-check.json`.

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
    },
    "OLD789": {
      "title": "Old completed task",
      "list": "Scheduled",
      "firstSeen": "2026-01-15T09:00:00Z",
      "nagCount": 1,
      "lastNagged": "2026-01-16T09:00:00Z",
      "status": "resolved",
      "resolvedAt": "2026-01-20T10:00:00Z"
    }
  },
  "lastUpdated": "2026-02-02T09:00:00Z"
}
```

**Status values:** `active`, `resolved`, `snoozed`, `dismissed`

**Nag escalation rules:**

| Nag Count | Days Overdue | Tone | Message Template |
|-----------|--------------|------|------------------|
| 1 | Any | Polite | "Reminder: [title] is overdue" |
| 2 | 3+ | Firmer | "[title] has been overdue for [N] days" |
| 3 | 7+ | Action prompt | "[title] overdue [N] days — should I remove it?" |
| 4+ | Any | Skip | Don't nag again unless user requests |

**Manager heartbeat actions:**
1. Read `inbox/reminder-check.json`
2. For each overdue item, look up in `nag-history.json`
3. If not in history: add with nagCount=0
4. Apply escalation rules based on nagCount and days_overdue
5. If nag warranted: increment nagCount, update lastNagged, include in Signal alert
6. Delete `inbox/reminder-check.json` after processing
7. If item appears in history but NOT in current overdue list: mark as resolved

---

### state/staleness-history.json

Tracks project staleness alerts to avoid repeated nagging.

```json
{
  "projects": {
    "old-experiment": {
      "path": "~/projects/old-experiment",
      "firstFlagged": "2026-01-20T10:00:00Z",
      "lastMentioned": "2026-01-27T10:00:00Z",
      "mentionCount": 2,
      "status": "active"
    }
  },
  "lastUpdated": "2026-02-02T10:00:00Z"
}
```

**Staleness escalation:** Mention once per week maximum. After 3 mentions, only mention if explicitly asked.

---

## Manager Heartbeat Processing Logic

This is the logic Manager's HEARTBEAT.md should follow:

```
ON HEARTBEAT:

1. PROCESS INBOX FILES
   for each file in inbox/:
     - reminder-check.json → process_reminders()
     - staleness.json → process_staleness()
     - calendar-prep.json → process_calendar()
     - [any other].json → log unknown, delete
   
2. CHECK HELPER STATUS
   helpers = sessions_list(kinds=["subagent"], activeMinutes=60)
   tracked = read state/active-helpers.json
   
   for each tracked helper:
     if not in helpers list and status=="running":
       check results/ for expectedFile
       if file exists: mark completed, queue for delivery
       else: mark failed
   
   for each running helper:
     if running > 15 min: flag as potentially stuck
   
   update state/active-helpers.json

3. COMPILE ALERTS
   alerts = []
   
   add reminder nags (max 3)
   add staleness warnings (max 1)
   add calendar prep notes (max 2)
   add helper results summaries
   add stuck helper warnings
   
   if len(alerts) > 5: truncate to most important 5

4. DELIVER OR SUPPRESS
   if alerts is empty:
     respond "HEARTBEAT_OK"  # suppresses output
   else:
     send consolidated message to Signal
     
5. CLEANUP
   delete all processed inbox/ files
```

### process_reminders()

```
read inbox/reminder-check.json
read state/nag-history.json

for each overdue item:
  history = nag-history[item.id] or new entry
  
  should_nag = false
  tone = "polite"
  
  if history.nagCount == 0:
    should_nag = true
    tone = "polite"
  elif history.nagCount == 1 and item.days_overdue >= 3:
    should_nag = true
    tone = "firmer"
  elif history.nagCount == 2 and item.days_overdue >= 7:
    should_nag = true
    tone = "action_prompt"
  # else: don't nag (capped at 3)
  
  if should_nag:
    add to alerts with appropriate tone
    history.nagCount++
    history.lastNagged = now()

# Mark resolved items
for each item in nag-history where status=="active":
  if item.id not in current overdue list:
    item.status = "resolved"
    item.resolvedAt = now()

write state/nag-history.json
delete inbox/reminder-check.json
```

---

## Directory Setup Commands

Run these to initialize Manager's workspace structure:

```bash
# Create directory structure
mkdir -p /Users/bruba/agents/bruba-manager/inbox
mkdir -p /Users/bruba/agents/bruba-manager/state
mkdir -p /Users/bruba/agents/bruba-manager/results
mkdir -p /Users/bruba/agents/bruba-manager/memory

# Initialize state files (empty)
echo '{"helpers": [], "lastUpdated": null}' > /Users/bruba/agents/bruba-manager/state/active-helpers.json
echo '{"reminders": {}, "lastUpdated": null}' > /Users/bruba/agents/bruba-manager/state/nag-history.json
echo '{"projects": {}, "lastUpdated": null}' > /Users/bruba/agents/bruba-manager/state/staleness-history.json

# Set permissions
chmod 755 /Users/bruba/agents/bruba-manager/inbox
chmod 755 /Users/bruba/agents/bruba-manager/state
chmod 755 /Users/bruba/agents/bruba-manager/results
```

---

## Cron Job Management Commands

```bash
# List all cron jobs
openclaw cron list

# Check specific job status
openclaw cron status --name reminder-check

# View recent runs
openclaw cron runs --name reminder-check --limit 10

# Manually trigger a job (for testing)
openclaw cron trigger --name reminder-check

# Disable a job temporarily
openclaw cron disable --name reminder-check

# Re-enable
openclaw cron enable --name reminder-check

# Remove a job
openclaw cron remove --name reminder-check
```

---

## Testing Checklist

### Phase 1: Directory & Management Setup
- [ ] Create inbox/, state/, results/ directories
- [ ] Initialize empty state files
- [ ] Verify Manager can read/write to these locations
- [ ] Create bruba-godo/cronjobs/ directory
- [ ] Create job definition files (all 4)
- [ ] Implement /cronjobs command in Main

### Phase 2: Reminder Check (IMPLEMENT NOW)
- [ ] Add reminder-check job via `openclaw cron add` or `/cronjobs sync`
- [ ] Manually trigger: `/cronjobs trigger reminder-check`
- [ ] Verify inbox/reminder-check.json created (when overdue items exist)
- [ ] Trigger heartbeat, verify Manager processes file
- [ ] Verify state/nag-history.json updated
- [ ] Verify inbox file deleted after processing
- [ ] Verify Signal message delivered (or HEARTBEAT_OK if nothing)
- [ ] Test nag escalation (create test overdue reminder, wait for multiple cycles)

### Phase 3: Full Integration Test
- [ ] Let reminder-check run for 24-48 hours
- [ ] Verify no duplicate alerts
- [ ] Verify nag escalation works correctly
- [ ] Check Manager's context isn't bloating
- [ ] Verify `/cronjobs status` shows correct state

### Future Phases (when ready to enable more jobs)
- [ ] Enable staleness-check: `/cronjobs enable staleness-check`
- [ ] Enable calendar-prep: `/cronjobs enable calendar-prep`  
- [ ] Enable morning-briefing: `/cronjobs enable morning-briefing`
- [ ] Test each individually before enabling the next

---

## Rollback Plan

If reminder-check cron causes issues:

```bash
# Disable via command
/cronjobs disable reminder-check

# Or directly via OpenClaw
openclaw cron disable --name reminder-check

# Clear inbox to stop processing
rm -f /Users/bruba/agents/bruba-manager/inbox/*.json

# Manager heartbeat will now just check helpers and return HEARTBEAT_OK
```

To fully remove:

```bash
openclaw cron remove --name reminder-check

# Update bruba-godo/cronjobs/reminder-check.yaml status to "disabled"
```

### If Future Jobs Cause Issues

```bash
# Disable specific job
/cronjobs disable <job-name>

# Or disable all monitoring jobs
/cronjobs disable reminder-check
/cronjobs disable staleness-check
/cronjobs disable calendar-prep
/cronjobs disable morning-briefing

# Clear inbox
rm -f /Users/bruba/agents/bruba-manager/inbox/*.json
```

---

## Cost Estimates

Based on OpenClaw patterns research:

### Current (reminder-check only)

| Job | Model | Frequency | Est. Monthly Cost |
|-----|-------|-----------|-------------------|
| reminder-check | Haiku | 3x daily | ~$0.20 |
| Manager heartbeat | Haiku | 60x daily | ~$3.00 |
| **Total current** | | | **~$3.20/month** |

### Future (all jobs enabled)

| Job | Model | Frequency | Est. Monthly Cost |
|-----|-------|-----------|-------------------|
| reminder-check | Haiku | 3x daily | ~$0.20 |
| staleness-check | Haiku | 1x weekly | ~$0.02 |
| calendar-prep | Haiku | 5x weekly | ~$0.05 |
| morning-briefing | Sonnet | 5x weekly | ~$0.50 |
| Manager heartbeat | Haiku | 60x daily | ~$3.00 |
| **Total future** | | | **~$4.00/month** |

---

## References

- [OpenClaw Cron vs Heartbeat Docs](https://docs.openclaw.ai/automation/cron-vs-heartbeat)
- [OpenClaw Heartbeat Docs](https://docs.openclaw.ai/gateway/heartbeat)
- [GitHub Issue #3589: Heartbeat Prompt Bleeding](https://github.com/openclaw/openclaw/issues/3589)
- [GitHub Issue #1594: Context Bloat](https://github.com/openclaw/openclaw/issues/1594)
- [Bruba Multi-Agent Spec](./bruba-multi-agent-spec.md)

---

## Appendix: Complete Job Definition Files

Create these files in `bruba-godo/cronjobs/`:

### cronjobs/reminder-check.yaml

```yaml
name: reminder-check
description: Check for overdue reminders and write to Manager inbox
status: active

schedule:
  cron: "0 9,14,18 * * *"
  timezone: America/New_York

execution:
  session: isolated
  model: anthropic/claude-haiku-4-5
  agent: bruba-manager

message: |
  Run this command and parse the output:
  remindctl list --overdue

  If there are overdue items, write JSON to inbox/reminder-check.json:
  {
    "timestamp": "[current ISO8601 timestamp]",
    "source": "reminder-check",
    "overdue": [
      {"id": "[reminder-id]", "title": "[title]", "list": "[list-name]", "days_overdue": [number]}
    ]
  }

  If there are NO overdue items, do NOT create the file. Just exit silently.

  IMPORTANT: Only write the file if there are actual overdue items. Empty arrays waste processing.

output:
  file: inbox/reminder-check.json
  cleanup: manager-heartbeat  # Manager deletes after processing
```

### cronjobs/staleness-check.yaml

```yaml
name: staleness-check
description: Weekly check for stale projects (14+ days without modification)
status: proposed  # NOT ENABLED - change to 'active' when ready

schedule:
  cron: "0 10 * * 1"
  timezone: America/New_York

execution:
  session: isolated
  model: anthropic/claude-haiku-4-5
  agent: bruba-manager

message: |
  Check for stale projects in ~/projects directory.

  A project is "stale" if:
  - It is a directory (not a file)
  - No files inside have been modified in 14+ days
  - It does NOT contain a .paused file (explicit pause marker)

  Use find or stat to check modification times.

  If there are stale projects, write JSON to inbox/staleness.json:
  {
    "timestamp": "[current ISO8601 timestamp]",
    "source": "staleness-check",
    "stale": [
      {"path": "[relative-path]", "name": "[project-name]", "days_stale": [number]}
    ]
  }

  If nothing is stale, do NOT create the file.

  Sort by days_stale descending (oldest first).

output:
  file: inbox/staleness.json
  cleanup: manager-heartbeat
```

### cronjobs/calendar-prep.yaml

```yaml
name: calendar-prep
description: Morning check for calendar events that might need preparation
status: proposed  # NOT ENABLED - change to 'active' when ready

schedule:
  cron: "0 7 * * 1-5"
  timezone: America/New_York

execution:
  session: isolated
  model: anthropic/claude-haiku-4-5
  agent: bruba-manager

message: |
  Check calendar for today's events that might need preparation.

  Use the appropriate calendar command to list today's events.

  An event "needs prep" if:
  - It is a meeting (not an all-day event or reminder)
  - It starts within the next 4 hours
  - Title suggests preparation might help (contains: review, discuss, present, demo, interview, 1:1)

  If there are events needing prep, write JSON to inbox/calendar-prep.json:
  {
    "timestamp": "[current ISO8601 timestamp]",
    "source": "calendar-prep",
    "events": [
      {"title": "[event-title]", "start": "[ISO8601]", "hours_until": [number], "prep_hint": "[why it might need prep]"}
    ]
  }

  If no events need prep, do NOT create the file.

  Keep prep_hint brief (under 10 words).

output:
  file: inbox/calendar-prep.json
  cleanup: manager-heartbeat
```

### cronjobs/morning-briefing.yaml

```yaml
name: morning-briefing
description: Daily summary delivered directly to Signal (fire-and-forget)
status: proposed  # NOT ENABLED - change to 'active' when ready

schedule:
  cron: "15 7 * * 1-5"  # 15 min after calendar-prep
  timezone: America/New_York

execution:
  session: isolated
  model: anthropic/claude-sonnet-4-5  # Sonnet for better synthesis
  agent: bruba-manager

delivery:
  enabled: true
  channel: signal
  # This job delivers directly to Signal, bypassing Manager inbox

message: |
  Create a brief morning briefing for <REDACTED-NAME>.

  Check:
  1. Today's calendar - any important meetings?
  2. Weather - only mention if severe (storms, extreme temps)
  3. Read inbox/calendar-prep.json if it exists - any prep needed?
  4. Read inbox/reminder-check.json if it exists - any critical overdue items?

  Format as 3-5 bullet points maximum. Be concise.

  Example:
  • 10am: Q1 Review - might want to check slides
  • 2 overdue reminders (dentist 5 days, expenses 2 days)
  • Clear weather, high 45°F

  Do NOT read state/nag-history.json - that's for Manager's heartbeat processing, not briefings.

output:
  direct: signal  # No inbox file, delivers directly
```

### cronjobs/README.md

```markdown
# Bruba Cron Jobs

This directory contains cron job definitions for Bruba's proactive monitoring system.

## Job Status Values

- `active` — Job is enabled and running in OpenClaw
- `proposed` — Job is defined but not yet enabled
- `disabled` — Job was active but has been turned off

## Managing Jobs

From Main agent:
- `/cronjobs` — List all jobs with status
- `/cronjobs enable <name>` — Enable a proposed job
- `/cronjobs disable <name>` — Disable an active job
- `/cronjobs trigger <name>` — Manually run a job
- `/cronjobs sync` — Sync definitions to OpenClaw

## Architecture

Isolated cron jobs (Haiku) write findings to `inbox/` files.
Manager's heartbeat reads, processes, and deletes these files.
This avoids context bloat and Bug #3589 (heartbeat prompt bleeding).

## Current Status

| Job | Status | Schedule |
|-----|--------|----------|
| reminder-check | ✅ active | 9am, 2pm, 6pm daily |
| staleness-check | 📋 proposed | Monday 10am |
| calendar-prep | 📋 proposed | 7am weekdays |
| morning-briefing | 📋 proposed | 7:15am weekdays |

## Adding New Jobs

1. Create `<job-name>.yaml` in this directory
2. Set `status: proposed`
3. Run `/cronjobs sync` to register
4. Test with `/cronjobs trigger <job-name>`
5. Enable with `/cronjobs enable <job-name>`
```