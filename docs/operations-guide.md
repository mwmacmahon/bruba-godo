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
| Start daemon | `/launch` | `ssh bruba "openclaw daemon start"` |
| Restart daemon | `/restart` | `ssh bruba "openclaw daemon restart"` |
| Stop daemon | `/stop` | `ssh bruba "openclaw daemon stop"` |
| Check status | `/status` | `ssh bruba "openclaw status"` |
| Mirror files | `/mirror` | `./tools/mirror.sh` |
| Pull sessions | `/pull` | `./tools/pull-sessions.sh` |
| Push content | `/push` | `./tools/push.sh` |

---

## Signal Rate Limits (Critical)

**NEVER repeatedly trigger Signal messages during testing.** Signal has strict rate limits and anti-spam detection that WILL get the account logged out.

**Safe testing patterns:**
- Use `NO_REPLY` in cron job messages to suppress unnecessary Signal delivery
- Test with direct agent messages that don't go to Signal
- Use isolated sessions that write to files instead of messaging
- When testing post-reset-wake or similar multi-agent pings, do ONE test run, not repeated runs

**Unsafe patterns (AVOID):**
- Running cron job tests multiple times in quick succession
- Triggering heartbeats repeatedly to "see if it works"
- Using `cron run --force` repeatedly on Signal-delivering jobs

**If logged out:** You'll need to re-link the Signal account via signal-cli. This requires the phone and is disruptive.

---

## 1. Daemon Management

The OpenClaw daemon runs as a LaunchAgent on the bot account.

```bash
# Start OpenClaw gateway
openclaw gateway start

# Stop
openclaw gateway stop

# Force stop if stuck
openclaw gateway stop --force

# Check status
openclaw gateway status
```

**When to restart:**
- After editing `~/.openclaw/openclaw.json`
- After editing `~/.openclaw/exec-approvals.json`
- If bot becomes unresponsive

### Health Checks

```bash
openclaw health                                          # Overall status
openclaw sessions list --agent bruba-main                # Check specific agent
openclaw cron list                                       # Check cron jobs
openclaw cron runs --name heartbeat --limit 5            # Recent heartbeats
```

### Log Locations

```
~/.openclaw/logs/gateway.log     # Gateway process
~/.openclaw/logs/agents/         # Per-agent logs
~/.openclaw/sessions/            # Session transcripts
```

---

## 2. Sessions & Agents

### Viewing Sessions

```bash
# Comprehensive status
ssh bruba "openclaw status"

# List sessions
ssh bruba "openclaw sessions"

# Only recent sessions (last 2 hours)
ssh bruba "openclaw sessions --active 120"
```

**Understanding session keys:**
- `agent:bruba-main:main` — Primary bot session
- `agent:web-reader:main` — Web search subagent (if configured)
- `agent:main:main` — Orphan from CLI testing (ignore)

### Managing Agents

```bash
# List configured agents
ssh bruba "openclaw agents list"

# Agent details with bindings
ssh bruba "openclaw agents list --bindings"
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

The bot stages draft tools in `~/.openclaw/agents/<agent-id>/workspace/code/` for review before production deployment.

### Directory Reference

| Location | Purpose |
|----------|---------|
| `~/.openclaw/agents/<id>/workspace/code/` | Staged scripts awaiting review |
| `~/clawd/tools/` | Production shell wrappers |
| `~/clawd/tools/helpers/` | Production Python helpers |
| `~/.openclaw/exec-approvals.json` | Exec command allowlist |

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
ssh bruba 'openclaw daemon restart'
```

**Manual (for custom tools):**

```bash
# 1. Add pattern to exec-approvals.json
ssh bruba 'cat ~/.openclaw/exec-approvals.json | jq ".agents[\"bruba-main\"].allowlist += [{\"pattern\": \"/Users/bruba/agents/bruba-main/tools/new-tool.sh\", \"id\": \"new-tool\"}]" > /tmp/ea.json && mv /tmp/ea.json ~/.openclaw/exec-approvals.json'

# 2. Restart daemon
ssh bruba 'openclaw daemon restart'

# 3. Verify
ssh bruba 'openclaw gateway health'
```

### Cleanup

**Important:** The bot cannot delete files from its own workspace. After migration, clean up from operator side:

```bash
ssh bruba 'rm ~/.openclaw/agents/bruba-main/workspace/code/migrated-script.sh'
```

Use `/code` skill to interactively review staged code, find conversation context, and migrate approved tools.

---

## 5. Memory & Search

```bash
# Check memory index status
ssh bruba "openclaw memory status"

# Verbose status (shows chunk counts, vector status)
ssh bruba "openclaw memory status --verbose"

# Reindex memory files
ssh bruba "openclaw memory index"

# Search memory
ssh bruba "openclaw memory search 'query terms'"
```

