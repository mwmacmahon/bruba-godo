---
version: 2.0.0
updated: 2026-02-01 23:30
type: packet
project: planning
tags: [packet, bruba, openclaw, multi-agent, claude-code, architecture]
---

# Bruba Architecture 2.0: Multi-Agent Implementation Packet

**Created:** 2026-02-01
**For:** Claude Code session on dadmini
**Scope:** Complete multi-agent architecture with ephemeral helpers
**Prerequisites:** OpenClaw migration complete, Phases 1-3 done

---

## Executive Summary

This packet finalizes the Bruba multi-agent architecture by:
1. Deleting `web-reader` (replaced by ephemeral helpers)
2. Configuring Manager to spawn helpers via `sessions_spawn`
3. Adding state tracking for helper lifecycle
4. Updating Manager prompts with spawn patterns
5. (Optional) Adding isolated cron for morning briefing

**Key architectural insight:** Helpers are ephemeral subagents spawned by Manager, not persistent agents. The old `web-reader` pattern was pre-multi-agent thinking.

---

## Current State (Post Phases 1-3)

### Agents Configured

| Agent | Model | Purpose | Status |
|-------|-------|---------|--------|
| bruba-main | Opus | Primary conversational agent | ✅ Working |
| bruba-manager | Sonnet (Haiku for heartbeat) | Coordinator, 15m heartbeat | ✅ Working |
| web-reader | Opus | Sandboxed web access | ❌ **DELETE** |

### Directory Structure

```
/Users/bruba/
├── .openclaw/
│   ├── openclaw.json           # Main config
│   ├── exec-approvals.json     # Allowlist
│   └── agents/
│       ├── bruba-main/
│       └── bruba-manager/
└── agents/
    ├── bruba-main/             # Main workspace
    │   ├── IDENTITY.md
    │   ├── SOUL.md
    │   ├── TOOLS.md
    │   └── MEMORY.md
    ├── bruba-manager/          # Manager workspace
    │   ├── IDENTITY.md
    │   ├── SOUL.md
    │   ├── TOOLS.md
    │   └── HEARTBEAT.md
    └── bruba-reader/           # ❌ DELETE THIS
```

---

## Target Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  User via Signal                                                     │
└───────────────────────────┬─────────────────────────────────────────┘
                            ▼
┌─────────────────────────────────────────────────────────────────────┐
│  bruba-main (Opus)                                                   │
│  • Handles conversations directly                                    │
│  • Full tools: read/write/edit/exec/memory/web                      │
│  • No heartbeat (saves tokens)                                       │
│  • For complex async tasks: sessions_send → Manager                  │
└───────────────────────────┬─────────────────────────────────────────┘
                            │ sessions_send (async, timeoutSeconds: 0)
                            ▼
┌─────────────────────────────────────────────────────────────────────┐
│  bruba-manager (Sonnet, Haiku for heartbeat)                         │
│  • Heartbeat every 15m (07:00-22:00)                                │
│  • Spawns helpers for research/tasks                                 │
│  • Tracks active helpers in state file                               │
│  • Read-only + session tools (no write/edit)                        │
│  • Forwards results to Signal or Main                                │
└───────────────────────────┬─────────────────────────────────────────┘
                            │ sessions_spawn (non-blocking)
                            ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Helper (ephemeral, inherits Sonnet from Manager)                    │
