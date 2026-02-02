---
version: 2.0.0
updated: 2026-02-01 23:45
type: packet
project: planning
tags: [bruba, openclaw, multi-agent, architecture, claude-code]
---

# Bruba Architecture 2.0: Complete Implementation Packet

**Created:** 2026-02-01
**For:** Claude Code on dadmini
**Status:** Phases 1-3 Complete, Phase 4+ Ready

---

## Executive Summary

This packet contains everything needed to complete Bruba's multi-agent architecture. It's self-contained — no need to reference other research docs.

### What's Done (Phases 1-3)

| Phase | Status | Notes |
|-------|--------|-------|
| OpenClaw Migration | ✅ | v2026.1.30 installed |
| Directory Restructure | ✅ | ~/agents/bruba-main/, ~/agents/bruba-manager/ |
| exec-approvals | ✅ | Paths updated |
| bruba-godo sync | ✅ | ~30 files updated |
| Manager Agent | ✅ | Configured with heartbeat |
| Agent-to-Agent | ✅ | agentToAgent enabled |

### What Remains (Phase 4+)

| Phase | Task | Priority |
|-------|------|----------|
| 4a | Delete web-reader, configure helper spawning | **HIGH** |
| 4b | Update Manager prompts for spawn pattern | **HIGH** |
| 4c | Add Manager state tracking | MEDIUM |
| 5 | Isolated cron for morning briefing | OPTIONAL |
| 6 | Siri integration | OPTIONAL |

---

## Part 1: Architecture Overview

### The Three-Tier Pattern

```
┌─────────────────────────────────────────────────────────────────────────┐
│  INPUT LAYER                                                             │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                              │
│  │  Signal  │  │   Siri   │  │ Heartbeat│                              │
│  │  (user)  │  │  (HTTP)  │  │  (timer) │                              │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘                              │
└───────┼─────────────┼─────────────┼────────────────────────────────────┘
        │             │             │
        ▼             │             │
┌───────────────────┐ │             │
│  bruba-main       │ │             │
│  ────────────     │ │             │
│  Model: Opus      │ │             │
│  Role: Primary    │ │             │
│  Heartbeat: OFF   │ │             │
│                   │ │             │
│  Handles:         │ │             │
│  • Conversations  │ │             │
│  • File ops       │ │             │
│  • Complex tasks  │ │             │
│                   │ │             │
│  For research:    │ │             │
│  sessions_send────┼─┼─────┐      │
│  to Manager       │ │     │      │
└───────────────────┘ │     │      │
                      │     │      │
                      ▼     ▼      ▼
              ┌─────────────────────────┐
              │  bruba-manager          │
              │  ──────────────         │
              │  Model: Sonnet/Haiku    │
              │  Role: Coordinator      │
              │  Heartbeat: 15m         │
              │                         │
              │  Handles:               │
              │  • Siri quick queries   │
              │  • Heartbeat checks     │
              │  • Spawning helpers     │
              │  • Tracking helper state│
              │                         │
              │  Tools: READ-ONLY       │
              │  + sessions_*           │
              └───────────┬─────────────┘
                          │
                          │ sessions_spawn
                          ▼
              ┌─────────────────────────┐
              │  Helper (ephemeral)     │
              │  ──────────────         │
              │  Model: Sonnet          │
              │  Lifetime: ~5-10 min    │
              │  Auto-archive: 60m      │
              │                         │
              │  Has:                   │
              │  • web_search           │
              │  • web_fetch            │
              │  • read (workspace)     │
              │  • write (results only) │
              │                         │
              │  On complete:           │
              │  • Write to file        │
              │  • Announce to Manager  │
              │  • Deliver to Signal    │
              └─────────────────────────┘
```

### Why This Architecture

| Problem | Solution |
|---------|----------|
| Opus heartbeats burn $$$  | Manager uses Haiku for heartbeats |
| Main can't see subagents it didn't spawn | Manager is sole spawner |
| web-reader is permanent overhead | Ephemeral helpers spawn on-demand |
| Helper results can be lost (gateway restart) | Helpers write to files first |
| Siri times out on Opus | Manager (fast) handles Siri, hands off to Main |

### Key Constraints (Verified)

| Feature | Status | Notes |
|---------|--------|-------|
| HTTP API agent targeting | ✅ Works | `model: "openclaw:bruba-manager"` |
| Webhook agent targeting | ❌ Not supported | Use HTTP API instead |
| sessions_send | ✅ Works | Fire-and-forget with `timeoutSeconds: 0` |
| sessions_spawn | ✅ Works | Non-blocking, auto-archive |
| Subagent nesting | ❌ Not allowed | Helpers cannot spawn helpers |
| Cross-agent visibility | ❌ Not allowed | Each agent sees only its own subagents |

