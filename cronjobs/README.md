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

Or via OpenClaw CLI:
- `openclaw cron list`
- `openclaw cron enable --name <name>`
- `openclaw cron trigger --name <name>`

## Architecture

Isolated cron jobs (Haiku) write findings to `inbox/` files.
Manager's heartbeat reads, processes, and deletes these files.
This avoids context bloat and Bug #3589 (heartbeat prompt bleeding).

## Current Status

| Job | Agent | Status | Schedule |
|-----|-------|--------|----------|
| nightly-export | bruba-manager → agents | ✅ active | 3:50am daily |
| nightly-reset-prep | bruba-manager → agents | ✅ active | 3:55am daily |
| nightly-reset-execute | bruba-manager → agents | ✅ active | 4:02am daily |
| nightly-reset-wake | bruba-manager → agents | ✅ active | 4:07am daily |
| pre-reset-continuity | bruba-main | ✅ active | 3:55am daily |
| guru-pre-reset-continuity | bruba-guru | 📋 proposed | 3:55am daily |
| reminder-check | bruba-manager | ✅ active | 9am, 2pm, 6pm daily |
| staleness-check | bruba-manager | 📋 proposed | Monday 10am |
| calendar-prep | bruba-manager | 📋 proposed | 7am weekdays |
| morning-briefing | bruba-manager | 📋 proposed | 7:15am weekdays |

**Note:** Nightly jobs run in sequence: export (3:50) → prep (3:55) → reset (4:02) → wake (4:07). Edit together to keep synchronized. The nightly-export job tells agents to follow Export.md's Non-Interactive Mode — see `components/distill/prompts/Export.md`.

## Adding New Jobs

1. Create `<job-name>.yaml` in this directory
2. Set `status: proposed`
3. Run `/cronjobs sync` to register
4. Test with `/cronjobs trigger <job-name>`
5. Enable with `/cronjobs enable <job-name>`

## Reference

See `docs/bruba-cron-job-system.md` for full implementation guide.
