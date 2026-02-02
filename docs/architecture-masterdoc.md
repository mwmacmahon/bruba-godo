---
version: 3.2.0
updated: 2026-02-02 21:00
type: refdoc
project: planning
tags: [bruba, openclaw, multi-agent, architecture, cron, operations]
---

# Bruba Multi-Agent Architecture Reference

Comprehensive reference for the Bruba multi-agent system. Covers the peer agent model, tool policy mechanics, cron-based proactive monitoring, heartbeat coordination, and security isolation.

---

## Executive Summary

Bruba uses a **three-agent architecture** with two peer agents and one service agent:

| Agent | Model | Role | Web Access |
|-------|-------|------|------------|
| **bruba-main** | Opus | Reactive — user conversations, file ops, complex reasoning | ❌ via bruba-web |
| **bruba-manager** | Sonnet/Haiku | Proactive — heartbeat, cron coordination, monitoring | ❌ via bruba-web |
| **bruba-web** | Sonnet | Service — stateless web search, prompt injection barrier | ✅ Direct |

**Key architectural insight:** OpenClaw's tool inheritance model means subagents cannot have tools their parent lacks. Web isolation requires a **separate agent** (bruba-web), not subagent spawning. Main and Manager are peers that communicate as equals; Web is a passive service both peers use.

**Proactive monitoring pattern:** Isolated cron jobs (cheap, stateless) detect conditions and write to inbox files. Manager's heartbeat (cheap, stateful) reads inbox, applies rules, delivers alerts. This separation keeps heartbeat fast while enabling rich monitoring.

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
│    bruba-main     │ │             └─────────────┼───────┐
│    ───────────    │ │                           │       │
│  Model: Opus      │ │                           ▼       │
│  Role: Reactive   │ │             ┌─────────────────────┴─────┐
│                   │ │             │      bruba-manager        │
│  • Conversations  │ │             │      ──────────────       │
│  • File ops       │ │             │  Model: Sonnet (Haiku HB) │
│  • Complex tasks  │ │             │  Role: Proactive          │
│  • Memory/PKM     │◄─────────────►│                           │
│                   │ sessions_send │  • Heartbeat checks       │
│                   │               │  • Cron job processing    │
└─────────┬─────────┘               │  • Inbox → delivery       │
          │                         │  • Siri sync queries      │
          │                         └─────────────┬─────────────┘
          │                                       │
          │ sessions_send                         │ sessions_send
          │                                       │
          └───────────────┐           ┌───────────┘
                          ▼           ▼
                ┌─────────────────────────────────────┐
                │          bruba-web                  │
                │          ─────────                  │
                │  Model: Sonnet                      │
                │  Role: Service (passive)           │
                │                                     │
                │  • Stateless web search             │
                │  • Prompt injection barrier         │
                │  • No memory, no initiative         │
                │  • Returns structured summary       │
                └─────────────────────────────────────┘
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

OpenClaw evaluates tool availability through precedence levels:

1. Tool profile (`tools.profile`)
2. Global tool policy (`tools.allow/deny`)
3. Provider policy (`tools.byProvider`)
4. **Agent policy** (`agents.list[].tools`) ← separate agents get independent config here
5. Agent provider policy
6. Sandbox policy
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
| exec | ✅ | remindctl, icalBuddy for Siri queries |
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
├── state/           # Persistent tracking (nag history, pending tasks)
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
| write | ✅ | Write results to results/ directory |
| exec | ❌ | No command execution |
| edit | ❌ | No file modification (write-only) |
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

**Workspace:** `/Users/bruba/agents/bruba-web/`

