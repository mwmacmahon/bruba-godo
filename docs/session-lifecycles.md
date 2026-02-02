---
version: 1.1.1
updated: 2026-02-03 00:15
type: refdoc
project: planning
tags: [bruba, openclaw, sessions, compaction, memoryflush, continuity]
---

# Bruba Session Lifecycle Reference

Comprehensive reference for session management, context continuity, and memory preservation across the Bruba multi-agent system. Covers the mechanics of compaction, memoryFlush, and the continuation packet system.

---

## Executive Summary

Bruba uses a **three-layer continuity system** to preserve context across session boundaries:

| Layer | Mechanism | Triggers On | Reliability | Purpose |
|-------|-----------|-------------|-------------|---------|
| **1. memoryFlush** | Agent writes to disk before compaction | Auto-compaction threshold | Best-effort (agent can ignore) | Safety net for unexpected compaction |
| **2. Continuation Packets** | Manual structured export | User request, conversation export | Guaranteed (explicit action) | Deliberate session handoff |
| **3. Pre-reset Cron** | Scheduled continuity write | 5 min before daily reset | Best-effort (agent can ignore) | Overnight safety net |

**Key insight:** These layers cover different gaps. memoryFlush catches surprise mid-session compaction. Manual packets handle intentional resets. Pre-reset cron catches "forgot to export before bed."

**Important limitation:** Session reset, compaction, and contextPruning settings are **global only** — they cannot be configured per-agent. All agents share the same session lifecycle settings.

---

## Part 1: Configuration Scope

### What Can Be Configured Per-Agent?

| Setting | Per-Agent? | Where It Goes |
|---------|------------|---------------|
| `session.reset` | ❌ No | Global `session.reset` |
| `compaction` / `memoryFlush` | ❌ No | `agents.defaults.compaction` |
| `contextPruning` | ❌ No | `agents.defaults.contextPruning` |
| `tools` | ✅ Yes | `agents.list[]` |
| `model` | ✅ Yes | `agents.list[]` |
| `heartbeat` | ✅ Yes | `agents.list[]` |
| `sandbox` | ✅ Yes | `agents.list[]` |
| `memorySearch` | ✅ Yes | `agents.list[]` |

**Implication:** All agents (bruba-main, bruba-manager, bruba-web) share the same session reset schedule and compaction settings. We cannot give bruba-web a separate idle timeout — it resets at 4am daily like everyone else.

---

## Part 2: Session Lifecycle Mechanisms

### What Resets a Session?

OpenClaw provides multiple session reset triggers:

| Trigger | Config | Effect |
|---------|--------|--------|
| **Daily reset** | `session.reset.mode: "daily"` | Fresh session at configured hour (default 4am) |
| **Idle timeout** | `session.reset.mode: "idle"` | Fresh session after N minutes of inactivity |
| **Manual reset** | `/reset` or `/new` command | Immediate fresh session |
| **Gateway restart** | N/A | Sessions persist (stored in JSONL) |

When both daily and idle are configured, **whichever expires first** triggers the reset.

**Our config:** Daily reset at 4am for all agents.

### What Happens on Reset?

1. Current session transcript archived (remains on disk)
2. New session ID created
3. Context starts fresh — only bootstrap files (IDENTITY.md, SOUL.md, etc.)
4. Memory system remains intact (separate from session)
5. Workspace files remain intact

**Critical:** memoryFlush does NOT fire on reset. Only on auto-compaction.

### Per-Type and Per-Channel Overrides

While per-agent reset isn't supported, you can override by session type or channel:

```json
{
  "session": {
    "reset": { "mode": "daily", "atHour": 4 },
    "resetByType": {
      "dm": { "mode": "idle", "idleMinutes": 240 },
      "group": { "mode": "idle", "idleMinutes": 30 }
    },
    "resetByChannel": {
      "discord": { "mode": "idle", "idleMinutes": 10080 }
    }
  }
}
```

**Not currently used in Bruba** — all sessions use the global daily reset.

---

## Part 3: Compaction Deep Dive

### What Compaction Does

Compaction summarizes older conversation history to free up context space:

