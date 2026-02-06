---
title: "OpenClaw Session API Reference"
scope: reference
type: doc
---

# OpenClaw Session API Reference

**Empirically tested 2026-02-06 on OpenClaw 2026.2.1 (ed4529e).** This document corrects the documentation-sourced reference with actual CLI behavior observed on the Bruba bot.

---

## Critical Correction: `openclaw agent --message` Does NOT Intercept Slash Commands

The original docs.openclaw.ai documentation states: "Slash commands sent via `--message` are intercepted by the Gateway's command handler." **This is empirically false on version 2026.2.1.** Slash commands (`/reset`, `/compact`, `/new`, `/status`) sent via `openclaw agent --message` are passed through as text to the model, which responds conversationally with no real effect.

| Command | Agent says | What actually happens | Session ID | Tokens |
|---------|------------|----------------------|------------|--------|
| `openclaw agent --agent bruba-web --message "/status"` | "bruba-web status: Role: Web search..." | Agent interprets as text | Unchanged | Go UP |
| `openclaw agent --agent bruba-web --message "/compact"` | "Session is already stateless..." | Nothing — no compaction | Unchanged | Go UP |
| `openclaw agent --agent bruba-web --message "/reset"` | "Session reset. Ready for..." | Nothing — no reset | Unchanged | Go UP |
| `openclaw agent --agent bruba-web --message "/new"` | "New session started. Standing by..." | Nothing — no new session | Unchanged | Go UP |

**Tested sequence on bruba-web (sessionId `9bba31e0-...`):**
- Pre-test: totalTokens 77610
- After `/status`: totalTokens 77751 (+141)
- After `/compact`: totalTokens 77683 (+73 from cache)
- After `/reset`: totalTokens 77816 (+133)
- After `/new`: totalTokens 77847 (+31)
- Session ID never changed throughout all tests.

**The same broken pattern applies to `sessions_send` from agents.** Both `openclaw agent --message "/reset"` and `sessions_send "/reset"` fail identically — the slash command is treated as text, not a Gateway operation.

---

## What Actually Works: `openclaw gateway call`

The **real scripting interface** for session lifecycle operations is `openclaw gateway call`, which sends RPC calls directly to the Gateway process.

### Session Reset (CONFIRMED WORKING)

```bash
openclaw gateway call sessions.reset --params '{"key":"agent:bruba-web:main"}'
```

**Output:**
```json
{
  "ok": true,
  "key": "agent:bruba-web:main",
  "entry": {
    "sessionId": "d9772418-e1f4-48d8-9b1c-308c2be7ad3e",
    "updatedAt": 1770391298815,
    "systemSent": false,
    "totalTokens": 0,
    "inputTokens": 0,
    "outputTokens": 0,
    "model": "claude-sonnet-4-5",
    "contextTokens": 1000000
  }
}
```

**Verified:** New `sessionId` generated, `totalTokens` reset to 0, `systemSent` reset to false. This is a real, verified reset.

### Session Compaction (CONFIRMED WORKING)

```bash
openclaw gateway call sessions.compact --params '{"key":"agent:bruba-guru:main"}'
```

**Output:**
```json
{
  "ok": true,
  "key": "agent:bruba-guru:main",
  "compacted": false,
  "kept": 213
}
```

The `compacted` field indicates whether compaction was actually performed (false if below threshold). The `kept` field shows how many entries remain in the session log.

### Session Listing (CONFIRMED WORKING)

```bash
openclaw gateway call sessions.list --json
```

Returns all sessions across all agents with full detail. Richer than `openclaw sessions --json` — includes `displayName`, `channel`, `origin`, `deliveryContext`, `lastChannel`, `lastTo`, `modelProvider`.

### Gateway Call Syntax

```bash
openclaw gateway call <method> [--params <json>] [--json] [--url <url>] [--token <token>] [--timeout <ms>]
```

| Method | Params | Description |
|--------|--------|-------------|
| `sessions.reset` | `{"key":"<session-key>"}` | Reset a specific session (new sessionId, 0 tokens) |
| `sessions.compact` | `{"key":"<session-key>"}` | Force compaction on a session |
| `sessions.list` | none | List all sessions across all agents |
| `health` | none | Gateway health check |
| `status` | none | Full status (same as `openclaw health --json`) |
| `system-presence` | none | Connected nodes/instances |
| `cron.*` | varies | Cron operations |

**Session key format:** `agent:<agentId>:main` for primary sessions, `agent:<agentId>:cron:<jobId>` for cron sessions.

---

## `openclaw sessions` — Read-Only Listing

A **flat command** with no subcommands. Arguments like `list`, `info`, `reset` are silently ignored.

```bash
openclaw sessions [--json] [--verbose] [--store <path>] [--active <minutes>]
```

