---
version: 3.0.0
updated: 2026-02-02 18:30
type: refdoc
project: planning
tags: [bruba, openclaw, multi-agent, architecture, security, cron]
---

# Bruba Multi-Agent Architecture Reference

Comprehensive reference for the Bruba multi-agent system. Covers the peer agent model, tool policy mechanics, cron-based proactive monitoring, and security isolation via node host.

---

## Executive Summary

Bruba uses a **three-agent architecture** with two peer agents and one service agent:

| Agent | Model | Role | Web Access |
|-------|-------|------|------------|
| **bruba-main** | Opus | Reactive — user conversations, file ops, complex reasoning | ❌ via bruba-web |
| **bruba-manager** | Sonnet/Haiku | Proactive — heartbeat, cron coordination, monitoring | ❌ via bruba-web |
| **bruba-web** | Sonnet | Service — stateless web search, prompt injection barrier | ✅ Direct |

**Key architectural insight:** OpenClaw's tool inheritance model means subagents cannot have tools their parent lacks. Web isolation requires a **separate agent** (bruba-web), not subagent spawning. Main and Manager are peers that communicate as equals; Web is a passive service both peers use.

**Security model:** Node host architecture (planned) sandboxes agents in Docker, preventing filesystem access to exec allowlists. Defense in depth: capability restrictions + sandbox isolation + exec allowlists.

---

## Part 1: Agent Topology

### Peer Model (Not Hierarchical)

```
┌─────────────────────────────────────────────────────────────────────┐
│                         INPUT SOURCES                               │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐            │
│  │  Signal  │  │   Siri   │  │ Heartbeat│  │   Cron   │            │
│  │  (user)  │  │  (HTTP)  │  │  (timer) │  │ (inbox)  │            │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘            │
└───────┼─────────────┼─────────────┼─────────────┼──────────────────┘
        │             │             │             │
        ▼             │             │             │
┌───────────────────┐ │             │             │
│    bruba-main     │ │             │             │
│    ───────────    │ │             │             │
│  Model: Opus      │ │             └─────────────┼───────┐
│  Role: Reactive   │ │                           │       │
│                   │ │                           ▼       │
│  • Conversations  │ │             ┌─────────────────────┴─────┐
│  • File ops       │ │             │      bruba-manager        │
│  • Complex tasks  │ │             │      ──────────────       │
│  • Memory/PKM     │ │             │  Model: Sonnet (Haiku HB) │
│                   │◄─────────────►│  Role: Proactive          │
│                   │ sessions_send │                           │
│                   │               │  • Heartbeat checks       │
└─────────┬─────────┘               │  • Cron job processing    │
          │                         │  • Inbox → delivery       │
          │                         │  • Siri sync queries      │
          │                         └─────────────┬─────────────┘
          │                                       │
          │ sessions_send                         │ sessions_send
          │                                       │
          └───────────────┐           ┌───────────┘
                          ▼           ▼
                ┌─────────────────────────────────┐
                │          bruba-web              │
                │          ─────────              │
                │  Model: Sonnet                  │
                │  Role: Service (passive)        │
                │                                 │
                │  • Stateless web search         │
                │  • Prompt injection barrier     │
                │  • No memory, no initiative     │
                │  • Returns structured summary   │
                └─────────────────────────────────┘
```

### Why Peers, Not Hierarchy

Main and Manager are **equals with different orientations**:

| Aspect | bruba-main | bruba-manager |
|--------|------------|---------------|
| Orientation | Reactive | Proactive |
| Trigger | User messages | Heartbeat, cron, Siri |
| Strength | Deep reasoning, file ops | Fast triage, coordination |
| Model cost | Opus (expensive) | Sonnet/Haiku (cheap) |

Neither is subordinate. They communicate via `sessions_send` as equals:
- Manager notices something → pokes Main to handle it
- Main needs background task → sends to Manager
- Both use bruba-web for searches

**bruba-web is a service**, not a peer:
- No agency or initiative
- Stateless — no memory, no context carryover
- Passive — only responds when asked
- Single purpose — web search + summarize

---

## Part 2: Tool Policy Mechanics

### The Inheritance Model

OpenClaw evaluates tool availability through eight precedence levels:

