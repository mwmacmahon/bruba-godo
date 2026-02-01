---
type: doc
scope: reference
title: "Operations Guide"
description: "Day-to-day bot operations and maintenance tasks"
---

# Operations Guide

Day-to-day operations reference for managing your bot. For initial setup, see [Setup Guide](setup.md).

---

## Quick Reference

| Task | Skill | Direct Command |
|------|-------|----------------|
| Start daemon | `/launch` | `ssh bruba "clawdbot daemon start"` |
| Restart daemon | `/restart` | `ssh bruba "clawdbot daemon restart"` |
| Stop daemon | `/stop` | `ssh bruba "clawdbot daemon stop"` |
| Check status | `/status` | `ssh bruba "clawdbot status"` |
| Mirror files | `/mirror` | `./tools/mirror.sh` |
| Pull sessions | `/pull` | `./tools/pull-sessions.sh` |
| Push content | `/push` | `./tools/push.sh` |

---

## 1. Daemon Management

The Clawdbot daemon runs as a LaunchAgent on the bot account.

```bash
# Start the daemon
ssh bruba "clawdbot daemon start"

# Stop the daemon
ssh bruba "clawdbot daemon stop"

# Restart (required after config changes)
ssh bruba "clawdbot daemon restart"

# Check daemon status
ssh bruba "clawdbot daemon status"

# Comprehensive status (daemon + agents + sessions + memory)
ssh bruba "clawdbot status"
```

**When to restart:**
- After editing `~/.clawdbot/clawdbot.json`
- After editing `~/.clawdbot/exec-approvals.json`
- If bot becomes unresponsive

---

## 2. Sessions & Agents

### Viewing Sessions

```bash
# Comprehensive status
ssh bruba "clawdbot status"

# List sessions
ssh bruba "clawdbot sessions"

# Only recent sessions (last 2 hours)
ssh bruba "clawdbot sessions --active 120"
```

**Understanding session keys:**
- `agent:bruba-main:main` — Primary bot session
- `agent:web-reader:main` — Web search subagent (if configured)
- `agent:main:main` — Orphan from CLI testing (ignore)

### Managing Agents

```bash
# List configured agents
ssh bruba "clawdbot agents list"

# Agent details with bindings
ssh bruba "clawdbot agents list --bindings"
```

---

## 3. Session Continuity

Use a continuation file to preserve context across session boundaries (restarts, crashes, `/reset`).

### How It Works

| Component | Location | Purpose |
|-----------|----------|---------|
| `CONTINUATION.md` | `~/clawd/memory/CONTINUATION.md` | Active continuation state |
| Archive | `~/clawd/memory/archive/continuation-YYYY-MM-DD.md` | Historical continuations |

**Startup sequence:**
1. On session start, bot checks if `memory/CONTINUATION.md` exists
2. If found → reads content → archives to `memory/archive/continuation-YYYY-MM-DD.md`
3. Uses continuation context to resume work-in-progress
4. Creates new continuation as needed during session

### Archive vs Delete

Continuations are archived rather than deleted for crash protection:
- If bot crashes mid-session, the continuation survives
- Archive provides audit trail of session handoffs

### Example Continuation

```markdown
# CONTINUATION.md
## What I Was Working On
- Processing files from 2026-01-28
- Waiting for user decision on X

## Context Needed
- User mentioned wanting Y approach
- File Z was partially modified
```

**Manual cleanup (if needed):**
```bash
ssh bruba "ls ~/clawd/memory/archive/"        # Check archive size
ssh bruba "rm ~/clawd/memory/archive/*.md"    # Clear old continuations
```

---

## 4. Code Review & Migration

The bot stages draft tools in `~/.clawdbot/agents/<agent-id>/workspace/code/` for review before production deployment.

### Directory Reference

| Location | Purpose |
|----------|---------|
| `~/.clawdbot/agents/<id>/workspace/code/` | Staged scripts awaiting review |
| `~/clawd/tools/` | Production shell wrappers |
| `~/clawd/tools/helpers/` | Production Python helpers |
| `~/.clawdbot/exec-approvals.json` | Exec command allowlist |

### Migration Checklist

Before approving staged code:

- [ ] **Paths:** No hardcoded absolute paths that should be relative
- [ ] **Secrets:** No API keys, tokens, or credentials in code
- [ ] **Dependencies:** All called tools exist and are allowlisted
- [ ] **Safety:** Destructive operations require confirmation or dry-run default
- [ ] **Context:** Understand the conversation that produced this code

