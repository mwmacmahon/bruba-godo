---
type: doc
scope: reference
title: "Cron System"
description: "Cron job architecture, nightly reset cycle, and session-control integration"
---

# Cron System

Cron-based nightly maintenance for the Bruba multi-agent system. A single unified cycle handles session export, prep, reset, and continuation loading across all agents.

> **Related docs:**
> - [Session Lifecycles](session-lifecycles.md) — Compaction, memoryFlush, continuation packets
> - [Channel Integrations](channel-integrations.md) — sessions_send limitations
> - [Session Control README](../components/session-control/README.md) — Reset/compact/status scripts

---

## Nightly Sequence Overview

One unified cycle, all managed by bruba-manager in isolated Sonnet sessions:

```
4:00 AM  nightly-export    Manager → Main, Rex: "Run export prompt"
4:00 AM  nightly-prep      Manager → Main, Manager, Guru, Rex: "Write CONTINUATION.md"
4:08 AM  nightly-reset     Manager (isolated) → exec session-reset.sh all
4:10 AM  nightly-continue  Manager → Main, Rex, Guru: "Load CONTINUATION.md"
```

**Why one job for all resets?** The isolated cron session runs `exec session-reset.sh all`, which resets all 5 agents (Main, Manager, Guru, Rex, Web) via `openclaw gateway call sessions.reset`. Because the cron runs in an isolated session, resetting Manager's main session doesn't affect the cron's own session.

**Why isolated sessions?** Each cron run gets a fresh context. No token accumulation in agents' main sessions.

**Why only 3 agents in continue?** Manager and Web don't need continuation packets — Manager is stateless coordination, Web is a stateless research service.

---

## Registered Cron Jobs (Live on Bot)

As of 2026-02-06, 4 active nightly jobs:

| Job | Schedule | Agent | Method | Targets |
|-----|----------|-------|--------|---------|
| `nightly-export` | 4:00 AM daily | bruba-manager | sessions_send | Main, Rex |
| `nightly-prep` | 4:00 AM daily | bruba-manager | sessions_send | Main, Manager, Guru, Rex |
| `nightly-reset` | 4:08 AM daily | bruba-manager | exec (isolated session) | All 5: Main, Manager, Guru, Rex, Web |
| `nightly-continue` | 4:10 AM daily | bruba-manager | sessions_send | Main, Rex, Guru |

### How Reset Works

`nightly-reset` runs `exec session-reset.sh all` directly in an isolated cron session. The script calls `openclaw gateway call sessions.reset` for each agent — all 5 including Manager itself. Because the cron runs in an isolated session (separate from Manager:main), resetting Manager's main session doesn't interfere with the cron execution.

**Previous approach (deprecated):** `sessions_send` delegation to Manager:main, which then ran exec. This was needed when Manager's `tools.allow` whitelist was missing `exec`. After fixing the whitelist, direct exec in isolated sessions works reliably.

**Broken approach (never worked):** `sessions_send "/reset"` — agents interpreted as text, no actual reset occurred.

---

## YAML Files

7 YAML files in `cronjobs/`, 4 active and 3 proposed:

### Active (synced to bot)

