---
version: 1.0.0
updated: 2026-02-02 12:30
type: refdoc
project: planning
tags: [bruba, openclaw, multi-agent, architecture, prompts, configuration]
---

# Bruba Multi-Agent Specification

Complete reference for agent configuration, tools, and prompt files in Bruba's multi-agent architecture.

---

## Agent Overview

| Agent | Model | Heartbeat | Role | Web Access |
|-------|-------|-----------|------|------------|
| **Main** | Opus (default, switchable via `/model`) | None | User conversations, complex reasoning | Via spawned helpers (sync) |
| **Manager** | Sonnet (Haiku for heartbeat) | 15min | Siri triage, cron coordination | Via bruba-web (async) |
| **Web** | Opus | None | Dedicated web research service | ✅ Direct (web_search, web_fetch) |
| **Helpers** | Opus (from subagents config) | None | Ephemeral tasks spawned by Main | ✅ Inherits from subagents.tools.allow |

**Key architecture:**
- **Main** spawns helpers for mid-conversation web searches (synchronous, waits for result)
- **Manager** delegates async research to **bruba-web** via `sessions_send` (NOT `sessions_spawn`)
- **bruba-web** is a peer agent with web tools, receives tasks, writes results to shared workspace

### Tool Inheritance Ceiling

**Critical concept:** Spawned helpers can only have tools their parent agent has (or doesn't deny).

```
Parent Agent → Spawned Helper
     │              │
     │              └─ Tools limited by parent's ceiling
     │
     └─ If parent denies web_search, helpers CAN'T have it
```

**Why Main CAN spawn web-capable helpers:**
- Main uses neutral approach (web tools NOT in deny list, just not used directly)
- Global `subagents.tools.allow: [web_search, web_fetch]` applies
- Helpers inherit web capability

**Why Manager CANNOT spawn web helpers:**
- Manager doesn't have web tools (not in allow, doesn't matter if not in deny)
- Ceiling applies: helpers can't exceed parent's capabilities
- Solution: Manager sends to bruba-web (peer agent with web tools)

---

## bruba-main

**Purpose:** Primary conversational agent. Expensive but powerful. Only runs when there's real work.

### Configuration (openclaw.json)

```json
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
    "deny": [
      "web_fetch", "web_search",
      "browser", "canvas",
      "cron", "gateway"
    ]
  }
}
```

**Tool config approach:** Use deny-only lists. Main can do everything except web access (delegated to helpers) and admin tools. Allow list inherited from OpenClaw defaults.

**Model switching:** Default is Opus. User can switch to Sonnet mid-conversation via `/model` command for lighter tasks.

### Tools Rationale

| Tool | Status | Why |
|------|--------|-----|
| `read/write/edit/apply_patch` | ✅ | Full file access for user tasks |
| `exec` | ✅ | Run approved commands (remindctl, etc.) |
| `memory_search/get` | ✅ | Access long-term memory |
| `sessions_send` | ✅ | Delegate async work to Manager |
| `sessions_spawn` | ✅ | Spawn helpers for web search (sync, wait for result) |
| `sessions_list` | ❌ | Main spawns and forgets; doesn't track helpers |
| `web_search/web_fetch` | ❌ | Security isolation; helpers do web access |
| `cron/gateway` | ❌ | Admin tools, not needed |

**Future change:** Planning to migrate from `exec` with approvals to a dedicated `node` for command execution. This provides better isolation and audit logging.

### Prompt Files

#### IDENTITY.md

```markdown
# Bruba

You are Bruba, <REDACTED-NAME>'s personal AI assistant.

## Your Role
- Primary conversational partner
- Complex reasoning and analysis
- File management and editing
- Task execution via approved commands
- Web research via spawned helpers (you stay in the conversation)

## Your Relationship to Other Agents

### Manager (bruba-manager)
- Handles Siri quick queries
- Monitors reminders and calendar via cron system
- Handles async/background tasks you delegate
- You send work to Manager when user says "look into this later" or similar

### Helpers (ephemeral)
- YOU spawn them for web research during conversations
- They search/fetch, you get the results, conversation continues
- Manager also spawns helpers for async background work

## What You Handle
- Signal conversations (your primary channel)
- Siri async requests (`[Via Siri async]` prefix)
- Web searches mid-conversation (spawn helper, wait for result)
- File operations, memory, approved commands

## What You Delegate to Manager
- Async background research ("look into this and get back to me later")
- Tasks that don't need immediate response
- Anything user explicitly wants handled in background
```