### Allowlist Update Procedure

**Automated (for component tools):**

Component tools with `allowlist.json` files are updated automatically:

```bash
# Check what entries are needed
./tools/update-allowlist.sh --check

# Add missing entries
./tools/update-allowlist.sh

# Or as part of push
./tools/push.sh --tools-only --update-allowlist

# Restart daemon after changes
ssh bruba 'clawdbot daemon restart'
```

**Manual (for custom tools):**

```bash
# 1. Add pattern to exec-approvals.json
ssh bruba 'cat ~/.clawdbot/exec-approvals.json | jq ".agents[\"bruba-main\"].allowlist += [{\"pattern\": \"/Users/bruba/clawd/tools/new-tool.sh\", \"id\": \"new-tool\"}]" > /tmp/ea.json && mv /tmp/ea.json ~/.clawdbot/exec-approvals.json'

# 2. Restart daemon
ssh bruba 'clawdbot daemon restart'

# 3. Verify
ssh bruba 'clawdbot gateway health'
```

### Cleanup

**Important:** The bot cannot delete files from its own workspace. After migration, clean up from operator side:

```bash
ssh bruba 'rm ~/.clawdbot/agents/bruba-main/workspace/code/migrated-script.sh'
```

Use `/code` skill to interactively review staged code, find conversation context, and migrate approved tools.

---

## 5. Memory & Search

```bash
# Check memory index status
ssh bruba "clawdbot memory status"

# Verbose status (shows chunk counts, vector status)
ssh bruba "clawdbot memory status --verbose"

# Reindex memory files
ssh bruba "clawdbot memory index"

# Search memory
ssh bruba "clawdbot memory search 'query terms'"
```

---

## 6. Configuration

### File Locations

| File | Purpose |
|------|---------|
| `~/.clawdbot/clawdbot.json` | Main config (agents, tools, channels) |
| `~/.clawdbot/exec-approvals.json` | Exec command allowlist |
| `~/.clawdbot/.env` | API keys (ANTHROPIC_API_KEY) |

### Viewing Config

```bash
# View specific config sections
ssh bruba "clawdbot config get agents"
ssh bruba "clawdbot config get tools"
```

### Diagnostic Commands

Quick health checks:

```bash
# Quick gateway health (compact)
ssh bruba "clawdbot gateway health"

# Security audit summary only
ssh bruba "clawdbot security audit --json" | jq '.summary'

# Full diagnostics
ssh bruba "clawdbot doctor"
ssh bruba "clawdbot security audit"
ssh bruba "clawdbot status"
```

**Output comparison:**

| Command | Output Size | Use Case |
|---------|-------------|----------|
| `gateway health` | ~4 lines | Quick post-restart verification |
| `security audit --json \| jq '.summary'` | 1 line | Check for new issues |
| `doctor` | ~40 lines | Full health check |
| `status` | ~30 lines | Session/agent details |
| `gateway probe` | ~12 lines | Connectivity debugging |

### Editing Config

```bash
# Option 1: SSH and edit directly
ssh bruba
nano ~/.clawdbot/clawdbot.json
exit

# Option 2: Use clawdbot config commands
ssh bruba 'clawdbot config set tools.exec.security allowlist'
```

**After any config change:** `ssh bruba "clawdbot daemon restart"`

---

## 7. File Sync Operations

