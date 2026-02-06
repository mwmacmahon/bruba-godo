---
type: doc
scope: reference
title: "Cron System"
description: "Cron job architecture, nightly reset cycle, and session-control integration"
---

# Cron System

Cron-based nightly maintenance for the Bruba multi-agent system. A single unified cycle handles session export, prep, reset, and wake across all agents.

> **Related docs:**
> - [Session Lifecycles](session-lifecycles.md) — Compaction, memoryFlush, continuation packets
> - [Channel Integrations](channel-integrations.md) — sessions_send limitations
> - [Session Control README](../components/session-control/README.md) — Reset/compact/status scripts

---

## Nightly Sequence Overview

One unified cycle, all managed by bruba-manager in isolated Haiku sessions:

```
4:00 AM  nightly-export    Manager → Main, Rex: "Run export prompt"
4:00 AM  nightly-prep      Manager → Main, Manager, Guru, Rex: "Write CONTINUATION.md"
4:08 AM  nightly-reset     Manager → exec session-reset.sh all (resets ALL agents incl. self)
4:10 AM  nightly-wake      Manager → Main, Manager, Web, Guru, Rex: "Good morning"
```

**Why one cycle?** The `session-reset.sh all` script resets every agent via `openclaw gateway call sessions.reset`, including Manager. No need for a separate Manager cycle run by Main.

**Why isolated sessions?** Each cron run gets a fresh context. No token accumulation in agents' main sessions.

---

## Registered Cron Jobs (Live on Bot)

As of 2026-02-06, 4 active nightly jobs:

| Job | Schedule | Agent | Method | Targets |
|-----|----------|-------|--------|---------|
| `nightly-export` | 4:00 AM daily | bruba-manager | sessions_send | Main, Rex |
| `nightly-prep` | 4:00 AM daily | bruba-manager | sessions_send | Main, Manager, Guru, Rex |
| `nightly-reset` | 4:08 AM daily | bruba-manager | exec session-reset.sh | All (Main, Manager, Guru, Rex) |
| `nightly-wake` | 4:10 AM daily | bruba-manager | sessions_send | Main, Manager, Web, Guru, Rex |

### How Reset Works

The critical fix: `nightly-reset` uses `exec` to run `session-reset.sh all`, which calls `openclaw gateway call sessions.reset` for each agent. This is the only confirmed working reset method.

Previous broken approach: `sessions_send "/reset"` — agents interpreted as text, no actual reset occurred.

---

## YAML Files

7 YAML files in `cronjobs/`, 4 active and 3 proposed:

### Active (synced to bot)

| File | Job Name | Description |
|------|----------|-------------|
| `nightly-export.yaml` | nightly-export | Manager tells export_cycle agents to run export prompt |
| `nightly-prep.yaml` | nightly-prep | Manager tells reset_cycle agents to write CONTINUATION.md |
| `nightly-reset.yaml` | nightly-reset | Manager execs session-reset.sh all |
| `nightly-wake.yaml` | nightly-wake | Manager wakes wake_cycle agents post-reset |

### Proposed (not synced)

| File | Job Name | Description |
|------|----------|-------------|
| `calendar-prep.yaml` | calendar-prep | 7am weekdays — check `icalBuddy` for prep-worthy meetings |
| `staleness-check.yaml` | staleness-check | Monday 10am — flag stale projects (14+ days) |
| `morning-briefing.yaml` | morning-briefing | 7:15am weekdays — daily summary to Signal |

Proposed jobs depend on the inbox/heartbeat pattern (see below) which is not yet operational.

---

## Cron Tooling

### sync-cronjobs.sh

Registers YAML jobs with the bot's OpenClaw instance.

```bash
./tools/sync-cronjobs.sh              # Sync all active YAML jobs
./tools/sync-cronjobs.sh --check      # Dry-run: show what would change
./tools/sync-cronjobs.sh --update     # Update existing jobs (schedule, message)
./tools/sync-cronjobs.sh --verbose    # Detailed output
```

Only syncs jobs with `status: active`. Detects schedule drift and warns about mismatches.

### generate-cronjobs.sh

Generates YAML files from templates in `templates/cronjobs/`. Uses agent lists from `config.yaml` (`reset_cycle`, `wake_cycle`, `export_cycle`) to build per-agent message blocks.

```bash
./tools/generate-cronjobs.sh              # Regenerate from templates
./tools/generate-cronjobs.sh --dry-run    # Preview without writing
./tools/generate-cronjobs.sh --verbose    # Show substitutions
```

**Template variables:**
- `{{AGENT_MESSAGES}}` — expanded to sessions_send instructions for each agent in the relevant cycle
- `{{HUMAN_NAME}}` — from agent's `identity.human_name` in config