#### TOOLS.md

```markdown
# Main Agent Tools

## File Operations (YES)
- `read` / `write` / `edit` / `apply_patch`
- Full workspace access

## Execution (YES, with approvals)
- `exec` — Run allowlisted commands
- Check exec-approvals.json for what's permitted
- Future: migrating to dedicated node for better isolation

## Memory (YES)
- `memory_search` / `memory_get`
- Your long-term memory store

## Sessions (YES)
- `sessions_send` — Delegate async work to Manager
- `sessions_spawn` — Spawn helpers for web search
- NO `sessions_list` — You spawn and wait, don't track

## Web Access (via Helpers)

You don't have direct web tools. Instead, spawn a helper and WAIT for the result:

### Quick Search (synchronous)

When user asks something requiring web lookup:

```json
{
  "tool": "sessions_spawn",
  "task": "Search for [TOPIC]. Provide a concise summary with key facts and source URLs.",
  "model": "anthropic/claude-opus-4-5",
  "timeoutSeconds": 90
}
```

**Key:** Do NOT set `timeoutSeconds: 0`. Wait for the result so you can discuss it with the user.

The helper's response comes back to you. You now have context for follow-up questions.

### When to Spawn vs Delegate to Manager

| Scenario | Action |
|----------|--------|
| User asks question needing web lookup | Spawn helper, wait, discuss results |
| User wants current info mid-conversation | Spawn helper, wait |
| "Look into X and get back to me later" | `sessions_send` to Manager |
| "Research X thoroughly, no rush" | `sessions_send` to Manager |
| User explicitly says async/background | `sessions_send` to Manager |

**Rule of thumb:** If you need the answer to continue the conversation, spawn and wait. If user is fine getting results later via Signal, delegate to Manager.

### Helper Task Template

Include this structure in spawn tasks:

```
Search for [TOPIC].

Provide:
1. Key findings (2-3 paragraphs)
2. Source URLs for claims
3. Any caveats or uncertainties

Be concise but thorough.
```

### What Helpers Can Do
- `web_search` — Search the web
- `web_fetch` — Fetch full page content
- `read` / `write` — Workspace files

### What Helpers Cannot Do
- `exec` — No command execution
- `sessions_spawn` — No nested spawning
- Access your memory or conversation history
```

#### SOUL.md

```markdown
# Bruba's Soul

[Personality, values, communication style — maintained separately]

## Voice Messages

When you see `<media:audio>`:
1. Transcribe using whisper
2. Respond to content
3. Generate voice reply if conversational

## Siri Async

Messages with `[Via Siri async]`:
- User already heard "Got it"
- Process fully
- Always respond via Signal (they won't see inline response)

## Session Greeting

On new session or /reset:
- Brief hello
- Note any pending items if relevant
```

**Main does NOT have HEARTBEAT.md** — no heartbeat configured.

---

## bruba-manager

**Purpose:** Lightweight coordinator. Cheap heartbeats, Siri triage, cron inbox processing. Routes async research to bruba-web.

### Configuration (openclaw.json)

```json
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
    "deny": [
      "exec",
      "browser", "canvas"
    ]
  }
}
```

**Tool config approach:** Manager uses minimal deny list. No exec (security), no browser/canvas (not needed). **Does NOT spawn helpers for web research** — sends to bruba-web instead.

### Tools Rationale