### Data Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    OPERATOR ←→ BOT FILE FLOW                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Operator Machine                          Bot Machine                      │
│  ────────────────                          ───────────                      │
│                                                                             │
│  exports/bot/  ─────────── push ─────────► ~/clawd/memory/                  │
│  (content to sync)                         (searchable via memory_search)   │
│                                                                             │
│  components/*/tools/ ───── push ─────────► ~/clawd/tools/                   │
│  (component tools)                         (executable scripts)             │
│                                                                             │
│  mirror/       ◄────────── mirror ──────── ~/clawd/                         │
│  (local backup)                            MEMORY.md, journals, etc.        │
│                                                                             │
│  sessions/     ◄────────── pull ────────── ~/.clawdbot/sessions/*.jsonl     │
│  (transcripts)                             (immutable after close)          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

| Flow | Direction | Source of Truth | Processing |
|------|-----------|-----------------|------------|
| **Push** | Operator → Bot | Operator | Copy, reindex |
| **Mirror** | Bot → Operator | Bot | Copy, no processing |
| **Pull** | Bot → Operator | Bot (then Operator) | Parse JSONL, review |

### Manual Script Usage

```bash
# Mirror bot files locally
./tools/mirror.sh --verbose

# Pull closed session transcripts
./tools/pull-sessions.sh --verbose

# Push content to bot memory (includes component tools)
./tools/push.sh --verbose

# Push only component tools (skip content)
./tools/push.sh --tools-only

# Reindex bot's memory after push
ssh bruba "clawdbot memory index"
```

### What Gets Mirrored

The mirror script pulls from the bot:

| Category | Files | Location |
|----------|-------|----------|
| Core files | `AGENTS.md`, `IDENTITY.md`, `MEMORY.md`, `SOUL.md`, `TOOLS.md`, `USER.md` | `~/clawd/` |
| Bot-created | `_bruba_*.md` (synthesis docs) | `~/clawd/` |
| Journals | `YYYY-MM-DD.md` (dated files only) | `~/clawd/memory/` |

### Session Import Workflow

Full pipeline for importing transcripts to bot memory:

```
/pull → /convert → /intake → /export → /push
  │         │          │         │         │
  ▼         ▼          ▼         ▼         ▼
intake/   CONFIG    reference/  exports/  bot
*.md      blocks    transcripts/ bot/     memory
```

**Using /sync (recommended):**
```bash
# Full pipeline with prompts + content
/sync     # Choose option 3 for full sync

# Or content pipeline only
/sync     # Choose option 2
```

**Manual steps:**
```bash
./tools/pull-sessions.sh              # Pull JSONL → intake/*.md
/convert intake/<file>.md             # AI-assisted: add CONFIG block
/intake                               # Canonicalize → reference/transcripts/
/export                               # Filter → exports/bot/
./tools/push.sh                       # Sync to bot memory
```

**Reference documents (non-transcripts):**

Place markdown files with YAML frontmatter in `reference/refdocs/`:
```yaml
---
title: My Guide
scope: [reference]
---
```

These are included in `/export` and synced alongside transcripts.

See [Pipeline Documentation](pipeline.md) for full details.

### Sync Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Push succeeds but memory search empty | Index stale | `ssh bruba "clawdbot memory index"` |
| Pull finds no new sessions | All sessions already pulled | Check `sessions/.pulled` |
| Mirror missing files | Bot hasn't created them | Check bot's `~/clawd/` directly |

**State tracking:** Session UUIDs tracked in `sessions/.pulled`. Closed sessions are immutable, so no need to re-pull.

---

## 8. Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| Commands hang/timeout | Daemon not running | `/launch` |
| Config changes not taking effect | Daemon needs restart | `/restart` |
| Exec command denied | Not in allowlist | Add to `exec-approvals.json`, restart |
| Memory search empty | Index stale | `ssh bruba "clawdbot memory index"` |
| "Cannot connect" | SSH config issue | Check `~/.ssh/config` |

### Checking Logs

```bash
# View recent daemon logs
ssh bruba "tail -50 /tmp/clawdbot/clawdbot-$(date +%Y-%m-%d).log"

# Follow logs in real-time
ssh bruba "tail -f /tmp/clawdbot/clawdbot-$(date +%Y-%m-%d).log"
```

---

## 9. Operator Interaction

All bot operations use `ssh bruba "..."`. Some operations require user intervention:

### Interactive Commands

Some commands require interactive prompts — run them directly via SSH session:

```bash
ssh bruba
# Run interactive command
clawdbot onboard
exit
```

### Sudo Commands

Config protection may require sudo. Run from operator machine with sudo access:

```bash
sudo chown root:staff /Users/bruba/.clawdbot/clawdbot.json
```

### Examples Requiring User Action

- `pnpm approve-builds` — Interactive package selection
- `chown root:staff` — Re-protecting config files after updates
- Starting Docker Desktop — GUI application

---

## 10. Updating Clawdbot

### From Source (Recommended)

```bash
ssh bruba
cd ~/src/clawdbot
git fetch --tags
git tag -l | grep 2026 | tail -5  # See recent releases
git checkout v2026.x.y            # Checkout latest
pnpm install
pnpm build
exit

# Restart daemon
ssh bruba "clawdbot daemon restart"
```

### Verify Update

```bash
ssh bruba "clawdbot --version"
ssh bruba "clawdbot status"
```

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-01-30 | Initial version |