**Directory Structure:**
```
bruba-web/
├── AGENTS.md        # Security instructions
└── results/         # Research outputs (written here, read by Manager)
```

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
Manager → sessions_send("Research Y, write to /Users/bruba/agents/bruba-web/results/...") → bruba-web
bruba-web → researches, writes file to results/
Manager (next heartbeat) → checks bruba-web/results/, forwards summary to Signal
```

**Note:** bruba-web writes to its own `results/` directory. Manager reads from there on subsequent heartbeats. The `pending-tasks.json` tracks expected file paths.

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

## Part 5: Heartbeat vs Cron — Why Both?

This is a key architectural decision. Understanding the distinction prevents confusion.

### The Problem

Manager needs to do proactive monitoring:
- Check for overdue reminders
- Flag stale projects  
- Surface calendar prep needs
- Deliver consolidated alerts

**Naive approach:** Do all checks in Manager's heartbeat.

**Problem with naive approach:**
1. **Context bloat** — Every `remindctl` call, every file check adds tokens to heartbeat session
2. **Bug #3589** — System events get heartbeat prompt appended, hijacking their purpose
3. **Cost** — Running Sonnet/Opus for routine detection is wasteful

### The Solution: Detection vs Coordination Split

| Layer | What | Model | Session | Purpose |
|-------|------|-------|---------|---------|
| **Detection** | Cron jobs | Haiku | Isolated (fresh each run) | Find conditions, write findings |
| **Coordination** | Heartbeat | Haiku | Persistent (Manager's session) | Read findings, apply rules, deliver |

**Cron jobs** are cheap, stateless detectors:
- Fresh session per run (no context carryover)
- Just run a command, check output, write JSON file
- Exit immediately
- No memory of previous runs

**Heartbeat** is a cheap, stateful coordinator:
- Runs in Manager's persistent session
- Has access to state files (nag history, etc.)
- Reads inbox, cross-references state, makes decisions
- Delivers consolidated alerts
- Deletes inbox files after processing

### When to Use Which

| Task | Use Cron | Use Heartbeat |
|------|----------|---------------|
| Run `remindctl overdue` | ✅ | ❌ |
| Check if projects are stale | ✅ | ❌ |
| Apply nag escalation rules | ❌ | ✅ |
| Consolidate multiple alerts | ❌ | ✅ |
| Track what's been nagged | ❌ | ✅ (via state files) |
| Deliver to Signal | ❌ | ✅ |
| Fire-and-forget briefing | ✅ (with --deliver) | ❌ |

### File-Based State vs Messages

**When to use files (state/, inbox/):**
- Persists across restarts and compaction
- Inspectable for debugging
- Survives if agent crashes mid-task
- Good for: nag history, pending task tracking, cron findings

**When to use sessions_send:**
- Immediate delivery needed
- Conversational flow
- Triggering another agent to act
- Good for: alerts, delegation, web search requests

**Pattern:** Cron writes to files → Heartbeat reads files → Heartbeat sends messages

---

## Part 6: Cron System

### Architecture

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

### Cron Jobs

| Job | Schedule | Status | Purpose |
|-----|----------|--------|---------|
| reminder-check | 9am, 2pm, 6pm | ✅ Active | Detect overdue reminders |
| staleness-check | Monday 10am | 📋 Proposed | Flag stale projects (14+ days) |
| calendar-prep | 7am weekdays | 📋 Proposed | Surface prep-worthy meetings |
| morning-briefing | 7:15am weekdays | 📋 Proposed | Daily summary to Signal |

### Adding a Cron Job

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

### Managing Cron Jobs

```bash
openclaw cron list                           # List all jobs
openclaw cron status --name reminder-check   # Check specific job
openclaw cron trigger --name reminder-check  # Manual test run
openclaw cron disable --name reminder-check  # Pause job
openclaw cron enable --name reminder-check   # Resume job
openclaw cron remove --name reminder-check   # Delete job
```

### State Files

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

### Heartbeat Processing Flow

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

## Part 7: Security Model

### Current Gap

Bruba can theoretically edit `~/.openclaw/exec-approvals.json` to self-escalate permissions. The allowlist lives in the same filesystem the agent has write access to.

### Node Host Solution (Planned)

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

### Defense in Depth

| Layer | Protection |
|-------|------------|
| Tool restrictions | Agents can only use allowed tools |
| Separate agents | Web access isolated in bruba-web |
| Exec allowlist | Only approved commands run |
| Docker sandbox | Agents can't reach host filesystem |
| Node host | Exec runs outside container |

---

## Part 8: Operations

### Prerequisites

**remindctl** — CLI for Apple Reminders
```bash
brew install steipete/formulae/remindctl
remindctl authorize  # Grant permissions
remindctl status     # Verify
```

**icalBuddy** — CLI for macOS Calendar
```bash
brew install ical-buddy
icalBuddy eventsToday  # Verify
```

### Starting the System

```bash
# Start OpenClaw gateway (runs all agents)
openclaw gateway start

# Or in foreground for debugging
openclaw gateway run

# Check status
openclaw gateway status
```

### Stopping the System

```bash
# Graceful shutdown
openclaw gateway stop

# Force stop if stuck
openclaw gateway stop --force
```

### Health Checks

```bash
# Overall status
openclaw health

# Check specific agent
openclaw sessions list --agent bruba-main

# Check cron jobs
openclaw cron list

# Check recent heartbeats
openclaw cron runs --name heartbeat --limit 5
```

### Log Locations

```
~/.openclaw/logs/gateway.log     # Gateway process
~/.openclaw/logs/agents/         # Per-agent logs
~/.openclaw/sessions/            # Session transcripts
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
│   │   └── results/        # Research outputs (Manager reads these)
│   └── bruba-web/
│       ├── AGENTS.md       # Security instructions
│       └── results/        # Research outputs (bruba-web writes here)
└── .openclaw/
    ├── openclaw.json
    ├── exec-approvals.json
    ├── cron/
    │   └── jobs.json
    └── agents/
        ├── bruba-main/sessions/
        ├── bruba-manager/sessions/
        └── bruba-web/sessions/
