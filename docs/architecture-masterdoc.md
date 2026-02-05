---
version: 3.11.0
updated: 2026-02-04
type: refdoc
project: planning
tags: [bruba, openclaw, multi-agent, architecture, cron, operations, guru, direct-message, docker, sandbox, security, rex]
---

# Bruba Multi-Agent Architecture Reference

Comprehensive reference for the Bruba multi-agent system. Covers the peer agent model, tool policy mechanics, cron-based proactive monitoring, heartbeat coordination, and security isolation.

---

## Executive Summary

Bruba uses a **five-agent architecture** with four peer agents and one service agent:

| Agent | Model | Role | Web Access |
|-------|-------|------|------------|
| **bruba-main** | Sonnet | Reactive — user conversations, file ops, routing | ❌ via bruba-web |
| **bruba-rex** | Sonnet | Reactive — alternate identity, separate phone binding | ❌ via bruba-web |
| **bruba-guru** | Opus | Specialist — technical deep-dives, debugging, architecture | ❌ via bruba-web |
| **bruba-manager** | Sonnet/Haiku | Proactive — heartbeat, cron coordination, monitoring | ❌ via bruba-web |
| **bruba-web** | Sonnet | Service — stateless web search, prompt injection barrier | ✅ Direct |

**Key architectural insight:** OpenClaw's tool inheritance model means subagents cannot have tools their parent lacks. Web isolation requires a **separate agent** (bruba-web), not subagent spawning. Main, Guru, and Manager are peers that communicate as equals; Web is a passive service all peers use.

**Specialist pattern:** Main routes technical deep-dives to Guru (Opus) for thorough analysis. Guru has full technical capabilities (read/write/edit/exec/memory) and can reach bruba-web for research. **Guru messages users directly via Signal** — returning only a one-sentence summary to Main. This keeps Main's context lightweight for everyday interactions while preserving deep reasoning capability.

**Proactive monitoring pattern:** Isolated cron jobs (cheap, stateless) detect conditions and write to inbox files. Manager's heartbeat (cheap, stateful) reads inbox, applies rules, delivers alerts. This separation keeps heartbeat fast while enabling rich monitoring.

**Prompt budget constraint:** OpenClaw injects AGENTS.md into context at session start. **Hard limit: 20,000 characters.** Despite the multi-agent architecture, component snippets, and detailed guidance, the assembled prompt must stay under this limit or it gets truncated. This means every component snippet needs to be concise — verbose examples and duplicated explanations bloat the prompt and risk losing critical instructions. When adding new components or updating existing ones, always check the assembled size: `wc -c exports/bot/bruba-main/core-prompts/AGENTS.md`.

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
│  • Routing        │ │             │  Role: Proactive          │
│  • Memory/PKM     │◄─────────────►│                           │
│                   │ sessions_send │  • Heartbeat checks       │
│                   │               │  • Cron job processing    │
└────────┬──────────┘               │  • Inbox → delivery       │
         │                          │  • Siri sync queries      │
         │ sessions_send            └─────────────┬─────────────┘
         │ (technical)                            │
         ▼                                        │
┌───────────────────┐                             │
│    bruba-guru     │                             │
│    ──────────     │                             │
│  Model: Opus      │                             │
│  Role: Specialist │                             │
│                   │                             │
│  • Technical      │                             │
│    deep-dives     │                             │
│  • Debugging      │                             │
│  • Architecture   │                             │
│  • Full file ops  │                             │
└────────┬──────────┘                             │
         │                                        │
         │ sessions_send                          │ sessions_send
         │ (research)                             │
         └───────────────┐            ┌───────────┘
                         ▼            ▼
               ┌─────────────────────────────────────┐
               │          bruba-web                  │
               │          ─────────                  │
               │  Model: Sonnet                      │
               │  Role: Service (passive)            │
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
| message | ✅ | Media attachments (voice responses, images) |
| sessions_spawn | ❌ | Not needed — uses bruba-web instead |
| web_search, web_fetch | ❌ | Security isolation — use bruba-web |
| browser, canvas | ❌ | Not needed |
| cron, gateway | ❌ | Admin tools |

**Heartbeat:** Disabled (`every: "0m"`)

**Bindings:** Signal DM (user-facing channel)

**Workspace:** `/Users/bruba/agents/bruba-main/`

---

### bruba-rex

**Purpose:** Alternate identity agent. Parallel to bruba-main with equivalent capabilities, bound to a different phone number for separate conversations.

**Model:** Sonnet

**Capabilities:**
| Tool | Status | Notes |
|------|--------|-------|
| read, write, edit, apply_patch | ✅ | Full file access within workspace |
| exec | ✅ | Via allowlist only |
| memory_search, memory_get | ✅ | PKM integration |
| sessions_send | ✅ | Communicate with other agents |
| message | ✅ | Media attachments (voice responses, images) |
| cron | ✅ | Schedule reminders, manage cron jobs |
| image | ✅ | Image generation |
| sessions_spawn | ❌ | Not needed — uses bruba-web instead |
| web_search, web_fetch | ❌ | Security isolation — use bruba-web |
| browser, canvas | ❌ | Not needed |
| gateway | ❌ | Admin tools |

**Heartbeat:** Disabled (`every: "0m"`)

**Bindings:** BlueBubbles DM (phone: <REDACTED-PHONE>)

**Workspace:** `/Users/bruba/agents/bruba-rex/`

**Distinction from bruba-main:**
- Bound to different phone number (separate contact routing)
- Can evolve distinct identity/personality via IDENTITY.md, SOUL.md
- Independent session/memory (no shared state with Main)
- Same technical capabilities as Main

---

### bruba-guru

**Purpose:** Technical specialist agent. Handles deep-dive analysis, debugging sessions, architecture reviews, and complex technical questions that need thorough reasoning.

**Model:** Opus

**Capabilities:**
| Tool | Status | Notes |
|------|--------|-------|
| read, write, edit, apply_patch | ✅ | Full file access within workspace |
| exec | ✅ | Via allowlist only |
| memory_search, memory_get | ✅ | PKM integration |
| sessions_send | ✅ | Communicate with bruba-web for research |
| sessions_list, session_status | ✅ | Monitor sessions |
| message | ✅ | Direct Signal delivery (bypasses Main relay) |
| sessions_spawn | ❌ | Not needed — uses bruba-web instead |
| web_search, web_fetch | ❌ | Security isolation — use bruba-web |
| browser, canvas | ❌ | Not needed |
| cron, gateway | ❌ | Admin tools |

**Heartbeat:** Disabled (`every: "0m"`)