│  • Fresh context per task                                            │
│  • Default tools: read, write, exec, web_search, web_fetch          │
│  • Writes results to workspace file (announce is best-effort)       │
│  • Announces completion → Manager                                    │
│  • Auto-archives after 60 minutes                                    │
│  • CANNOT spawn sub-helpers (no nesting)                            │
└─────────────────────────────────────────────────────────────────────┘
```

### Why Manager Spawns (Not Main)

OpenClaw's visibility is per-agent scoped:
- `sessions_list` only shows that agent's subagents
- If Main spawned helpers, Manager couldn't monitor them
- Single coordination point simplifies lifecycle management

**Pattern:** Main → sessions_send → Manager → sessions_spawn → Helper

---

## Known Bugs and Workarounds

### Bug #6295: Subagent Model Override Broken (OPEN, 14 hours old)

**Impact:** `sessions_spawn` model parameter is ignored. Helpers inherit spawner's model.

**Workaround:** Since Manager uses Sonnet, helpers will use Sonnet. This is actually fine for our use case (Sonnet is good for research). If you need Haiku helpers, spawn from a Haiku-configured agent.

**Status:** Monitor for fix.

### Bug #4355: Session Lock Contention (OPEN)

**Impact:** Default 10-second session write lock causes concurrent subagents to block and terminate.

**Workaround:** Cap `maxConcurrent` at 2-3 until fixed.

```json
"subagents": {
  "maxConcurrent": 2
}
```

### Bug #3589: Heartbeat Prompt Bleeding (OPEN)

**Impact:** Cron events get heartbeat prompt appended, causing them to respond `HEARTBEAT_OK`.

**Workaround:** Use isolated cron for non-heartbeat scheduled tasks (morning briefing, daily digest).

### Bug #5433: Compaction Overflow Recovery (OPEN, 2 days old)

**Impact:** Auto-compaction may not trigger correctly on context overflow.

**Workaround:** Monitor for context issues; consider lower `contextTokens` limit for long-running agents.

---

## Verified Configuration Patterns

### HTTP API Agent Targeting ✓

```bash
# Method 1: Model field encoding
curl -X POST http://dadmini.ts.net:18789/v1/chat/completions \
  -H 'Authorization: Bearer $TOKEN' \
  -H 'Content-Type: application/json' \
  -d '{"model": "openclaw:bruba-manager", "messages": [...]}'

# Method 2: Header
curl -X POST http://dadmini.ts.net:18789/v1/chat/completions \
  -H 'x-openclaw-agent-id: bruba-manager' \
  -d '{"model": "openclaw", "messages": [...]}'
```

### sessions_send (Main → Manager) ✓

```json
{
  "tool": "sessions_send",
  "sessionKey": "agent:bruba-manager:main",
  "message": "Spawn a helper to research X and deliver to Signal",
  "timeoutSeconds": 0
}
```

- `timeoutSeconds: 0` = fire-and-forget
- Target doesn't need to be "awake" — message queues

### sessions_spawn (Manager → Helper) ✓

```json
{
  "tool": "sessions_spawn",
  "task": "Research X. Write results to workspace/results/YYYY-MM-DD-task.md",
  "label": "research-x",
  "runTimeoutSeconds": 300,
  "cleanup": "delete",
  "deliver": true,
  "channel": "signal"
}
```

- Non-blocking: returns `{ status: "accepted", runId, childSessionKey }`
- Results announced to requester chat
- `cleanup: "delete"` = archive immediately after announce
- Subagents CANNOT spawn sub-subagents

### Webhook Targeting ✗

Webhooks (`/hooks/agent`) do NOT support agent targeting.
**For Siri:** Use HTTP API with `x-openclaw-agent-id` header instead.

---

## Phase 4: Implementation Tasks

### 4a. Delete web-reader Agent

**Remove from openclaw.json agents.list:**
```json
// DELETE THIS ENTRY:
{
  "id": "web-reader",
  "name": "Web Reader",
  "workspace": "/Users/bruba/agents/bruba-reader",
  ...
}
```

**Remove from agentToAgent.allow:**
```json
// BEFORE:
"allow": ["bruba-main", "bruba-manager", "web-reader"]

// AFTER:
"allow": ["bruba-main", "bruba-manager"]
```

**Archive the directory:**
```bash
mv /Users/bruba/agents/bruba-reader /Users/bruba/agents/.archived-bruba-reader
```

### 4b. Configure Subagents Defaults

**Add to openclaw.json:**

```json
{
  "agents": {
    "defaults": {
      "subagents": {
        "maxConcurrent": 2,
        "archiveAfterMinutes": 60,
        "model": "anthropic/claude-sonnet-4-5"
      }
    }
  },
  "tools": {
    "subagents": {
      "tools": {
        "allow": ["read", "write", "exec", "web_search", "web_fetch", "memory_search", "memory_get"],
        "deny": ["gateway", "cron", "sessions_spawn", "browser", "canvas", "nodes"]
      }
    }
  }
}
```

**Note:** Due to Bug #6295, the `model` setting may be ignored. Helpers will inherit Manager's model (Sonnet), which is fine.

### 4c. Create Manager State Directory

```bash
mkdir -p /Users/bruba/agents/bruba-manager/state
mkdir -p /Users/bruba/agents/bruba-manager/results
```

**Create active-helpers.json:**
```json
{
  "helpers": [],
  "lastUpdated": null
}
```

### 4d. Update Manager TOOLS.md

**Replace /Users/bruba/agents/bruba-manager/TOOLS.md with:**

```markdown
# Manager Tools

