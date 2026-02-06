---
version: 4.0.0
updated: 2026-02-06
type: refdoc
project: planning
tags: [bruba, openclaw, multi-agent, architecture]
---

# Bruba Multi-Agent Architecture Reference

Core architecture reference for the Bruba multi-agent system. Covers the peer agent model, tool policy mechanics, agent specifications, communication patterns, and the heartbeat/cron split.

> **Extracted docs** (previously Parts 6-14 of this document):
> - [Cron System](cron-system.md) — Cron jobs, inbox handoff, heartbeat coordination, cost estimates
> - [Security Model](security-model.md) — Docker sandbox, access matrices, network isolation, defense layers
> - [Operations Guide](operations-guide.md) — Signal rate limits, transport, prerequisites, agent setup
> - [Troubleshooting](troubleshooting.md) — Multi-agent issues, heartbeat, context bloat
> - [Configuration Reference](configuration-reference.md) — config.yaml and openclaw.json settings
> - [Prompt Management](prompt-management.md) — Assembly system, component variants, budget
> - [Vault Strategy](vault-strategy.md) — Symlink-based private content management
> - [Known Issues](known-issues.md) — Active bugs and workarounds

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

**Proactive monitoring pattern:** Isolated cron jobs (cheap, stateless) detect conditions and write to inbox files. Manager's heartbeat (cheap, stateful) reads inbox, applies rules, delivers alerts. This separation keeps heartbeat fast while enabling rich monitoring. See [Cron System](cron-system.md) for details.

**Prompt budget constraint:** OpenClaw injects AGENTS.md into context at session start. **Hard limit: 20,000 characters.** Despite the multi-agent architecture, component snippets, and detailed guidance, the assembled prompt must stay under this limit or it gets truncated. This means every component snippet needs to be concise — verbose examples and duplicated explanations bloat the prompt and risk losing critical instructions. When adding new components or updating existing ones, always check the assembled size: `wc -c agents/bruba-main/exports/core-prompts/AGENTS.md`.

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

**Bindings:** BlueBubbles DM (phone configured in openclaw.json)

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
    "auto": "inbound",
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

For cron job details, schedules, state files, and processing flow, see [Cron System](cron-system.md).

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

**Vault changes not committed?** Run `/vault-sync` or `./tools/vault-sync.sh`. `/sync` does this automatically.

**Want to promote vault content?** `./tools/vault-propose.sh` — scans vault, filters through vault.deny, creates PR.

**Voice response not sending?** Check `messages.tts.auto` config. For manual, use message tool with `NO_REPLY`.

**Guru response too long for Main?** Guru should message directly via message tool, return summary only.

**Technical question routing?** Auto-route to Guru → Guru messages user directly → Main gets one-liner summary.

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 4.0.0 | 2026-02-06 | **Masterdoc split:** Extracted Parts 6-14 to dedicated docs (cron-system, security-model, operations-guide, troubleshooting, configuration-reference, prompt-management, vault-strategy, known-issues). Core architecture (Parts 1-5) retained. ~2187 lines → ~700 lines. |
| 3.13.0 | 2026-02-05 | **Vault mode (symlinks):** Replaced rsync + private branch vault model with symlink-based integration. Gitignored dirs become symlinks into a separate vault repo. New `vault-setup.sh` (enable/disable/status), rewritten `vault-sync.sh` (simple commit) and `vault-propose.sh` (direct vault→PR, no private branch). Added `load_vault_config()` to lib.sh, `vault:` config section, `docs/vault-strategy.md`. |
| 3.12.0 | 2026-02-05 | **Per-agent content pipeline:** Content pipeline (`/pull` → `/convert` → `/intake` → `/export` → `/push`) now handles per-agent intake and export. Agents opt in with `content_pipeline: true` in config.yaml. Files carry `agents:` frontmatter field for routing to specific agent memories. Per-agent dirs under `agents/{agent}/` (sessions, intake, exports, mirror, assembled). Backward compatible — files without `agents:` default to bruba-main. |
| 3.11.0 | 2026-02-04 | **bruba-rex agent:** Added new alternate identity agent bound to different phone number. Same capabilities as Main, independent identity. Added bindings section to config.yaml for declarative routing management. Updated agent count to five-agent architecture. |
| 3.10.0 | 2026-02-04 | **Component variant support:** Added `component:variant` syntax for components that need different prompts per agent. Merged `http-api` and `siri-async` components into `siri-async` with `:router` (Manager) and `:handler` (Main) variants. |
| 3.9.0 | 2026-02-04 | **Docker sandbox enabled for bruba-web:** Cross-agent session visibility bug fixed in OpenClaw 2026.2.1. bruba-web now runs in Docker container (`sandbox.mode: "all"`, `network: "bridge"`). Added `web-search` component to bruba-main prompts. |
| 3.8.4 | 2026-02-03 | **Voice compaction bug documented:** Added known issue for voice messages causing silent context compaction (binary audio data in context). |
| 3.8.3 | 2026-02-03 | **OpenClaw config migration:** config.yaml is now source of truth for openclaw.json settings. New `sync-openclaw-config.sh`. |
| 3.8.2 | 2026-02-03 | **Compaction fixes:** bruba-main switched from Opus to Sonnet (mid-session fallback was triggering compaction). softThresholdTokens increased 8K→40K. |
| 3.8.1 | 2026-02-03 | **Bot transport abstraction:** `./tools/bot` and `bot_exec()` now support multiple transports (sudo, tailscale-ssh, ssh). |
| 3.8.0 | 2026-02-03 | **Siri async via Manager:** Manager acts as fast HTTP front door for Siri async requests. |
| 3.7.0 | 2026-02-03 | **Automatic voice handling:** OpenClaw now handles STT (Groq Whisper) and TTS (ElevenLabs) automatically. |
| 3.6.0 | 2026-02-03 | **Manager coordination pattern:** Nightly reset jobs now route through bruba-manager. |
| 3.5.3 | 2026-02-03 | **Sandbox disabled:** Agent-to-agent session visibility broken in sandbox mode. *(Fixed in 3.9.0)* |
| 3.5.2 | 2026-02-03 | **Sandbox tool policy:** Documented tools.sandbox.tools.allow ceiling. |
| 3.5.1 | 2026-02-03 | **Defense-in-depth:** ALL agents now have tools/:ro. |
| 3.5.0 | 2026-02-03 | **Part 7 major expansion:** Docker sandbox implementation details, per-agent access matrix. |
| 3.4.0 | 2026-02-03 | **Guru direct response pattern:** Guru messages users directly via message tool. |
| 3.3.3 | 2026-02-02 | Added USER.md Signal UUID setup requirement for Siri async replies. |
| 3.3.2 | 2026-02-02 | Added message tool documentation: voice response workflow, NO_REPLY pattern. |
| 3.3.1 | 2026-02-02 | Phase 2 updates: added guru cron job, bruba-guru to agentToAgent.allow. |
| 3.2.3 | 2026-02-02 | Added session continuity documentation. |
| 3.2.2 | 2026-02-02 | Fixed sessions_send format: use `sessionKey` not `target`. |
| 3.2.1 | 2026-02-02 | Added new agent setup (auth, session priming), documented global allowlist ceiling. |
| 3.2.0 | 2026-02-02 | Fixed bruba-web tools: added write to allow. |
| 3.1.0 | 2026-02-02 | Added heartbeat vs cron, operations guide, troubleshooting, cost estimates. |
| 3.0.0 | 2026-02-02 | Major rewrite: peer model, tool inheritance fix, cron integration, node host. |
