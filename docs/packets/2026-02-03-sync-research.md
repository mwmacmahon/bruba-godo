# Research Packet: Alternatives to SSH-Based Bot Sync

**Date:** 2026-02-03
**Researcher:** Claude Projects (Web)
**Context:** bruba-godo operator workspace

---

## Goal

Research modern alternatives to SSH-based file synchronization and remote command execution for managing a bot running on a separate macOS machine.

---

## Current Situation

### Architecture
- **Operator machine:** Local dev machine (macOS) running `bruba-godo` workspace
- **Bot machine:** Remote macOS server running OpenClaw (AI agent framework)
- **Communication:** All interaction via SSH (`./tools/bot` wrapper)

### The Problem
SSH-based operations are extremely slow:
- Single SSH call: **1.5-2.7 seconds** (even with ControlMaster connection reuse)
- Typical `/prompt-sync` operation: **~2 minutes** before useful work

This makes iterating on prompts painful.

### Current Implementation

Tools use `./tools/bot` wrapper which does:
```bash
ssh -o ControlMaster=auto -o ControlPath=/tmp/ssh-... "$HOST" "$command"
```

**Scripts and their SSH call counts:**

| Script | SSH Calls | Purpose |
|--------|-----------|---------|
| mirror.sh | 14-20+ per agent | Pull bot state locally |
| push.sh | 9 | Push exports to bot |
| pull-sessions.sh | 3 | Pull conversation logs |

---

## Efficiency Recommendations Status

From `docs/efficiency-recommendations.md`:

### ✅ Implemented
| Recommendation | Status | Notes |
|----------------|--------|-------|
| SSH ControlMaster | ✅ Done | In lib.sh, but still ~1.5s/call |

### ❌ Not Implemented
| Recommendation | Status | Impact |
|----------------|--------|--------|
| mirror.sh N+1 fix | ❌ | Would reduce 14 calls → 3 calls |
| mirror.sh incremental | ❌ | Skip unchanged files via mtime |
| push.sh batch mkdir | ❌ | Minor improvement |
| sync-cronjobs.sh YAML parse | ❌ | Parse YAML once, not 9x/field |
| Manifest-based sync | ❌ | Track what's synced for deletions |

### Why SSH is still slow
Even with ControlMaster reuse, each call takes 1.5s. Possible causes:
- Network latency (VPN, geographic distance)
- Slow remote shell startup (zsh plugins, profile scripts)
- SSH config overhead

---

## Research Questions

### 1. File Synchronization Alternatives

**Question:** What are the best tools for keeping directories synchronized between two macOS machines in near-real-time?

Candidates to research:
- **Mutagen** - Developer-focused sync, handles file watching
- **Syncthing** - P2P, works without central server
- **Unison** - Bidirectional sync with conflict handling
- **lsyncd** - Uses rsync under the hood with inotify/fsevents
- **rclone bisync** - Cloud-focused but has local support

**Evaluation criteria:**
- Latency (how fast do changes propagate?)
- macOS support and reliability
- Resource usage (CPU, memory)
- Conflict handling
- Setup complexity
- Ability to exclude patterns (gitignore-style)

### 2. Remote Command Execution Alternatives

**Question:** What are alternatives to SSH for executing commands on a remote machine?

Candidates to research:
- **HTTP/REST API** - Simple server on bot, curl from operator
- **gRPC** - Faster than HTTP, good for tooling
- **Tailscale SSH** - Faster handshakes over WireGuard
- **mosh** - Mobile shell with better latency handling
- **WebSocket tunnel** - Persistent connection for commands

**Evaluation criteria:**
- Latency per command
- Authentication/security
- Implementation complexity
- macOS daemon support

### 3. Push vs Pull Architecture

**Question:** Should the operator pull from bot, or should bot push to operator?

Research patterns:
- Git-based workflows (bot commits, operator pulls)
- Webhook-based (bot POSTs changes to operator)
- Shared storage (both access same volume)
- Event streaming (bot emits change events)

### 4. Hybrid Approaches

**Question:** Are there existing tools that combine file sync with command execution?

Research:
- Development environment sync tools (like DevPod, Gitpod, Coder)
- Docker/container sync mechanisms
- IDE remote development features

---

## Specific Tool Research Requests

### Mutagen Deep Dive
1. How does Mutagen handle macOS file watching (fsevents)?
2. What's the typical sync latency for small file changes?
3. How does it handle .git directories and large binary files?
4. Can it run as a launchd service on macOS?
5. What's the conflict resolution UX?

### Tailscale SSH
1. How much faster is Tailscale SSH vs regular SSH?
2. Does it still support ControlMaster-like connection reuse?
3. Any gotchas with macOS?

---

## Constraints

- Both machines are macOS (Apple Silicon)
- Bot machine runs continuously (can run daemons)
- Operator machine is intermittent (laptop)
- Security: prefer encrypted transport, key-based auth
- No cloud services required (direct machine-to-machine preferred)
- Must work with existing rsync-based push.sh (can replace mirror.sh independently)

---

## Deliverables Requested

1. **Comparison table** of file sync tools with latency, setup complexity, pros/cons
2. **Recommendation** for which tool(s) to try first
3. **Setup guide** for recommended tool on macOS
4. **Migration path** from current SSH-based approach
5. **Any gotchas** specific to macOS or intermittent connections

---

## Current Directory Structure (for context)

```
bruba-godo/           # Operator workspace
├── mirror/           # Local copy of bot state (needs sync FROM bot)
│   └── {agent}/
│       ├── prompts/  # AGENTS.md, etc.
│       ├── memory/   # Bot's memory files
│       └── config/   # Bot's config
├── exports/          # Built content (needs sync TO bot)
│   └── bot/
│       ├── core-prompts/
│       ├── prompts/
│       └── transcripts/
└── tools/
    ├── mirror.sh     # Currently pulls via SSH
    └── push.sh       # Currently pushes via rsync/SSH
```

Bot machine paths:
- `/Users/bruba/agents/bruba-main/` — Agent workspace
- `/Users/bruba/.openclaw/` — OpenClaw config

---

## Success Criteria

After implementing an alternative:
1. `/prompt-sync` completes in <10 seconds (vs current ~2 min)
2. Local mirror reflects bot changes within seconds (vs manual pull)
3. No loss of current functionality
4. Reasonable setup complexity (< 1 hour)
