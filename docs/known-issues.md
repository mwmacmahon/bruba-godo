---
type: doc
scope: reference
title: "Known Issues"
description: "Active bugs, workarounds, and unconfirmed behaviors"
---

# Known Issues and Workarounds

Active bugs and behavioral observations affecting the Bruba multi-agent system.

> **Related docs:**
> - [Troubleshooting](troubleshooting.md) — Symptom-based fixes
> - [Security Model](security-model.md) — Security gaps and mitigations

---

## Bug #3589: Heartbeat Prompt Bleeding

**Status:** Open — [GitHub Issue #3589](https://github.com/openclaw/openclaw/issues/3589)

When cron jobs fire system events, the heartbeat prompt gets appended to ALL events. Cron job purposes get hijacked.

**Workaround:** File-based inbox handoff. Cron writes to files, no system events involved. See [Cron System](cron-system.md).

---

## Bug #4355: Session Lock Contention

Concurrent operations cause write lock contention.

**Workaround:** Keep `maxConcurrent` reasonable (4 for agents).

---

## Bug #5433: Compaction Overflow

Auto-recovery sometimes fails on context overflow.

**Workaround:** Monitor, restart gateway if stuck. `openclaw sessions reset --agent <id>` to clear.

---

## Issue #6295: Subagent Model Override Ignored

`sessions_spawn` parameter `model` is ignored; subagents inherit parent's model.

**Impact:** Not relevant for our architecture — we use separate agents instead of subagents for capability isolation.

---

## Voice Messages Cause Silent Compaction

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
3. **Turn off experimental session memory** — set `memorySearch.experimental.sessionMemory` to false in openclaw.json

**Proper fix needed:** OpenClaw should exclude binary content from context, keeping only the transcript.

**Reference:** Full investigation in `docs/cc_logs/2026-02-03-voice-message-context-crash.md`

---

## Global tools.allow Ceiling Effect (Needs Confirmation)

**Status:** Observed behavior — needs confirmation from OpenClaw docs/community

**Observed:** When `tools.allow` is set at the global level (`tools.allow` in openclaw.json root), it appears to create a **ceiling** for all agents. Even if an agent has a tool in its own `tools.allow`, it won't work unless the tool is also in the global list.

**Example:** bruba-web had `web_search` in its agent-level `tools.allow`, but the tool wasn't available until `web_search` was added to the global `tools.allow`.

**Current workaround:** Include all tools that ANY agent needs in global `tools.allow`. Use agent-level `tools.deny` to restrict specific agents.

```json
{
  "tools": {
    "allow": ["read", "write", "web_search", "web_fetch", ...],
    ...
  },
  "agents": {
    "list": [
      {
        "id": "bruba-main",
        "tools": {
          "deny": ["web_search", "web_fetch"]
        }
      },
      {
        "id": "bruba-web",
        "tools": {
          "allow": ["web_search", "web_fetch", "read", "write"]
        }
      }
    ]
  }
}
```

**TODO:** Confirm this behavior with OpenClaw documentation or community.