| Flag | Status | Description |
|------|--------|-------------|
| `--json` | Works | Machine-readable JSON output |
| `--verbose` | Works (no extra data) | No visible difference from normal output |
| `--store <path>` | Works | Target a specific agent's session store |
| `--active <minutes>` | Works | Filter to sessions updated within N minutes |
| `--agent <id>` | DOES NOT EXIST | Silently ignored — not a recognized flag |

### Critical Limitation: Default Agent Only

Without `--store`, `openclaw sessions` reads from the **default agent's** session store (`/Users/bruba/.openclaw/agents/main/sessions/sessions.json`). On this bot, that store is empty because `main` is a legacy agent ID. To list sessions for a specific agent:

```bash
# Per-agent session listing
openclaw sessions --store /Users/bruba/.openclaw/agents/bruba-main/sessions/sessions.json --json
openclaw sessions --store /Users/bruba/.openclaw/agents/bruba-guru/sessions/sessions.json --json

# Or use gateway call for ALL sessions at once (preferred)
openclaw gateway call sessions.list --json
```

### Actual JSON Schema (Per-Agent Store)

```json
{
  "path": "/Users/bruba/.openclaw/agents/bruba-web/sessions/sessions.json",
  "count": 1,
  "activeMinutes": null,
  "sessions": [
    {
      "key": "agent:bruba-web:main",
      "kind": "direct",
      "updatedAt": 1770391042747,
      "ageMs": 45058,
      "sessionId": "9bba31e0-2ec4-4691-9f48-01bb72ebbf20",
      "abortedLastRun": false,
      "inputTokens": 10,
      "outputTokens": 141,
      "totalTokens": 77610,
      "model": "claude-sonnet-4-5",
      "contextTokens": 1000000
    }
  ]
}
```

**Fields present:** `key`, `kind`, `updatedAt`, `ageMs`, `sessionId`, `abortedLastRun`, `inputTokens`, `outputTokens`, `totalTokens`, `model`, `contextTokens`, optionally `systemSent`.

**Fields NOT present (despite docs claiming):** `compactionCount`, `memoryFlushAt`, `memoryFlushCompactionCount`, `chatType`, `provider`, `displayName`. These may exist in the raw `sessions.json` file but are not exposed by the CLI command.

### Session Key Patterns (Observed)

| Pattern | Example | Source |
|---------|---------|--------|
| Agent main session | `agent:bruba-main:main` | User/channel messages |
| Cron isolated session | `agent:bruba-main:cron:ab84e6c9-...` | Cron jobs |
| Agent-to-agent (via sessions_send) | `agent:bruba-guru:main` | Re-uses main session |
| Group chat | `agent:bruba-main:bluebubbles:group:any;-;+12818143450` | BB group messages |
| OpenAI-routed | `agent:bruba-manager:openai:5dfec21b-...` | OpenAI API routing |

---

## `openclaw agent --message` — Useful for Messages, NOT for Slash Commands

Good for sending text messages to agents. **Not** for session lifecycle operations.

```bash
openclaw agent --message <text> [options]
```

| Flag | Description | Default |
|------|-------------|---------|
| `--message <text>` | **Required.** Message to send | — |
| `--agent <id>` | Target a specific agent | default agent |
| `--to <dest>` | Destination (derives session key) | — |
| `--session-id <id>` | Reuse a specific session by ID | — |
| `--thinking <level>` | `off\|minimal\|low\|medium\|high\|xhigh` | — |
| `--verbose <level>` | `on\|full\|off` | — |
| `--channel <name>` | Channel for delivery context | whatsapp |
| `--deliver` | Send reply to channel (CAUTION: Signal rate limits) | false |
| `--reply-channel <ch>` | Override delivery channel | — |
| `--reply-to <target>` | Override delivery target | — |
| `--local` | Run embedded agent (bypass Gateway) | false |
| `--timeout <seconds>` | Agent turn timeout (default 600) | — |
| `--json` | Structured JSON output | false |

The `--json` output includes useful metadata:
```json
{
  "runId": "ba05a4b5-...",
  "status": "ok",
  "summary": "completed",
  "result": {
    "payloads": [{"text": "agent response", "mediaUrl": null}],
    "meta": {
      "durationMs": 8530,
      "agentMeta": {
        "sessionId": "9bba31e0-...",
        "provider": "anthropic",
        "model": "claude-sonnet-4-5",
        "usage": {
          "input": 10,
          "output": 141,
          "cacheRead": 0,
          "cacheWrite": 77600,
          "total": 77751
        }
      }
    }
  }
}
```

**Use for:** Sending instructions to agents, triggering exports, wake messages, asking questions.
**Do NOT use for:** `/reset`, `/compact`, `/new`, `/status` — these are not intercepted.

---

## `openclaw status` — Aggregated System View

The best single command for a system overview. Shows all agents and sessions.