```

### Directory Setup (First Time)

```bash
# Create Manager workspace
mkdir -p /Users/bruba/agents/bruba-manager/{inbox,state,results}

# Initialize state files
echo '{"reminders": {}, "lastUpdated": null}' > /Users/bruba/agents/bruba-manager/state/nag-history.json
echo '{"projects": {}, "lastUpdated": null}' > /Users/bruba/agents/bruba-manager/state/staleness-history.json
echo '{"tasks": [], "lastUpdated": null}' > /Users/bruba/agents/bruba-manager/state/pending-tasks.json

# Create bruba-web workspace
mkdir -p /Users/bruba/agents/bruba-web/results
```

---

## Part 9: Troubleshooting

### Heartbeat Not Delivering

**Symptom:** No alerts even when overdue reminders exist.

**Check:**
1. Is inbox file being created? `ls -la ~/agents/bruba-manager/inbox/`
2. Is cron job running? `openclaw cron runs --name reminder-check`
3. Is heartbeat running? `openclaw cron runs --name heartbeat`
4. Check Manager logs for errors

**Common causes:**
- Cron job failed silently (check `remindctl status`)
- Heartbeat processing error (check logs)
- Bug #3589 if using system events instead of files

### Heartbeat Always Returns HEARTBEAT_OK

**Symptom:** Manager never sends alerts.

**Check:**
1. Are inbox files being created with content?
2. Is nag-history.json capping all items at nagCount 4+?
3. Is heartbeat reading the right directory?

### Agent Can't Reach Another Agent

**Symptom:** `sessions_send` fails with "agent not found".

**Check:**
1. Is target agent configured? `openclaw config show`
2. Is agentToAgent enabled? Check `tools.agentToAgent.enabled`
3. Is target agent in allow list? Check `tools.agentToAgent.allow`

### Context Bloat

**Symptom:** Responses getting slow, compaction warnings.

**Check:**
1. Is Manager running checks directly instead of via cron?
2. Are inbox files being deleted after processing?
3. Check session size: `openclaw sessions list --agent bruba-manager`

**Fix:** Reset session: `openclaw sessions reset --agent bruba-manager`

### Web Search Failing

**Symptom:** bruba-web returns errors or times out.

**Check:**
1. Is bruba-web's Docker network configured? (needs `bridge` for internet)
2. Is bruba-web sandbox too restrictive?
3. Check bruba-web logs

---

## Part 10: Configuration Reference

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
          "allow": ["web_search", "web_fetch", "read", "write"],
          "deny": ["exec", "edit", "apply_patch",
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

---

## Part 11: Known Issues and Workarounds

### Bug #3589: Heartbeat Prompt Bleeding

**Status:** Open — [GitHub Issue #3589](https://github.com/openclaw/openclaw/issues/3589)

When cron jobs fire system events, the heartbeat prompt gets appended to ALL events. Cron job purposes get hijacked.

**Workaround:** File-based inbox handoff. Cron writes to files, no system events involved.

### Bug #4355: Session Lock Contention

Concurrent operations cause write lock contention.

**Workaround:** Keep `maxConcurrent` reasonable (4 for agents).

### Bug #5433: Compaction Overflow

Auto-recovery sometimes fails on context overflow.

**Workaround:** Monitor, restart gateway if stuck. `openclaw sessions reset --agent <id>` to clear.

### Issue #6295: Subagent Model Override Ignored

`sessions_spawn` parameter `model` is ignored; subagents inherit parent's model.

**Impact:** Not relevant for our architecture — we use separate agents instead of subagents for capability isolation.

---

## Part 12: Implementation Status

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

**Why both cron and heartbeat?** Cron = cheap detection (isolated). Heartbeat = coordination (stateful).

**Files vs messages?** Files persist, survive restarts. Messages for immediate delivery.

**Cross-context denied?** Use `sessions_send` between agents, not `message` tool.

**Agent can edit allowlist?** Known gap. Node host migration fixes this.

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

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 3.2.0 | 2026-02-02 | Fixed bruba-web tools: added write to allow (needed to write results/) |
| 3.1.0 | 2026-02-02 | Added heartbeat vs cron explanation, operations guide, troubleshooting, cost estimates, full cron integration |
| 3.0.0 | 2026-02-02 | Major rewrite: peer model, tool inheritance fix, cron integration, node host |
| 2.x | 2026-02-01 | Broken subagent pattern (deprecated) |
| 1.x | 2026-01-31 | Initial single-agent |