```
BEFORE COMPACTION:
[Message 1] [Message 2] [Message 3] ... [Message 500] [Message 501]
                                              ↑
                                        context limit approaching

AFTER COMPACTION:
[Summary of Messages 1-450] [Message 451] ... [Message 501]
```

The summary replaces detailed history. Nuance is lost — exact phrasing, reasoning chains, specific values discussed.

### Compaction Triggers

| Trigger | memoryFlush fires? | Notes |
|---------|-------------------|-------|
| Auto (threshold crossed) | ✅ Yes | `contextTokens > contextWindow - reserveTokensFloor` |
| Manual `/compact` | ❌ No | User-initiated, no flush |
| Overflow recovery | ✅ Yes | Model returns context overflow error |

**Threshold formula:**
```
Auto-compaction when: currentTokens >= contextWindow - reserveTokensFloor - softThresholdTokens
```

With defaults on 200K window: `200,000 - 20,000 - 8,000 = 172,000 tokens`

### Compaction Modes

| Mode | Behavior |
|------|----------|
| `default` | Basic summarization |
| `safeguard` | Chunked summarization for very long histories, adaptive retry, progressive fallback |

**Our config:** Always use `safeguard` mode.

---

## Part 4: memoryFlush Explained

### What memoryFlush Actually Does

memoryFlush is a **pre-compaction hook** that gives the agent a chance to write structured information to disk before summarization destroys nuance.

**The sequence:**
```
1. Token threshold crossed
2. memoryFlush fires (silent agentic turn)
   → Agent receives flush prompt
   → Agent writes to memory/CONTINUATION.md (hopefully)
3. Compaction runs
   → Old messages summarized
4. Post-compaction state
   → Summary + recent messages in context
   → Memory files searchable via memory_search tool
```

### What memoryFlush Does NOT Do

- ❌ Does not fire on manual `/compact`
- ❌ Does not fire on daily reset
- ❌ Does not fire on idle timeout reset
- ❌ Does not seed post-compaction context (just writes to disk)
- ❌ Does not guarantee agent compliance

### memoryFlush vs Compaction: What's Preserved?

| Lost in Compaction | Preserved via memoryFlush |
|--------------------|---------------------------|
| Exact reasoning chains | Decisions with rationale |
| Specific code changes | Task completion logs |
| Configuration details | Skills/integrations setup |
| Conversational nuances | Structured summaries |
| User priorities discussed | Explicit preference notes |

**The value:** Post-compaction, the agent can use `memory_search` to find details that the summary lost.

### Effective memoryFlush Prompts

Agent compliance is the weak link. Community patterns that improve compliance:

**Our prompt (urgency + structure):**
```
CRITICAL: Session nearing compaction. Save all important context NOW.

Write to memory/CONTINUATION.md immediately:
1. Session summary
2. In-progress work with status
3. Open questions
4. Next steps
5. Relevant files

Reply NO_REPLY when done.
```

Using words like "CRITICAL," "MUST," and "NOW" significantly improves agent compliance across models.

---

## Part 5: Continuation Packet System

### What Continuation Packets Are

A structured markdown file (`memory/CONTINUATION.md`) that bridges session resets with explicit context handoff.

**Standard format:**
```markdown
# Continuation Packet — 2026-02-02

## Session Summary
[What we discussed/accomplished]

## In Progress
- [Task 1]: [status, blockers]
- [Task 2]: [status, next step]

## Open Questions
- [Question 1]
- [Question 2]

## Next Steps
1. [Action item]
2. [Action item]

## Relevant Files
- `path/to/file.md` — [what it contains]
- `path/to/other.md` — [what it contains]
```

### When to Create Packets

| Situation | Create Packet? | Mechanism |
|-----------|---------------|-----------|
| Exporting conversation | ✅ Yes | Part of export flow |
| End of work session | ✅ Yes | Manual request |
| Before intentional `/reset` | ✅ Yes | Manual request |
| Overnight (forgot to export) | ✅ Yes | Pre-reset cron (automatic) |
| Mid-session compaction | ✅ Yes | memoryFlush (automatic, best-effort) |

### Why Keep Instead of Archive

If you `/reset` again before making progress, the context is still there. Only overwritten when creating a new packet. This prevents context loss from rapid resets during testing.

---

