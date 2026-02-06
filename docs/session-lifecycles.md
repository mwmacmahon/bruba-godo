---
version: 1.2.0
updated: 2026-02-03 17:30
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
| **3. Nightly Cron Cycle** | Prep → reset → continue | Nightly at 4:00–4:10 AM | Automated (prep is best-effort) | Full overnight handoff |

**Key insight:** These layers cover different gaps. memoryFlush catches surprise mid-session compaction. Manual packets handle intentional resets. The nightly cron cycle (prep → reset → continue) automates overnight handoff — prep writes CONTINUATION.md, reset clears sessions, continue loads the packet into the fresh session.

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

**Note:** We do NOT use OpenClaw's built-in `session.reset` config. Instead, our nightly cron job runs `exec session-reset.sh all` via `openclaw gateway call sessions.reset`, resetting all 5 agents (Main, Manager, Guru, Rex, Web) at 4:08 AM.

---

## Part 2: Session Lifecycle Mechanisms

### What Resets a Session?

OpenClaw provides multiple session reset triggers:

| Trigger | Method | Effect |
|---------|--------|--------|
| **Nightly cron** | `exec session-reset.sh all` | Isolated Manager cron at 4:08 AM resets all 5 agents; `nightly-continue` at 4:10 AM loads CONTINUATION.md for Main, Rex, Guru |
| **Manual CLI** | `openclaw gateway call sessions.reset --params '{"key":"..."}'` | Immediate real reset |
| **Manual script** | `session-reset.sh <agent>` | Wrapper around gateway call |
| **Gateway restart** | N/A | Sessions persist (stored in JSONL) |

**Our approach:** We do NOT use OpenClaw's built-in `session.reset` config (e.g. `session.reset.mode: daily`). Instead, the nightly cron job runs `exec session-reset.sh all` which calls `openclaw gateway call sessions.reset` per agent. This gives us explicit control over which agents reset and when.

**What does NOT work:** `sessions_send "/reset"`, `openclaw agent --message "/reset"`, `openclaw sessions reset --agent <id>` — all silently fail or are interpreted as text.

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

With our config on 200K window: `200,000 - 20,000 - 40,000 = 140,000 tokens`

**Note:** softThresholdTokens was increased from 8K to 40K (2026-02-03) to give more warning before compaction and reduce surprise compaction frequency.

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

### Layer 3: Nightly Cron Cycle (Automated Overnight Handoff)

**Covers:** Full overnight session handoff — prep writes CONTINUATION.md, reset clears all sessions, continue loads packets into fresh sessions.

**Sequence:**
1. `nightly-prep` (4:00 AM) — asks Main, Manager, Guru, Rex to write CONTINUATION.md
2. `nightly-reset` (4:08 AM) — resets all 5 agents via `exec session-reset.sh all`
3. `nightly-continue` (4:10 AM) — asks Main, Rex, Guru to load CONTINUATION.md

**Limitation:** Prep is best-effort (agent can ignore prompt). Continue only targets agents with meaningful session state (Manager and Web excluded — stateless).

### Coverage Matrix

| Event | memoryFlush | Manual Packet | Nightly Cron Cycle |
|-------|-------------|---------------|-------------------|
| Auto-compaction | ✅ | ❌ | ❌ |
| Manual `/compact` | ❌ | ✅ | ❌ |
| Manual `/reset` | ❌ | ✅ | ❌ |
| Daily reset (4am) | ❌ | ❌ | ✅ (prep → reset → continue) |
| Idle timeout reset | ❌ | ✅ | ❌ |
| End of work session | ❌ | ✅ | ❌ |

---

## Part 7: Isolated Cron Jobs

### What "Isolated" Means

When a cron job runs with `--session isolated --agent bruba-manager`:

| Inherits from Agent | Stays Isolated |
|--------------------|----------------|
| Tool permissions (from `tools.allow`/`tools.deny` — see note below) | Session context (fresh each run) |
| Workspace access (directories) | No carryover between runs |
| Auth profiles (API keys) | No impact on agent's main session |

The cron job runs under the agent's *identity* but in a completely *separate session* that starts fresh each execution.