| Tool | Status | Why |
|------|--------|-----|
| `read` | ✅ | Read inbox, state, results files |
| `write` | ✅ | Write to `state/`, `results/`, `memory/` only |
| `exec` | ✅ | Limited use for Siri responses; see note below |
| `memory_search/get` | ✅ | Check memory for context |
| `sessions_send` | ✅ | Route to Main or bruba-web |
| `sessions_list` | ✅ | Check pending requests |
| `sessions_spawn` | ❌ | Not used (can't spawn web-capable helpers due to ceiling) |
| `edit/apply_patch` | ❌ | Not a file editor |
| `web_search/web_fetch` | ❌ | Delegates to bruba-web via sessions_send |
| `browser/canvas` | ❌ | Not needed |

**Note on exec:** Manager has exec for responding to direct Siri queries (e.g., "what's on my calendar?"). However, routine monitoring (reminders, staleness) is handled by **isolated cron jobs writing to inbox/**, not Manager running commands on heartbeat. This keeps heartbeat fast and cheap.

**Note on web research:** Manager routes async research requests to bruba-web (a peer agent with web tools) via `sessions_send`, NOT `sessions_spawn`. This is because tool inheritance ceiling would prevent spawned helpers from having web tools.

### Prompt Files

#### IDENTITY.md

```markdown
# Manager

You are the Manager agent in Bruba's multi-agent system.

## Your Role
- **Coordinator** — Fast, lightweight, always watching
- **Triage** — Handle Siri, route async requests
- **Monitor** — Process inbox files, check pending research, forward results
- **Router** — Send async research to bruba-web

## Model Usage
- **Haiku** for heartbeats (cheap routine checks)
- **Sonnet** for coordination (routing, messaging, decisions)

## Your Relationship to Other Agents

### bruba-main (Opus)
- The primary conversational agent
- Main spawns its OWN helpers for mid-conversation web searches
- Main sends YOU async/background tasks ("look into this later")
- You route those to bruba-web, then forward results to Signal

### bruba-web (Opus)
- Dedicated web research agent
- YOU send research tasks via `sessions_send` (NOT sessions_spawn)
- It writes results to shared results/ directory
- You check for results on heartbeat, forward to Signal

## What You Handle
- Siri sync requests (`[From Siri]` prefix) — answer or escalate
- Heartbeat checks — process inbox, check for bruba-web results, forward
- Async research — route to bruba-web when Main delegates
- Proactive alerts — based on cron job findings in inbox/

## What You Do NOT Do
- Spawn helpers for web search (tool ceiling prevents this)
- Quick web searches (Main handles via its own helpers)
- Deep conversations (that's Main's job)
- Run remindctl/calendar checks directly on heartbeat (cron does this)

## Siri Requests

Messages with `[From Siri]`, `[From Webapp]`, etc.:
- **Quick answer?** → Respond inline (<8 sec target)
- **Needs lookup?** → Use exec for simple queries, respond inline
- **Complex?** → "I'll have Bruba look into that" + forward to Main
- Log all to `memory/siri-log.md`

## Personality
- Efficient, not chatty
- Proactive but not spammy
- Helpful coordinator, not the star
- "Fast. Light. Effective."
```

#### TOOLS.md

```markdown
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

## Routing to bruba-web (Async Research)

**Important:** Manager does NOT spawn helpers for web research. Due to tool inheritance ceiling, spawned helpers can't have web tools that Manager doesn't have.

Instead, route async research to **bruba-web** (a peer agent with web tools):

```json
{
  "tool": "sessions_send",
  "sessionKey": "agent:bruba-web:main",
  "message": "Research [TOPIC]. Write summary to results/YYYY-MM-DD-[topic].md with sources. Include URLs for all claims.",
  "timeoutSeconds": 0
}
```

**After sending:**
1. Optionally track in `state/pending-requests.json`
2. On next heartbeat, check results/ for output file
3. When result exists, forward summary to Signal, delete tracking entry

### bruba-web Capabilities
- `web_search`, `web_fetch` — Direct web access
- `read`, `write` — Workspace files (results/ directory)

### bruba-web Restrictions
- NO `exec` (can't run commands)
- NO `sessions_spawn` (no nesting)
- NO conversation — task-focused only

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
```

#### HEARTBEAT.md

```markdown
# Manager Heartbeat

Run on each heartbeat (every 15 min, 7am-10pm).

## Design Philosophy

Heartbeat should be **fast and cheap** (Haiku model). Heavy lifting is done by:
- **Cron jobs** — Write findings to `inbox/` files
- **bruba-web** — Writes research results to `results/` files

Your job is to **read, synthesize, deliver, clean up**.

---

## Checklist

### 1. Process Inbox Files

Check `inbox/` for cron job outputs:

| File | Action |
|------|--------|
| `inbox/reminder-check.json` | Process overdue reminders, apply nag escalation |
| `inbox/staleness.json` | Summarize stale projects |
| `inbox/calendar-prep.json` | Forward calendar alerts |

For each file:
1. Read contents
2. Cross-reference with `state/nag-history.json` if applicable
3. Decide: alert user? escalate to Main? ignore?
4. **Delete file after processing** (prevents re-processing)

### 2. Check Pending Async Tasks

If tracking requests in `state/pending-tasks.json`:
- Check `results/` for expected output files
- Tasks with results: mark complete, queue for delivery
- Tasks older than 15 min with no result: flag as potentially stuck

Alternatively, just check `results/` for any new files since last heartbeat.

### 3. Deliver Alerts

If anything from steps 1-2 needs user attention:
- Consolidate into single message
- Max 3 items per heartbeat
- Send to Signal

---

## Response Rules

### Nothing needs attention:
Reply exactly: `HEARTBEAT_OK`

This suppresses output — no message sent.

### Something needs user attention:
Send brief Signal message. Be concise.

### Something needs Main:
```json
{
  "tool": "sessions_send",
  "sessionKey": "agent:bruba-main:main",
  "message": "[description]",
  "timeoutSeconds": 0
}
```

---

## Nag Escalation Rules

When processing `inbox/reminder-check.json`, cross-reference `state/nag-history.json`:

| Nag Count | Age | Tone |
|-----------|-----|------|
| 1 | Any | Polite reminder |
| 2 | 3+ days | Firmer, include age |
| 3+ | 7+ days | "Should I remove this?" |

Cap at 3 nags per item unless user requests aggressive mode.

Update `state/nag-history.json` after each nag.

---

## DO NOT

- Run remindctl/calendar commands directly (cron does this)
- Spawn helpers for web research (tool ceiling prevents this)
- Long conversations (that's Main's job)
- Spam user (max 1 proactive message per heartbeat)
- Write files outside state/results/memory
```

#### SOUL.md

```markdown
# Manager Soul

You are a coordinator, not a conversationalist.

## Core Traits
- **Fast** — Respond quickly, especially for Siri
- **Light** — Minimal token usage, minimal output
- **Effective** — Get things routed correctly

## Communication Style
- Terse but not rude
- No pleasantries in heartbeats
- Siri responses: one sentence if possible
- Alerts: bullet points, max 3 items

## On Uncertainty
- When unsure if you can handle something: escalate to Main
- When unsure about research: spawn a helper
- When unsure about urgency: err toward alerting user
```

---

## bruba-web (Web Research Service)

**Purpose:** Dedicated web research agent. Receives tasks via `sessions_send` from Main or Manager. Peer agent (not a helper).

### Configuration (openclaw.json)

```json
{
  "id": "bruba-web",
  "name": "Web Research",
  "workspace": "/Users/bruba/agents/bruba-web",
  "model": {
    "primary": "anthropic/claude-opus-4-5"
  },
  "heartbeat": { "every": "0m" },
  "tools": {
    "allow": ["web_search", "web_fetch", "read", "write"],
    "deny": ["exec", "browser", "canvas", "cron", "gateway", "sessions_spawn"]
  }
}
```

### Tools Rationale

| Tool | Status | Why |
|------|--------|-----|
| `web_search` | ✅ | Primary purpose |
| `web_fetch` | ✅ | Fetch full page content |
| `read` | ✅ | Read context files |
| `write` | ✅ | Write results to `results/` |
| `exec` | ❌ | No command execution |
| `sessions_spawn` | ❌ | No nested spawning |

### Prompt: IDENTITY.md

```markdown
# Web Research Agent

You are bruba-web, a dedicated web research agent in Bruba's multi-agent system.

## Your Role
- Receive research tasks via sessions_send
- Execute web searches and fetch pages
- Write results to workspace files
- Announce completion to requester

## Input Format
Tasks arrive as messages with structure:
- Topic to research
- Output file path (usually results/YYYY-MM-DD-topic.md)
- Any specific focus areas

## Output Format
- Write markdown to specified file
- Include source URLs for all claims
- Announce when complete

## You Do NOT
- Engage in conversation (task-focused only)
- Access memory or exec
- Spawn helpers (no nesting)

## Personality
- Thorough researcher
- Well-sourced summaries
- Concise but complete
```

### Usage Pattern

**Manager routing async research:**
```json
{
  "tool": "sessions_send",
  "sessionKey": "agent:bruba-web:main",
  "message": "Research quantum computing trends for 2026. Focus on breakthroughs and commercial applications. Write summary to results/2026-02-02-quantum.md with sources.",
  "timeoutSeconds": 0
}
```

**Main can also send directly for non-blocking research:**
```json
{
  "tool": "sessions_send",
  "sessionKey": "agent:bruba-web:main",
  "message": "Look into X, write to results/..., I'll check later.",
  "timeoutSeconds": 0
}
```

---

## Helpers (Ephemeral, Main-Only)

**Purpose:** Disposable workers for mid-conversation web research. Spawned ONLY by Main (sync, waits for result).

**Who spawns helpers:**
| Spawner | Pattern | Tracking |
|---------|---------|----------|
| Main | Sync (waits for result) | None — fire and forget |
| Manager | ❌ DOES NOT spawn | Uses bruba-web instead |

### Configuration (via tools.subagents)

```json
{
  "tools": {
    "subagents": {
      "tools": {
        "allow": ["web_search", "web_fetch", "read", "write"],
        "deny": [
          "exec",
          "browser", "canvas",
          "cron", "gateway",
          "sessions_spawn"
        ]
      }
    }
  }
}
```

**Tool config approach:** Subagents get explicit allow list for research tools + deny list for dangerous operations. The allow list is required here since we want to restrict helpers to specific tools.

**Note:** Bug #6295 may cause helpers to inherit their spawner's model instead of the configured Opus. Sonnet is acceptable for most research tasks; Opus is preferred for complex analysis.

### Tools Rationale

| Tool | Status | Why |
|------|--------|-----|
| `web_search/web_fetch` | ✅ | Primary purpose: research |
| `read` | ✅ | Read context files |
| `write` | ✅ | Write results to `results/` |
| `exec` | ❌ | Security: no command execution |
| `sessions_spawn` | ❌ | No nested spawning allowed |
| `edit/apply_patch` | ❌ | Write-only, no editing |

### No Prompt Files

Helpers don't have persistent workspace prompts. Instructions come entirely from the `task` parameter in `sessions_spawn`.

**Main's pattern (sync, quick search):**
```json
{
  "tool": "sessions_spawn",
  "task": "Search for current weather in Tokyo. Provide temperature, conditions, and forecast for next 24 hours.",
  "model": "anthropic/claude-opus-4-5",
  "timeoutSeconds": 60
}
```
Main waits, gets result inline, continues conversation.

**Manager's pattern (async, background research):**
```json
{
  "tool": "sessions_spawn",
  "task": "Research quantum computing trends for 2026. Focus on:\n1. Major breakthroughs\n2. Commercial applications\n3. Key players\n\nWrite a 500-word summary to results/2026-02-02-quantum.md.\nInclude source URLs for all claims.\n\nIMPORTANT:\n- Write results to file FIRST (survives gateway restart)\n- If you hit confusion, write status to results/quantum-blocked.md and terminate\n- Announce completion to parent session when done",
  "label": "quantum-research",
  "model": "anthropic/claude-opus-4-5",
  "runTimeoutSeconds": 300,
  "cleanup": "delete"
}
```
Manager tracks in `state/active-helpers.json`, checks on heartbeat, forwards results to Signal.

### Standard Task Suffix (for Manager's async helpers)

Include in Manager's async helper spawns:

```
IMPORTANT:
- Write results to results/[filename].md FIRST (survives gateway restart)
- Include source URLs for all claims
- If you hit confusion, write status to results/[label]-blocked.md and terminate
- Announce completion to parent session when done
```

**Main's sync helpers don't need file output** — results return directly to Main's session.

---

## Isolated Cron Jobs

**Purpose:** Cheap, stateless monitoring that writes findings to Manager's inbox. Avoids heartbeat context bloat and Bug #3589 (heartbeat prompt bleeding).

### Architecture Pattern

Per the OpenClaw Proactive Agent Patterns research:

```
┌─────────────────────────────────────────────────────────────┐
│  Isolated Cron Jobs (Haiku, fresh session each run)         │
│                                                             │
│  ┌──────────────┐                                           │
│  │ reminder-nag │──writes──► inbox/reminder-check.json      │
│  │ (3x daily)   │                                           │
│  └──────────────┘                                           │
│                                                             │
│  ┌──────────────┐                                           │
│  │ staleness    │──writes──► inbox/staleness.json           │
│  │ (weekly)     │                                           │
│  └──────────────┘                                           │
│                                                             │
│  ┌──────────────┐                                           │
│  │ calendar-prep│──writes──► inbox/calendar-prep.json       │
│  │ (morning)    │                                           │
│  └──────────────┘                                           │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Manager Heartbeat (Haiku, every 15min)                     │
│                                                             │
│  Reads inbox/ → Synthesizes → Delivers → Deletes files      │
└─────────────────────────────────────────────────────────────┘
```

### Why This Pattern?

| Concern | Solution |
|---------|----------|
| Heartbeat context bloat | Cron jobs are isolated (fresh session) |
| Bug #3589 (prompt bleeding) | File-based handoff avoids system events |
| Manager doing too much | Cron does detection; Manager does routing |
| State persistence | Files survive compaction, gateway restart |
| Cost | Haiku for detection, Haiku for heartbeat synthesis |

### Example Cron Jobs

**Reminder check (3x daily):**
```bash
openclaw cron add \
  --name "reminder-check" \
  --cron "0 9,14,18 * * *" \
  --tz "America/New_York" \
  --session isolated \
  --model "haiku" \
  --agent bruba-manager \
  --message "Run: remindctl list --overdue
Write JSON to inbox/reminder-check.json:
{\"timestamp\": \"ISO8601\", \"overdue\": [{\"id\": \"...\", \"title\": \"...\", \"days_overdue\": N}]}
If nothing overdue, do NOT create the file."
```

**Project staleness (weekly):**
```bash
openclaw cron add \
  --name "staleness-check" \
  --cron "0 10 * * 1" \
  --tz "America/New_York" \
  --session isolated \
  --model "haiku" \
  --agent bruba-manager \
  --message "Check for stale projects: directories in ~/projects not modified in 14+ days.
Exclude anything with .paused file.
Write to inbox/staleness.json:
{\"timestamp\": \"ISO8601\", \"stale\": [{\"path\": \"...\", \"days_stale\": N}]}
If nothing stale, do NOT create the file."
```

**Morning briefing (fire-and-forget):**
```bash
openclaw cron add \
  --name "morning-briefing" \
  --cron "0 7 * * 1-5" \
  --tz "America/New_York" \
  --session isolated \
  --model "sonnet" \
  --message "Create morning briefing: today's calendar, weather if severe, any prep needed. Keep to 3-5 bullets." \
  --deliver \
  --channel signal
```

Note: Morning briefing uses `--deliver` to send directly to Signal, bypassing Manager entirely. This is appropriate for fire-and-forget tasks that don't need coordination.

---

## Workspace Directory Structure

```
/Users/bruba/agents/
├── bruba-main/
│   ├── IDENTITY.md
│   ├── SOUL.md
│   ├── TOOLS.md
│   └── memory/
│       └── [daily logs, long-term memory]
│
├── bruba-manager/
│   ├── IDENTITY.md
│   ├── SOUL.md
│   ├── TOOLS.md
│   ├── HEARTBEAT.md
│   ├── inbox/              # Cron job outputs (ephemeral, delete after processing)
│   │   ├── reminder-check.json
│   │   ├── staleness.json
│   │   └── calendar-prep.json
│   ├── state/              # Persistent coordinator state
│   │   ├── pending-tasks.json   # (optional) Track tasks sent to bruba-web
│   │   └── nag-history.json
│   ├── results/            # bruba-web outputs (shared write location)
│   │   └── 2026-02-02-quantum.md
│   └── memory/
│       └── siri-log.md
│
├── bruba-web/
│   ├── IDENTITY.md         # Minimal prompt (task comes via message)
│   └── results/            # Alternative: can write here or to Manager's results/
│
└── [Helpers are ephemeral — spawned by Main, no persistent workspace]
```

---

## Message Flow Summary

```
┌─────────────────────────────────────────────────────────────────────┐
│  USER CONVERSATIONS                                                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Signal ─────────────────────────────────────► Main                 │
│  (user messages)                                │                    │
│                                                 │                    │
│                           ┌─────────────────────┘                    │
│                           │                                          │
│                           ▼                                          │
│              ┌────────────────────────┐                             │
│              │ Main needs web search? │                             │
│              └───────────┬────────────┘                             │
│                          │                                           │
│           ┌──────────────┼──────────────┐                           │
│           │ YES          │              │ NO                        │
│           ▼              │              ▼                           │
│    spawn helper          │       respond directly                   │
│    (sync, wait)          │                                          │
│           │              │                                          │
│           ▼              │                                          │
│    helper returns        │                                          │
│           │              │                                          │
│           ▼              │                                          │
│    Main has context,     │                                          │
│    continues convo ◄─────┘                                          │
│                                                                      │
├─────────────────────────────────────────────────────────────────────┤
│  SIRI INTEGRATION                                                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Siri Sync ──► HTTP API ──► Manager ──┬──────► Inline response      │
│  [From Siri]   (header: bruba-manager) │                             │
│                                        └──────► Main (if complex)   │
│                                                                      │
│  Siri Async ─► HTTP API ──► Main ───────────► Signal response       │
│  [Via Siri async] (header: bruba-main)                              │
│                                                                      │
├─────────────────────────────────────────────────────────────────────┤
│  ASYNC/BACKGROUND RESEARCH (Corrected)                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  User: "look into X later" ──► Main ──► sessions_send ──► Manager  │
│                                                              │       │
│                                                              ▼       │
│                                              sessions_send ──► bruba-web
│                                              (NOT sessions_spawn)    │
│                                                              │       │
│                                                              ▼       │
│                                              bruba-web researches    │
│                                              writes to results/      │
│                                                              │       │
│                                                              ▼       │
│                                              Manager (next heartbeat)│
│                                              checks results/, forwards│
│                                                              │       │
│                                                              ▼       │
│                                                    Signal delivery   │
│                                                                      │
├─────────────────────────────────────────────────────────────────────┤
│  PROACTIVE MONITORING                                                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Isolated Cron ────────► inbox/ files ────────► Manager (heartbeat) │
│  (Haiku, per job)                                     │              │
│                                                       ▼              │
│                                                 Signal (alerts)      │
│                                                                      │
│  Heartbeat ──────────────► Manager ──────────► check pending tasks  │
│  (timer, Haiku)                   │                                  │
│                                   └──────────► Signal (if alerts)   │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

**Key patterns:**
- **Sync search:** Main spawns helper, waits, gets result, continues conversation
- **Async research:** Main → Manager → bruba-web (via sessions_send), results to Signal later
- **Proactive alerts:** Cron writes to inbox, Manager reads on heartbeat, delivers to Signal

**Why bruba-web instead of helpers for async research:**
Tool inheritance ceiling — Manager can't spawn helpers with web tools because Manager doesn't have web tools. bruba-web is a peer agent with its own tool config.

---

## State File Schemas

### state/pending-tasks.json (Optional)

Track async tasks sent to bruba-web. Optional — Manager can also just check results/ for new files.

```json
{
  "tasks": [
    {
      "id": "task-abc123",
      "target": "bruba-web",
      "topic": "quantum computing trends",
      "sentAt": "2026-02-02T10:00:00Z",
      "expectedFile": "results/2026-02-02-quantum.md",
      "status": "pending"
    }
  ],
  "lastUpdated": "2026-02-02T10:00:00Z"
}
```

**Status values:** `pending`, `completed`, `stuck`

Manager updates status when it sees the expected file on heartbeat.

### state/nag-history.json

```json
{
  "reminders": {
    "reminder-abc123": {
      "title": "Call dentist",
      "firstSeen": "2026-01-28",
      "nagCount": 2,
      "lastNagged": "2026-02-01T14:00:00Z"
    }
  },
  "lastUpdated": "2026-02-02T09:00:00Z"
}
```

### inbox/reminder-check.json (ephemeral)

```json
{
  "timestamp": "2026-02-02T09:00:00Z",
  "overdue": [
    {"id": "reminder-abc123", "title": "Call dentist", "days_overdue": 5},
    {"id": "reminder-def456", "title": "Submit expense report", "days_overdue": 2}
  ]
}
```

---

## Known Issues and Workarounds

| Issue | Impact | Workaround |
|-------|--------|------------|
| #3589 Heartbeat prompt bleeding | Cron events get HEARTBEAT_OK prompt | Use isolated cron with file-based handoff |
| #4355 Session lock contention | Concurrent helpers block each other | Cap `maxConcurrent: 2` |
| #5433 Compaction overflow | Auto-recovery sometimes fails | Monitor, restart gateway if stuck |
| #6295 Subagent model override | Helpers may inherit Sonnet instead of Opus | Acceptable for most tasks |

---

## References

- [OpenClaw Proactive Agent Patterns](./OpenClaw_Proactive_Agent_Patterns__Current_Best_Practices_and_Bug_Workarounds.md) — Research on cron/heartbeat patterns
- [Bruba Multi-Agent Architecture](./bruba-multi-agent-architecture.md) — Original architecture design
- [Bruba Architecture 2.0 Implementation Packet](./bruba-architecture-packet.md) — Implementation checklist