### Tool Group Shorthand

OpenClaw supports `group:*` entries that expand to multiple tools:

| Group | Expands To |
|-------|------------|
| `group:fs` | read, write, edit, apply_patch |
| `group:runtime` | exec, bash, process |
| `group:sessions` | sessions_list, sessions_history, sessions_send, sessions_spawn, session_status |
| `group:memory` | memory_search, memory_get |
| `group:ui` | browser, canvas |
| `group:automation` | cron, gateway |

### Known Bugs to Work Around

| Bug | Impact | Workaround |
|-----|--------|------------|
| #3589 Heartbeat prompt bleeding | Cron jobs get HEARTBEAT_OK prompt | Use isolated cron for non-heartbeat tasks |
| #4355 Session lock contention | Concurrent helpers block each other | Cap `maxConcurrent: 2` |
| #5433 Compaction overflow | Auto-recovery sometimes fails | Monitor, restart gateway if stuck |
| #6295 Subagent model override | Model param in sessions_spawn ignored | Helpers inherit spawner's model (Sonnet) — OK for us |

---

## Part 2: Current Configuration

This is what's deployed after Phases 1-3:

### Agent List (in openclaw.json)

```json
{
  "agents": {
    "defaults": {
      "workspace": "/Users/bruba/.openclaw/workspace",
      "compaction": { "mode": "safeguard" },
      "maxConcurrent": 4
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
          "allow": ["read", "write", "edit", "apply_patch", "exec", 
                    "memory_search", "memory_get", "sessions_list", 
                    "sessions_send", "sessions_spawn", "session_status"],
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
          "allow": ["read", "sessions_list", "sessions_send", "sessions_spawn",
                    "session_status", "exec", "memory_search", "memory_get"],
          "deny": ["write", "edit", "apply_patch", "browser", "canvas",
                   "gateway", "cron", "nodes", "process"]
        }
      },
      {
        "id": "web-reader",
        "name": "Web Reader",
        "workspace": "/Users/bruba/agents/bruba-reader",
        "model": { "primary": "anthropic/claude-opus-4-5" },
        "sandbox": { "mode": "all", "scope": "agent" },
        "tools": {
          "allow": ["web_fetch", "web_search", "read"],
          "deny": ["exec", "write", "edit", "apply_patch", "memory_search"]
        }
      }
    ]
  },
  "tools": {
    "agentToAgent": {
      "enabled": true,
      "allow": ["bruba-main", "bruba-manager", "web-reader"]
    }
  },
  "bindings": [
    { "agentId": "bruba-main", "match": { "channel": "signal" } }
  ]
}
```

### Directory Structure

```
/Users/bruba/
├── agents/
│   ├── bruba-main/           # Main agent workspace
│   │   ├── IDENTITY.md
│   │   ├── SOUL.md
│   │   ├── TOOLS.md
│   │   ├── MEMORY.md
│   │   └── memory/
│   ├── bruba-manager/        # Manager workspace
│   │   ├── IDENTITY.md
│   │   ├── SOUL.md
│   │   ├── TOOLS.md
│   │   └── HEARTBEAT.md
│   └── bruba-reader/         # TO BE DELETED
│       └── SOUL.md
└── .openclaw/
    ├── openclaw.json
    ├── exec-approvals.json
    └── agents/
        ├── bruba-main/
        │   └── sessions/
        └── bruba-manager/
            └── sessions/
```

---

## Part 3: Phase 4a — Delete web-reader, Configure Helpers

### Step 1: Remove web-reader from config

Edit `/Users/bruba/.openclaw/openclaw.json`:

**DELETE this entire agent entry:**
```json
{
  "id": "web-reader",
  "name": "Web Reader",
  "workspace": "/Users/bruba/agents/bruba-reader",
  ...
}
```

**UPDATE agentToAgent.allow:**
```json
"agentToAgent": {
  "enabled": true,
  "allow": ["bruba-main", "bruba-manager"]  // REMOVED "web-reader"
}
```

### Step 2: Add subagents configuration