---

## 6. Configuration

### File Locations

| File | Purpose |
|------|---------|
| `~/.openclaw/openclaw.json` | Main config (agents, tools, channels) |
| `~/.openclaw/exec-approvals.json` | Exec command allowlist |
| `~/.openclaw/.env` | API keys (ANTHROPIC_API_KEY) |

### Viewing Config

```bash
# View specific config sections
ssh bruba "openclaw config get agents"
ssh bruba "openclaw config get tools"
```

### Diagnostic Commands

Quick health checks:

```bash
# Quick gateway health (compact)
ssh bruba "openclaw gateway health"

# Security audit summary only
ssh bruba "openclaw security audit --json" | jq '.summary'

# Full diagnostics
ssh bruba "openclaw doctor"
ssh bruba "openclaw security audit"
ssh bruba "openclaw status"
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
nano ~/.openclaw/openclaw.json
exit

# Option 2: Use openclaw config commands
ssh bruba 'openclaw config set tools.exec.security allowlist'
```

**After any config change:** `ssh bruba "openclaw daemon restart"`

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
│  agents/*/exports/ ─────── push ─────────► ~/agents/*/memory/               │
│  (content to sync)                         (searchable via memory_search)   │
│                                                                             │
│  components/*/tools/ ───── push ─────────► ~/clawd/tools/                   │
│  (component tools)                         (executable scripts)             │
│                                                                             │
│  agents/*/mirror/ ◄─────── mirror ──────── ~/agents/*/                      │
│  (local backup)                            MEMORY.md, journals, etc.        │
│                                                                             │
│  agents/*/sessions/ ◄───── pull ────────── ~/.openclaw/agents/*/sessions/*.jsonl │
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
ssh bruba "openclaw memory index"
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
agents/*/  CONFIG    reference/  agents/*/ bot
intake/    blocks    transcripts/ exports/ memory
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
./tools/pull-sessions.sh              # Pull JSONL → agents/*/intake/*.md
/convert agents/{agent}/intake/<file>.md  # AI-assisted: add CONFIG block
/intake                               # Canonicalize → reference/transcripts/
/export                               # Filter → agents/*/exports/
./tools/push.sh                       # Sync to bot memory
```

**Reference documents (non-transcripts):**

Place markdown files with YAML frontmatter in `reference/refdocs/`:
```yaml
---
title: My Guide
type: refdoc
---
```

These are included in `/export` and synced alongside transcripts.

See [Pipeline Documentation](pipeline.md) for full details.

### Sync Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Push succeeds but memory search empty | Index stale | `ssh bruba "openclaw memory index"` |
| Pull finds no new sessions | All sessions already pulled | Check `agents/{agent}/sessions/.pulled` |
| Mirror missing files | Bot hasn't created them | Check bot's `~/clawd/` directly |

**State tracking:** Session UUIDs tracked in `agents/{agent}/sessions/.pulled`. Closed sessions are immutable, so no need to re-pull.

---

## 8. Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| Commands hang/timeout | Daemon not running | `/launch` |
| Config changes not taking effect | Daemon needs restart | `/restart` |
| Exec command denied | Not in allowlist | Add to `exec-approvals.json`, restart |
| Memory search empty | Index stale | `ssh bruba "openclaw memory index"` |
| "Cannot connect" | SSH config issue | Check `~/.ssh/config` |

### Checking Logs

```bash
# View recent daemon logs
ssh bruba "tail -50 /tmp/openclaw/openclaw-$(date +%Y-%m-%d).log"

# Follow logs in real-time
ssh bruba "tail -f /tmp/openclaw/openclaw-$(date +%Y-%m-%d).log"
```

---

## 9. Operator Interaction

All bot operations use `ssh bruba "..."`. Some operations require user intervention:

### Interactive Commands

Some commands require interactive prompts — run them directly via SSH session:

```bash
ssh bruba
# Run interactive command
openclaw onboard
exit
```

### Sudo Commands

Config protection may require sudo. Run from operator machine with sudo access:

```bash
sudo chown root:staff /Users/bruba/.openclaw/openclaw.json
```

### Examples Requiring User Action

- `pnpm approve-builds` — Interactive package selection
- `chown root:staff` — Re-protecting config files after updates
- Starting Docker Desktop — GUI application

---

## 10. Updating OpenClaw

### From Source (Recommended)

```bash
ssh bruba
cd ~/src/openclaw
git fetch --tags
git tag -l | grep 2026 | tail -5  # See recent releases
git checkout v2026.x.y            # Checkout latest
pnpm install
pnpm build
exit