You are the Manager agent. Your primary job is coordination, not execution.

## Available Tools

| Tool | Purpose | Use When |
|------|---------|----------|
| read | Read files | Checking state, reading results |
| exec | Run commands | remindctl, calendar checks |
| sessions_list | List sessions | Checking helper status |
| sessions_send | Message another agent | Forwarding to Main |
| sessions_spawn | Spawn helper | Research, complex tasks |
| session_status | Check session state | Debugging |
| memory_search | Search memory | Finding context |
| memory_get | Get memory entry | Retrieving specific info |

## Tools You DON'T Have

- write, edit, apply_patch (read-only for safety)
- browser, canvas (not needed for coordination)
- gateway, cron (dangerous)

---

## Spawning Helpers

For web research, analysis, or time-consuming tasks:

```json
{
  "tool": "sessions_spawn",
  "task": "Research [TOPIC]. Write detailed results to workspace/results/[DATE]-[SLUG].md before completing. Summarize key findings in your announce message.",
  "label": "[SHORT-LABEL]",
  "runTimeoutSeconds": 300,
  "cleanup": "delete",
  "deliver": true,
  "channel": "signal"
}
```

### Helper Behavior
- Helpers get: read, write, exec, web_search, web_fetch
- Helpers DON'T get: sessions_spawn (no nesting), gateway, cron
- Helpers auto-archive after 60 minutes
- Announce is best-effort — always require file output

### After Spawning
1. Update state/active-helpers.json with new helper
2. On next heartbeat, check sessions_list for status
3. Read results from workspace/results/ when complete
4. Forward relevant results to Signal or Main

---

## Forwarding to Main

For tasks requiring Main's full context or capabilities:

```json
{
  "tool": "sessions_send",
  "sessionKey": "agent:bruba-main:main",
  "message": "User requested: [FULL DESCRIPTION]. Please handle and message user on Signal when done.",
  "timeoutSeconds": 0
}
```

Use this when:
- Task needs Main's conversation history
- Task needs Main's write access
- Task is conversational, not research

---

## State Tracking

Track active helpers in `state/active-helpers.json`:

```json
{
  "helpers": [
    {
      "runId": "abc123",
      "childSessionKey": "agent:bruba-manager:subagent:xyz",
      "label": "research-quantum",
      "task": "Research quantum computing trends",
      "spawnedAt": "2026-02-01T22:00:00Z",
      "status": "running",
      "expectedFile": "results/2026-02-01-quantum.md"
    }
  ],
  "lastUpdated": "2026-02-01T22:00:00Z"
}
```

On each heartbeat:
1. Read state/active-helpers.json
2. Check sessions_list for each helper
3. If completed: read result file, update state, optionally forward
4. If stuck (>10min): consider stopping via /subagents stop

---

## Slash Commands (in Signal)

- `/subagents list` — Show active helpers
- `/subagents info <id>` — Details on specific helper
- `/subagents stop <id|all>` — Kill stuck helpers
- `/subagents log <id>` — View helper transcript
```

### 4e. Update Manager HEARTBEAT.md

**Replace /Users/bruba/agents/bruba-manager/HEARTBEAT.md with:**

```markdown
# Manager Heartbeat

You are the Manager agent. On each heartbeat, perform a quick coordination check.

## Heartbeat Checklist

### 1. Check Calendar (Quick)
- Any events in next 2 hours?
- If yes: Brief reminder to Signal

### 2. Check Reminders (Quick)
- Run: `remindctl list --due-today`
- Any overdue or due soon?
- If yes: Brief nag to Signal

### 3. Check Helpers (Important)
Read `state/active-helpers.json`:
- Any helpers listed?
- Use `sessions_list` to check their status
- If completed: 
  - Read their result file from `results/`
  - Forward summary to Signal if noteworthy
  - Update state file (remove from helpers array)
- If stuck (>10 minutes running):
  - Send warning to Signal
  - Consider `/subagents stop`

### 4. Check Result Files (Quick)
- Any new files in `results/` not yet forwarded?
- Forward summaries to Signal

## Response Rules