**Session Reset:** Daily at 4am (matches Main's schedule)

**Workspace:** `/Users/bruba/agents/bruba-guru/`

**Directory Structure:**
```
bruba-guru/
├── workspace/       # Working files, analysis artifacts
├── memory/          # Persistent notes
└── results/         # Technical analysis outputs
```

**Shared Directory:** `/Users/bruba/agents/bruba-shared/`
```
bruba-shared/
├── packets/         # Work handoff packets between Main and Guru
└── context/         # Shared context files
```

**Routing from Main:**
Main routes technical questions to Guru via `sessions_send`:
- Auto-routing: Main detects technical content (code dumps, config files, debugging)
- Guru mode: User explicitly enters extended technical session
- Status check: User asks what Guru is working on

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
| read | ❌ | No file access |
| write | ❌ | No file creation |
| exec | ❌ | No command execution |
| edit | ❌ | No file modification |
| memory_* | ❌ | Stateless — no memory |
| sessions_send | ❌ | Can't initiate communication |
| sessions_spawn | ❌ | Can't create subagents |
| browser | ❌ | Search/fetch only |

**Heartbeat:** Disabled

**Memory:** Disabled (`memorySearch.enabled: false`)

**Sandbox:** ✅ **Enabled** — Docker container with `network: bridge` for web access

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

bruba-main has instructions (via `web-search` component) for using bruba-web:

```
User → Signal → bruba-main
Main: "I'll look that up"
Main → sessions_send("Search for X, summarize findings") → bruba-web
bruba-web: [searches, fetches, processes in Docker sandbox]
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

### sessions_send Format

When using `sessions_send` to reach another agent, use the `sessionKey` parameter (not `target`):

```json
{
  "tool": "sessions_send",
  "sessionKey": "agent:bruba-web:main",
  "message": "Search for X. Summarize findings.",
  "wait": true
}
```

The sessionKey format is `agent:<agent-id>:<session-name>`. For the default session, use `main`.

### Manager Pokes Main

```
Manager heartbeat → notices something requiring Main's attention
Manager → sessions_send("User has 3 overdue items, might want to check in") → bruba-main
Main → handles however appropriate (may message user, may just note)
Manager → Signal: "Heads up, I noticed X and let Bruba know"
```

### Siri Integration

**Problem:** Siri has a 10-15 second HTTP timeout, but Main (Opus) can take 20-30 seconds to process. Manager acts as a fast HTTP front door.

```
Siri → HTTPS POST (model: openclaw:manager) → bruba-manager
Manager: sessions_send to Main (timeoutSeconds=0, fire-and-forget)
Manager → "✓" to HTTP → Siri says "Got it"
[Meanwhile, async:]
Main processes (20-30s, full Opus thinking)
Main → message to Signal → Response appears in Signal
```

**Why Manager?** Even though `/v1/chat/completions` is synchronous, the HTTP response happens when the **agent** finishes. Manager finishes in ~2 seconds (just forwards and returns "✓"), beating Siri's timeout.

**iOS Shortcut structure:**
```
1. Ask for input / accept Siri dictation
2. Get Contents of URL
   - URL: https://your-bruba.ts.net/v1/chat/completions
   - Method: POST
   - Headers: Content-Type: application/json
   - Body: {
       "model": "openclaw:manager",
       "messages": [{
         "role": "user",
         "content": "[From Siri async] {{input}}"
       }]
     }
3. Get response → parse JSON → get assistant message
4. Speak Text: "Got it, I'll message you"
```

**Tag:** `[From Siri async]` — Manager forwards to Main, Main responds via Signal

### Voice Messages (Automatic STT/TTS)

OpenClaw handles voice transcription and text-to-speech automatically. Agents don't need to call whisper or TTS tools.

**How it works:**

1. **Inbound voice → automatic STT:** When a voice message arrives, OpenClaw transcribes it using Groq Whisper before delivering to the agent. The agent sees:
   ```
   [Audio] User audio message:
   <transcribed text here>
   ```

2. **Agent responds with text:** Just respond normally — no special handling needed.

3. **Automatic TTS (when inbound was voice):** OpenClaw converts the agent's text response to voice using ElevenLabs and sends both audio and text to Signal.

**Configuration** (in openclaw.json):
```json
{
  "tools.media.audio": {
    "enabled": true,
    "models": [{ "provider": "groq", "model": "whisper-large-v3-turbo" }]
  },
  "messages.tts": {
    "auto": "inbound",  // Voice response only when user sent voice
    "provider": "elevenlabs"
  }
}
```

**`auto` modes:**
- `"inbound"` — Voice reply only when user sent voice (recommended)
- `"always"` — Always reply with voice
- `"off"` — Never auto-TTS (manual only)

**Agent prompts are voice-agnostic:** The agent doesn't need to know about voice handling. It just sees transcribed text and responds with text.

### Message Tool (Media Attachments)

The `message` tool sends media files (images, files) to Signal. For voice, prefer automatic TTS over manual message tool.

**Tool syntax:**
```
message action=send target=uuid:<recipient-uuid> filePath=/path/to/file message="optional text"
```

**Use cases:**
- Sending images or files
- Manual voice when automatic TTS is disabled
- Siri async replies (no inbound voice context)

**Target format:** Use `uuid:<recipient-uuid>` from the incoming message's `From:` header.

**Setup requirement:** The user's Signal UUID must be in `USER.md` for Siri async replies:
```markdown
## Signal Identity
- **Signal UUID:** `uuid:XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX`
```

**Tool permissions:** The `message` tool must be in:
1. Global `tools.allow` (ceiling effect)
2. Agent's `tools.allow` (bruba-main, bruba-guru)

### Guru Direct Response Pattern

Unlike bruba-web (which returns results to the caller), bruba-guru messages the user directly via the `message` tool:

```
User → Signal → bruba-main
Main: "Routing to Guru"
Main → sessions_send("Debug this config: [...]") → bruba-guru
bruba-guru: [deep analysis - potentially 40K tokens]
bruba-guru → message tool → Signal (direct to user)
bruba-guru → returns to Main: "Summary: missing message tool in config"
Main tracks: "Guru: missing message tool in config"
```

**Why direct messaging:**
- Technical deep-dives generate 10-40K tokens of analysis
- If Main relayed these, Main's context would bloat rapidly
- Direct messaging keeps Main lightweight for everyday interactions
- Transcripts naturally separate (Guru's = technical, Main's = coordination)

**Guru returns summary only:** A one-liner helps Main track what Guru is working on without carrying the payload.

**Who has message tool:**

| Agent | Has message? | Use case |
|-------|--------------|----------|
| bruba-main | ✅ | Voice replies, Siri async |
| bruba-guru | ✅ | Direct technical responses |
| bruba-manager | ❌ | Uses sessions_send to Main |
| bruba-web | ❌ | Passive service |

**Note:** Guru doesn't need `NO_REPLY` because Guru isn't bound to Signal. Guru's return goes to Main (via sessions_send callback), not to Signal.

### Session Continuity and Context Persistence

Understanding how context persists (or doesn't) across agents is critical for proper use.

#### bruba-web: Session Context Only

| Aspect | Behavior |
|--------|----------|
| **Session** | Persists — conversation history within `agent:bruba-web:main` |
| **Memory** | Disabled — `memorySearch.enabled: false` |
| **PKM access** | None — cannot search or retrieve from memory/ |
| **Cross-session** | None — each new session starts fresh |

**What "stateless" means:** bruba-web has no long-term memory or PKM integration. However, within a single session, conversation context DOES persist. If you send multiple searches to the same session, bruba-web remembers previous exchanges.

**Implications:**
- Related searches can reference prior results ("search for more details on the second point")
- Context accumulates within the session (watch for bloat on heavy use)
- To clear context: `openclaw sessions reset --agent bruba-web`

**Design rationale:** Web content is untrusted. By disabling memory, we prevent prompt injection from persisting to other sessions or corrupting the knowledge base.

#### bruba-manager: Full Persistence

| Aspect | Behavior |
|--------|----------|
| **Session** | Persists — heartbeat runs in the same session |
| **Memory** | Enabled — `memory_search`, `memory_get` available |
| **State files** | Persists — `state/pending-tasks.json`, `state/nag-history.json` |
| **Cross-session** | Yes — session context carries forward |

**Implications:**
- Heartbeat context accumulates over time (context bloat risk)
- Manager can reference previous heartbeat findings
- State files provide persistence even if session is reset
- To clear context: `openclaw sessions reset --agent bruba-manager` (state files preserved)

**When to reset:** If Manager responses get slow or heartbeat exceeds time limits, reset the session. State files (nag history, pending tasks) survive the reset.

#### bruba-main: Full Persistence

| Aspect | Behavior |
|--------|----------|
| **Session** | Persists per conversation thread |
| **Memory** | Enabled — full PKM access |
| **Cross-session** | Via memory system |

Main uses standard OpenClaw conversation persistence. Long conversations may trigger compaction (safeguard mode).

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

| Job | Agent | Schedule | Status | Purpose |
|-----|-------|----------|--------|---------|
| **nightly-reset-prep** | bruba-manager | 3:55am daily | ✅ Active | Tell agents to write continuation packets |
| **nightly-reset-execute** | bruba-manager | 4:02am daily | ✅ Active | Send /reset to main and guru |
| **nightly-reset-wake** | bruba-manager | 4:07am daily | ✅ Active | Initialize fresh sessions |
| reminder-check | bruba-manager | 9am, 2pm, 6pm | ✅ Active | Detect overdue reminders |
| staleness-check | bruba-manager | Monday 10am | 📋 Proposed | Flag stale projects (14+ days) |
| calendar-prep | bruba-manager | 7am weekdays | 📋 Proposed | Surface prep-worthy meetings |
| morning-briefing | bruba-manager | 7:15am weekdays | 📋 Proposed | Daily summary to Signal |

### Manager Coordination Pattern (Nightly Reset)

**Important:** All nightly reset jobs route through bruba-manager, not directly to bruba-main.

**Why:** OpenClaw has a bug/limitation where `systemEvent` + `main session` = always disabled. The working pattern is `agentTurn` + `isolated session`, which fits manager's role as proactive coordinator.

```
3:55 AM  nightly-reset-prep
         └─→ Manager uses sessions_send to tell main/guru: "Write continuation packet"

4:02 AM  nightly-reset-execute
         └─→ Manager uses sessions_send to send "/reset" to main/guru

4:07 AM  nightly-reset-wake
         └─→ Manager uses sessions_send to ping main/guru/web: "Good morning"
```

**Benefits:**
- Main stays reactive (user conversations only)
- Each step can fail independently
- Manager already has sessions_send capability
- Uses `NO_REPLY` to avoid Signal spam

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

### Security Status

**Status:** ✅ bruba-web runs in Docker sandbox (as of 2026-02-04, OpenClaw 2026.2.1)

**Previous issue (resolved):** With `sandbox.scope: "agent"`, `sessions_send` could not see other agents' sessions. This was fixed in OpenClaw 2026.2.1 — cross-agent routing now works with per-agent sandbox.

**Current state:**
- **bruba-web:** Docker sandbox enabled (`mode: "all"`, `network: "bridge"`)
- **Other agents:** Running directly on host (`sandbox.mode: "off"` globally)

**Why only bruba-web sandboxed:**
- bruba-web handles untrusted web content — highest risk for prompt injection
- Other agents don't need network access, so tool-level restrictions suffice
- Can enable sandbox for other agents later if needed

**Remaining mitigations for non-sandboxed agents:**
- `exec-approvals.json` allowlist (enforced)
- `tools.allow/deny` lists per agent (enforced)
- Workspace isolation via separate directories

**Container auto-start:** `~/bin/bruba-start` warms the bruba-web sandbox container. A LaunchAgent attempts to run this on login (may require manual run after reboot).

### Docker Sandbox Architecture

bruba-web runs in a Docker container via OpenClaw's native sandbox support. Other agents run directly on host. Exec commands route through the node host process on the host machine.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          Mac Host (dadmini)                              │
│                                                                          │
│  PROTECTED (not mounted into containers):                                │
│  ├── ~/.openclaw/exec-approvals.json   ← Exec allowlist                  │
│  ├── ~/.openclaw/openclaw.json         ← Agent configs                   │
│  └── ~/agents/bruba-main/tools/        ← Scripts (ro overlay only)       │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │                    Node Host Process (port 18789)                  │  │
│  │  • Reads exec-approvals.json from HOST filesystem                  │  │
│  │  • Validates commands against allowlist                            │  │
│  │  • Executes approved commands ON THE HOST                          │  │
│  │  • Returns results to gateway                                      │  │
│  └────────────────────────────▲───────────────────────────────────────┘  │
│                               │ exec requests                            │
│  ┌────────────────────────────┼───────────────────────────────────────┐  │
│  │                   Docker Containers                                │  │
│  │  ┌─────────────────────────┴─────────────────────────────────────┐ │  │
│  │  │                   OpenClaw Gateway                             │ │  │
│  │  │                                                                │ │  │
│  │  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐           │ │  │
│  │  │  │ bruba-main   │ │ bruba-guru   │ │bruba-manager │           │ │  │
│  │  │  │ network:none │ │ network:none │ │ network:none │           │ │  │
│  │  │  └──────────────┘ └──────────────┘ └──────────────┘           │ │  │
│  │  │                                                                │ │  │
│  │  │  ┌──────────────┐                                              │ │  │
│  │  │  │  bruba-web   │  ← Only agent with network access            │ │  │
│  │  │  │network:bridge│                                              │ │  │
│  │  │  └──────────────┘                                              │ │  │
│  │  └────────────────────────────────────────────────────────────────┘ │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────────────┘
```

### Critical: File Tools vs Exec

**Simple rule:** Use full host paths for everything.

| Operation | Tool | Example |
|-----------|------|---------|
| **Read file** | `read` | `read /Users/bruba/agents/bruba-main/memory/docs/Doc - setup.md` |
| **Write file** | `write` | `write /Users/bruba/agents/bruba-main/workspace/output/result.md` |
| **Edit file** | `edit` | `edit /Users/bruba/agents/bruba-main/workspace/drafts/draft.md` |
| **List files** | `exec` | `exec /bin/ls /Users/bruba/agents/bruba-main/memory/` |
| **Find files** | `exec` | `exec /usr/bin/find /Users/bruba/agents/bruba-main/memory/ -name "*.md"` |
| **Search content** | `exec` | `exec /usr/bin/grep -r "pattern" /Users/bruba/agents/bruba-main/memory/` |
| **Run script** | `exec` | `exec /Users/bruba/agents/bruba-main/tools/tts.sh "hello" /tmp/out.wav` |
| **Memory search** | `memory_search` | `memory_search "topic"` (indexed content) |

**When to use what:**
- `read/write/edit` = when you need exactly that file operation
- `exec` = when you need shell utilities (ls, find, grep, head, tail, etc.)
- `memory_search` = when searching indexed content (most efficient for large memory)

**Allowlisted exec commands:**

| Category | Commands |
|----------|----------|
| File listing | `/bin/ls` |
| File viewing | `/bin/cat`, `/usr/bin/head`, `/usr/bin/tail` |
| Searching | `/usr/bin/grep`, `/usr/bin/find` |
| Info | `/usr/bin/wc`, `/usr/bin/du`, `/usr/bin/uname`, `/usr/bin/whoami` |
| Custom tools | `/Users/bruba/agents/bruba-main/tools/*.sh` |
| System utils | `/opt/homebrew/bin/remindctl`, `/opt/homebrew/bin/icalBuddy` |

**File System Layout (host paths):**

| Directory | Path | Access | Purpose |
|-----------|------|--------|---------|
| **Agent workspace** | `/Users/bruba/agents/bruba-main/` | Read-write | Prompts, memory, working files |
| **Memory** | `/Users/bruba/agents/bruba-main/memory/` | Read-write | Docs, transcripts, repos |
| **Tools** | `/Users/bruba/agents/bruba-main/tools/` | Read (exec only) | Per-agent scripts (read-only in sandbox) |
| **Shared packets** | `/Users/bruba/agents/bruba-shared/packets/` | Read-write | Main↔Guru handoff |

**Security:**
- Tools directory (`/Users/bruba/agents/{agent}/tools/`) is read-only in sandbox mode
- Each agent has its own tools directory
- Only allowlisted commands can be executed

**Examples:**

✅ **Correct:**
- `read /Users/bruba/agents/bruba-main/memory/docs/Doc - setup.md`
- `write /Users/bruba/agents/bruba-main/workspace/output/result.md`
- `exec /bin/ls /Users/bruba/agents/bruba-main/memory/`
- `exec /usr/bin/grep -r "pattern" /Users/bruba/agents/bruba-main/`
- `exec /Users/bruba/agents/bruba-main/tools/tts.sh "hello" /tmp/out.wav`

❌ **Incorrect:**
- `write /Users/bruba/agents/bruba-main/tools/new.sh` → tools/ is read-only in sandbox

### Sandbox Configuration

**Global defaults** (`agents.defaults.sandbox` in openclaw.json):

```json
{
  "mode": "all",
  "scope": "agent",
  "workspaceAccess": "rw",
  "docker": {
    "readOnlyRoot": true,
    "network": "none",
    "memory": "512m",
    "binds": [
      "/Users/bruba/agents/bruba-shared/packets:/workspaces/shared/packets:rw",
      "/Users/bruba/agents/bruba-shared/context:/workspaces/shared/context:rw",
      "/Users/bruba/agents/bruba-shared/repo:/workspaces/shared/repo:ro"
    ]
  }
}
```

**Per-agent config** (each agent needs `sandbox.workspaceRoot` to match their `workspace`):

```json
{
  "id": "bruba-main",
  "workspace": "/Users/bruba/agents/bruba-main",
  "sandbox": {
    "workspaceRoot": "/Users/bruba/agents/bruba-main"
  }
}
```

**Key settings:**
- `sandbox.workspaceRoot` = agent's `workspace` path (tells OpenClaw file tools where `/workspace/` is)
- Tools are at `/Users/bruba/agents/{agent}/tools/` (per-agent, read-only in sandbox)

**Per-agent overrides:**

| Agent | Override | Reason |
|-------|----------|--------|
| bruba-main | `workspaceRoot` | File tool validation |
| bruba-guru | `workspaceRoot` | File tool validation |
| bruba-manager | `workspaceRoot` | File tool validation |
| bruba-web | `workspaceRoot` + `network: "bridge"` | Needs internet for web_search |

### Sandbox Tool Policy (IMPORTANT)

**There's a sandbox-level tool ceiling** in addition to global and agent-level tool policies:

```json
{
  "tools": {
    "sandbox": {
      "tools": {
        "allow": [
          "group:memory",
          "group:media",
          "group:sessions",
          "exec",
          "group:web",
          "message"    // Must be here for containerized agents!
        ]
      }
    }
  }
}
```

**Tool availability hierarchy (all must allow):**
1. Global `tools.allow` → ceiling for all agents
2. Agent `tools.allow` → ceiling for specific agent
3. **Sandbox `tools.sandbox.tools.allow`** → ceiling for containerized agents

**Gotcha:** If a tool is allowed at global and agent level but NOT in `tools.sandbox.tools.allow`, containerized agents won't have it. This caused the `message` tool to disappear after sandbox migration.

### Container Path Mapping

Each agent's workspace is mounted at `/workspace/` inside its container.

| Host Path | Container Path | Notes |
|-----------|----------------|-------|
| `/Users/bruba/agents/bruba-main/` | `/workspace/` | bruba-main's container |
| `/Users/bruba/agents/bruba-guru/` | `/workspace/` | bruba-guru's container |
| `/Users/bruba/agents/bruba-manager/` | `/workspace/` | bruba-manager's container |
| `/Users/bruba/agents/bruba-web/` | `/workspace/` | bruba-web's container |
| `/Users/bruba/agents/bruba-shared/packets/` | `/workspaces/shared/packets/` | All containers |
| `/Users/bruba/agents/bruba-shared/context/` | `/workspaces/shared/context/` | All containers |
| `/Users/bruba/agents/bruba-shared/repo/` | `/workspaces/shared/repo/` | All containers (ro) |

### Per-Agent Access Matrix

#### bruba-main

| Resource | Container Path | Access | Notes |
|----------|----------------|--------|-------|
| Workspace root | `/workspace/` | **rw** | Prompts, working files |
| memory/ | `/workspace/memory/` | **rw** | PKM docs, transcripts (synced by operator) |
| tools/ | `/workspace/tools/` | **ro** | Scripts (overlay mount, read-only) |
| workspace/ | `/workspace/workspace/` | **rw** | Working files |
| artifacts/ | `/workspace/artifacts/` | **rw** | Generated artifacts |
| output/ | `/workspace/output/` | **rw** | Script outputs |
| Shared packets | `/workspaces/shared/packets/` | **rw** | Main↔Guru handoff |
| Shared context | `/workspaces/shared/context/` | **rw** | Shared context files |
| Shared repo | `/workspaces/shared/repo/` | **ro** | bruba-godo reference |
| Host filesystem | N/A | **none** | Cannot access |
| exec-approvals.json | N/A | **none** | Cannot access |
| openclaw.json | N/A | **none** | Cannot access |

#### bruba-guru

| Resource | Container Path | Access | Notes |
|----------|----------------|--------|-------|
| Workspace root | `/workspace/` | **rw** | Prompts, analysis |
| workspace/ | `/workspace/workspace/` | **rw** | Technical analysis |
| memory/ | `/workspace/memory/` | **rw** | Persistent notes |
| tools/ | `/workspace/tools/` | **ro** | Scripts (defense-in-depth) |
| results/ | `/workspace/results/` | **rw** | Analysis outputs |
| Shared packets | `/workspaces/shared/packets/` | **rw** | Main↔Guru handoff |
| Shared context | `/workspaces/shared/context/` | **rw** | Shared context files |
| Shared repo | `/workspaces/shared/repo/` | **ro** | bruba-godo reference |
| Host filesystem | N/A | **none** | Cannot access |

#### bruba-manager

| Resource | Container Path | Access | Notes |
|----------|----------------|--------|-------|
| Workspace root | `/workspace/` | **rw** | Prompts |
| inbox/ | `/workspace/inbox/` | **rw** | Cron job outputs |
| state/ | `/workspace/state/` | **rw** | Persistent tracking |
| tools/ | `/workspace/tools/` | **ro** | Scripts (defense-in-depth) |
| results/ | `/workspace/results/` | **rw** | Research outputs |
| memory/ | `/workspace/memory/` | **rw** | Agent memory |
| Shared packets | `/workspaces/shared/packets/` | **rw** | Work packets |
| Shared context | `/workspaces/shared/context/` | **rw** | Shared context |
| Shared repo | `/workspaces/shared/repo/` | **ro** | bruba-godo reference |
| Host filesystem | N/A | **none** | Cannot access |

#### bruba-web

| Resource | Container Path | Access | Notes |
|----------|----------------|--------|-------|
| Workspace root | `/workspace/` | **rw** | Prompts only |
| tools/ | `/workspace/tools/` | **ro** | Scripts (defense-in-depth) |
| results/ | `/workspace/results/` | **rw** | Research outputs |
| Shared packets | `/workspaces/shared/packets/` | **rw** | (rarely used) |
| Shared context | `/workspaces/shared/context/` | **rw** | (rarely used) |
| Shared repo | `/workspaces/shared/repo/` | **ro** | bruba-godo reference |
| Host filesystem | N/A | **none** | Cannot access |
| **Internet** | via bridge network | **yes** | Only agent with web access |

### What Containers CANNOT Access

These resources are explicitly NOT mounted into any container:

| Resource | Why Protected |
|----------|---------------|
| `~/.openclaw/exec-approvals.json` | **Critical:** Prevents privilege self-escalation |
| `~/.openclaw/openclaw.json` | Config shouldn't be agent-writable |
| `~/.clawdbot/agents/*/auth-profiles.json` | API keys stay on host |
| `/Users/bruba/` (general) | No arbitrary host filesystem access |
| Other agents' workspaces | Cross-agent isolation |
| `/tmp/` on host | Container has its own /tmp |

### Security Implications

#### Privilege Escalation Prevention

**Before sandbox:** Agent could edit `exec-approvals.json` to allow any command.

**After sandbox:**
1. `exec-approvals.json` not mounted → agent cannot read or modify
2. Even if agent somehow got the file content, it couldn't write changes back
3. Node host reads allowlist from HOST filesystem, outside container

#### Tool Script Integrity

**Before sandbox:** Agent could modify its own tool scripts (e.g., make `whisper.sh` exfiltrate data).

**After sandbox:**
1. **ALL agents** have `tools/` mounted read-only (defense-in-depth)
2. Write attempts fail with "Read-only file system"
3. Original scripts on host remain unchanged
4. Future tools are automatically protected when added

#### Web Content Isolation

**bruba-web's isolation:**
1. Has internet access (bridge network)
2. Has NO memory persistence (`memorySearch.enabled: false`)
3. Cannot use `sessions_send` (can't initiate contact)
4. Cannot modify other agents' files
5. Web content stays in bruba-web's context
6. Only structured summaries cross to other agents

**Prompt injection defense:** If fetched web content contains "ignore previous instructions," it's processed in bruba-web's isolated context. bruba-web has no tools to affect other agents or the host.

#### Network Isolation

| Agent | Network | Can Reach |
|-------|---------|-----------|
| bruba-main | none | Only gateway (internal) |
| bruba-guru | none | Only gateway (internal) |
| bruba-manager | none | Only gateway (internal) |
| bruba-web | bridge | Internet + gateway |

**Implication:** Even if an agent were compromised, it cannot make outbound network connections (except bruba-web, which is already the web-facing agent).

### Defense in Depth Summary

| Layer | Protection | Threat Mitigated |
|-------|------------|------------------|
| Docker containers | Filesystem isolation | Host filesystem access |
| Bind mount restrictions | Selective access only | Reading sensitive configs |
| Read-only mounts | tools/ immutable | Tool script tampering |
| Network isolation | No outbound (except web) | Data exfiltration |
| Separate bruba-web | Web isolated from others | Prompt injection spread |
| Node host exec | Allowlist enforced on host | Command injection |
| exec-approvals.json on host | Not in container | Privilege escalation |
| Per-agent containers | Workspace separation | Cross-agent contamination |

### Container Lifecycle

**Startup:**
1. Gateway LaunchAgent starts on system boot (`ai.openclaw.gateway.plist`)
2. Gateway creates containers on-demand when agents are first used
3. No manual `docker start` required

**Runtime:**
- Containers persist while gateway runs
- Each agent gets its own container (scope: agent)
- Container state survives agent session resets

**Shutdown:**
- `openclaw gateway stop` gracefully stops containers
- Containers auto-prune after 24h idle (configurable)

**Verification:**
```bash
# From bruba-godo
./tools/test-sandbox.sh           # All tests
./tools/test-sandbox.sh --security    # Security only
./tools/test-sandbox.sh --status      # Container status
```

### Debugging Sandbox Issues

```bash
# Check sandbox configuration
openclaw sandbox explain

# List running containers
openclaw sandbox list

# Recreate containers after config change
openclaw sandbox recreate --all

# Exec into container for debugging
docker exec -it openclaw-sandbox-bruba-main /bin/sh

# Verify isolation (should fail)
docker exec openclaw-sandbox-bruba-main cat /root/.openclaw/exec-approvals.json
docker exec openclaw-sandbox-bruba-main ls /Users/bruba/

# Verify tools/:ro on ALL agents (should all fail)
docker exec openclaw-sandbox-bruba-main touch /workspace/tools/test.txt
docker exec openclaw-sandbox-bruba-guru touch /workspace/tools/test.txt
docker exec openclaw-sandbox-bruba-manager touch /workspace/tools/test.txt
docker exec openclaw-sandbox-bruba-web touch /workspace/tools/test.txt
```

---

## Part 8: Operations

### ⚠️ Critical Operational Warning: Signal Rate Limits

**NEVER repeatedly trigger Signal messages during testing.** Signal has strict rate limits and anti-spam detection that WILL get the account logged out.

**Safe testing patterns:**
- Use `NO_REPLY` in cron job messages to suppress unnecessary Signal delivery
- Test with direct agent messages that don't go to Signal
- Use isolated sessions that write to files instead of messaging
- When testing post-reset-wake or similar multi-agent pings, do ONE test run, not repeated runs

**Unsafe patterns (AVOID):**
- Running cron job tests multiple times in quick succession
- Triggering heartbeats repeatedly to "see if it works"
- Using `cron run --force` repeatedly on Signal-delivering jobs
- Any loop or script that sends multiple Signal messages

**If logged out:** You'll need to re-link the Signal account via signal-cli. This requires the phone and is disruptive.

### Signal-CLI Installation

**Use the brew version, not OpenClaw's bundled version.**

OpenClaw may auto-download signal-cli to `~/.openclaw/tools/signal-cli/`. On macOS ARM64 (Apple Silicon), this can download the wrong architecture (Linux x86-64), causing "exec format error" or "spawn ENOEXEC" errors.

**Fix:**
1. Install via brew: `brew install signal-cli`
2. Update OpenClaw config to use brew version:
   ```bash
   jq '.channels.signal.cliPath = "/opt/homebrew/bin/signal-cli"' \
     ~/.openclaw/openclaw.json > /tmp/oc.json && \
     mv /tmp/oc.json ~/.openclaw/openclaw.json
   ```
3. Restart gateway: `openclaw gateway restart`
4. Verify: `openclaw doctor | grep Signal`

**Delete the broken bundled version** (optional but recommended):
```bash
rm -rf ~/.openclaw/tools/signal-cli
```

The brew version is preferred anyway — brew handles updates automatically.

**Signal data location:** Account credentials and keys are stored in `~/.local/share/signal-cli/`, not in the installation directory. Deleting the binary doesn't affect your linked account.

### Bot Transport Abstraction

The `./tools/bot` wrapper (and `bot_exec()` in lib.sh) supports multiple transports for running commands as the bot user:

| Transport | `BOT_TRANSPORT=` | Use Case |
|-----------|------------------|----------|
| **sudo** | `sudo` | Same machine, different user (fastest) |
| **Tailscale SSH** | `tailscale-ssh` | Remote via Tailscale's SSH server |
| **SSH** | `ssh` | Remote via regular SSH with multiplexing (default) |

**Configuration in config.yaml:**
```yaml
transport: sudo  # Options: sudo, tailscale-ssh, ssh
```

Override per-command if needed: `BOT_TRANSPORT=ssh ./tools/bot ls ~/agents`

**For same-machine setups** (bruba is a local account on the operator machine):
1. Add sudoers entry: `dadbook ALL=(bruba) NOPASSWD: ALL` in `/etc/sudoers.d/bruba-admin`
2. Set `transport: sudo` in config.yaml
3. Commands execute instantly without SSH overhead

**For remote setups:**
- Default `ssh` transport uses multiplexing for faster subsequent connections
- `tailscale-ssh` requires `sudo tailscale set --ssh` on the bot machine

**Scripts using lib.sh** (mirror.sh, push.sh, etc.) automatically use the configured transport via `bot_exec()`.

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

### New Agent Auth Setup

When adding a new agent, you must copy the auth profile from an existing agent:

```bash
# Create the agent's clawdbot directory
mkdir -p ~/.clawdbot/agents/<new-agent-id>

# Copy auth from existing agent
cp ~/.clawdbot/agents/bruba-main/auth-profiles.json \
   ~/.clawdbot/agents/<new-agent-id>/
```

**Why:** Each agent has its own `agentDir` where OpenClaw looks for `auth-profiles.json`. Without this file, the agent can't authenticate with model providers.

**Example (bruba-web):**
```bash
mkdir -p /Users/bruba/.clawdbot/agents/bruba-web
cp /Users/bruba/.clawdbot/agents/bruba-main/auth-profiles.json \
   /Users/bruba/.clawdbot/agents/bruba-web/
```

**Example (bruba-guru):**
```bash
mkdir -p /Users/bruba/.clawdbot/agents/bruba-guru
cp /Users/bruba/.clawdbot/agents/bruba-main/auth-profiles.json \
   /Users/bruba/.clawdbot/agents/bruba-guru/
```

**Important:** Auth profiles live in `~/.clawdbot/agents/`, NOT `~/.openclaw/agents/`. The `.openclaw/agents/` directory holds session data.

### Priming New Agent Sessions

New agents have no session until they receive their first message. To initialize:

```bash
# Send a test message to create the session
openclaw agent --agent <agent-id> --message "Test initialization. Confirm you're operational."
```

**Why:** Some agent features (like tool availability reporting) only work after a session exists. Priming ensures the agent is ready before production use.

**Example (bruba-web):**
```bash
openclaw agent --agent bruba-web \
  --message "Test: Search for 'OpenClaw documentation'. Return a 2-sentence summary." \
  --timeout 120
```

Expected response should show web_search working and return structured results.

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

### New Agent Has No API Key

**Symptom:** `No API key found for provider "anthropic". Auth store: ~/.clawdbot/agents/<id>/auth-profiles.json`

**Cause:** New agent doesn't have auth-profiles.json in its agentDir.

**Fix:**
```bash
cp ~/.clawdbot/agents/bruba-main/auth-profiles.json \
   ~/.clawdbot/agents/<new-agent-id>/
```

### Agent Tools Not Available

**Symptom:** Agent claims it doesn't have tools that are in its config (e.g., bruba-web says "I don't have web_search").

**Possible causes:**

1. **No session yet** — Agent hasn't been initialized. Send a test message:
   ```bash
   openclaw agent --agent <id> --message "Test initialization"
   ```

2. **Global allowlist ceiling** — See "Global tools.allow Ceiling Effect" in Known Issues. Tools must be in global `tools.allow` for any agent to use them.

3. **Config not reloaded** — Restart gateway after config changes:
   ```bash
   openclaw gateway restart
   ```

---

## Part 10: Configuration Reference

### config.yaml (Operator Source of Truth)

As of v3.8.3, `config.yaml` is the source of truth for OpenClaw settings. The operator controls configuration locally, then syncs to the bot via `sync-openclaw-config.sh`.

**Key sections:**

```yaml
# Global defaults (synced to agents.defaults in openclaw.json)
openclaw:
  model:
    primary: opus
    fallbacks: [anthropic/claude-sonnet-4-5, anthropic/claude-haiku-4-5]
  compaction:
    mode: safeguard
    reserve_tokens_floor: 20000
    memory_flush:
      enabled: true
      soft_threshold_tokens: 40000
      prompt: |-
        Write to memory/CONTINUATION.md immediately...
  context_pruning:
    mode: cache-ttl
    ttl: 1h
  sandbox:
    mode: "off"
  max_concurrent: 4

# Per-agent settings (synced to agents.list[] in openclaw.json)
agents:
  bruba-main:
    model: sonnet                    # String alias or object
    heartbeat: false                 # false = disabled (every: "0m")
    tools_allow: [...]
    tools_deny: [...]

  bruba-manager:
    model:
      primary: anthropic/claude-sonnet-4-5
      fallbacks: [anthropic/claude-haiku-4-5]
    heartbeat:
      every: 15m
      model: anthropic/claude-haiku-4-5
      target: signal
      active_hours:
        start: "07:00"
        end: "22:00"

  bruba-web:
    model: anthropic/claude-sonnet-4-5
    heartbeat: false
    memory_search: false             # Stateless (memorySearch.enabled)
```

**Syncing:**

```bash
./tools/sync-openclaw-config.sh --check      # Show discrepancies
./tools/sync-openclaw-config.sh              # Apply changes
./tools/sync-openclaw-config.sh --dry-run    # Preview without applying
```

**What's NOT managed by config.yaml:**
- `auth.profiles` - API keys/tokens
- `channels` - Signal/Telegram secrets
- `gateway` - Port/auth config
- `env.vars` - API keys
- `plugins`, `skills`, `messages` - Runtime config

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
      "allow": ["bruba-main", "bruba-manager", "bruba-web", "bruba-guru"]
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

### Bug: Voice Messages Cause Silent Compaction

**Status:** Open — needs OpenClaw fix

**Symptoms:**
- Bruba loses context mid-conversation after receiving a voice message
- Session claims "0 compactions" but context is clearly truncated
- Earlier messages disappear, replaced by a summary

**Root cause:** Voice messages include **raw audio binary data inline** in the context:

```
[Audio] User text: ... <media:audio> Transcript: Hello
<file name="abc123.mp3" mime="text/plain">
[MASSIVE BINARY BLOB - null bytes and garbage data]
</file>
```

This binary blob causes massive token inflation (~50K+ tokens for a short voice message), triggering compaction.

**Evidence:** The session JSONL shows actual `{"type":"compaction"}` events, but `compactionCount` in session metadata stays at 0. This is a secondary bug — compaction counting doesn't match actual compaction events.

**Workarounds:**
1. **Increase compaction threshold:** Bump `softThresholdTokens` to 100K+ to delay compaction
   ```bash
   jq '.agents.defaults.compaction.memoryFlush.softThresholdTokens = 100000' \
     ~/.openclaw/openclaw.json > /tmp/oc.json && mv /tmp/oc.json ~/.openclaw/openclaw.json
   ```
2. **Use text instead of voice** when context preservation is critical
3. **Turn off experimental session memory**, as suggested by someone online. Not clear why this would matter, but a few people have reported it working for some reason. Just set memorySearch.experimental.sessionMemory to false in openclaw.json.

**Proper fix needed:** OpenClaw should exclude binary content from context, keeping only the transcript.

**Reference:** Full investigation in `docs/cc_logs/2026-02-03-voice-message-context-crash.md`

### Global tools.allow Ceiling Effect (Needs Confirmation)

**Status:** Observed behavior — needs confirmation from OpenClaw docs/community

**Observed:** When `tools.allow` is set at the global level (`tools.allow` in openclaw.json root), it appears to create a **ceiling** for all agents. Even if an agent has a tool in its own `tools.allow`, it won't work unless the tool is also in the global list.

**Example:** bruba-web had `web_search` in its agent-level `tools.allow`, but the tool wasn't available until `web_search` was added to the global `tools.allow`.

**Current workaround:** Include all tools that ANY agent needs in global `tools.allow`. Use agent-level `tools.deny` to restrict specific agents.

```json
{
  "tools": {
    "allow": ["read", "write", "web_search", "web_fetch", ...],  // Global ceiling
    ...
  },
  "agents": {
    "list": [
      {
        "id": "bruba-main",
        "tools": {
          "deny": ["web_search", "web_fetch"]  // Main can't use these
        }
      },
      {
        "id": "bruba-web",
        "tools": {
          "allow": ["web_search", "web_fetch", "read", "write"]  // Web can
        }
      }
    ]
  }
}
```

**TODO:** Confirm this behavior with OpenClaw documentation or community. The expected behavior (agent-level allow should work independently) may be a bug or may require different config structure.

---

## Part 12: Implementation Status

### Complete

| Item | Status | Notes |
|------|--------|-------|
| OpenClaw migration | ✅ | v2026.1.30 |
| bruba-main config | ✅ | Sonnet (was Opus, changed due to fallback-induced compaction), no web |
| bruba-manager config | ✅ | Sonnet/Haiku heartbeat |
| Agent-to-agent comms | ✅ | `agentToAgent.enabled` |
| Directory structure | ✅ | Workspaces created |
| Siri integration | ✅ | Via tailscale serve; async routes through Manager |
| bruba-godo tooling | ✅ | Multi-agent prompt assembly |
| bruba-web agent | ✅ | Configured, auth setup, session primed |
| Tool restriction cleanup | ✅ | Main/Manager deny web tools, use bruba-web |
| bruba-web Docker sandbox | ✅ | Enabled with bridge network (2026-02-04) |
| web-search component | ✅ | Prompts for Main to use bruba-web |

### In Progress

| Item | Status | Notes |
|------|--------|-------|
| Global allowlist investigation | 🔄 | Confirm ceiling behavior with OpenClaw docs |

### Planned

| Item | Priority | Notes |
|------|----------|-------|
| Cron: reminder-check | High | First proactive job |
| Full agent sandboxing | Medium | Enable Docker sandbox for all agents (optional) |
| Cron: other jobs | Medium | After reminder-check stable |

---

## Part 13: Prompt Assembly and Components

Prompts (AGENTS.md, TOOLS.md, etc.) are assembled from config-driven section lists. The operator manages templates and components in bruba-godo, then pushes assembled prompts to the bot.

### Assembly Pipeline

```
templates/prompts/         → Base prompts (committed)
components/*/prompts/      → Component snippets (committed)
user/prompts/              → User customizations (gitignored)
mirror/*/prompts/          → Bot state (gitignored)
        ↓
   assemble-prompts.sh
        ↓
exports/bot/*/core-prompts/ → Assembled output
        ↓
      push.sh
        ↓
   Bot workspace
```

### Section Types

| Type | Syntax | Resolves To |
|------|--------|-------------|
| Base template | `base` | `templates/prompts/{NAME}.md` |
| Manager base | `manager-base` | `templates/prompts/manager/{NAME}.md` |
| Component | `name` | `components/{name}/prompts/{NAME}.snippet.md` |
| Component variant | `name:variant` | `components/{name}/prompts/{NAME}.{variant}.snippet.md` |
| Template section | `name` | `templates/prompts/sections/{name}.md` |
| Bot-managed | `bot:name` | Preserved from mirror (`<!-- BOT-MANAGED: name -->`) |

### Component Variants

Components can provide multiple prompt snippets for different agents or roles using the `component:variant` syntax.

**Why variants?** Some capabilities need different prompts depending on the agent's role:

| Component | Variant | Agent | Purpose |
|-----------|---------|-------|---------|
| `siri-async` | `:router` | bruba-manager | Receives HTTP, forwards to Main |
| `siri-async` | `:handler` | bruba-main | Processes forwarded requests |
| `web-search` | `:consumer` | bruba-main | How to use bruba-web |
| `web-search` | `:service` | bruba-web | How to be bruba-web (planned) |

**File naming:**
- Default: `components/{name}/prompts/{NAME}.snippet.md`
- Variant: `components/{name}/prompts/{NAME}.{variant}.snippet.md`

**Config example:**
```yaml
agents:
  bruba-main:
    agents_sections:
      - siri-async:handler    # → AGENTS.handler.snippet.md
      - web-search            # → AGENTS.snippet.md (default)

  bruba-manager:
    agents_sections:
      - siri-async:router     # → AGENTS.router.snippet.md
```

**No fallback rule:** If you specify `:variant`, that exact file must exist. The system won't fall back to the default file — this prevents silent misconfiguration.

### Allowlist Variants

Allowlist files can also have variants for component-specific exec permissions:

- Default: `components/{name}/allowlist.json`
- Variant: `components/{name}/allowlist.{variant}.json`

### Component Organization

```
components/
├── siri-async/
│   ├── README.md
│   └── prompts/
│       ├── AGENTS.router.snippet.md   # Manager: forward to Main
│       └── AGENTS.handler.snippet.md  # Main: handle forwarded
├── web-search/
│   ├── README.md
│   ├── allowlist.json
│   └── prompts/
│       └── AGENTS.snippet.md          # Default (no variant)
├── reminders/
│   ├── README.md
│   ├── allowlist.json
│   └── prompts/
│       ├── AGENTS.snippet.md
│       └── TOOLS.snippet.md
└── ...
```

### Assembly Commands

```bash
# Assemble all agents
./tools/assemble-prompts.sh

# Single agent
./tools/assemble-prompts.sh --agent=bruba-main

# Preview without writing
./tools/assemble-prompts.sh --dry-run --verbose

# Skip conflict check
./tools/assemble-prompts.sh --force
```

### Conflict Detection

Before pushing, the system detects if the bot has made changes that would be overwritten:

```bash
# Check for conflicts
./tools/detect-conflicts.sh

# Show specific component diff
./tools/detect-conflicts.sh --diff siri-async:handler
```

**Conflict types:**
1. New bot-managed sections (bot created a new `<!-- BOT-MANAGED: x -->`)
2. Edited components (bot modified content inside a `<!-- COMPONENT: x -->`)

---

## Quick Reference

**Main can't search?** By design. Use `sessions_send` with `sessionKey: "agent:bruba-web:main"`.

**Manager can't search?** Same pattern. Use `sessions_send` with `sessionKey: "agent:bruba-web:main"`.

**Subagent has no web tools?** Parent's restrictions propagate. Use separate agent.

**Heartbeat delivering garbage?** Bug #3589. Use file-based inbox.

**Why both cron and heartbeat?** Cron = cheap detection (isolated). Heartbeat = coordination (stateful).

**Files vs messages?** Files persist, survive restarts. Messages for immediate delivery.

**Cross-context denied?** Use `sessions_send` between agents, not `message` tool.

**Agent can edit allowlist?** Known gap. Node host migration fixes this.

**New agent has no API key?** Copy auth-profiles.json from existing agent's agentDir.

**Agent tools not working?** Check global tools.allow ceiling, prime session, restart gateway.

**Does bruba-web remember previous searches?** Yes, within the same session. No long-term memory though.

**Manager getting slow?** Context bloat. Reset session: `openclaw sessions reset --agent bruba-manager`.

**Voice response not sending?** Check `messages.tts.auto` config. For manual, use message tool with `NO_REPLY`.

**Guru response too long for Main?** Guru should message directly via message tool, return summary only.

**Technical question routing?** Auto-route to Guru → Guru messages user directly → Main gets one-liner summary.

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
| 3.11.0 | 2026-02-04 | **bruba-rex agent:** Added new alternate identity agent bound to different phone number. Same capabilities as Main, independent identity. Added bindings section to config.yaml for declarative routing management. Updated agent count to five-agent architecture. |
| 3.10.0 | 2026-02-04 | **Component variant support:** Added `component:variant` syntax for components that need different prompts per agent. Merged `http-api` and `siri-async` components into `siri-async` with `:router` (Manager) and `:handler` (Main) variants. Added Part 13 documenting prompt assembly and component organization. |
| 3.9.0 | 2026-02-04 | **Docker sandbox enabled for bruba-web:** Cross-agent session visibility bug fixed in OpenClaw 2026.2.1. bruba-web now runs in Docker container (`sandbox.mode: "all"`, `network: "bridge"`). Added `web-search` component to bruba-main prompts (instructions for using bruba-web via `sessions_send`). Added `~/bin/bruba-start` script and LaunchAgent for container auto-warm. |
| 3.8.4 | 2026-02-03 | **Voice compaction bug documented:** Added known issue for voice messages causing silent context compaction (binary audio data in context). Also documented compactionCount mismatch bug. |
| 3.8.3 | 2026-02-03 | **OpenClaw config migration:** config.yaml is now source of truth for openclaw.json settings. New `openclaw:` section for global defaults, per-agent model/heartbeat config. New `sync-openclaw-config.sh` replaces `update-agent-tools.sh`. Extended `parse-yaml.py` with `--to-json` mode for snake_case→camelCase conversion. |
| 3.8.2 | 2026-02-03 | **Compaction fixes:** bruba-main switched from Opus to Sonnet (mid-session fallback was triggering compaction). softThresholdTokens increased 8K→40K. bruba-guru retains Opus. |
| 3.8.1 | 2026-02-03 | **Bot transport abstraction:** `./tools/bot` and `bot_exec()` now support multiple transports (sudo, tailscale-ssh, ssh). Enables same-machine operation without SSH overhead when bruba is a local account. |
| 3.8.0 | 2026-02-03 | **Siri async via Manager:** Manager acts as fast HTTP front door for Siri async requests. Uses `sessions_send timeoutSeconds=0` (fire-and-forget) to forward to Main. Beats Siri's 10-15s timeout. Added `siri-async` component for Manager. |
| 3.7.0 | 2026-02-03 | **Automatic voice handling:** OpenClaw now handles STT (Groq Whisper) and TTS (ElevenLabs) automatically. Agents are voice-agnostic. Updated Part 4 voice documentation. |
| 3.6.0 | 2026-02-03 | **Manager coordination pattern:** Nightly reset jobs now route through bruba-manager (isolated + agentTurn) instead of directly to bruba-main (systemEvent + main = disabled bug). Added Signal rate limit warning. |
| 3.5.3 | 2026-02-03 | **Sandbox disabled:** Agent-to-agent session visibility broken in sandbox mode. Set `sandbox.mode: "off"` until OpenClaw fixes. Added `/wake` skill. *(Fixed in 3.9.0)* |
| 3.5.2 | 2026-02-03 | **Sandbox tool policy:** Documented tools.sandbox.tools.allow ceiling (message tool missing fix) |
| 3.5.1 | 2026-02-03 | **Defense-in-depth:** ALL agents now have tools/:ro (not just bruba-main), updated access matrices and debugging commands |
| 3.5.0 | 2026-02-03 | **Part 7 major expansion:** Docker sandbox implementation details, per-agent access matrix (read/write/none for every resource), network isolation matrix, exec vs file path split, security implications, container lifecycle, debugging commands |
| 3.4.0 | 2026-02-03 | **Guru direct response pattern:** Guru messages users directly via message tool, returns only summary to Main. Added message tool to bruba-guru. Updated topology notes, communication patterns, Quick Reference. |
| 3.3.3 | 2026-02-02 | Added USER.md Signal UUID setup requirement for Siri async replies |
| 3.3.2 | 2026-02-02 | Added message tool documentation: voice response workflow, NO_REPLY pattern, uuid target format |
| 3.3.1 | 2026-02-02 | Phase 2 updates: added guru cron job to table, bruba-guru to agentToAgent.allow, clarified auth path is ~/.clawdbot not ~/.openclaw |
| 3.2.3 | 2026-02-02 | Added session continuity documentation: context persistence for bruba-web vs bruba-manager |
| 3.2.2 | 2026-02-02 | Fixed sessions_send format: use `sessionKey: "agent:bruba-web:main"` not `target` |
| 3.2.1 | 2026-02-02 | Added new agent setup (auth, session priming), documented global allowlist ceiling issue |
| 3.2.0 | 2026-02-02 | Fixed bruba-web tools: added write to allow (needed to write results/) |
| 3.1.0 | 2026-02-02 | Added heartbeat vs cron explanation, operations guide, troubleshooting, cost estimates, full cron integration |
| 3.0.0 | 2026-02-02 | Major rewrite: peer model, tool inheritance fix, cron integration, node host |
| 2.x | 2026-02-01 | Broken subagent pattern (deprecated) |
| 1.x | 2026-01-31 | Initial single-agent |