## Part 6: The Three-Layer Continuity System

### Layer 1: memoryFlush (Auto-Compaction Safety Net)

**Covers:** Unexpected mid-session compaction when context grows too large.

**Limitation:** Does not fire on manual `/compact`, daily reset, or idle reset. Agent can ignore prompt.

**Config:** Global in `agents.defaults.compaction.memoryFlush`

### Layer 2: Manual Continuation Packets

**Covers:** Intentional session handoffs — exports, end of work session, before testing resets.

**Limitation:** Requires explicit action. Can forget.

**Mechanism:** Part of export flow, or explicit request to agent.

### Layer 3: Pre-Reset Cron (Overnight Safety Net)

**Covers:** "Forgot to export before bed" — automatic continuity write before daily reset.

**Limitation:** Agent can ignore prompt. Adds tokens to session right before reset.

**Config:** Cron job at 3:55am running in bruba-main's session.

### Coverage Matrix

| Event | memoryFlush | Manual Packet | Pre-reset Cron |
|-------|-------------|---------------|----------------|
| Auto-compaction | ✅ | ❌ | ❌ |
| Manual `/compact` | ❌ | ✅ | ❌ |
| Manual `/reset` | ❌ | ✅ | ❌ |
| Daily reset (4am) | ❌ | ❌ | ✅ |
| Idle timeout reset | ❌ | ✅ | ❌ |
| End of work session | ❌ | ✅ | ❌ |

---

## Part 7: Isolated Cron Jobs

### What "Isolated" Means

When a cron job runs with `--session isolated --agent bruba-manager`:

| Inherits from Agent | Stays Isolated |
|--------------------|----------------|
| Tool permissions (allowlist/denylist) | Session context (fresh each run) |
| Workspace access (directories) | No carryover between runs |
| Auth profiles (API keys) | No impact on agent's main session |

The cron job runs under the agent's *identity* but in a completely *separate session* that starts fresh each execution.

### Why This Matters for Context Bloat

```
WITHOUT isolation (cron in main session):
  Each cron run adds tokens to main session
  → Context grows with every execution
  → Eventually triggers compaction or crashes

WITH isolation (--session isolated):
  Each cron run gets fresh session
  → Main session unaffected
  → Cron outputs go to files, not session context
```

**The file-based inbox pattern:**
- Isolated cron writes findings to `inbox/reminder-check.json`
- Manager's heartbeat (in main session) reads and deletes inbox files
- No session overlap, no context pollution

### Session Parameter Reference

| `--session` Value | Behavior |
|-------------------|----------|
| `isolated` | Fresh session ID each run, no context carryover |
| `main` | Runs in agent's main session, full context visible |
| `<custom-key>` | Named session, persists between runs with same key |

---

## Part 8: Complete Configuration

### openclaw.json

```json
{
  "session": {
    "reset": {
      "mode": "daily",
      "atHour": 4
    }
  },
  "agents": {
    "defaults": {
      "compaction": {
        "mode": "safeguard",
        "reserveTokensFloor": 20000,
        "memoryFlush": {
          "enabled": true,
          "softThresholdTokens": 8000,
          "systemPrompt": "CRITICAL: Session nearing compaction. Save all important context NOW.",
          "prompt": "Write to memory/CONTINUATION.md immediately:\n1. Session summary\n2. In-progress work with status\n3. Open questions\n4. Next steps\n5. Relevant files\n\nReply NO_REPLY when done."
        }
      }
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

### Pre-Reset Continuity Cron

**Important:** Main session cron jobs require `--system-event`, not `--message`. Shell quoting with multiline prompts is fragile — use temp file approach.

```bash
# Create temp file with message (avoids shell quoting issues)
cat > /tmp/pre-reset-msg.txt << 'EOF'
Session reset in 5 minutes. Write continuation packet to memory/CONTINUATION.md:

## Session Summary
[What we discussed/accomplished today]

## In Progress
[Tasks with status and blockers]

## Open Questions
[Unresolved items]

## Next Steps
[Action items for tomorrow]

## Relevant Files
[Paths and descriptions]

Reply NO_REPLY when done.
EOF