**ADD to agents.defaults:**
```json
{
  "agents": {
    "defaults": {
      "workspace": "/Users/bruba/.openclaw/workspace",
      "compaction": { "mode": "safeguard" },
      "maxConcurrent": 4,
      "subagents": {
        "maxConcurrent": 2,
        "archiveAfterMinutes": 60,
        "model": "anthropic/claude-sonnet-4-5"
      }
    },
    ...
  }
}
```

**ADD to bruba-manager specifically:**
```json
{
  "id": "bruba-manager",
  ...
  "subagents": {
    "maxConcurrent": 2,
    "archiveAfterMinutes": 60,
    "model": "anthropic/claude-sonnet-4-5"
  },
  ...
}
```

### Step 3: Configure subagent tool restrictions

**ADD to tools section:**
```json
{
  "tools": {
    "agentToAgent": {
      "enabled": true,
      "allow": ["bruba-main", "bruba-manager"]
    },
    "subagents": {
      "tools": {
        "allow": ["web_search", "web_fetch", "read", "write"],
        "deny": ["exec", "edit", "apply_patch", "gateway", "cron", 
                 "sessions_spawn", "browser", "canvas", "nodes"]
      }
    }
  }
}
```

### Step 4: Archive web-reader directory

```bash
# Archive, don't delete (in case we need to reference)
mv /Users/bruba/agents/bruba-reader /Users/bruba/agents/.archived-bruba-reader
```

### Step 5: Create helper results directory

```bash
mkdir -p /Users/bruba/agents/bruba-manager/results
```

### Verification

```bash
# Restart gateway
openclaw gateway restart

# Check agents
openclaw agents
# Should show: bruba-main, bruba-manager (NO web-reader)

# Check health
openclaw gateway health
```

---

## Part 4: Phase 4b — Update Manager Prompts

### File: /Users/bruba/agents/bruba-manager/TOOLS.md

**REPLACE entire file with:**

```markdown
# Manager Tools Reference

You are the Manager agent. You have LIMITED tools by design.

## Your Tools

### Reading (YES)
- `read` — Read files in your workspace
- `memory_search` / `memory_get` — Search indexed memory

### Sessions (YES)
- `sessions_list` — See active sessions and your subagents
- `sessions_send` — Send message to another agent's session
- `sessions_spawn` — Spawn a helper subagent
- `session_status` — Check session info

### Execution (LIMITED)
- `exec` — Run allowlisted commands only (remindctl, etc.)

### DENIED (by design)
- `write`, `edit`, `apply_patch` — You're read-only
- `browser`, `canvas`, `nodes` — Not your job
- `gateway`, `cron` — Admin tools

---

## Spawning Helpers

For web research, analysis, or time-consuming tasks, spawn a helper:

\`\`\`json
{
  "tool": "sessions_spawn",
  "task": "Research [TOPIC]. Write a summary to workspace file results/YYYY-MM-DD-[topic].md. Include sources.",
  "label": "[short-label]",
  "model": "anthropic/claude-sonnet-4-5",
  "runTimeoutSeconds": 300,
  "cleanup": "delete"
}
\`\`\`

### Helper Capabilities
- `web_search` — Search the web
- `web_fetch` — Fetch full page content
- `read` — Read files
- `write` — Write results to workspace

### Helper Restrictions
- NO `exec` (can't run commands)
- NO `sessions_spawn` (can't spawn more helpers)
- Auto-archives after 60 minutes
- Results announced to your session

### When to Spawn vs Handle Directly

**Spawn a helper for:**
- Web research requiring multiple searches
- Summarizing long documents
- Tasks taking > 30 seconds
- Anything needing web access

**Handle directly:**
- Quick calendar/reminder checks (use exec + remindctl)
- Status queries
- Forwarding to Main

---

## Forwarding to Main

For tasks requiring Main's full capabilities (file editing, complex conversations):

\`\`\`json
{
  "tool": "sessions_send",
  "sessionKey": "agent:bruba-main:main",
  "message": "User requested: [FULL DESCRIPTION]. Please handle and message user on Signal when done.",
  "timeoutSeconds": 0
}
\`\`\`

`timeoutSeconds: 0` = fire-and-forget (don't wait for response)

---

## Checking Helper Status

On heartbeat, check your helpers:

\`\`\`json
{
  "tool": "sessions_list",
  "kinds": ["subagent"],
  "activeMinutes": 60
}
\`\`\`

Look for:
- Helpers running > 10 minutes (may be stuck)
- New results in `results/` directory
- Completed helpers to report on

---

## State Tracking

Track active helpers in `state/active-helpers.json`:

\`\`\`json
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
\`\`\`

Update this file when you spawn or complete helpers.
```

