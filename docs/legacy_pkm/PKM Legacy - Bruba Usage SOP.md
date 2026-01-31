---
type: doc
scope: reference
title: "Bruba Usage SOP"
version: 1.4.0
updated: 2026-01-29
tags: [bruba, clawdbot, operations, reference]
description: "Day-to-day Bruba operations reference"
---
# Bruba Usage SOP

Operational reference for day-to-day Bruba usage. For setup/installation, see `Bruba Setup SOP.md`.

> **Claude Code:** If you discover new useful commands while working with Bruba (from `--help`, testing, or troubleshooting), add them to this document — particularly to § "Diagnostic Commands". This keeps the SOP current with token-efficient alternatives and debugging tools. Version bump accordingly.

Make sure to notify <REDACTED-NAME> about these changes with a loud callout in your output text, but you don't have to ask permission (he validates git diffs).


---

## Quick Reference

| Task | PKM Skill | Direct Command |
|------|-----------|----------------|
| Start daemon after reboot | `/bruba:launch` | `ssh bruba "clawdbot daemon start"` |
| Restart after config changes | `/bruba:restart` | `ssh bruba "clawdbot daemon restart"` |
| Stop daemon | `/bruba:stop` | `ssh bruba "clawdbot daemon stop"` |
| Check status | `/bruba:status` | `ssh bruba "clawdbot status"` |
| Full bidirectional sync | `/bruba:sync` | (runs multiple scripts) |
| Pull sessions + mirror | `/bruba:pull` | `./tools/pull-bruba-sessions.sh && ./tools/mirror-bruba.sh` |
| Push bundle to Bruba | `/bruba:push` | `./tools/sync-to-bruba.sh` |

---

## 1. Daemon Management

The Clawdbot daemon runs as a LaunchAgent on the `bruba` macOS account.

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
- If Bruba becomes unresponsive

---

## 2. Sessions & Agents

### Viewing Sessions

```bash
# Comprehensive status (shows all agents' sessions)
ssh bruba "clawdbot status"

# List sessions (defaults to main agent store)
ssh bruba "clawdbot sessions"

# Only recent sessions (last 2 hours)
ssh bruba "clawdbot sessions --active 120"
```

**Understanding session keys:**
- `agent:bruba-main:main` — Primary Bruba session (Signal)
- `agent:web-reader:main` — Web search subagent
- `agent:main:main` — Orphan from CLI testing (ignore)

### Managing Agents

```bash
# List configured agents
ssh bruba "clawdbot agents list"

# Agent details with bindings
ssh bruba "clawdbot agents list --bindings"
```

**Configured agents:**
| Agent | Purpose | Workspace |
|-------|---------|-----------|
| `bruba-main` | Primary assistant (Signal) | `~/clawd` |
| `web-reader` | Sandboxed web search | `~/bruba-reader` |

---

## 2.5 Session Continuity

Bruba uses a continuation file to preserve context across session boundaries (restarts, crashes, `/reset`).

### How It Works

| Component | Location | Purpose |
|-----------|----------|---------|
| `CONTINUATION.md` | `~/clawd/memory/CONTINUATION.md` | Active continuation state |
| Archive | `~/clawd/memory/archive/continuation-YYYY-MM-DD.md` | Historical continuations |

**Startup sequence:**
1. On session start, Bruba checks if `memory/CONTINUATION.md` exists
2. If found → reads content → archives to `memory/archive/continuation-YYYY-MM-DD.md`
3. Uses continuation context to resume work-in-progress
4. Creates new continuation as needed during session

### Archive vs Delete

Continuations are archived rather than deleted for crash protection:
- If Bruba crashes mid-session, the continuation survives
- Archive provides audit trail of session handoffs
- Cleanup happens via the "delete old crud" pipeline (retention TBD)

### Usage