1. Tool profile (`tools.profile`)
2. Global tool policy (`tools.allow/deny`)
3. Provider policy (`tools.byProvider`)
4. Agent policy (`agents.list[].tools`)
5. Agent provider policy (`agents.list[].tools.byProvider`)
6. Sandbox policy (`tools.sandbox.tools`)
7. Subagent policy (`tools.subagents.tools`)

**Critical rule:** Each level can further restrict tools, but **cannot grant back** denied tools from earlier levels.

### The Ceiling Effect

| Mechanism | Effect on Agent | Effect on Subagents |
|-----------|-----------------|---------------------|
| `deny: ["web_search"]` | Blocked | **Propagates** — subagents can't restore |
| Not in `allow` list | Blocked | **Also propagates** — allowlist is the ceiling |

When an agent uses an explicit allowlist, that becomes the **ceiling** for all subagents. The subagent policy can only select from or further restrict what's already allowed — it cannot add tools the parent doesn't have.

### Why Subagents Can't Have Web Access

```
Main config:
  tools.deny: ["web_search", "web_fetch"]

Subagent config (tools.subagents.tools):
  allow: ["web_search", "read"]  # ← IGNORED for web_search
```

The subagent policy isn't evaluated in isolation. It's evaluated **after** the parent's restrictions have established the ceiling. Since Main denies `web_search`, subagents can never get it regardless of `tools.subagents.tools` configuration.

This is **by design** — it prevents privilege escalation through subagent spawning.

### The Correct Pattern: Separate Agents

Separate agents have independent tool configs at the **agent level** (step 4 in the hierarchy). They don't inherit restrictions from other agents.

```yaml
bruba-main:
  tools.deny: ["web_search", "web_fetch", "browser"]
  # Main cannot search

bruba-web (SEPARATE AGENT):
  tools.allow: ["web_search", "web_fetch", "read"]
  tools.deny: ["exec", "write", "sessions_spawn"]
  # Independent config — not constrained by Main's restrictions
```

Communication happens via `sessions_send` (agent-to-agent messaging), not `sessions_spawn` (parent-child subagent).

---

## Part 3: Agent Specifications

### bruba-main

**Purpose:** Primary conversational agent. Handles user interactions, file operations, complex reasoning, PKM work.

**Model:** Opus (with Sonnet fallback)

**Capabilities:**
| Tool | Status | Notes |
|------|--------|-------|
| read, write, edit, apply_patch | ✅ | Full file access within workspace |
| exec | ✅ | Via allowlist only |
| memory_search, memory_get | ✅ | PKM integration |
| sessions_send | ✅ | Communicate with Manager and Web |
| sessions_spawn | ❌ | Not needed — uses bruba-web instead |
| web_search, web_fetch | ❌ | Security isolation — use bruba-web |
| browser, canvas | ❌ | Not needed |
| cron, gateway | ❌ | Admin tools |

**Heartbeat:** Disabled (`every: "0m"`)

**Bindings:** Signal DM (user-facing channel)

**Workspace:** `/Users/bruba/agents/bruba-main/`

---

### bruba-manager

**Purpose:** Proactive coordination. Handles heartbeat monitoring, cron job processing, Siri sync queries, and poking Main when action needed.

**Model:** Sonnet primary, Haiku for heartbeats

**Capabilities:**
| Tool | Status | Notes |
|------|--------|-------|
| read | ✅ | Read inbox, state files |
| write | ✅ | Update state files only |
| exec | ✅ | remindctl, calendar commands |
| sessions_send | ✅ | Communicate with Main and Web |
| sessions_list, session_status | ✅ | Monitor system state |
| memory_search, memory_get | ✅ | Limited memory access |
| edit, apply_patch | ❌ | Not a file editor |
| web_search, web_fetch | ❌ | Security isolation — use bruba-web |
| browser, canvas | ❌ | Not needed |
| cron, gateway | ❌ | Admin tools |

**Heartbeat:** Every 15 minutes, 7am-10pm, Haiku model

**Workspace:** `/Users/bruba/agents/bruba-manager/`

**Directory Structure:**
```
bruba-manager/
├── inbox/           # Cron job outputs (processed and deleted)
├── state/           # Persistent tracking (nag history, etc.)
├── results/         # Research outputs (from bruba-web)
└── memory/          # Agent memory
```

---

### bruba-web