# Restart daemon
ssh bruba "openclaw daemon restart"
```

### Verify Update

```bash
ssh bruba "openclaw --version"
ssh bruba "openclaw status"
```

---

## 11. Bot Transport

The `./tools/bot` wrapper supports multiple transports for running commands as the bot user:

| Transport | `BOT_TRANSPORT=` | Use Case |
|-----------|------------------|----------|
| **sudo** | `sudo` | Same machine, different user (fastest) |
| **Tailscale SSH** | `tailscale-ssh` | Remote via Tailscale's SSH server |
| **SSH** | `ssh` | Remote via regular SSH with multiplexing (default) |

**Configuration in config.yaml:**
```yaml
transport: sudo  # Options: sudo, tailscale-ssh, ssh
```

Override per-command: `BOT_TRANSPORT=ssh ./tools/bot ls ~/agents`

**For same-machine setups** (bruba is a local account):
1. Add sudoers entry: `dadbook ALL=(bruba) NOPASSWD: ALL` in `/etc/sudoers.d/bruba-admin`
2. Set `transport: sudo` in config.yaml

Scripts using `lib.sh` (mirror.sh, push.sh, etc.) automatically use the configured transport via `bot_exec()`.

---

## 12. Signal-CLI Installation

**Use the brew version, not OpenClaw's bundled version.**

OpenClaw may auto-download signal-cli to `~/.openclaw/tools/signal-cli/`. On macOS ARM64, this can download the wrong architecture, causing "exec format error" or "spawn ENOEXEC" errors.

```bash
brew install signal-cli
jq '.channels.signal.cliPath = "/opt/homebrew/bin/signal-cli"' \
  ~/.openclaw/openclaw.json > /tmp/oc.json && mv /tmp/oc.json ~/.openclaw/openclaw.json
openclaw gateway restart
openclaw doctor | grep Signal
```

**Signal data location:** Account credentials are in `~/.local/share/signal-cli/`, not the installation directory.

---

## 13. Prerequisites

**remindctl** — CLI for Apple Reminders
```bash
brew install steipete/formulae/remindctl
remindctl authorize  # Grant permissions
remindctl status     # Verify
```

**icalBuddy** — CLI for macOS Calendar
```bash
brew install ical-buddy
icalBuddy eventsToday  # Verify
```

---

## 14. New Agent Setup

### Directory Structure

```
/Users/bruba/
├── agents/
│   ├── bruba-main/
│   │   ├── IDENTITY.md, SOUL.md, TOOLS.md, AGENTS.md
│   │   ├── workspace/
│   │   ├── memory/
│   │   └── tools/          # Scripts (read-only post-migration)
│   ├── bruba-manager/
│   │   ├── IDENTITY.md, SOUL.md, TOOLS.md, HEARTBEAT.md
│   │   ├── inbox/          # Cron job outputs
│   │   ├── state/          # Persistent tracking
│   │   └── results/
│   └── bruba-web/
│       ├── AGENTS.md
│       └── results/
└── .openclaw/
    ├── openclaw.json
    ├── exec-approvals.json
    ├── cron/jobs.json
    └── agents/*/sessions/
```

### First-Time Directory Setup

```bash
# Create Manager workspace
mkdir -p /Users/bruba/agents/bruba-manager/{inbox,state,results}
echo '{"reminders": {}, "lastUpdated": null}' > /Users/bruba/agents/bruba-manager/state/nag-history.json
echo '{"projects": {}, "lastUpdated": null}' > /Users/bruba/agents/bruba-manager/state/staleness-history.json
echo '{"tasks": [], "lastUpdated": null}' > /Users/bruba/agents/bruba-manager/state/pending-tasks.json

# Create bruba-web workspace
mkdir -p /Users/bruba/agents/bruba-web/results
```

### Auth Profile Setup

Each agent needs `auth-profiles.json` in its agentDir:

```bash
mkdir -p ~/.clawdbot/agents/<new-agent-id>
cp ~/.clawdbot/agents/bruba-main/auth-profiles.json \
   ~/.clawdbot/agents/<new-agent-id>/
```

**Important:** Auth profiles live in `~/.clawdbot/agents/`, NOT `~/.openclaw/agents/`.

### Priming New Sessions

New agents have no session until their first message:

```bash
openclaw agent --agent <agent-id> --message "Test initialization. Confirm you're operational."
```

Some features (like tool availability reporting) only work after a session exists.

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 2.0.0 | 2026-02-06 | Merged from masterdoc: Signal rate limits, health checks, log locations, transport, signal-cli install, prerequisites, agent setup, auth, priming |
| 1.0.0 | 2026-01-30 | Initial version |