### File: /Users/bruba/agents/bruba-manager/HEARTBEAT.md

**REPLACE entire file with:**

```markdown
# Manager Heartbeat

You are the Manager agent for Bruba. Your job is lightweight coordination.

## On Each Heartbeat

### 1. Check Calendar (if morning)
- Any events in next 2 hours?
- Only alert if action needed

### 2. Check Reminders
\`\`\`bash
remindctl list --due-within 2h
remindctl list --overdue
\`\`\`
- Alert on overdue items (max 3)
- Escalate if item overdue > 3 days

### 3. Check Helper Status
\`\`\`json
{"tool": "sessions_list", "kinds": ["subagent"], "activeMinutes": 60}
\`\`\`
- Any helpers running > 10 minutes? May be stuck
- Any completed results to forward?

### 4. Check State File
Read `state/active-helpers.json` for tracked tasks.

---

## Response Rules

### If nothing needs attention:
Reply exactly: `HEARTBEAT_OK`

This suppresses output — no message sent.

### If something needs user attention:
Send brief Signal message via your normal response.
Keep it under 3 items. Be concise.

### If something needs Main's capabilities:
\`\`\`json
{
  "tool": "sessions_send",
  "sessionKey": "agent:bruba-main:main",
  "message": "[description of what Main should do]",
  "timeoutSeconds": 0
}
\`\`\`

---

## DO NOT

- Do deep research (spawn a helper instead)
- Write files (you're read-only except state/)
- Engage in long conversations (that's Main's job)
- Spam the user (max 1 proactive message per heartbeat)

---

## Spawning Helpers from Heartbeat

If heartbeat reveals a task needing research:

\`\`\`json
{
  "tool": "sessions_spawn",
  "task": "Research [TOPIC]. Write summary to results/YYYY-MM-DD-[topic].md",
  "model": "anthropic/claude-sonnet-4-5",
  "runTimeoutSeconds": 300,
  "cleanup": "delete"
}
\`\`\`

Then respond `HEARTBEAT_OK` — you'll see results next heartbeat.
```

### File: /Users/bruba/agents/bruba-manager/IDENTITY.md

**REPLACE entire file with:**

```markdown
# Manager Identity

You are the **Manager** agent in Bruba's multi-agent system.

## Your Role

You are the **coordinator** — fast, lightweight, always watching.

- **Model:** Sonnet (Haiku for heartbeats)
- **Heartbeat:** Every 15 minutes, 7am-10pm
- **Purpose:** Triage, dispatch, monitor

## Your Relationship to Other Agents

### bruba-main (Opus)
- The primary conversational agent
- Has full file access, memory, tools
- You forward complex tasks to Main
- You spawn helpers on Main's behalf

### Helpers (ephemeral, Sonnet)
- You spawn them for research/analysis
- They auto-archive after completion
- You track their status
- You forward their results

## Your Capabilities

✅ Read files and memory
✅ Check calendar and reminders (via exec)
✅ Spawn helper subagents
✅ Send messages to Main
✅ Track helper state

❌ Write/edit files (except state tracking)
❌ Long conversations
❌ Deep research (spawn helper instead)
❌ Admin operations

## Your Personality

- Efficient, not chatty
- Proactive but not spammy
- Helpful coordinator, not the star
- "Fast. Light. Effective."
```

---

## Part 5: Phase 4c — Manager State Tracking

### Create state directory and file

```bash
mkdir -p /Users/bruba/agents/bruba-manager/state
mkdir -p /Users/bruba/agents/bruba-manager/results
```

### File: /Users/bruba/agents/bruba-manager/state/active-helpers.json

**Initial (empty):**
```json
{
  "helpers": [],
  "lastUpdated": null
}
```

**Schema (when populated):**
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

**Fields:**
- `runId` — From sessions_spawn response
- `childSessionKey` — For checking status via sessions_list
- `label` — Short identifier (matches sessions_spawn label)
- `task` — Full task description
- `spawnedAt` — ISO timestamp
- `status` — "running" | "completed" | "failed" | "stuck"
- `expectedFile` — Where helper should write results

### Update Manager tools.allow to include write for state/

**In openclaw.json, update bruba-manager:**

```json
{
  "id": "bruba-manager",
  ...
  "tools": {
    "allow": ["read", "sessions_list", "sessions_send", "sessions_spawn",
              "session_status", "exec", "memory_search", "memory_get",
              "write"],  // ADD write
    "deny": ["edit", "apply_patch", "browser", "canvas",
             "gateway", "cron", "nodes", "process"]
  }
}
```