```bash
openclaw status [--json] [--all] [--deep] [--usage]
```

The `--json` output includes comprehensive session data under `sessions.byAgent[]` with full token counts, session IDs, and per-agent breakdowns. This is the **most complete session overview** available from any single CLI command.

**Current state (2026-02-06):**

| Agent | Session Key | Tokens | Model | Context |
|-------|-------------|--------|-------|---------|
| bruba-main | agent:bruba-main:main | 51k | sonnet | 1000k |
| bruba-manager | agent:bruba-manager:main | 14k | sonnet | 1000k |
| bruba-guru | agent:bruba-guru:main | 46k | opus | 200k (23%) |
| bruba-rex | agent:bruba-rex:main | 32k | opus | 200k (16%) |
| bruba-web | agent:bruba-web:main | 0 (just reset) | sonnet | 1000k |

6 agent stores, 27 total sessions (includes cron and historical sessions).

---

## `openclaw reset` — Nuclear Reset (NOT for Individual Agents)

```bash
openclaw reset [--scope config|config+creds+sessions|full] [--yes] [--non-interactive] [--dry-run]
```

This resets **all** sessions plus optionally config and credentials. There is no per-agent targeting. **Never use this for routine maintenance.**

---

## `session.reset` Config — Does NOT Exist

```bash
$ openclaw config get session.reset
Config path not found: session.reset

$ openclaw config get session.reset.mode
Config path not found: session.reset.mode
```

The docs.openclaw.ai documentation claims `session.reset.mode: "daily"` enables automatic daily resets at a configured hour. **This config path does not exist on version 2026.2.1.** Either it was removed, or it was never implemented.

The `openclaw config get session` only returns:
```json
{
  "agentToAgent": {
    "maxPingPongTurns": 2
  }
}
```

**Implication:** There is no automatic daily reset. Sessions accumulate indefinitely without manual intervention.

---

## Compaction Config (Verified)

```bash
$ openclaw config get agents.defaults.compaction
```
```json
{
  "mode": "safeguard",
  "reserveTokensFloor": 20000,
  "memoryFlush": {
    "enabled": true,
    "softThresholdTokens": 100000,
    "prompt": "Write to memory/CONTINUATION.md immediately: ...",
    "systemPrompt": "CRITICAL: Session nearing compaction. Save all important context NOW."
  }
}
```

Compaction mode is `safeguard` (only compacts when context would overflow). Auto-compaction triggers when tokens exceed the context window minus `reserveTokensFloor` (20k). Memory flush fires at 100k tokens.

---

## Cron System (Verified)

```bash
openclaw cron list [--all] [--json]     # List jobs (7 registered)
openclaw cron status                     # Scheduler status (shows 8 jobs — discrepancy)
openclaw cron runs --id <id> [--limit N] # Execution history per job
openclaw cron run <jobId> [--force]      # Manual trigger
openclaw cron add ...                    # Create job
openclaw cron edit <jobId> ...           # Modify job
openclaw cron rm <jobId>                 # Delete job
openclaw cron enable/disable <jobId>     # Toggle job
```

`cron list --json` returns full job definitions including payload messages, schedule, isolation config, and state (lastRunAtMs, lastStatus, nextRunAtMs).

---

## System Events & Heartbeat (Verified)

```bash
openclaw system event --text "..." --mode now|next-heartbeat [--json]
openclaw system heartbeat enable|disable|last [--json]
openclaw system presence [--json]
```

All heartbeats currently disabled across all agents.

---

## Agent Management (Verified)

```bash
openclaw agents list [--json]            # List agents (5 + legacy 'main')
openclaw agents add <id> [options]       # Create agent
openclaw agents set-identity <id> ...    # Update name/emoji/avatar
openclaw agents delete <id> [--force]    # Remove agent
```

`agents list --json` includes `id`, `name`, `workspace`, `agentDir`, `model`, `bindings` count, `isDefault`.

---

## ACP (Agent Control Protocol) — Session Reset Flag

```bash
openclaw acp --reset-session --session <key>
```

The `--reset-session` flag resets a session before starting an ACP bridge. Not tested empirically, but the flag exists. Less useful than `gateway call sessions.reset` for scripting.

---

## Scripting Verdict

### For Session Reset

| Method | Works? | Notes |
|--------|--------|-------|
| `openclaw gateway call sessions.reset --params '{"key":"..."}'` | **YES** | New sessionId, 0 tokens. The correct method. |
| `openclaw agent --message "/reset" --agent <id>` | **NO** | Agent interprets as text. Tokens go UP. |
| `sessions_send "/reset"` (from another agent) | **NO** | Same broken pattern. |
| `openclaw sessions reset --agent <id>` | **NO** | Not a real subcommand. Silently ignored. |
| `openclaw reset --scope config+creds+sessions` | Works but nuclear | Resets ALL sessions + config. Not for individual agents. |