**Creating continuations (Bruba does this automatically):**
```markdown
# CONTINUATION.md
## What I Was Working On
- Processing intake files from 2026-01-28
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

### Cross-References

- Bruba's operational instructions: `~/clawd/AGENTS.md` (on Bruba side)
- Full session management: § 7 of this document

---

## 2.7 Code Review & Migration

Bruba stages draft tools in `~/.clawdbot/agents/bruba-main/workspace/code/` for review before production deployment.

### Directory Reference

See Bruba's `DIRECTORY-STRUCTURE.md` (mirrored in `reference/bruba-mirror/`) for full workspace layout. Key paths:

| Location | Purpose |
|----------|---------|
| `~/.clawdbot/agents/bruba-main/workspace/code/` | Staged scripts awaiting review |
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

After migrating a tool:

1. Add pattern to `exec-approvals.json`:
   ```bash
   ssh bruba 'cat ~/.clawdbot/exec-approvals.json | jq ".agents[\"bruba-main\"].allowlist += [{\"pattern\": \"/Users/bruba/clawd/tools/new-tool.sh\", \"id\": \"new-tool\"}]" > /tmp/ea.json && mv /tmp/ea.json ~/.clawdbot/exec-approvals.json'
   ```
2. Restart daemon: `ssh bruba 'clawdbot daemon restart'`
3. Verify: `ssh bruba 'clawdbot gateway health'`

### Cleanup

**Important:** Bruba cannot delete files from its own workspace. After migration, clean up from PKM side:

```bash
ssh bruba 'rm ~/.clawdbot/agents/bruba-main/workspace/code/migrated-script.sh'
```

### Related Skill

Use `/bruba:code` to interactively review staged code, find conversation context, and migrate approved tools.

---

## 3. Memory & Search

```bash
# Check memory index status
ssh bruba "clawdbot memory status"

# Reindex memory files
ssh bruba "clawdbot memory index"

# Search memory
ssh bruba "clawdbot memory search 'query terms'"
```

---

## 4. Configuration

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

Quick health checks (token-efficient for Claude Code):

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

Config files are on the bruba account. To edit:

```bash
# Option 1: SSH and edit directly
ssh bruba
nano ~/.clawdbot/clawdbot.json
exit

# Option 2: Edit via local mirror (then copy back)
# Mirror is at: reference/bruba-mirror/shared/config/
```

**After any config change:** `ssh bruba "clawdbot daemon restart"`

---

## 5. PKM Sync Operations

### Sync Skills

| Skill | Direction | What It Does |
|-------|-----------|--------------|
| `/bruba:sync` | Both | Full cycle: pull + push |
| `/bruba:pull` | Bruba → PKM | Pull closed sessions + mirror Bruba's files |
| `/bruba:push` | PKM → Bruba | Push filtered bundle to Bruba's `~/clawd/memory/` |
| `/bruba:status` | Read-only | Show daemon, sessions, sync state |

### Data Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    PKM ←→ BRUBA KNOWLEDGE FLOW                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  PKM (Claude Code)                        Bruba (Clawdbot/Signal)           │
│  ─────────────────                        ───────────────────────           │
│                                                                             │
│  bundles/bruba/  ─────── push ──────────► ~/clawd/memory/                   │
│  (filtered PKM content)                   (searchable via memory_search)    │
│                                                                             │
│  reference/bruba-mirror/ ◄──── mirror ─── ~/clawd/                          │
│  (backup copy)                            MEMORY.md, USER.md, journals      │
│                                                                             │
│  reference/transcripts/ ◄───── import ─── ~/.clawdbot/sessions/*.jsonl      │
│  (processed transcripts)                  (immutable after /reset)          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

| Flow | Direction | Source of Truth | Processing |
|------|-----------|-----------------|------------|
| **Push** | PKM → Bruba | PKM | Bundle, filter, rsync, reindex |
| **Mirror** | Bruba → PKM | Bruba | Copy files, no processing |
| **Import** | Bruba → PKM | PKM (after import) | parse-jsonl → /convert → canonicalize |

### Bundle Filtering

The Bruba bundle is defined in `config/bundles.yaml`:

| Setting | Value | Rationale |
|---------|-------|-----------|
| **Includes** | meta scope only | PKM system docs, prompts, reference material |
| **Excludes** | work, personal, home, sensitive | Privacy boundary — no work or personal content |
| **Redacts** | names, companies, locations, health, financial | Scrub PII before sync |

**Safety:** `/bruba:sync` won't push if bundle is empty or missing (prevents accidental deletion).

### What Gets Mirrored

Mirror script (`./tools/mirror-bruba.sh`) pulls from Bruba:

| Category | Files | Location |
|----------|-------|----------|
| Core files | `AGENTS.md`, `BOOTSTRAP.md`, `HEARTBEAT.md`, `IDENTITY.md`, `MEMORY.md`, `SOUL.md`, `TOOLS.md`, `USER.md` | `~/clawd/` |
| Bruba-created | `_bruba_*.md` (synthesis docs) | `~/clawd/` |
| Journals | `YYYY-MM-DD.md` (dated files only) | `~/clawd/memory/` |

**Note:** Other files in `memory/` are PKM exports and skipped to prevent circular sync.

### Session Import Workflow

Full pipeline for importing Bruba transcripts into PKM:

```
1. PULL                    2. CONVERT                3. INTAKE
──────                     ──────────                ─────────

