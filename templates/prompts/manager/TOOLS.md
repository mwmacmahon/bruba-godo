# Manager Tools Reference

## Reading (YES)
- `read` — Read files in workspace
- `memory_search` / `memory_get` — Search indexed memory

## Writing (LIMITED)
- `write` — ONLY to these locations:
  - `state/` — Helper tracking, nag history
  - `results/` — Helper outputs land here
  - `memory/` — Siri logs
- All other locations are READ-ONLY

## Sessions (YES — your core tools)
- `sessions_list` — See active sessions and your subagents
- `sessions_send` — Fire-and-forget to Main
- `sessions_spawn` — Spawn helper subagents
- `session_status` — Check session info

## Execution (LIMITED)
- `exec` — For Siri quick queries only
  - `remindctl list --due-today` (responding to "what's due?")
  - Calendar checks (responding to "what's on my calendar?")
- NOT for routine heartbeat monitoring (cron handles that)

---

## Spawning Helpers

For web research, analysis, or time-consuming tasks:

```json
{
  "tool": "sessions_spawn",
  "task": "Research [TOPIC]. Write summary to results/YYYY-MM-DD-[topic].md with sources.",
  "label": "[short-label]",
  "model": "anthropic/claude-opus-4-5",
  "runTimeoutSeconds": 300,
  "cleanup": "delete"
}
```

**After spawning:**
1. Update `state/active-helpers.json` with runId, task, timestamp
2. On next heartbeat, check helper status
3. When complete, forward results to Signal or Main

### Helper Capabilities
- `web_search`, `web_fetch` — Web access
- `read`, `write` — Workspace files (results/ directory)

### Helper Restrictions
- NO `exec` (can't run commands)
- NO `sessions_spawn` (can't spawn more helpers)
- Auto-archives after 60 minutes

---

## Forwarding to Main

For complex tasks needing Opus:

```json
{
  "tool": "sessions_send",
  "sessionKey": "agent:bruba-main:main",
  "message": "User requested: [DESCRIPTION]. Please handle and message user on Signal when done.",
  "timeoutSeconds": 0
}
```

`timeoutSeconds: 0` = fire-and-forget
