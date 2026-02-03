---
version: 1.0.0
updated: 2026-02-03 01:30
type: doc
project: planning
tags: [bruba, prompts, architecture, message-tool, guru, siri, voice]
---

# Consolidated Prompt & Architecture Updates

Session discoveries from 2026-02-02/03 that need to be applied to bruba-godo.

---

## Executive Summary

**Key discovery:** The `message` tool enables direct Signal delivery from any agent. This changes:
1. **Guru pattern** — Guru messages user directly, returns only summary to Main
2. **Siri async** — Main messages Signal directly for HTTP requests that need Signal delivery
3. **Voice workflow** — Unified pattern: whisper → tts → message tool → NO_REPLY

**Result:** Main stays lightweight. Technical payload stays in Guru. Routing overhead minimized.

---

## Part 1: The Direct Message Pattern

### What We Learned

Any agent with the `message` tool can send to Signal directly:

```
message action=send target=uuid:<REDACTED-UUID> message="text"
message action=send target=uuid:... filePath=/tmp/audio.wav message="caption"
```

After using `message` tool, respond with `NO_REPLY` to prevent duplicate delivery (since the agent's bound channel would also receive the normal response).

### Impact on Architecture

**Before (planned Guru pattern):**
```
User → Main → sessions_send → Guru processes → full response back to Main → Main relays to Signal
                                                      ↓
                                    Main's context bloated with technical payload
```

**After (new Guru pattern):**
```
User → Main → sessions_send → Guru processes → message tool → Signal (direct)
         ↑                           ↓
         └── "Summary: fixed X" ─────┘  (one sentence in Main's context)
```

Main tracks "Guru: debugging voice issue" without holding the 40K token payload.

---

## Part 2: Prompt Component Updates

### 2.1 components/guru-routing/prompts/AGENTS.snippet.md

**Current state:** Routes to Guru, expects full response back for relay.

**Update needed:** Guru sends directly, returns summary only.

```markdown
<!-- COMPONENT: guru-routing -->
## Technical Routing (Guru)

You have access to **bruba-guru**, a technical specialist running Opus for deep-dive problem solving.

### Routing Modes

**Auto-routing triggers:**
- Code dumps, config files, error logs pasted
- "Why isn't this working", "debug", "what's wrong"
- Architecture/design questions
- Complex technical analysis
- Explicit: "ask guru", "guru question"

**Guru Mode (extended session):**
- User says: "guru mode", "route me to guru", "let me talk to guru"
- Enter pass-through: forward messages to Guru, Guru responds directly to user
- Track internally: `[GURU MODE ACTIVE]`
- Exit: "back to main", "normal mode", "that's all for guru"
- On exit: Note Guru's summary of what was worked on

**Single Query:**
- Detect technical trigger
- `sessions_send` to bruba-guru with context
- Guru responds directly to user via message tool
- Guru returns summary to you for tracking
- Track: "Guru: [one-liner of current work]"

**Status Check:**
- "What's guru working on?" → Report from your tracking

### What You Track (Not Full Payload)

Maintain internally:
```
Guru status: [idle | working on: one-liner]
Last topic: [brief description]
Mode: [normal | guru-mode]
```

You do NOT receive Guru's full technical responses. Guru messages the user directly.
You only receive a brief summary for your own context tracking.

### Example Flow

```
User: [pastes 200 lines of config] why isn't voice working?

You: Routing to Guru for debugging.
[sessions_send to bruba-guru with the config and question]

Guru: [analyzes, messages user directly with full explanation]
Guru → returns to you: "Summary: missing message tool in tools_allow"

You track: Guru status = "diagnosed voice issue as missing message tool"
[NO visible response needed - Guru already messaged user]
```
<!-- /COMPONENT: guru-routing -->
```

---

### 2.2 templates/prompts/guru/AGENTS.md

**Current state:** Returns full response to Main.

**Update needed:** Message user directly, return summary to Main.

Add this section after the existing content:

```markdown
## Response Delivery

You message <REDACTED-NAME> directly via Signal — your responses don't go through Main.

**Standard response pattern:**
1. Complete your technical analysis
2. Send to <REDACTED-NAME>: `message action=send target=uuid:<REDACTED-UUID> message="[your full response]"`
3. Return to Main: A **one-sentence summary** only
   - Example: "Summary: diagnosed voice issue as missing message tool in tools_allow"

**Voice response pattern:**
1. Complete analysis
2. Generate TTS: `exec /Users/bruba/agents/bruba-main/tools/tts.sh "response" /tmp/response.wav`
3. Send: `message action=send target=uuid:18ce66e6-... filePath=/tmp/response.wav message="[text version]"`
4. Return summary to Main

**Why this pattern:**
- Main stays lightweight (tracks "Guru: working on X" not 40K tokens)
- You get full context for deep reasoning
- User gets your full response without relay latency
- Transcripts separate naturally (your session = technical, Main's session = coordination)

**Quick answers exception:** For brief responses (<200 words), you can return normally through Main. Use direct messaging for substantial technical responses.

**<REDACTED-NAME>'s Signal UUID:** `uuid:<REDACTED-UUID>`
```

---

### 2.3 templates/prompts/guru/TOOLS.md

**Update needed:** Add message tool documentation.

Add to the tools list:

```markdown
### message

Send messages directly to Signal (bypassing Main's response flow).

**Syntax:**
```
message action=send target=uuid:<recipient-uuid> message="text"
message action=send target=uuid:<recipient-uuid> filePath=/path/to/file message="caption"
```

**<REDACTED-NAME>'s Signal UUID:** `uuid:<REDACTED-UUID>`

**Use cases:**
- Direct response pattern (send full technical response, return summary to Main)
- Voice responses (with filePath for audio)

**Important:** After using message tool for user-facing response, return only a summary to Main, not the full content.
```

---

### 2.4 components/voice/prompts/AGENTS.snippet.md

**Current state:** Uses MEDIA: syntax (broken).

**Update needed:** Use message tool pattern.

```markdown
<!-- COMPONENT: voice -->
## 🎤 Voice Messages

When <REDACTED-NAME> sends a voice note:

1. **Extract audio path** from `[media attached: /path/to/file ...]` line
2. **Transcribe** (don't echo raw transcript to chat):
   ```
   exec /Users/bruba/agents/bruba-main/tools/whisper-clean.sh "/path/to/audio"
   ```
3. **Process** the content and formulate your response
4. **Generate TTS:**
   ```
   exec /Users/bruba/agents/bruba-main/tools/tts.sh "your response text" /tmp/response.wav
   ```
5. **Send voice + text:**
   ```
   message action=send target=uuid:<REDACTED-UUID> filePath=/tmp/response.wav message="your response text"
   ```
6. **Respond:** `NO_REPLY`

**Critical:** After using the message tool, respond with `NO_REPLY` to prevent duplicate text delivery. The message tool already delivered both audio and text.

**Target UUID:** For <REDACTED-NAME>, always `uuid:<REDACTED-UUID>`
<!-- /COMPONENT: voice -->
```

---

### 2.5 components/http-api/prompts/AGENTS.snippet.md

**Current state:** Doesn't handle Siri async → Signal routing clearly.

**Update needed:** Add direct message pattern for Siri async.

```markdown
<!-- COMPONENT: http-api -->
## HTTP API Requests

Messages may arrive via HTTP (Siri, automations) instead of Signal.

### Siri Async — `[From Siri async]`

User already heard "Got it, I'll message you" from Siri. They expect the response in Signal.

1. Process the request fully
2. Send via message tool:
   ```
   message action=send target=uuid:<REDACTED-UUID> message="[your response]"
   ```
3. Return to HTTP: `✓` (minimal acknowledgment)

**Do NOT use NO_REPLY here** — HTTP responses don't go to Signal anyway.

### Siri Sync — `[Ask Bruba]`

User is waiting for Siri to speak the response.

1. Process the request
2. Return response directly (this goes back to Siri TTS)
3. Keep concise — Siri TTS limit ~30 seconds

### Detecting Source

| Tag | Source | Response Destination |
|-----|--------|---------------------|
| `[From Siri async]` | Siri "tell" shortcut | Signal (via message tool) |
| `[Ask Bruba]` | Siri "ask" shortcut | HTTP → Siri speaks |
| No tag + Signal header | Normal Signal | Normal response |

### <REDACTED-NAME>'s Signal UUID

For Siri async: `uuid:<REDACTED-UUID>`
<!-- /COMPONENT: http-api -->
```

---

### 2.6 components/signal/prompts/AGENTS.snippet.md

**Update needed:** Document UUID in message headers.

Add:

```markdown
### Message Headers & UUID

Signal messages include sender UUID in the header:
```
[Signal NAME id:uuid:XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX +Ns TIMESTAMP] text
```

**<REDACTED-NAME>'s UUID:** `uuid:<REDACTED-UUID>`

This UUID is stable. Use it for `message` tool targeting when sending direct responses or media.
```

---

## Part 3: Config Updates

### 3.1 config.yaml — bruba-main

**Issue:** `message` tool missing from tools_allow.

```yaml
bruba-main:
  tools_allow:
    - read
    - write
    - edit
    - exec
    - group:memory
    - group:sessions
    - image
    - message              # ADD THIS
```

### 3.2 config.yaml — bruba-manager

**Issue:** `exec` was incorrectly in deny list. Manager needs remindctl, icalBuddy.

```yaml
bruba-manager:
  tools_allow:
    - read
    - write
    - exec                 # KEEP - needs remindctl, icalBuddy
    - group:memory
    - group:sessions
  tools_deny:
    - browser
    - canvas
    - cron
    - gateway
    - web_search           # ADD - use bruba-web
    - web_fetch            # ADD - use bruba-web
    - edit                 # ADD - not a file editor
    - apply_patch          # ADD
    - sessions_spawn       # ADD - no helper spawning
```

### 3.3 config.yaml — bruba-web

**Issue:** Some security restrictions were removed incorrectly.

```yaml
bruba-web:
  tools_allow:
    - web_search
    - web_fetch
    - read
    - write
  tools_deny:
    - exec
    - browser
    - canvas
    - cron
    - gateway
    - sessions_spawn
    - edit                 # RESTORE - write-only, no editing
    - apply_patch          # RESTORE
    - memory_search        # RESTORE - stateless, no memory
    - memory_get           # RESTORE
    - sessions_send        # RESTORE - passive, can't initiate
```

### 3.4 config.yaml — bruba-guru

**New:** Add message tool for direct Signal delivery.

```yaml
bruba-guru:
  tools_allow:
    - read
    - write
    - edit
    - exec
    - group:memory
    - sessions_send        # Keep for bruba-web delegation
    - sessions_list
    - session_status
    - message              # ADD - for direct Signal responses
  tools_deny:
    - browser
    - canvas
    - cron
    - gateway
    - web_search           # Use bruba-web
    - web_fetch
    - sessions_spawn
```

---

## Part 4: Architecture Masterdoc Updates

### 4.1 Agent Topology Diagram

Update to show Guru's direct message path:

```
                    ┌─────────────┐
                    │   Signal    │◄──────────────────────────┐
                    └──────┬──────┘                           │
                           │                                  │
                           ▼                                  │
                    ┌─────────────┐                           │
                    │ bruba-main  │  Opus                     │
                    │ (router)    │  Coordination, personal   │
                    └──────┬──────┘                           │
                           │                                  │
           ┌───────────────┼───────────────┐                  │
           │ sessions_send │               │                  │
           ▼               ▼               ▼                  │
    ┌─────────────┐ ┌─────────────┐ ┌─────────────┐          │
    │ bruba-guru  │ │ bruba-web   │ │bruba-manager│          │
    │   (Opus)    │ │  (Sonnet)   │ │  (Sonnet)   │          │
    │ Technical   │ │ Web search  │ │ Coordination│          │
    └──────┬──────┘ └─────────────┘ └─────────────┘          │
           │                                                  │
           │ message tool (direct)                            │
           └──────────────────────────────────────────────────┘
```

### 4.2 bruba-guru Specification

Add to capabilities table:

| Tool | Status | Notes |
|------|--------|-------|
| message | ✅ | Direct Signal delivery (bypasses Main relay) |

Add response delivery section:

```markdown
**Response Delivery:** Guru messages users directly via the `message` tool, bypassing Main entirely. This keeps Main's context lightweight — Main only receives a one-sentence summary for tracking purposes ("Summary: diagnosed X as Y").
```

### 4.3 New Communication Pattern Section

Add after existing patterns:

```markdown
### Guru Direct Response Pattern

Unlike bruba-web (which returns results to the caller), bruba-guru messages the user directly:

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
```

### 4.4 Expand Message Tool Section

Replace/expand existing section:

```markdown
### Message Tool (Media and Direct Delivery)

The `message` tool serves two purposes:
1. **Media attachments** — Send voice files, images to Signal
2. **Direct delivery** — Any agent can message Signal without going through the bound agent

**Tool syntax:**
```
message action=send target=uuid:<recipient-uuid> message="text"
message action=send target=uuid:<recipient-uuid> filePath=/path/to/file message="caption"
```

**<REDACTED-NAME>'s Signal UUID:** `uuid:<REDACTED-UUID>`

**After using message tool:** Respond with `NO_REPLY` to prevent duplicate delivery (the bound channel would otherwise also receive the normal response).

**Exception:** Guru doesn't need `NO_REPLY` because Guru isn't bound to Signal. Guru's return goes to Main (via sessions_send callback), not to Signal.

**Who has message tool:**
| Agent | Has message? | Use case |
|-------|--------------|----------|
| bruba-main | ✅ | Voice replies, Siri async |
| bruba-guru | ✅ | Direct technical responses |
| bruba-manager | ❌ | Uses sessions_send to Main |
| bruba-web | ❌ | Passive service |

**Voice Response Workflow:**
```
1. Transcribe: whisper-clean.sh "/path/to/audio.m4a"
2. Generate TTS: tts.sh "response text" /tmp/response.wav
3. Send: message action=send target=uuid:... filePath=/tmp/response.wav message="response text"
4. Respond: NO_REPLY
```
```

### 4.5 Quick Reference Updates

Add to Quick Reference section:

```markdown
**Voice not working?** Check `message` in tools_allow. Use message tool + NO_REPLY, not MEDIA: syntax.

**Guru response too long for Main?** Guru should message directly, return summary only.

**Siri async not appearing in Signal?** Use message tool with <REDACTED-NAME>'s UUID, return `✓` to HTTP.
```

---

## Part 5: Implementation Checklist

### Immediate (Fix Broken Voice)

- [ ] Add `message` to bruba-main tools_allow in config.yaml
- [ ] Run `./tools/update-agent-tools.sh`
- [ ] Restart gateway: `./tools/bot 'openclaw daemon restart'`
- [ ] Test voice reply

### Prompt Component Updates

| File | Status | Notes |
|------|--------|-------|
| `components/voice/prompts/AGENTS.snippet.md` | ❌ | Replace MEDIA: with message tool |
| `components/http-api/prompts/AGENTS.snippet.md` | ❌ | Add Siri async routing |
| `components/signal/prompts/AGENTS.snippet.md` | ❌ | Add UUID documentation |
| `components/guru-routing/prompts/AGENTS.snippet.md` | ❌ | Update for direct-message pattern |
| `templates/prompts/guru/AGENTS.md` | ❌ | Add response delivery section |
| `templates/prompts/guru/TOOLS.md` | ❌ | Add message tool |

### Config Corrections

| Config Item | Status | Notes |
|------------|--------|-------|
| bruba-main + message | ❌ | Required for voice |
| bruba-guru + message | ❌ | Required for direct pattern |
| bruba-manager denies | ❌ | Add web tools, edit, apply_patch |
| bruba-web denies | ❌ | Restore edit, memory, sessions_send |

### Documentation

- [ ] Update `docs/architecture-masterdoc.md` → v3.4.0
  - Updated topology diagram
  - Expanded message tool section  
  - Guru direct response pattern
  - Corrected tool permissions

### Cron Jobs

- [ ] Register guru-pre-reset-continuity (proposed, not active)

---

## Part 6: Testing Matrix

| Test | Expected |
|------|----------|
| Voice message to Main | Transcribe → TTS → message tool → NO_REPLY → audio in Signal |
| Siri async "tell bruba remind me X" | Process → message tool → Signal shows response |
| Siri sync "ask bruba what time" | Process → return to HTTP → Siri speaks |
| Technical question to Main | Routes to Guru → Guru messages directly → Main gets summary |
| "guru mode" → technical chat | Pass-through to Guru → Guru messages directly each turn |
| "back to main" | Exit guru mode → summary of what Guru worked on |
| "what's guru working on?" | Main reports from tracking |

---

## Summary

The `message` tool unlocks a cleaner architecture:

| Before | After |
|--------|-------|
| Guru → Main → Signal (context bloat) | Guru → Signal direct (Main gets summary) |
| Voice: MEDIA: syntax (broken) | Voice: message tool + NO_REPLY |
| Siri async: unclear routing | Siri async: message tool to Signal |

**One pattern to remember:** `message action=send target=uuid:... message="text"` then `NO_REPLY`