**Add workspace restriction in SOUL.md:**

```markdown
## File Access

You can ONLY write to these locations:
- `state/` — For tracking helper status
- `results/` — For storing helper outputs (helpers write here)

All other locations are READ-ONLY for you.
```

---

## Part 6: Complete Configuration (Final State)

After Phase 4, your `openclaw.json` should look like:

```json
{
  "agents": {
    "defaults": {
      "workspace": "/Users/bruba/.openclaw/workspace",
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
        "subagents": {
          "maxConcurrent": 2,
          "archiveAfterMinutes": 60,
          "model": "anthropic/claude-sonnet-4-5"
        },
        "tools": {
          "allow": ["read", "write", "sessions_list", "sessions_send",
                    "sessions_spawn", "session_status", "exec",
                    "memory_search", "memory_get"],
          "deny": ["edit", "apply_patch", "browser", "canvas",
                   "gateway", "cron", "nodes", "process"]
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
        "allow": ["web_search", "web_fetch", "read", "write"],
        "deny": ["exec", "edit", "apply_patch", "gateway", "cron",
                 "sessions_spawn", "browser", "canvas", "nodes"]
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
    "bind": "loopback",
    "auth": {
      "mode": "token",
      "token": "YOUR_GATEWAY_TOKEN"
    }
  }
}
```

---

## Part 7: Testing Checklist

### Phase 4a Verification

```bash
# 1. Restart gateway
openclaw gateway restart

# 2. Check agents (should be 2, not 3)
openclaw agents
# Expected: bruba-main, bruba-manager

# 3. Check gateway health
openclaw gateway health
# Expected: healthy, <100ms

# 4. Check Signal probe
openclaw channels status
# Expected: signal: connected
```

### Phase 4b Verification (Manager Prompts)

```bash
# 1. Trigger a heartbeat manually
openclaw system heartbeat

# 2. Check Manager responds with HEARTBEAT_OK or alert
# (watch Signal or check sessions)

# 3. Test helper spawn via Signal
# Message Main: "Research the latest OpenClaw release notes"
# Main should forward to Manager, Manager should spawn helper
```

### Phase 4c Verification (State Tracking)

```bash
# 1. Check state file exists
cat /Users/bruba/agents/bruba-manager/state/active-helpers.json

# 2. After spawning a helper, verify state updated
# (Manager should write to state file)

# 3. Check results directory
ls /Users/bruba/agents/bruba-manager/results/
```

### Full Flow Test

1. **Message Main via Signal:** "Can you research what's new in OpenClaw this week?"
2. **Main should:** Forward to Manager via sessions_send
3. **Manager should:** Spawn a helper with sessions_spawn
4. **Helper should:** Research, write to results/, announce completion
5. **Manager should:** See results on next heartbeat, forward to Signal
6. **User receives:** Research summary on Signal

---

## Part 8: Phase 5 — Isolated Cron (Optional)

Morning briefing as isolated cron avoids Bug #3589 (heartbeat prompt bleeding).

### Add Cron Job

```bash
openclaw cron add \
  --name "morning-briefing" \
  --cron "0 7 * * 1-5" \
  --tz "America/New_York" \
  --session isolated \
  --model "anthropic/claude-sonnet-4-5" \
  --message "Create morning briefing:
1. Today's calendar events (check via remindctl or system)
2. Overdue reminders (remindctl list --overdue)
3. Weather if severe conditions
Keep it to 5 bullet points max." \
  --deliver \
  --channel signal
```

### Verify

```bash
# List cron jobs
openclaw cron list

# Check next run
openclaw cron status --id morning-briefing
```

---

## Part 9: Phase 6 — Siri Integration (Optional)

### Architecture

```
Siri → Shortcut → HTTP API → Manager → Response → Siri
                     │
                     └─(if complex)─→ sessions_send → Main
                                           │
                                           └─→ Signal
```

### HTTP API Targeting (Verified)

```bash
curl -X POST http://dadmini.ts.net:18789/v1/chat/completions \
  -H 'Authorization: Bearer YOUR_GATEWAY_TOKEN' \
  -H 'Content-Type: application/json' \
  -H 'x-openclaw-agent-id: bruba-manager' \
  -d '{
    "model": "openclaw",
    "messages": [{"role":"user","content":"What meetings do I have today?"}]
  }'
```

### iOS Shortcut: "Ask Bruba"

