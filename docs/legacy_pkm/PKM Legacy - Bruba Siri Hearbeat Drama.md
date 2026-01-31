---
type: doc
scope: reference
title: "Siri/Shortcuts Integration Journey"
version: 1.0.0
updated: 2026-01-29 00:15
project: planning
tags: [bruba, siri, shortcuts, http-api, integration]
---

# Siri/Shortcuts Integration Journey

## Goal

Enable voice commands to Bruba via Siri: "Hey Siri, Go Tell Bruba [message]"

This creates a hands-free interface for quick commands (add reminders, quick questions) without opening Signal.

---

## Part 1: HTTP Endpoint Setup

### Initial Approach (Too Permissive)

Clawdbot has an OpenAI-compatible HTTP endpoint. Initial setup:

```json
// ~/.clawdbot/clawdbot.json
"gateway": {
  "http": {
    "endpoints": {
      "chatCompletions": { "enabled": true }
    }
  }
}
```

Problem: Gateway was bound to `loopback` (127.0.0.1 only), unreachable from phone.

First attempt: Changed `bind: "loopback"` → `bind: "all"`

**Security issue:** This exposed the endpoint to the entire LAN, not just Tailscale. Anyone on home wifi could hit it with just the Bearer token.

### Secure Approach: Tailscale Serve

Better solution: Keep gateway on loopback, use Tailscale's HTTPS proxy.

```bash
# Gateway stays on loopback (default)
# Tailscale proxies HTTPS → localhost:18789
tailscale serve --bg 18789
```

**Security properties:**
- Gateway only listens on 127.0.0.1 (not exposed to LAN)
- Tailscale handles TLS (automatic certs)
- Only devices on your Tailnet can reach the endpoint
- Bearer token provides second layer of auth

**Result:** `https://[HOSTNAME].ts.net/v1/chat/completions`

### Token Rotation

If the Bearer token is ever exposed, rotate with:

```bash
NEW_TOKEN="bruba_gw_$(openssl rand -base64 32 | tr -d '/+=' | head -c 40)"
ssh bruba "clawdbot config set gateway.http.auth.token '$NEW_TOKEN'"
ssh bruba 'clawdbot gateway restart'
```

---

## Part 2: Apple Shortcut Creation

### Shortcut Structure

**Name:** "Go Tell Bruba" (this IS the Siri trigger phrase)

**Input Configuration:**
| Field | Value |
|-------|-------|
| Receive | Text (and Apps) |
| from | Nowhere |
| If there's no input | Ask For |

### Action 1: Get Contents of URL

**URL:** `https://[HOSTNAME].ts.net/v1/chat/completions`

**Method:** POST

**Headers:**
| Key | Value |
|-----|-------|
| Authorization | Bearer [TOKEN] |
| Content-Type | application/json |
| x-clawdbot-session-key | agent:bruba-main:main |

**Request Body:** JSON
| Key | Type | Value |
|-----|------|-------|
| model | Text | clawdbot:bruba-main |
| messages | Array | → Dictionary with role/content |

**messages array structure:**
- Item 1: Dictionary
  - role: Text → `user`
  - content: Text → `[From Siri] [Shortcut Input]`

### Action 2: Get Dictionary Value

| Field | Value |
|-------|-------|
| Key | choices.1.message.content |

**Note:** Shortcuts uses 1-indexed arrays, not 0-indexed.

### Action 3: Speak Text

| Field | Value |
|-------|-------|
| Speak | `Bruba says: [Dictionary Value]` |

### Troubleshooting Encountered

**Issue: "Missing user message in messages"**
- Cause: Shortcuts' JSON builder created `messages` as Dictionary, not Array
- Fix: Must be Array → Dictionary → role/content

**Issue: "No value found for dictionary key 'choices'"**
- Cause: API returning error, not valid response
- Debug: Add "Quick Look" action after URL fetch to see raw response
- Common causes: malformed JSON body, missing/wrong auth header