**Purpose:** Stateless web research service. Provides prompt injection barrier between raw web content and peer agents.

**Model:** Sonnet

**Capabilities:**
| Tool | Status | Notes |
|------|--------|-------|
| web_search | ✅ | Core function |
| web_fetch | ✅ | Core function |
| read | ✅ | Read task instructions |
| exec | ❌ | No command execution |
| write, edit | ❌ | No file modification |
| memory_* | ❌ | Stateless — no memory |
| sessions_send | ❌ | Can't initiate communication |
| sessions_spawn | ❌ | Can't create subagents |
| browser | ❌ | Search/fetch only |

**Heartbeat:** Disabled

**Memory:** Disabled (`memorySearch.enabled: false`)

**Sandbox:** Full Docker isolation (bridge network for web access)

**Security Properties:**
- Raw web content stays in bruba-web's context
- Only structured summary crosses to caller
- If web content contains injection attempts, they're processed in isolation
- Cannot affect Main or Manager's memory/state

**Workspace:** Minimal — security instructions only

---

## Part 4: Communication Patterns

### Main Requests Web Search

```
User → Signal → bruba-main
Main: "I'll look that up"
Main → sessions_send("Search for X, summarize findings") → bruba-web
bruba-web: [searches, fetches, processes in sandbox]
bruba-web → returns structured summary
Main → receives summary (no raw web content exposure)
Main → Signal: "Here's what I found..."
```

### Manager Requests Web Search

```
Manager heartbeat → checks inbox → finds task needing research
Manager → sessions_send("Research Y for context") → bruba-web
bruba-web → returns structured summary
Manager → writes summary to results/ or sends to Signal
```

### Manager Pokes Main

```
Manager heartbeat → notices something requiring Main's attention
Manager → sessions_send("User has 3 overdue items, might want to check in") → bruba-main
Main → handles however appropriate (may message user, may just note)
Manager → Signal: "Heads up, I noticed X and let Bruba know"
```

### Siri Integration

```
Siri sync ("Hey Siri, ask Bruba..."):
  Shortcut → HTTPS → bruba-manager
  Manager answers directly (fast, Sonnet)
  Manager → HTTP response → Siri speaks

Siri async ("Hey Siri, tell Bruba..."):
  Shortcut → HTTPS → bruba-main
  Main processes, responds via Signal
  Siri gets "Got it, I'll message you" acknowledgment
```

---

## Part 5: Cron System

### Architecture Overview

**Problem:** Running checks directly in Manager's heartbeat causes context bloat and is affected by Bug #3589 (heartbeat prompt bleeding).

**Solution:** Isolated cron jobs write findings to `inbox/` files. Manager's heartbeat reads, processes, delivers, and deletes.

```
┌─────────────────────────────────────────────────────────────────────┐
│                 DETECTION LAYER (Isolated Cron Jobs)                │
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
└─────────────────────────────────────────────────────────────────────┘
```

### Why File-Based Handoff?

| Approach | Pros | Cons |
|----------|------|------|
| Direct heartbeat checks | Simple | Context bloat; every check adds tokens |
| `isolation.postToMainPrefix` | Built-in | Bug #3589 causes prompt bleeding |
| **File-based inbox** | Explicit control; no bloat; inspectable | Manual file management |

### Cron Jobs

| Job | Schedule | Status | Purpose |
|-----|----------|--------|---------|
| reminder-check | 9am, 2pm, 6pm | ✅ Active | Detect overdue reminders |
| staleness-check | Monday 10am | 📋 Proposed | Flag stale projects |
| calendar-prep | 7am weekdays | 📋 Proposed | Surface prep-worthy meetings |
| morning-briefing | 7:15am weekdays | 📋 Proposed | Daily summary to Signal |

### State Files

Manager maintains persistent state in `state/`:

**state/nag-history.json** — Reminder escalation tracking
```json
{
  "reminders": {
    "ABC123": {
      "title": "Call dentist",
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
| 1 | Any | Polite reminder |
| 2 | 3+ | Firmer |
| 3 | 7+ | Action prompt ("should I remove it?") |
| 4+ | Any | Stop nagging |

**state/staleness-history.json** — Project staleness tracking (same pattern)

### Heartbeat Processing Flow

```
ON HEARTBEAT:

1. PROCESS INBOX FILES
   for each file in inbox/:
     - reminder-check.json → apply nag rules, queue alerts
     - staleness-check.json → apply staleness rules, queue alerts
     - calendar-prep.json → queue prep notes
     - delete after processing

2. CHECK FOR WEB RESEARCH NEEDS
   if any task needs current info:
     sessions_send → bruba-web
     (results come back async, handle next heartbeat)

3. COMPILE ALERTS
   alerts = []
   add reminder nags (max 3)
   add staleness warnings (max 1)
   add calendar prep notes (max 2)
   
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

## Part 6: Security Model

### Current Gap

Bruba can theoretically edit `~/.openclaw/exec-approvals.json` to self-escalate permissions. The allowlist lives in the same filesystem the agent has write access to.

### Node Host Solution

**Architecture:**
```
┌─────────────────────────────────────────────────────────────────┐
│                     Mac Host (dadmini)                          │
│                                                                 │
│  ~/.openclaw/exec-approvals.json  ←── Out of agent's reach     │
│  ~/agents/bruba-main/tools/       ←── Read-only mount          │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Node Host Process                          │   │
│  │  • Executes allowlisted commands only                   │   │
│  │  • Manages tool scripts                                 │   │
│  └──────────────────────▲──────────────────────────────────┘   │
│                         │ system.run                           │
│  ┌──────────────────────┼──────────────────────────────────┐   │
│  │              Docker Container                           │   │
│  │  ┌───────────────────┴───────────────────────────────┐  │   │
│  │  │              OpenClaw Gateway                      │  │   │
│  │  │  ┌─────────────────────────────────────────────┐  │  │   │
│  │  │  │  bruba-main, bruba-manager, bruba-web       │  │  │   │
│  │  │  │  • Bind mounts only                         │  │  │   │
│  │  │  │  • No host filesystem access                │  │  │   │
│  │  │  └─────────────────────────────────────────────┘  │  │   │
│  │  └───────────────────────────────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### Bind Mounts

| Host Path | Container Path | Access | Purpose |
|-----------|---------------|--------|---------|
| `~/agents/bruba-main/workspace/` | `/workspace` | read-write | Working files |
| `~/agents/bruba-main/memory/` | `/memory` | read-write | PKM docs |
| `~/agents/bruba-main/tools/` | `/tools` | **read-only** | Scripts |
| `~/.openclaw/media/` | `/media` | read-write | Voice I/O |

**Key insight:** `tools/` is read-only because agents call scripts via node host; humans (Claude Code) edit them.

### Defense in Depth

| Layer | Protection |
|-------|------------|
| Tool restrictions | Agents can only use allowed tools |
| Separate agents | Web access isolated in bruba-web |
| Exec allowlist | Only approved commands run |
| Docker sandbox | Agents can't reach host filesystem |
| Node host | Exec runs outside container |

### Workspace Permissions (Post-Migration)

With Docker as the security boundary, agents can have fuller control within their sandboxed directories:

**Trash pattern for safe deletion:**
```
~/agents/bruba-main/
├── workspace/     ← full control
├── memory/        ← full control
├── tools/         ← read-only
└── .trash/        ← "deleted" files moved here
    └── 2026-02-02/
        └── old-file.md