### For Compaction

| Method | Works? | Notes |
|--------|--------|-------|
| `openclaw gateway call sessions.compact --params '{"key":"..."}'` | **YES** | Returns `compacted` boolean and `kept` count. |
| `openclaw agent --message "/compact" --agent <id>` | **NO** | Agent interprets as text. |
| `sessions_send "/compact"` (from another agent) | **NO** | Same broken pattern. |

### For Session Listing

| Method | Works? | Notes |
|--------|--------|-------|
| `openclaw gateway call sessions.list --json` | **YES** | All agents, richest data. |
| `openclaw status --json` | **YES** | All agents via `sessions.byAgent[]`. Includes more system context. |
| `openclaw sessions --store <path> --json` | **YES** | Per-agent only. Must know the store path. |
| `openclaw sessions --json` | Misleading | Only reads default agent store (usually empty on multi-agent). |
| `openclaw sessions --agent <id>` | **NO** | Flag silently ignored. |

### Correct Nightly Maintenance Pattern

```bash
#!/bin/bash
# Nightly session reset for all agents

# 1. Force compaction (preserves summaries)
for key in "agent:bruba-main:main" "agent:bruba-guru:main" "agent:bruba-rex:main"; do
    openclaw gateway call sessions.compact --params "{\"key\":\"$key\"}"
done

# 2. Reset sessions
for key in "agent:bruba-main:main" "agent:bruba-guru:main" "agent:bruba-rex:main"; do
    openclaw gateway call sessions.reset --params "{\"key\":\"$key\"}"
done

# 3. Manager cycle (separate — Main handles Manager)
openclaw gateway call sessions.compact --params '{"key":"agent:bruba-manager:main"}'
openclaw gateway call sessions.reset --params '{"key":"agent:bruba-manager:main"}'

# 4. Verify
openclaw gateway call sessions.list --json | jq '[.sessions[] | select(.key | endswith(":main")) | {key, totalTokens, sessionId}]'
```

---

## Previously Documented Claims vs. Reality

| Claim (from docs.openclaw.ai) | Reality (empirical) |
|-------------------------------|-------------------|
| "Slash commands via `--message` are intercepted by Gateway" | **FALSE** — passed through as text |
| "`/compact`, `/reset`, `/new`, `/status` all work through agent interface" | **FALSE** — none are intercepted |
| "`session.reset.mode: 'daily'` enables automatic resets" | **FALSE** — config path doesn't exist |
| "Session entries include `compactionCount`, `memoryFlushAt`" | **NOT VISIBLE** — not in CLI output |
| "`openclaw sessions reset --agent <id>` works" | **FALSE** — not a real subcommand |
| "The agent command is your primary scripting interface" | **PARTIALLY TRUE** — for messages yes, for lifecycle ops no |

**The real scripting interface for session lifecycle is `openclaw gateway call`.**

---

## Tool Provisioning: `tools.allow` vs `tools.deny`

OpenClaw uses two complementary lists in `openclaw.json` per agent:

| Field | Behavior | When Absent |
|-------|----------|-------------|
| `tools.allow` | **Strict whitelist** — only these tools are provisioned | All tools available (minus deny list) |
| `tools.deny` | **Blacklist** — these tools are removed | No tools removed |

**Critical:** When `tools.allow` is present, it's a **strict whitelist**. The model will only see the listed tools — regardless of what else is available. Both lists can coexist: allow defines the ceiling, deny removes from it.

### The `sync-openclaw-config.sh` Gotcha

The config-sync script only writes `tools.allow` to `openclaw.json` when `tools_allow` is explicitly defined in `config.yaml` for that agent. If `tools_allow` is missing from config.yaml:
- The script skips the allow-list entirely
- Any existing `tools.allow` on the bot is **preserved unchanged**
- This can leave stale whitelists that are missing newly needed tools

**Example failure (2026-02-06):** Manager had `tools.allow` set to 7 tools in `openclaw.json` (from initial setup), but config.yaml only had `tools_deny`. Adding session-control (which needs `exec`) to config.yaml didn't help because `sync-openclaw-config.sh` never touched the existing allow list.

**Fix:** Always define explicit `tools_allow` for every agent in `config.yaml`. If an agent should have all tools except those denied, either:
1. List all desired tools in `tools_allow`, or
2. Remove `tools.allow` from `openclaw.json` manually and rely solely on `tools.deny`

### Isolated Cron Sessions

Isolated cron sessions inherit `tools.allow`/`tools.deny` from the agent config. If `exec` is not in the allow list, the cron session cannot run exec commands — the model literally won't see exec as an available tool.

**Best practice:** For cron jobs that need exec, use `sessions_send` to delegate to the agent's main session rather than running exec directly in the isolated session.