| File | Job Name | Description |
|------|----------|-------------|
| `nightly-export.yaml` | nightly-export | Manager tells export_cycle agents to run export prompt |
| `nightly-prep.yaml` | nightly-prep | Manager tells reset_cycle agents to write CONTINUATION.md |
| `nightly-reset.yaml` | nightly-reset | Manager resets all agents via exec in isolated session |
| `nightly-continue.yaml` | nightly-continue | Manager tells Main, Rex, Guru to load CONTINUATION.md |

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
./tools/sync-cronjobs.sh              # Sync all active YAML jobs (register new ones)
./tools/sync-cronjobs.sh --check      # Show drift across all fields (exits 1 if differences)
./tools/sync-cronjobs.sh --update     # Update existing jobs (all fields: schedule, message, description, model)
./tools/sync-cronjobs.sh --update --delete        # Also remove bot-only orphan jobs (prompts for confirmation)
./tools/sync-cronjobs.sh --update --delete --force # Remove orphans without prompting
./tools/sync-cronjobs.sh --verbose    # Detailed output
```

Compares all fields: schedule, message, description, model, agent, session. Detects orphan jobs on bot that aren't tracked in local YAML.

### generate-cronjobs.sh

Generates YAML files from templates in `templates/cronjobs/`. Uses agent lists from `config.yaml` (`reset_cycle`, `continue_cycle`, `export_cycle`) to build per-agent message blocks.

```bash
./tools/generate-cronjobs.sh              # Regenerate from templates
./tools/generate-cronjobs.sh --dry-run    # Preview without writing
./tools/generate-cronjobs.sh --verbose    # Show substitutions
```

**Template variables:**
- `{{AGENT_MESSAGES}}` — expanded to sessions_send instructions for each agent in the relevant cycle
- `{{HUMAN_NAME}}` — from agent's `identity.human_name` in config

**Continuation types:** Agents with `continuation_type: technical` get a technical-flavored prep message (topics worked on, debugging status, handoff notes) instead of the standard one.

**Static templates:** `nightly-reset.yaml` has no `{{AGENT_MESSAGES}}` — it uses a fixed `exec session-reset.sh all` pattern (direct exec in isolated session).

### config.yaml cycle membership

```yaml
agents:
  bruba-main:
    reset_cycle: true
    continue_cycle: true
    export_cycle: true
  bruba-manager:
    reset_cycle: true
  bruba-guru:
    reset_cycle: true
    continue_cycle: true
  bruba-rex:
    reset_cycle: true
    continue_cycle: true
    export_cycle: true
  bruba-web:
    reset_cycle: true
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

All scripts are in the exec-approvals allowlist for bruba-main, bruba-manager, bruba-guru, and bruba-rex.

See `components/session-control/README.md` for full documentation.

---

## Tool Availability in Cron Sessions

**Critical gotcha:** Isolated cron sessions inherit tool permissions from the agent's `tools.allow` whitelist in `openclaw.json`. If `tools.allow` is defined, **only those exact tools are provisioned** — it's a strict whitelist, not additive.

This caused the nightly-reset failure on 2026-02-06: Manager's `tools.allow` was a stale list from before session-control was added, missing `exec`. The model literally could not see exec as an available tool.

**Fix:** Always define explicit `tools_allow` for every agent in `config.yaml`, and run `sync-openclaw-config.sh` after changes. The sync script only writes `tools.allow` when `tools_allow` is defined in config.yaml — if missing, the stale value on the bot is preserved.

**Best practice for cron jobs that need exec:** Ensure `exec` is in the agent's `tools_allow` in `config.yaml`, then run `sync-openclaw-config.sh`. Direct exec in isolated sessions works reliably once the whitelist is correct.

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
| nightly-export | Sonnet | 1x daily | ~$0.15 |
| nightly-prep | Sonnet | 1x daily | ~$0.15 |
| nightly-reset | Sonnet (isolated) + Sonnet (main session) | 1x daily | ~$0.20 |
| nightly-continue | Sonnet | 1x daily | ~$0.10 |
| **Active total** | | | **~$0.60/mo** |

### Proposed (if all enabled)

| Component | Model | Frequency | Est. Monthly |
|-----------|-------|-----------|--------------|
| reminder-check | Haiku | 3x daily | ~$0.20 |
| calendar-prep | Haiku | 5x weekly | ~$0.05 |
| morning-briefing | Sonnet | 5x weekly | ~$0.50 |
| staleness-check | Haiku | 1x weekly | ~$0.02 |
| Manager heartbeat | Haiku | 60x daily | ~$3.00 |
| **Proposed total** | | | **~$3.77/mo** |