**If nothing needs attention:**
```
HEARTBEAT_OK
```
This suppresses output. Use it liberally — most heartbeats should be silent.

**If something needs user attention:**
Send a brief, actionable message to Signal. Examples:
- "📅 Meeting with X in 90 minutes"
- "⏰ Overdue: [reminder title] (3 days)"
- "✅ Research complete: [summary]. Full results in results/[file].md"

**If something needs Main's capabilities:**
Use sessions_send to forward to Main with context.

## DO NOT

- Do deep research yourself (spawn a helper)
- Write files (you're read-only)
- Engage in long conversations (that's Main's job)
- Spam the user with non-actionable info

## Token Budget

You run on Haiku during heartbeat. Be concise:
- Read only what you need
- Don't load full result files unless summarizing
- HEARTBEAT_OK early if nothing needs attention
```

### 4f. Verify Configuration

After all changes, restart and verify:

```bash
# Restart gateway
openclaw gateway restart

# Check health
openclaw gateway health

# List agents (should show 2: bruba-main, bruba-manager)
openclaw agents

# Check status
openclaw status
```

---

## Phase 5 (Optional): Isolated Cron for Morning Briefing

### Why Isolated Cron?

Bug #3589 causes heartbeat prompt to bleed into cron events. Morning briefing works better as isolated cron:
- Fresh context each run (no accumulated history)
- Exact timing (8 AM sharp)
- No HEARTBEAT_OK interference

### Configuration

```bash
openclaw cron add \
  --name "morning-briefing" \
  --cron "0 8 * * 1-5" \
  --tz "America/New_York" \
  --session isolated \
  --model "anthropic/claude-sonnet-4-5" \
  --thinking medium \
  --message "Create morning briefing:
1. Today's calendar events with any prep notes needed
2. Overdue reminders from remindctl --overdue
3. Any stale helpers or failed tasks from yesterday
4. Weather if severe conditions (skip if normal)

Be concise — aim for 3-5 bullet points max. Start with the most actionable item." \
  --deliver \
  --channel signal
```

### Verify

```bash
# List cron jobs
openclaw cron list

# Check job details
openclaw cron runs --id morning-briefing --limit 5
```

---

## Testing Checklist

### After Phase 4a (Delete web-reader)

- [ ] `openclaw agents` shows only bruba-main and bruba-manager
- [ ] No errors in gateway logs about missing agent
- [ ] Signal messages still route to bruba-main

### After Phase 4b (Subagents config)

- [ ] `openclaw config get agents.defaults.subagents` shows config
- [ ] `openclaw config get tools.subagents` shows tool restrictions

### After Phase 4c-e (Manager updates)

- [ ] Manager heartbeat still fires (check `openclaw status`)
- [ ] state/active-helpers.json exists and is valid JSON
- [ ] results/ directory exists

### Spawn Test

1. Send to Manager (via HTTP API or sessions_send):
   ```
   Spawn a helper to search the web for "OpenClaw multi-agent patterns" and summarize top 3 results.
   ```

2. Verify:
   - [ ] Helper spawns (check `/subagents list`)
   - [ ] Result file appears in `results/`
   - [ ] Announce delivers to Signal
   - [ ] Helper archives after completion

### End-to-End Test

1. Send to Main via Signal:
   ```
   Research the latest developments in quantum computing and message me a summary.
   ```

2. Main should:
   - [ ] Recognize this as async research task
   - [ ] Forward to Manager via sessions_send
   - [ ] Ack to user ("On it")

3. Manager should:
   - [ ] Spawn helper for research
   - [ ] Track in state file

4. Helper should:
   - [ ] Do web research
   - [ ] Write results to file
   - [ ] Announce completion

5. Manager (next heartbeat) should:
   - [ ] Detect completed helper
   - [ ] Forward summary to Signal
   - [ ] Clean up state

---

## Rollback Plan

### If Helper Spawning Breaks

```bash
# Disable subagents
openclaw config set agents.defaults.subagents.maxConcurrent 0
openclaw gateway restart
```

### If Manager Breaks

```bash
# Remove Manager from config entirely
ssh bruba 'cat ~/.openclaw/openclaw.json | jq "del(.agents.list[] | select(.id == \"bruba-manager\"))" > /tmp/oc.json && mv /tmp/oc.json ~/.openclaw/openclaw.json'
openclaw gateway restart
```

### If Agent-to-Agent Breaks

```bash
openclaw config set tools.agentToAgent.enabled false
openclaw gateway restart
```

### Full Rollback to Single Agent

```bash
# Reset to minimal config
cat > /tmp/minimal.json << 'EOF'
{
  "agents": {
    "list": [
      {
        "id": "bruba-main",
        "name": "Bruba",
        "default": true,
        "workspace": "/Users/bruba/agents/bruba-main",
        "model": { "primary": "anthropic/claude-opus-4-5" }
      }
    ]
  }
}
EOF

# Merge with existing config
ssh bruba 'jq -s ".[0] * .[1]" ~/.openclaw/openclaw.json /tmp/minimal.json > /tmp/merged.json && mv /tmp/merged.json ~/.openclaw/openclaw.json'
openclaw gateway restart
```

---

## Final Configuration Reference

After all changes, openclaw.json should include:

```json
{
  "agents": {
    "defaults": {
      "workspace": "~/.openclaw/workspace",
      "compaction": { "mode": "safeguard" },
      "maxConcurrent": 4,
      "subagents": {
        "maxConcurrent": 2,
        "archiveAfterMinutes": 60,
        "model": "anthropic/claude-sonnet-4-5"
      }
    },
    "list": [
      {
        "id": "bruba-main",
        "name": "Bruba",
        "default": true,
        "workspace": "/Users/bruba/agents/bruba-main",
        "model": {
          "primary": "anthropic/claude-opus-4-5",
          "fallbacks": ["anthropic/claude-sonnet-4-5"]
        },
        "heartbeat": { "every": "0m" },
        "sandbox": { "mode": "off" },
        "tools": {
          "allow": ["group:fs", "group:runtime", "group:sessions", "group:memory", "exec", "web_search", "web_fetch"],
          "deny": ["cron", "gateway"]
        }
      },
      {
        "id": "bruba-manager",
        "name": "Manager",
        "workspace": "/Users/bruba/agents/bruba-manager",
        "model": {
          "primary": "anthropic/claude-sonnet-4-5",
          "fallbacks": ["anthropic/claude-haiku-4-5"]
        },
        "heartbeat": {
          "every": "15m",
          "model": "anthropic/claude-haiku-4-5",
          "target": "signal",
          "activeHours": { "start": "07:00", "end": "22:00" }
        },
        "sandbox": { "mode": "off" },
        "tools": {
          "allow": ["read", "exec", "sessions_list", "sessions_send", "sessions_spawn", "session_status", "memory_search", "memory_get"],
          "deny": ["write", "edit", "apply_patch", "browser", "canvas", "gateway", "cron", "nodes"]
        }
      }
    ]
  },
  "bindings": [
    { "agentId": "bruba-main", "match": { "channel": "signal" } }
  ],
  "tools": {
    "agentToAgent": {
      "enabled": true,
      "allow": ["bruba-main", "bruba-manager"]
    },
    "subagents": {
      "tools": {
        "allow": ["read", "write", "exec", "web_search", "web_fetch", "memory_search", "memory_get"],
        "deny": ["gateway", "cron", "sessions_spawn", "browser", "canvas", "nodes"]
      }
    }
  },
  "channels": {
    "signal": {
      "enabled": true,
      "dmPolicy": "pairing"
    }
  },
  "hooks": {
    "enabled": true,
    "token": "YOUR_HOOK_TOKEN"
  },
  "gateway": {
    "port": 18789,
    "bind": "tailnet",
    "auth": {
      "mode": "token",
      "token": "YOUR_GATEWAY_TOKEN"
    }
  }
}
```

---

## Summary

| Phase | Task | Effort |
|-------|------|--------|
| 4a | Delete web-reader | 5 min |
| 4b | Configure subagents | 5 min |
| 4c | Create state directories | 2 min |
| 4d | Update TOOLS.md | 5 min |
| 4e | Update HEARTBEAT.md | 5 min |
| 4f | Verify and test | 15 min |
| 5 | Morning briefing cron (optional) | 10 min |

**Total estimated time:** 45-60 minutes

**This packet is self-contained.** You should not need to reference the research documents during implementation.

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 2.0.0 | 2026-02-01 | Complete rewrite: ephemeral helpers, state tracking, verified patterns |
| 1.0.0 | 2026-02-01 | Initial packet (migration + manager setup) |