1. **Get Contents of URL**
   - URL: `http://dadmini.ts.net:18789/v1/chat/completions`
   - Method: POST
   - Headers:
     - `Authorization`: `Bearer YOUR_TOKEN`
     - `Content-Type`: `application/json`
     - `x-openclaw-agent-id`: `bruba-manager`
   - Request Body (JSON):
     ```json
     {
       "model": "openclaw",
       "messages": [{"role":"user","content":"VIA SIRI: [Shortcut Input]"}]
     }
     ```

2. **Get Dictionary Value**
   - Key: `choices[0].message.content`

3. **Speak Text** (result)

### Manager Prompt Addition for Siri

Add to IDENTITY.md:

```markdown
## Siri Requests

Messages starting with "VIA SIRI:" come from voice shortcuts.

For these:
- Respond concisely (Siri will speak it)
- Handle quick queries directly (time, calendar, reminders)
- For complex tasks: Acknowledge briefly, then forward to Main
  - "On it. I'll message you on Signal when done."
  - Then use sessions_send to Main
```

---

## Part 10: Rollback Plan

### If Phase 4 Breaks Things

```bash
# Revert to Phase 3 state (before helper changes)

# 1. Restore web-reader
mv /Users/bruba/agents/.archived-bruba-reader /Users/bruba/agents/bruba-reader

# 2. Remove subagents config from openclaw.json
# (manual edit - remove agents.defaults.subagents and tools.subagents)

# 3. Restore agentToAgent
# "allow": ["bruba-main", "bruba-manager", "web-reader"]

# 4. Restart
openclaw gateway restart
```

### If Everything Breaks

```bash
# Full rollback to single-agent
openclaw config set agents.list '[{"id":"bruba-main","default":true,"workspace":"/Users/bruba/agents/bruba-main"}]'
openclaw config set tools.agentToAgent.enabled false
openclaw gateway restart
```

### If Gateway Won't Start

```bash
# Check logs
openclaw gateway logs --tail 50

# Common fixes:
# - Port conflict: lsof -i :18789
# - Config syntax: jq . ~/.openclaw/openclaw.json
# - Service conflict: launchctl list | grep -i openclaw
```

---

## Part 11: Implementation Order

### Recommended Sequence

```
┌─────────────────────────────────────────┐
│ Phase 4a: Delete web-reader (10 min)    │
│ • Edit config                           │
│ • Archive directory                     │
│ • Restart gateway                       │
│ • Verify 2 agents                       │
└─────────────────┬───────────────────────┘
                  ▼
┌─────────────────────────────────────────┐
│ Phase 4b: Update Manager prompts (5 min)│
│ • Replace TOOLS.md                      │
│ • Replace HEARTBEAT.md                  │
│ • Replace IDENTITY.md                   │
└─────────────────┬───────────────────────┘
                  ▼
┌─────────────────────────────────────────┐
│ Phase 4c: State tracking (5 min)        │
│ • Create state/ and results/ dirs       │
│ • Create active-helpers.json            │
│ • Update tools.allow for write          │
└─────────────────┬───────────────────────┘
                  ▼
┌─────────────────────────────────────────┐
│ Test: Full flow verification (10 min)   │
│ • Trigger heartbeat                     │
│ • Test helper spawn                     │
│ • Verify Signal delivery                │
└─────────────────┬───────────────────────┘
                  ▼
┌─────────────────────────────────────────┐
│ Phase 5: Morning cron (optional, 5 min) │
└─────────────────┬───────────────────────┘
                  ▼
┌─────────────────────────────────────────┐
│ Phase 6: Siri integration (optional)    │
│ • Requires iOS Shortcut setup           │
│ • Test on phone                         │
└─────────────────────────────────────────┘
```

---

## Summary

| What | Status | Action |
|------|--------|--------|
| bruba-main | ✅ Done | No changes |
| bruba-manager | ✅ Done | Update prompts (4b) |
| web-reader | ❌ Delete | Phase 4a |
| Helper spawning | 🔲 Configure | Phase 4a |
| Manager prompts | 🔲 Update | Phase 4b |
| State tracking | 🔲 Create | Phase 4c |
| Morning cron | 🔲 Optional | Phase 5 |
| Siri | 🔲 Optional | Phase 6 |

**Total estimated time:** 30-45 minutes for required phases

---

## End of Packet

This packet is self-contained. All configuration, file contents, commands, and verification steps are included. No external references needed.

**Start with Phase 4a** — delete web-reader, configure helpers.