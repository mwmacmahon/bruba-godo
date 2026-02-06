---
title: "Channel Integrations Reference"
scope: reference
type: doc
---

# Channel Integrations Reference

Two messaging channels connect users to the bot system. Agents also communicate with each other via `sessions_send` (see [Inter-Agent Communication](#inter-agent-communication-sessions_send)).

## BlueBubbles (iMessage)

**Status:** Primary channel for user conversations.

### Actions

| Action | Description | Format |
|--------|-------------|--------|
| `send` | Send text message | `{ "action": "send", "channel": "bluebubbles", "target": "<target>", "message": "..." }` |
| `sendAttachment` | Send file/media | `{ "action": "sendAttachment", "channel": "bluebubbles", "target": "<target>", "path": "/path/to/file", "caption": "..." }` |
| `reply` | Reply to specific message | `{ "action": "reply", "channel": "bluebubbles", "target": "<target>", "replyToGuid": "<guid>", "message": "..." }` |
| `react` | Add tapback reaction | `{ "action": "react", "channel": "bluebubbles", "target": "<target>", "messageGuid": "<guid>", "reaction": "love" }` |
| `edit` | Edit sent message | `{ "action": "edit", "channel": "bluebubbles", "messageGuid": "<guid>", "message": "..." }` |
| `unsend` | Unsend message | `{ "action": "unsend", "channel": "bluebubbles", "messageGuid": "<guid>" }` |
| `sendWithEffect` | Send with iMessage effect | `{ "action": "sendWithEffect", "channel": "bluebubbles", "target": "<target>", "message": "...", "effect": "slam" }` |

### Target Formats

| Format | Example | Notes |
|--------|---------|-------|
| E.164 phone | `+15551234567` | Preferred format |
| Email | `user@example.com` | For iMessage-registered emails |
| Chat GUID | `chat_guid:iMessage;-;+15551234567` | For specific chat threads |

### Configuration

In `openclaw.json` (synced from `config.yaml`):
```json
{
  "channels": {
    "bluebubbles": {
      "enabled": true,
      "serverUrl": "https://<tailscale-host>:2345",
      "password": "<api-password>",
      "webhookPath": "/bluebubbles-webhook",
      "dmPolicy": "allowlist",
      "groupPolicy": "allowlist"
    }
  }
}
```

### Bindings

```yaml
# config.yaml
bindings:
  - agent: bruba-main
    channel: bluebubbles
    peer:
      kind: dm
      id: "+12818143450"    # Gus's phone
  - agent: bruba-rex
    channel: bluebubbles
    peer:
      kind: dm
      id: "+18326714584"    # Rex's human
```

Bindings route **inbound** messages from a peer to a specific agent. Agents can send **outbound** to any target using the `message` tool without needing a binding.

## Signal

**Status:** Active but deprecated for user conversations. Used for operator commands and manager alerts.

### Action Format

```
message action=send target=uuid:<recipient-uuid> message="Your message"
```

With media:
```
message action=send target=uuid:<recipient-uuid> filePath=/path/to/file message="Caption"
```

### Configuration

```json
{
  "channels": {
    "signal": {
      "enabled": true,
      "account": "+12026437862",
      "httpPort": 8088,
      "cliPath": "/opt/homebrew/bin/signal-cli",
      "dmPolicy": "pairing",
      "allowFrom": ["+12818143450"]
    }
  }
}
```

### Binding

```yaml
bindings:
  - agent: bruba-main
    channel: signal
    # Catches all Signal messages (no peer filter)
```

## Agent Channel Usage

| Agent | Inbound | Outbound | Notes |
|-------|---------|----------|-------|
| bruba-main | BB (Gus's phone), Signal | BB, Signal | Primary user-facing agent |
| bruba-rex | BB (Rex's phone) | BB | Separate identity, separate phone |
| bruba-guru | sessions_send only | BB (Gus's phone) | No inbound binding; outbound-only direct messaging |
| bruba-manager | Cron/internal only | Via Main | Coordination agent |
| bruba-web | sessions_send only | None | Stateless research service |

## NO_REPLY Pattern

When an agent is **bound** to a channel (has an inbound binding), its normal text response goes to that channel. If it also uses the `message` tool to send, the response would be duplicated. Use `NO_REPLY` after `message` to suppress the duplicate.

**Applies to:** bruba-main (bound to BB + Signal), bruba-rex (bound to BB)
**Does NOT apply to:** bruba-guru, bruba-web, bruba-manager (not channel-bound)

## Inter-Agent Communication (sessions_send)

Agents communicate with each other via `sessions_send`, not through messaging channels. This is separate from the external channel system above.

### Reply Field

When an agent calls `sessions_send` with a timeout (e.g. `timeoutSeconds=30`), the tool blocks and returns the target agent's response:

```json
{
  "status": "ok",
  "reply": "Plain text response from target agent",
  "sessionKey": "agent:bruba-guru:main",
  "delivery": { "status": "pending", "mode": "announce" }
}
```

The `reply` field contains **only the target agent's text response** — not internal reasoning, tool calls, or conversation history.

### Fire-and-Forget (timeoutSeconds=0)

With `timeoutSeconds=0`, the call returns immediately without waiting for a response:

```json
{
  "status": "accepted",
  "runId": "9e1c2f47-...",
  "sessionKey": "agent:bruba-guru:main",
  "delivery": { "status": "pending", "mode": "announce" }
}
```

No `reply` field — the calling agent doesn't get the response. Useful when the target agent delivers directly to the user (e.g. Guru messages via iMessage).

### maxPingPongTurns

`session.agentToAgent.maxPingPongTurns = 2` in openclaw.json controls how many back-and-forth exchanges happen after `sessions_send`:

```
Turn 1: Main → Guru: "What's your agent ID?"
Turn 2: Guru → Main: "bruba-guru"
[ping-pong limit reached]
Announce step: automatic cleanup/acknowledgment
```

Without this limit, agents could respond to each other indefinitely.

### REPLY_SKIP / ANNOUNCE_SKIP

These are **prompt-level conventions only**, not OpenClaw protocol commands. OpenClaw passes them through verbatim in the `reply` field — it does not strip or act on them.

- **REPLY_SKIP** — tells the calling agent "don't ask follow-up questions"
- **ANNOUNCE_SKIP** — tells the agent to skip the post-exchange announcement

The real turn limiter is `maxPingPongTurns`, not these conventions.

### Bidirectional with No Channel Leakage

Agent-to-agent messages stay within the session system. When Guru calls `sessions_send` to Main, Main receives it as an internal session message — it does **not** leak to iMessage/Signal.

This enables safe bidirectional context flow:

```
1. Main → Guru: "Handle this technical question"  (sessions_send)
2. Guru → User: direct iMessage via message tool
3. Guru → Main: "Done: answered question about X"  (sessions_send)
4. Main updates its context — no iMessage sent
```

## Silent Handoff Pattern

When a channel-bound agent (e.g. Main) dispatches work to a specialist agent (e.g. Guru) and the specialist delivers directly to the user, the dispatching agent must stay silent to avoid duplicate messages.

### How It Works

```
1. User → Main: "Ask guru about X"
2. Main → Guru: sessions_send(timeoutSeconds=60)
3. Guru → User: "[Guru] ..." via message tool (iMessage)
4. Guru → Main: full response text + REPLY_SKIP (in sessions_send reply)
5. Main: NO_REPLY (suppresses channel-bound auto-response)
```

**Why NO_REPLY?** Main is bound to BlueBubbles — any text it returns automatically goes to iMessage. Since Guru already sent the response directly, Main must suppress its own output with `NO_REPLY`.

**Why `[Guru]` prefix?** The user needs to know which agent is talking. All direct messages from Guru start with `[Guru]` so there's no confusion.

**Why full text in reply?** Guru returns the complete response (not just a summary) in the `sessions_send` reply field. Main stores this for context tracking — knowing what Guru told the user — but never relays it.

### Timeout and Error Handling

| Scenario | Main's response |
|----------|----------------|
| Guru replies within timeout | `NO_REPLY` (silent) |
| Timeout (no reply in 60s) | "Guru is still working on this — expect a direct iMessage response soon" |
| Error (sessions_send fails) | Handles the question directly |

### Prerequisites

- Dispatching agent must be **channel-bound** (has inbound binding) for `NO_REPLY` to matter
- Specialist agent must have the **message** tool to send directly
- Specialist agent must NOT have an inbound binding (otherwise its reply would also auto-send)

### Applicable Agents

| Role | Agent | Channel-bound? | Uses NO_REPLY? |
|------|-------|----------------|----------------|
| Dispatcher | bruba-main | Yes (BB + Signal) | Yes — after guru handoff |
| Specialist | bruba-guru | No (outbound only) | No — uses message tool directly |

## Limitations: Session Management via sessions_send

Slash commands like `/reset`, `/compact`, and `/status` sent via `sessions_send` **do not trigger actual OpenClaw operations**. The target agent interprets them as text messages and responds conversationally ("Session cleared. Standing by.") without any real effect.

### What Doesn't Work

| Command via sessions_send | Agent says | What actually happens |
|--------------------------|------------|----------------------|
| `/reset` | "Session cleared." | Nothing — same session ID, tokens go UP |
| `/compact` | "Compacting context." | Nothing — no compaction event in JSONL |
| `/status` / `session_status` tool | "Context: 0/200k" | Reports near-zero due to context pruning, not actual session size |

### Why /status Shows 0

`session_status` reports the **live API context window** (what's sent to Claude on this turn), not cumulative session size. With `context_pruning: cache-ttl`, old messages are dropped between turns. Each sessions_send invocation starts with a near-empty context (bootstrap + current message only).

`openclaw status` (CLI) shows **cumulative total tokens** across all turns — a very different metric.

### What Works (Updated 2026-02-06)

| Method | Effect | Verified |
|--------|--------|----------|
| `openclaw gateway call sessions.reset --params '{"key":"agent:<id>:main"}'` | Real session reset — new session ID, tokens to 0 | Yes (empirically tested 2026-02-06) |
| `openclaw gateway call sessions.compact --params '{"key":"agent:<id>:main"}'` | Real compaction | Yes (empirically tested 2026-02-06) |
| `openclaw gateway call sessions.list --json` | All sessions with tokens, model, timestamps | Yes |
| `exec session-reset.sh all` (from agent via cron) | Resets all agents via gateway calls | Yes (nightly cron) |

### Nightly Cron (Fixed 2026-02-06)

The old `nightly-reset-execute` cron (sessions_send `/reset`) was replaced with `nightly-reset` which uses `exec session-reset.sh all`. This runs `openclaw gateway call sessions.reset` for each agent — the only confirmed working reset method.

4 jobs now handle the full cycle: prep (4:00) → export (4:00) → reset (4:08) → wake (4:10). See `docs/cron-system.md` for details.

## BB vs Signal Quick Reference

| Feature | BlueBubbles | Signal |
|---------|-------------|--------|
| Target format | Phone/email/chat_guid | UUID |
| Attachments | `sendAttachment` action | `filePath` parameter |
| Reactions | `react` action | Not supported |
| Edit/unsend | Supported | Not supported |
| Effects | `sendWithEffect` | Not supported |
| JSON format | Yes | Key-value string |