**Continuation types:** Agents with `continuation_type: technical` get a technical-flavored prep message (topics worked on, debugging status, handoff notes) instead of the standard one.

**Static templates:** `nightly-reset.yaml` has no `{{AGENT_MESSAGES}}` — it uses a fixed `exec session-reset.sh all` command.

### config.yaml cycle membership

```yaml
agents:
  bruba-main:
    reset_cycle: true
    wake_cycle: true
    export_cycle: true
  bruba-manager:
    reset_cycle: true
    wake_cycle: true
  bruba-guru:
    reset_cycle: true
    wake_cycle: true
  bruba-rex:
    reset_cycle: true
    wake_cycle: true
    export_cycle: true
  bruba-web:
    wake_cycle: true    # wake only, no reset/export
```

---

## Managing Cron Jobs

```bash
# On the bot (via ./tools/bot)
openclaw cron list                           # List all registered jobs
openclaw cron trigger --name nightly-export  # Manual test run
openclaw cron disable --name <name>          # Pause job
openclaw cron enable --name <name>           # Resume job
openclaw cron remove <id>                    # Delete job (use ID, not name)
```

---

## Session Control Scripts

Deployed to `/Users/bruba/agents/bruba-shared/tools/` on the bot:

| Script | Purpose | Usage |
|--------|---------|-------|
| `session-status.sh` | Show session health | `session-status.sh all` or `session-status.sh <agent>` |
| `session-reset.sh` | Reset sessions via gateway call | `session-reset.sh all` or `session-reset.sh <agent>` |
| `session-compact.sh` | Force compaction via gateway call | `session-compact.sh <agent>` |
| `session-broadcast.sh` | Send templated messages to agents | `session-broadcast.sh prep\|export\|wake` |

All scripts are in the exec-approvals allowlist for bruba-main, bruba-manager, and bruba-rex.

See `components/session-control/README.md` for full documentation.

---

## Planned: Inbox + Heartbeat Architecture

The proposed detection jobs (reminder-check, staleness-check, calendar-prep) are designed around a file-based inbox pattern. **This is not yet operational** — Manager's heartbeat is disabled due to token burn issues.

### Design

```
┌─────────────────────────────────────────────────────────────────────┐
│                    DETECTION LAYER (Isolated Cron Jobs)             │
│  Fresh session per run (no context carryover)                      │
│  Haiku model (cheap)                                               │
│  Write findings to inbox/ files                                    │
│  Exit immediately after writing                                    │
│                                                                    │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐             │
│  │reminder-check│  │staleness     │  │calendar-prep │             │
│  │ 9am,2pm,6pm  │  │ Mon 10am     │  │ 7am weekdays │             │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘             │
│         │                 │                 │                      │
│         ▼                 ▼                 ▼                      │
│     inbox/reminder-   inbox/staleness-  inbox/calendar-            │
│     check.json        check.json        prep.json                  │
└─────────────────────────────────────────────────────────────────────┘
                             │
                             │ (files sit until next heartbeat)
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                 COORDINATION LAYER (Manager Heartbeat)              │
│  Runs every 15 min (Haiku model)                                   │
│  Reads inbox/ files                                                │
│  Cross-references state/ for history                               │
│  Decides: alert user? poke Main? ignore?                           │
│  Delivers to Signal                                                │
│  Deletes processed inbox files                                     │
│  Updates state/ files                                              │
└─────────────────────────────────────────────────────────────────────┘
```

### Blocker

Manager heartbeat is disabled in `config.yaml` (`heartbeat: false`). Was burning tokens on every 15-min cycle without useful output. Needs the inbox jobs registered first to have something to process.

---

## Cost Estimates

### Active (nightly cycle only)

| Component | Model | Frequency | Est. Monthly |
|-----------|-------|-----------|--------------|
| nightly-export | Haiku | 1x daily | ~$0.05 |
| nightly-prep | Haiku | 1x daily | ~$0.05 |
| nightly-reset | Haiku | 1x daily | ~$0.03 |
| nightly-wake | Haiku | 1x daily | ~$0.03 |
| **Active total** | | | **~$0.16/mo** |

### Proposed (if all enabled)

| Component | Model | Frequency | Est. Monthly |
|-----------|-------|-----------|--------------|
| reminder-check | Haiku | 3x daily | ~$0.20 |
| calendar-prep | Haiku | 5x weekly | ~$0.05 |
| morning-briefing | Sonnet | 5x weekly | ~$0.50 |
| staleness-check | Haiku | 1x weekly | ~$0.02 |
| Manager heartbeat | Haiku | 60x daily | ~$3.00 |
| **Proposed total** | | | **~$3.77/mo** |