**Issue: Authorization header incomplete**
- Must include full value: `Bearer [TOKEN]`
- Not just `Bearer` in one field and token in another

---

## Part 3: Session Sharing

### The Problem

Each HTTP request creates a new session by default. Siri commands have no context of Signal conversations.

### Solution: Session Header

Adding header `x-clawdbot-session-key: agent:bruba-main:main` makes HTTP requests share the same session as Signal.

**With shared session:**
- Bruba has full context from both interfaces
- Can reference earlier Signal conversation in Siri command
- Siri response is contextually aware

**Tradeoff:**
- Signal doesn't automatically see Siri exchanges
- Conversation history includes both, but Signal UI only shows Signal messages

---

## Part 4: HTTP API Logging

### The Problem

With shared sessions, Bruba knows about Siri messages, but Signal users don't see them. The canonical conversation record (Signal) is incomplete.

### Solution: Source Tagging + Log Relay

**Step 1:** Shortcut prefixes messages with `[From Siri]`

**Step 2:** Bruba logs HTTP API messages to `memory/HTTP_API_LOG.md`:

```markdown
## [YYYY-MM-DD HH:MM] From Siri
**User:** [message without prefix]
**Bruba:** [response]
---
```

**Step 3:** Periodic relay sends log contents to Signal, then archives.

### AGENTS.md Addition

```markdown
### 📬 HTTP API Messages

Messages may arrive via HTTP API (Siri, Shortcuts, automations) rather than Signal. These are identified by:
- `[From SOURCE]` prefix in the message (e.g., `[From Siri]`, `[From Webapp]`)

**When you receive an HTTP API message:**
1. Respond normally (goes back to the caller)
2. Append to `memory/HTTP_API_LOG.md`:
   ```
   ## [YYYY-MM-DD HH:MM] From SOURCE
   **User:** [message without prefix]
   **Bruba:** [your response]
   ---
   ```

**Source registry:**
| Prefix | Source |
|--------|--------|
| `[From Siri]` | Apple Shortcuts via voice |
| `[From Webapp]` | Custom web interfaces |
| `[From Automation]` | Scripts, cron jobs |

Relay to Signal happens via cron job (see below).
```

---

## Part 5: Relay Mechanism Attempts

### Attempt 1: Heartbeat-Based Relay

**Approach:** Add to HEARTBEAT.md instructions to check for HTTP_API_LOG.md and send contents to Signal.

**Result:** Mixed. 
- First attempt: `Signal RPC -1: Failed to send message`
- Second attempt: Worked successfully

**Problem:** Heartbeat uses the main model (Opus), making this expensive for a simple file-check task.

### Attempt 2: Cron-Based Relay

**Approach:** Use Clawdbot cron with Haiku (cheap model) for the relay task.

```bash
clawdbot cron add \
  --name "HTTP API Relay" \
  --every "2m" \
  --session isolated \
  --model haiku \
  --message "Check ~/clawd/memory/HTTP_API_LOG.md. If it has content: (1) output the contents prefixed with '📬 HTTP API activity:', (2) archive to ~/clawd/memory/archive/ with filename http-api-YYYY-MM-DD-HHMMSS.md using current timestamp, (3) clear the original file. If empty or missing, reply HEARTBEAT_OK." \
  --deliver \
  --channel signal \
  --to "[PHONE_NUMBER]"
```

**Result:** Also experiencing `Signal RPC -1: Failed to send message` errors.

**Observation:** When there's no content (HEARTBEAT_OK), no error occurs — likely because `--deliver` doesn't attempt Signal delivery for empty/ack responses.

---

## Part 6: Current Status

### What Works

- ✅ Siri → Bruba HTTP endpoint (via Tailscale HTTPS)
- ✅ Bearer token authentication
- ✅ Shared session context (Siri and Signal share conversation)
- ✅ `[From Siri]` tagging in messages
- ✅ HTTP API logging to `memory/HTTP_API_LOG.md`
- ✅ Archive pattern for processed logs