```

- Delete = move to `.trash/YYYY-MM-DD/`
- Cron job purges files older than 7 days
- Provides undo without blocking cleanup

---

## Part 7: Configuration Reference

### openclaw.json (Target State)

```json
{
  "agents": {
    "defaults": {
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
        "tools": {
          "deny": ["web_search", "web_fetch", "browser", "canvas", 
                   "cron", "gateway", "sessions_spawn"]
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
        "tools": {
          "deny": ["web_search", "web_fetch", "browser", "canvas",
                   "cron", "gateway", "edit", "apply_patch"]
        }
      },
      {
        "id": "bruba-web",
        "name": "Web",
        "workspace": "/Users/bruba/agents/bruba-web",
        "model": "anthropic/claude-sonnet-4-5",
        "memorySearch": { "enabled": false },
        "heartbeat": { "every": "0m" },
        "sandbox": {
          "mode": "all",
          "scope": "agent",
          "workspaceAccess": "none",
          "docker": {
            "network": "bridge",
            "readOnlyRoot": true,
            "memory": "512m"
          }
        },
        "tools": {
          "allow": ["web_search", "web_fetch", "read"],
          "deny": ["exec", "write", "edit", "apply_patch",
                   "memory_search", "memory_get",
                   "sessions_spawn", "sessions_send",
                   "browser", "canvas", "cron", "gateway"]
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
      "allow": ["bruba-main", "bruba-manager", "bruba-web"]
    }
  },
  "channels": {
    "signal": {
      "enabled": true,
      "dmPolicy": "pairing"
    }
  },
  "gateway": {
    "port": 18789,
    "bind": "loopback"
  }
}
```

### Directory Structure

```
/Users/bruba/
├── agents/
│   ├── bruba-main/
│   │   ├── IDENTITY.md
│   │   ├── SOUL.md
│   │   ├── TOOLS.md
│   │   ├── AGENTS.md
│   │   ├── workspace/
│   │   ├── memory/
│   │   └── tools/          # Scripts (read-only post-migration)
│   ├── bruba-manager/
│   │   ├── IDENTITY.md
│   │   ├── SOUL.md
│   │   ├── TOOLS.md
│   │   ├── HEARTBEAT.md
│   │   ├── inbox/          # Cron job outputs
│   │   ├── state/          # Persistent tracking
│   │   └── results/        # Research outputs
│   └── bruba-web/
│       └── AGENTS.md       # Security instructions only
└── .openclaw/
    ├── openclaw.json
    ├── exec-approvals.json
    └── agents/
        ├── bruba-main/sessions/
        ├── bruba-manager/sessions/
        └── bruba-web/sessions/
```

---

## Part 8: Known Issues and Workarounds

### Bug #3589: Heartbeat Prompt Bleeding

**Status:** Open

When cron jobs fire system events, the heartbeat prompt gets appended to ALL events. Cron job purposes get hijacked.

**Workaround:** File-based inbox handoff. Cron writes to files, no system events involved.

### Bug #4355: Session Lock Contention

Concurrent operations cause write lock contention.

**Workaround:** Keep `maxConcurrent` reasonable (4 for agents).

### Bug #5433: Compaction Overflow

Auto-recovery sometimes fails on context overflow.

**Workaround:** Monitor, restart gateway if stuck.

### Issue #6295: Subagent Model Override Ignored

`sessions_spawn` parameter `model` is ignored; subagents inherit parent's model.

**Impact:** Not relevant for our architecture — we use separate agents instead of subagents for capability isolation.

---

## Part 9: Implementation Status

### Complete

| Item | Status | Notes |
|------|--------|-------|
| OpenClaw migration | ✅ | v2026.1.30 |
| bruba-main config | ✅ | Opus, no web |
| bruba-manager config | ✅ | Sonnet/Haiku heartbeat |
| Agent-to-agent comms | ✅ | `agentToAgent.enabled` |
| Directory structure | ✅ | Workspaces created |
| Siri integration | ✅ | Via tailscale serve |
| bruba-godo tooling | ✅ | Multi-agent prompt assembly |

### In Progress

| Item | Status | Notes |
|------|--------|-------|
| bruba-web agent | 🔄 | Needs configuration |
| Tool restriction cleanup | 🔄 | Remove broken subagent patterns |

### Planned

| Item | Priority | Notes |
|------|----------|-------|
| Cron: reminder-check | High | First proactive job |
| Node host migration | High | Security fix |
| Cron: other jobs | Medium | After reminder-check stable |
| Workspace permissions | Medium | After node host |

---

## Quick Reference

**Main can't search?** By design. Use `sessions_send` to bruba-web.

**Manager can't search?** Same pattern. Use `sessions_send` to bruba-web.

**Subagent has no web tools?** Parent's restrictions propagate. Use separate agent.

**Heartbeat delivering garbage?** Bug #3589. Use file-based inbox.

**Cross-context denied?** Use `sessions_send` between agents, not `message` tool.

**Agent can edit allowlist?** Known gap. Node host migration fixes this.

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 3.0.0 | 2026-02-02 | Major rewrite: peer model, tool inheritance fix, cron integration, node host |
| 2.x | 2026-02-01 | Broken subagent pattern (deprecated) |
| 1.x | 2026-01-31 | Initial single-agent |