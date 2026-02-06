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

## BB vs Signal Quick Reference

| Feature | BlueBubbles | Signal |
|---------|-------------|--------|
| Target format | Phone/email/chat_guid | UUID |
| Attachments | `sendAttachment` action | `filePath` parameter |
| Reactions | `react` action | Not supported |
| Edit/unsend | Supported | Not supported |
| Effects | `sendWithEffect` | Not supported |
| JSON format | Yes | Key-value string |