### What's Flaky

- ⚠️ Signal delivery from cron/heartbeat contexts
  - `Signal RPC -1: Failed to send message` errors
  - Intermittent — sometimes works, sometimes fails
  - May be Signal connection stability issue
  - May be permissions/channel issue for non-main-session contexts

### Open Questions

1. **Why does Signal delivery fail from cron context?**
   - Is it a session/permissions issue?
   - Is it Signal connection instability?
   - Does `--deliver` use a different code path than main session?

2. **Is there a retry mechanism?**
   - Failed relays lose the message (already archived)
   - May need to not archive until delivery confirmed

3. **Alternative relay approaches?**
   - Have main Bruba session poll the log on user message
   - Use `sessions_send` tool explicitly instead of `--deliver` flag
   - Webhook to a different notification channel (Pushover, etc.)

---

## Part 7: Configuration Reference

### Cron Job Management

```bash
# List all cron jobs
clawdbot cron ls

# View run history for specific job
clawdbot cron runs --id [JOB_ID]

# Edit job
clawdbot cron edit [JOB_ID] --every "5m"

# Delete job
clawdbot cron rm [JOB_ID]

# Disable/enable
clawdbot cron disable [JOB_ID]
clawdbot cron enable [JOB_ID]
```

### Current Cron Job

```json
{
  "id": "[JOB_ID]",
  "name": "HTTP API Relay",
  "enabled": true,
  "schedule": { "kind": "every", "everyMs": 120000 },
  "sessionTarget": "isolated",
  "payload": {
    "model": "haiku",
    "deliver": true,
    "channel": "signal",
    "to": "[PHONE_NUMBER]"
  }
}
```

### File Locations

| File | Purpose |
|------|---------|
| `~/clawd/memory/HTTP_API_LOG.md` | Pending HTTP API exchanges |
| `~/clawd/memory/archive/http-api-*.md` | Archived exchanges |
| `~/.clawdbot/logs/daemon.log` | Clawdbot daemon logs |

### Debugging Commands

```bash
# Check cron run history
clawdbot cron runs --id [JOB_ID]

# Check daemon logs for Signal errors
grep -i "signal rpc" ~/.clawdbot/logs/daemon.log | tail -20

# Check if HTTP_API_LOG exists
cat ~/clawd/memory/HTTP_API_LOG.md

# Check archives
ls ~/clawd/memory/archive/http-api-*
```

---

## Part 8: Security Summary

| Layer | Protection |
|-------|------------|
| Network | Tailscale mesh — only your devices |
| Transport | HTTPS with auto-provisioned TLS cert |
| Application | Bearer token in Authorization header |
| Session | Optional session key for context sharing |
| Execution | Bruba's exec allowlist still applies |

The HTTP endpoint inherits all of Bruba's existing security constraints. A Siri command can't do anything Bruba couldn't do via Signal.

---

## Appendix: Full Shortcut Summary

```
Shortcut: "Go Tell Bruba"
Trigger: "Hey Siri, Go Tell Bruba [message]"

┌─────────────────────────────────────────┐
│ Receive [Text] from [Nowhere]           │
│ If there's no input: [Ask For]          │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│ Get Contents of URL                     │
│ URL: https://[HOSTNAME].ts.net/v1/...   │
│ Method: POST                            │
│ Headers:                                │
│   Authorization: Bearer [TOKEN]         │
│   Content-Type: application/json        │
│   x-clawdbot-session-key: agent:...     │
│ Body: JSON                              │
│   model: clawdbot:bruba-main            │
│   messages: [{                          │
│     role: user,                         │
│     content: [From Siri] [Input]        │
│   }]                                    │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│ Get Dictionary Value                    │
│ Key: choices.1.message.content          │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│ Speak Text                              │
│ "Bruba says: [Dictionary Value]"        │
└─────────────────────────────────────────┘
```