~/.clawdbot/sessions/      intake/bruba/             reference/transcripts
*.jsonl                    YYYY-MM-DD-xxx.md         transcript-*.md
     │                          │                    summary-*.md
     │ pull-bruba-sessions.sh   │ /convert skill          ▲
     │ (parse-jsonl)            │ (interactive)      convo-processor
     ▼                          ▼                    canonicalize+variants
Delimited markdown         + CONFIG block
=== MESSAGE N | ROLE ===   + Summary
```

**Typical workflow:**
```
1. /bruba:pull                              # Pull closed sessions + mirror
2. /convert intake/bruba/2026-01-26-xxx.md  # Add CONFIG (interactive)
3. /intake                                  # Canonicalize + variants
4. /sync                                    # Full workflow (includes bruba:push)
```

### Manual Script Usage

```bash
# Pull session transcripts to intake/bruba/
./tools/pull-bruba-sessions.sh

# Mirror Bruba's workspace to reference/bruba-mirror/
./tools/mirror-bruba.sh

# Push PKM bundle to Bruba's memory
./tools/sync-to-bruba.sh

# Reindex Bruba's memory after push
ssh bruba "clawdbot memory index"
```

### Sync Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Push succeeds but memory search empty | Index stale | `ssh bruba "clawdbot memory index"` |
| Pull finds no new sessions | All sessions already pulled | Check `~/.pkm-state/pulled-bruba-sessions.txt` |
| Mirror missing files | Bruba hasn't created them | Check Bruba's `~/clawd/` directly |
| Bundle empty | Wrong scope tags | Verify `config/bundles.yaml` selection |
| Circular content appearing | Non-dated file in memory/ | Adjust mirror script patterns |

**State tracking:** Session UUIDs tracked in `~/.pkm-state/pulled-bruba-sessions.txt`. Closed sessions are immutable, so no need to re-pull.

---

## 6. Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| Commands hang/timeout | Daemon not running | `/bruba:launch` |
| Config changes not taking effect | Daemon needs restart | `/bruba:restart` |
| Exec command denied | Not in allowlist | Add to `exec-approvals.json`, restart |
| Web search failing | Docker not running | Start Docker Desktop |
| Signal messages not arriving | Daemon stopped | `/bruba:launch` |
| Memory search empty | Index stale | `ssh bruba "clawdbot memory index"` |
| "Cannot connect to bruba" | SSH config issue | Check `~/.ssh/config` has bruba host |

### Checking Logs

```bash
# View recent daemon logs
ssh bruba "tail -50 /tmp/clawdbot/clawdbot-$(date +%Y-%m-%d).log"

# Follow logs in real-time
ssh bruba "tail -f /tmp/clawdbot/clawdbot-$(date +%Y-%m-%d).log"
```

---

## 7. Claude Code Interaction

All Bruba operations use `ssh bruba "..."` since Clawdbot runs on the bruba account. Some operations require user intervention:

**Interactive commands** — Claude Code can't handle interactive prompts. If a command requires input:
```
Claude: "This requires interactive input. Please run:"
        ssh bruba
        [command with prompts]
        exit
```

**Sudo commands** — Claude Code can't run sudo. If elevated privileges needed:
```
Claude: "Please run this with sudo:"
        sudo chown root:staff /Users/bruba/.clawdbot/clawdbot.json
```

**Examples requiring user action:**
- `pnpm approve-builds` — Interactive package selection
- `chown root:staff` — Re-protecting config files after updates
- Starting Docker Desktop — GUI application

---

## 8. Related Documentation

| Topic | Document |
|-------|----------|
| Full setup from scratch | `Bruba Setup SOP.md` |
| Architecture & philosophy | `Bruba Vision and Roadmap.md` |
| Security model | `Bruba Security Overview.md` |
| Voice integration | `Bruba Voice Integration.md` |
| Config structure | `Bruba Setup SOP.md` § 1.10 |
| Bruba directory layout | `DIRECTORY-STRUCTURE.md` (on Bruba, mirrored in `reference/bruba-mirror/`) |
| Code review skill | `/bruba:code` |