# Add cron with --system-event (required for main session jobs)
openclaw cron add \
  --name "pre-reset-continuity" \
  --cron "55 3 * * *" \
  --tz "America/New_York" \
  --session main \
  --system-event "$(cat /tmp/pre-reset-msg.txt)" \
  --agent bruba-main
```

**Notes:**
- Uses `--session main` (not isolated) so the cron runs inside bruba-main's conversation context
- Uses `--system-event` (not `--message`) — required for main session cron jobs
- The `continuity` prompt component handles the READ side — detects and announces loaded packets on session start

---

## Part 9: Operations

### Monitoring Session Health

```bash
# Check session size
openclaw sessions list --agent bruba-main

# Check compaction history
openclaw sessions info --agent bruba-main --session main

# Check if memoryFlush fired
grep "memoryFlush" ~/.openclaw/logs/agents/bruba-main.log
```

### Manual Interventions

```bash
# Force compaction (memoryFlush will NOT fire)
openclaw agent --agent bruba-main --message "/compact"

# Reset session (start fresh)
openclaw agent --agent bruba-main --message "/reset"

# Request continuation packet before reset
openclaw agent --agent bruba-main --message "Write a continuation packet to memory/CONTINUATION.md, then I'll reset"

# Reset bruba-web if it accumulates too much context
openclaw sessions reset --agent bruba-web
```

### Debugging Context Issues

**Symptom:** Responses getting slow, agent forgetting recent context.

**Check:**
1. Session size: `openclaw sessions list --agent bruba-main`
2. Recent compactions in logs
3. Whether memoryFlush ran (check for memory/CONTINUATION.md updates)

**Fix:**
1. Request manual continuation packet
2. Reset session: `/reset`
3. Agent reads CONTINUATION.md on next interaction

---

## Part 10: Known Limitations

### No Per-Agent Session Reset

All agents share the same `session.reset` config. We cannot give bruba-web a separate idle timeout — it resets at 4am daily like bruba-main and bruba-manager.

**Workaround:** Manually reset bruba-web if it accumulates too much context:
```bash
openclaw sessions reset --agent bruba-web
```

In practice, bruba-web sessions stay small (just search/summarize), so daily reset is likely sufficient.

### No Per-Agent Context Pruning

Context pruning (`contextPruning`) is global. We cannot enable aggressive pruning for bruba-manager without affecting bruba-main's tool results.

**Decision:** Context pruning disabled entirely. Rely on compaction + memoryFlush instead.

### memoryFlush Reliability

memoryFlush depends on agent compliance — the agent can ignore the prompt. Community workarounds:

1. **Urgency language** in prompts ("CRITICAL", "MUST", "NOW")
2. **Real-time logging rules** in AGENTS.md (write continuously, not just at flush)
3. **Multiple layers** (memoryFlush + manual packets + pre-reset cron)

---

## Part 11: Quick Reference

### When Does memoryFlush Fire?

| Event | Fires? |
|-------|--------|
| Auto-compaction (threshold) | ✅ |
| Manual `/compact` | ❌ |
| Daily reset | ❌ |
| Idle reset | ❌ |
| Manual `/reset` | ❌ |
| Gateway restart | ❌ |

### What Preserves What?

| Mechanism | Preserves | Survives |
|-----------|-----------|----------|
| memoryFlush | Structured details before auto-compaction | Compaction |
| Continuation packets | Explicit session handoff | Any reset |
| Pre-reset cron | Overnight context | Daily reset |
| State files | Operational data (manager) | Everything |
| Memory files | Searchable knowledge | Everything |

### Global Settings Summary

| Setting | Value | Applies To |
|---------|-------|------------|
| Daily reset | 4am | All agents |
| Compaction mode | safeguard | All agents |
| memoryFlush | Enabled, 8K threshold | All agents |
| Context pruning | Disabled | All agents |

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.1.1 | 2026-02-02 | Fixed pre-reset cron syntax: `--system-event` not `--message` for main session jobs. Added temp file approach for multiline prompts. |
| 1.1.0 | 2026-02-02 | Corrected config scope: session/compaction/pruning are global-only, not per-agent. Removed contextPruning (would affect main). Added known limitations section. |
| 1.0.0 | 2026-02-02 | Initial version (had incorrect per-agent configs) |