**Tool availability caveat:** If the agent has a `tools.allow` whitelist in `openclaw.json`, the isolated session gets **only those tools**. This is a strict whitelist — tools not listed are simply not provisioned. If `exec` is missing from `tools.allow`, the cron job cannot run exec commands. This caused the nightly-reset failure on 2026-02-06 (Manager's allow list was stale, missing `exec`).

**Best practice for exec in cron:** Ensure `exec` is in the agent's `tools_allow` in `config.yaml`, then run `sync-openclaw-config.sh`. Direct exec in isolated sessions works reliably once the whitelist is correct.

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

### openclaw.json (Simplified, Session-Relevant Portions)

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
          "softThresholdTokens": 40000,
          "systemPrompt": "CRITICAL: Session nearing compaction. Save all important context NOW.",
          "prompt": "Write to memory/CONTINUATION.md immediately:\n1. Session summary\n2. In-progress work with status\n3. Open questions\n4. Next steps\n5. Relevant files\n\nReply NO_REPLY when done."
        }
      },
      "sandbox": { "mode": "off" }
    },
    "list": [
      {
        "id": "bruba-main",
        "name": "Bruba",
        "default": true,
        "workspace": "/Users/bruba/agents/bruba-main",
        "model": "sonnet",
        "heartbeat": { "every": "1h" },
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
        "tools": {
          "allow": ["web_search", "web_fetch", "read", "write"],
          "deny": ["exec", "edit", "apply_patch",
                   "memory_search", "memory_get",
                   "sessions_spawn", "sessions_send",
                   "browser", "canvas", "cron", "gateway"]
        }
      },
      {
        "id": "bruba-guru",
        "name": "Guru",
        "workspace": "/Users/bruba/agents/bruba-guru",
        "model": "opus",
        "heartbeat": { "every": "0m" },
        "tools": {
          "deny": ["web_search", "web_fetch", "browser", "canvas",
                   "cron", "gateway", "sessions_spawn"]
        }
      }
    ]
  },
  "tools": {
    "agentToAgent": {
      "enabled": true,
      "allow": ["bruba-main", "bruba-manager", "bruba-web", "bruba-guru"]
    }
  }
}
```

**Model notes:**
- **bruba-main:** Uses Sonnet directly (previously Opus with Sonnet fallback, but mid-session model switching caused compaction issues)
- **bruba-guru:** Uses Opus for deep research tasks
- **bruba-manager/bruba-web:** Sonnet (cost-effective for coordination/web tasks)

### Nightly Cron Cycle

The nightly cycle is managed by 4 cron jobs, all running as bruba-manager in isolated Sonnet sessions. See [Cron System](cron-system.md) for full details.

```
4:00 AM  nightly-export    Manager → Main, Rex: "Run export prompt"
4:00 AM  nightly-prep      Manager → Main, Manager, Guru, Rex: "Write CONTINUATION.md"
4:08 AM  nightly-reset     Manager (isolated) → exec session-reset.sh all
4:10 AM  nightly-continue  Manager → Main, Rex, Guru: "Load CONTINUATION.md"
```

**Notes:**
- `nightly-prep` uses `sessions_send` to ask agents to write CONTINUATION.md before reset
- `nightly-reset` runs `exec session-reset.sh all` directly in an isolated session (resets all 5 agents including Manager itself)
- `nightly-continue` asks Main, Rex, and Guru to load their continuation packets into fresh sessions (Manager and Web excluded — stateless)
- The `continuity` prompt component handles the READ side — detects and announces loaded packets on session start

---

## Part 9: Operations

### Monitoring Session Health

```bash
# Check all sessions (via session-control scripts on bot)
./tools/bot '/Users/bruba/agents/bruba-shared/tools/session-status.sh all'

# Check single agent
./tools/bot '/Users/bruba/agents/bruba-shared/tools/session-status.sh bruba-main'

# Check if memoryFlush fired
./tools/bot 'grep "memoryFlush" ~/.openclaw/logs/agents/bruba-main.log'
```

### Manual Interventions

```bash
# Force compaction (memoryFlush will NOT fire)
./tools/bot '/Users/bruba/agents/bruba-shared/tools/session-compact.sh bruba-main'

# Reset single agent session
./tools/bot '/Users/bruba/agents/bruba-shared/tools/session-reset.sh bruba-web'

# Reset ALL agents (same as nightly cron)
./tools/bot '/Users/bruba/agents/bruba-shared/tools/session-reset.sh all'

# Or via gateway call directly
./tools/bot 'openclaw gateway call sessions.reset --params '\''{"key":"agent:bruba-main:main"}'\'''
```

**Important:** `sessions_send "/reset"` and `openclaw agent --message "/reset"` do NOT work. Agents interpret them as text. Only `openclaw gateway call sessions.reset` performs a real reset.

### Debugging Context Issues

**Symptom:** Responses getting slow, agent forgetting recent context.

**Check:**
1. Session health: `./tools/bot 'session-status.sh all'` (shows tokens per agent)
2. Recent compactions in logs
3. Whether memoryFlush ran (check for memory/CONTINUATION.md updates)

**Fix:**
1. Request manual continuation packet
2. Reset session: `./tools/bot 'session-reset.sh bruba-main'`
3. Agent reads CONTINUATION.md on next interaction

---

## Part 10: Known Limitations

### Per-Agent Reset via Cron Script

We don't use OpenClaw's built-in `session.reset` config (which would be global and non-customizable). Instead, `session-reset.sh all` explicitly resets all 5 agents at 4:08 AM. Individual agents can be reset manually:
```bash
./tools/bot '/Users/bruba/agents/bruba-shared/tools/session-reset.sh bruba-web'
```

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
| Nightly cron cycle | Overnight context (prep + reset + continue) | Daily reset |
| State files | Operational data (manager) | Everything |
| Memory files | Searchable knowledge | Everything |

### Global Settings Summary

| Setting | Value | Applies To |
|---------|-------|------------|
| Daily reset | 4:08 AM (all 5 agents via cron) | All agents |
| Compaction mode | safeguard | All agents |
| reserveTokensFloor | 20,000 tokens | All agents |
| memoryFlush | Enabled, 40K threshold | All agents |
| Sandbox | Off | All agents |

### Agent Model Summary

| Agent | Model | Purpose |
|-------|-------|---------|
| bruba-main | Sonnet | Primary conversation (was Opus, changed due to fallback-induced compaction) |
| bruba-manager | Sonnet (Haiku fallback) | Coordination, heartbeats |
| bruba-web | Sonnet | Web research |
| bruba-guru | Opus | Deep research tasks |

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.2.0 | 2026-02-03 | **Model and compaction updates:** bruba-main switched to Sonnet (Opus fallback caused mid-session compaction). softThresholdTokens increased 8K→40K. Added bruba-guru to agent list. Sandbox mode now "off" for all agents. |
| 1.1.1 | 2026-02-02 | Fixed pre-reset cron syntax: `--system-event` not `--message` for main session jobs. Added temp file approach for multiline prompts. |
| 1.1.0 | 2026-02-02 | Corrected config scope: session/compaction/pruning are global-only, not per-agent. Removed contextPruning (would affect main). Added known limitations section. |
| 1.0.0 | 2026-02-02 | Initial version (had incorrect per-agent configs) |