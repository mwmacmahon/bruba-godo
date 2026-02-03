---
version: 1.3.0
updated: 2026-02-02
type: refdoc
project: planning
tags: [bruba, filesystem, data-flow, bruba-godo, operations, guru]
---

# Bruba Filesystem & Data Flow Guide

Complete reference for file locations, ownership, and data flow between operator and bot machines.

---

## Part 1: Two Machines, Two Purposes

| Machine | Role | Key Path | SSH Access |
|---------|------|----------|------------|
| **Operator** (your Mac) | Development, prompt authoring, content pipeline | `~/bruba-godo/` | N/A |
| **Bot** (dadmini) | Runtime, agent execution, state | `/Users/bruba/` | `./tools/bot` |

**Principle:** Operator is source of truth for prompts/config. Bot is source of truth for runtime state.

---

## Part 2: Operator Side — bruba-godo

```
~/bruba-godo/
├── config.yaml                 # Master config: agents, exports, paths
├── config.yaml.example         # Template for new setups
├── CLAUDE.md                   # Claude Code workspace instructions
│
├── templates/
│   ├── prompts/
│   │   ├── AGENTS.md           # Base for bruba-main (not used directly)
│   │   ├── TOOLS.md            # Base tools template
│   │   ├── HEARTBEAT.md        # Base heartbeat template
│   │   ├── IDENTITY.md         # Identity template (pushed directly)
│   │   ├── SOUL.md             # Soul template
│   │   ├── USER.md             # User context template
│   │   ├── MEMORY.md           # Long-term memory template
│   │   ├── BOOTSTRAP.md        # Initial setup template
│   │   ├── sections/           # AGENTS.md section fragments
│   │   │   ├── header.md
│   │   │   ├── first-run.md
│   │   │   ├── safety.md
│   │   │   ├── tools.md
│   │   │   ├── external-internal.md
│   │   │   └── make-it-yours.md
│   │   ├── manager/            # Manager-specific templates
│   │   │   ├── AGENTS.md
│   │   │   ├── TOOLS.md
│   │   │   ├── HEARTBEAT.md
│   │   │   ├── IDENTITY.md
│   │   │   └── SOUL.md
│   │   ├── web/                # Web agent templates
│   │   │   └── AGENTS.md
│   │   └── helper/
│   │       └── README.md       # Documentation only (helpers are ephemeral)
│   ├── config/
│   │   ├── clawdbot.json.template
│   │   └── exec-approvals.json.template
│   └── tools/
│       └── example-tool.sh
│
├── components/                  # Reusable capability modules
│   ├── continuity/
│   │   ├── README.md
│   │   └── prompts/AGENTS.snippet.md
│   ├── memory/
│   ├── distill/                # Full pipeline with setup, config, lib
│   ├── http-api/
│   ├── web-search/             # ⚠️ NEEDS UPDATE per v3.2
│   ├── voice/
│   ├── reminders/
│   ├── signal/
│   ├── signal-media-filter/
│   ├── workspace/
│   ├── repo-reference/
│   ├── group-chats/
│   ├── cc-packets/
│   ├── heartbeats/
│   └── session/
│
├── reference/                   # Canonical content (source of truth)
│   ├── transcripts/            # Canonicalized conversation transcripts
│   │   └── YYYY-MM-DD-slug.md
│   └── refdocs/                # Reference documents
│       └── descriptive-name.md
│
├── intake/                      # Pre-canonicalized files awaiting CONFIG
│   ├── {uuid}.md               # Raw converted sessions
│   └── processed/              # Moved here after canonicalization
│
├── sessions/                    # Raw JSONL from bot (~81 files)
│   ├── {uuid}.jsonl
│   └── .pulled                 # Tracks which sessions have been pulled
│
├── exports/                     # Filtered content for sync
│   ├── bot/                    # For bot memory (may be empty)
│   │   └── bruba-main/
│   │       └── core-prompts/
│   └── claude/                 # For Claude Projects
│       ├── transcripts/
│       ├── refdocs/
│       ├── docs/
│       ├── summaries/
│       └── cc_logs/
│
├── mirror/                      # Bot state backup (for conflict detection)
│   ├── bruba-main/
│   │   ├── prompts/            # Current bot prompts
│   │   ├── memory/             # Date-prefixed files only
│   │   ├── config/             # openclaw.json, exec-approvals.json
│   │   ├── tools/              # Bot scripts
│   │   └── state/              # (if applicable)
│   └── bruba-manager/
│       ├── prompts/
│       └── state/
│
├── cronjobs/                    # Cron job definitions
│   ├── pre-reset-continuity.yaml    # Main's daily continuation packet
│   ├── guru-pre-reset-continuity.yaml  # Guru's daily continuation packet
│   ├── reminder-check.yaml
│   ├── staleness-check.yaml
│   ├── calendar-prep.yaml
│   └── morning-briefing.yaml
│
├── tools/                       # Shell scripts
│   ├── assemble-prompts.sh     # Templates + components → exports
│   ├── push.sh                 # Sync exports → bot
│   ├── mirror.sh               # Bot → mirror (conflict detection)
│   ├── pull-sessions.sh        # Bot JSONL → sessions/
│   ├── bot                     # SSH wrapper for bot commands
│   ├── lib.sh                  # Shared functions
│   ├── update-allowlist.sh     # Sync exec-approvals.json
│   ├── update-agent-tools.sh   # Sync tool permissions
│   └── detect-conflicts.sh     # Compare exports vs mirror
│
├── tests/
│   └── test-prompt-assembly.sh
│
├── docs/
│   ├── architecture-masterdoc.md
│   ├── bruba-multi-agent-spec.md  # ⚠️ STALE - use v3.2
│   ├── bruba-cron-job-system.md
│   └── cc_logs/
│
├── logs/                        # Script execution logs
│
└── .claude/
    ├── settings.json
    └── commands/                # Custom slash commands
```

---

## Part 3: Bot Side — /Users/bruba

```
/Users/bruba/
├── agents/
│   ├── bruba-main/
│   │   ├── AGENTS.md           # Assembled prompt (from bruba-godo)
│   │   ├── TOOLS.md            # Assembled prompt
│   │   ├── HEARTBEAT.md        # Assembled prompt
│   │   ├── IDENTITY.md         # Pushed directly (not assembled)
│   │   ├── SOUL.md             # Bot-managed
│   │   ├── USER.md             # Bot-managed (user context)
│   │   ├── MEMORY.md           # Bot-managed (long-term memory)
│   │   ├── BOOTSTRAP.md        # Initial setup (pushed)
│   │   │
│   │   ├── memory/             # Content files (~154 items, FLAT)
│   │   │   ├── archive/        # Continuation packets
│   │   │   ├── Claude Code Log - *.md
│   │   │   ├── Transcript - *.md
│   │   │   ├── Refdoc - *.md
│   │   │   ├── Doc - *.md
│   │   │   ├── Summary - *.md
│   │   │   └── YYYY-MM-DD-*.md  # Daily logs
│   │   │
│   │   ├── tools/              # Scripts (read-only post-migration)
│   │   │   ├── whisper-clean.sh
│   │   │   ├── tts.sh
│   │   │   ├── web-search.sh
│   │   │   ├── voice-status.sh
│   │   │   ├── cleanup-reminders.sh
│   │   │   ├── ensure-web-reader.sh
│   │   │   └── helpers/
│   │   │       └── cleanup-reminders.py
│   │   │
│   │   ├── workspace/          # Working files
│   │   ├── artifacts/          # Generated artifacts
│   │   ├── canvas/             # Canvas outputs
│   │   ├── output/             # Script outputs
│   │   ├── logs/               # Agent logs
│   │   ├── media/              # Local media files
│   │   └── intake/             # Bot-side intake (if used)
│   │
│   ├── bruba-manager/
│   │   ├── AGENTS.md           # Assembled
│   │   ├── TOOLS.md            # Assembled
│   │   ├── HEARTBEAT.md        # Assembled
│   │   ├── IDENTITY.md         # Pushed directly
│   │   ├── SOUL.md             # Bot-managed
│   │   ├── USER.md             # Bot-managed
│   │   │
│   │   ├── inbox/              # Cron job outputs (ephemeral)
│   │   │   ├── reminder-check.json
│   │   │   ├── staleness.json
│   │   │   └── calendar-prep.json
│   │   │
│   │   ├── state/              # Persistent tracking
│   │   │   └── pending-tasks.json
│   │   │
│   │   ├── results/            # Research outputs (reads from bruba-web)
│   │   │   └── *.txt
│   │   │
│   │   └── memory/
│   │       └── siri-log.md
│   │
│   ├── bruba-web/
│   │   ├── AGENTS.md           # Security instructions only
│   │   └── results/            # Research outputs (bruba-web writes here)
│   │       └── YYYY-MM-DD-topic.md
│   │
│   ├── bruba-guru/             # Technical specialist agent
│   │   ├── AGENTS.md           # Assembled prompt
│   │   ├── TOOLS.md            # Assembled prompt
│   │   ├── IDENTITY.md         # Pushed directly
│   │   │
│   │   ├── workspace/          # Working files, analysis artifacts
│   │   ├── memory/             # Persistent notes
│   │   └── results/            # Technical analysis outputs
│   │
│   └── bruba-shared/           # Shared resources (all agents)
│       ├── repo/               # bruba-godo clone (read-only reference)
│       ├── packets/            # Work handoff packets (CC ↔ Bruba, Guru ↔ Main)
│       │   └── archive/        # Completed packets
│       └── context/            # Shared context files
│
└── .openclaw/
    ├── openclaw.json           # Agent configs, tool policies
    ├── exec-approvals.json     # Allowlisted commands
    │
    ├── agents/
    │   ├── bruba-main/
    │   │   └── sessions/       # Session transcripts (~90 JSONL files)
    │   ├── bruba-guru/
    │   │   └── sessions/
    │   ├── bruba-manager/
    │   │   └── sessions/
    │   ├── bruba-web/
    │   │   └── sessions/
    │   └── main/               # Legacy (can be cleaned up)
    │
    ├── sandboxes/              # Runtime copies + installed skills
    │   └── agent-main-main-{hash}/
    │       ├── IDENTITY.md, SOUL.md, etc.
    │       └── skills/
    │           ├── nano-pdf/
    │           ├── himalaya/
    │           ├── openai-whisper/
    │           ├── sherpa-onnx-tts/
    │           └── [~17 more skills]
    │
    └── media/
        ├── inbound/            # Voice messages in (~128 items)
        └── outbound/           # Voice messages out (~56 items)
```

---

## Part 4: Data Flow Pipelines

### Pipeline 1: Prompt Assembly

```
config.yaml (agents.{agent}.{prompt}_sections)
       │
       ▼
┌─────────────────────────────────────────────────────────────┐
│                   assemble-prompts.sh                        │
│  Resolves each section entry to content:                     │
│    base         → templates/prompts/{NAME}.md                │
│    manager-base → templates/prompts/manager/{NAME}.md        │
│    web-base     → templates/prompts/web/{NAME}.md            │
│    bot:name     → mirror/{agent}/prompts/ (BOT-MANAGED)      │
│    component    → components/{name}/prompts/{NAME}.snippet.md│
│    section      → templates/prompts/sections/{name}.md       │
└─────────────────────────────────────────────────────────────┘
       │
       ▼
exports/bot/{agent}/core-prompts/{NAME}.md
       │
       ▼
┌─────────────────────────────────────────────────────────────┐
│                        push.sh                               │
│  rsync to: {SSH_HOST}:{AGENT_WORKSPACE}/                     │
└─────────────────────────────────────────────────────────────┘
       │
       ▼
/Users/bruba/agents/{agent}/{NAME}.md  (DEPLOYED)
```

### Pipeline 2: Content (Transcripts)

```
Bot Sessions (remote)
/Users/bruba/.openclaw/agents/bruba-main/sessions/*.jsonl
       │
       ▼
┌─────────────────────────────────────────────────────────────┐
│                  /pull (pull-sessions.sh)                    │
│  1. SCP closed sessions to sessions/*.jsonl                  │
│  2. Convert via distill CLI → intake/*.md                    │
│  3. Track in sessions/.pulled                                │
└─────────────────────────────────────────────────────────────┘
       │
       ▼
intake/{uuid}.md (delimited markdown, no CONFIG)
       │
       ▼
┌─────────────────────────────────────────────────────────────┐
│            /convert (AI-assisted) or /intake --auto-config   │
│  Adds CONFIG block:                                          │
│    title, slug, date, source, tags, sections_remove          │
└─────────────────────────────────────────────────────────────┘
       │
       ▼
intake/{uuid}.md (with CONFIG block)
       │
       ▼
┌─────────────────────────────────────────────────────────────┐
│                    /intake (canonicalize)                    │
│  - Split large files (>60K chars)                            │
│  - Parse CONFIG → YAML frontmatter                           │
│  - Apply transcription corrections                           │
│  - Rename to {slug}.md                                       │
│  - Move original to intake/processed/                        │
└─────────────────────────────────────────────────────────────┘
       │
       ▼
reference/transcripts/{slug}.md (canonical)
       │
       ▼
┌─────────────────────────────────────────────────────────────┐
│                        /export                               │
│  - Filter by include/exclude rules                           │
│  - Apply sections_remove                                     │
│  - Apply redaction                                           │
│  - Add type prefix (Transcript -, Doc -, etc.)               │
└─────────────────────────────────────────────────────────────┘
       │
       ▼
exports/bot/bruba-main/transcripts/Transcript - {slug}.md
       │
       ▼
┌─────────────────────────────────────────────────────────────┐
│                        /push                                 │
│  rsync FLAT to {WORKSPACE}/memory/                           │
└─────────────────────────────────────────────────────────────┘
       │
       ▼
/Users/bruba/agents/bruba-main/memory/Transcript - {slug}.md
```

### Pipeline 3: Mirror (Conflict Detection)

```
Bot Workspace (source of truth for bot-managed files)
/Users/bruba/agents/{agent}/
       │
       ▼
┌─────────────────────────────────────────────────────────────┐
│                    /mirror (mirror.sh)                       │
│  Pulls:                                                      │
│    - *.md at workspace root (prompts)                        │
│    - memory/YYYY-MM-DD*.md (date-prefixed only)              │
│    - config/*.json (tokens redacted)                         │
│    - tools/*.sh                                              │
│    - state/*.json (manager only)                             │
└─────────────────────────────────────────────────────────────┘
       │
       ▼
mirror/{agent}/
  prompts/    - Current bot prompts (for conflict detection)
  memory/     - Bot's memory files (subset)
  config/     - openclaw.json, exec-approvals.json
  tools/      - Bot's tool scripts
  state/      - Manager state files
```

---

## Part 5: File Ownership Matrix

### Prompt Files

| File | Source | Transformation | Sync | Bot Can Edit? |
|------|--------|----------------|------|---------------|
| `AGENTS.md` | templates + components | Assembled | push → bot | ❌ (overwritten) |
| `TOOLS.md` | templates + components | Assembled | push → bot | ❌ (overwritten) |
| `HEARTBEAT.md` | templates + components | Assembled | push → bot | ❌ (overwritten) |
| `IDENTITY.md` | templates/prompts/ | Direct push | push → bot | ⚠️ (preserved via BOT-MANAGED) |
| `SOUL.md` | Bot creates/edits | None | ← mirror | ✅ Bot-managed |
| `USER.md` | Bot creates/edits | None | ← mirror | ✅ Bot-managed |
| `MEMORY.md` | Bot creates/edits | None | ← mirror | ✅ Bot-managed |
| `BOOTSTRAP.md` | templates/prompts/ | Direct push | push → bot | ❌ |

### Content Files

| Location | Source | Sync Direction | Notes |
|----------|--------|----------------|-------|
| `memory/*.md` | Export pipeline | push → bot | FLAT structure with prefix naming |
| `state/*.json` | Bot runtime | ← mirror | Never pushed, bot-managed |
| `inbox/*.json` | Cron jobs | Never synced | Ephemeral, deleted after processing |
| `results/*.md` | bruba-web | Never synced | Read by Manager heartbeat |

### Config Files

| File | Source | Sync Direction | Notes |
|------|--------|----------------|-------|
| `openclaw.json` | update-agent-tools.sh | push → bot | Tool permissions |
| `exec-approvals.json` | update-allowlist.sh | push → bot | Command allowlist |

---

## Part 6: Section Type Reference

| Section Type | Config Entry | Source Location | Resolution |
|--------------|--------------|-----------------|------------|
| `base` | `base` | `templates/prompts/{NAME}.md` | Full file copy |
| `manager-base` | `manager-base` | `templates/prompts/manager/{NAME}.md` | Full file for manager |
| `web-base` | `web-base` | `templates/prompts/web/{NAME}.md` | Full file for web agent |
| `component` | `component-name` | `components/{name}/prompts/{NAME}.snippet.md` | Wrapped in `<!-- COMPONENT: name -->` |
| `section` | `section-name` | `templates/prompts/sections/{name}.md` | Wrapped in `<!-- SECTION: name -->` |
| `bot-managed` | `bot:section-name` | `mirror/{agent}/prompts/{NAME}.md` | Extracted from `<!-- BOT-MANAGED: name -->` |

### Resolution Priority (in assemble-prompts.sh)

1. `base` → check `templates/prompts/{NAME}.md`
2. `manager-base` → check `templates/prompts/manager/{NAME}.md`
3. `web-base` → check `templates/prompts/web/{NAME}.md`
4. `bot:*` → extract from mirror's BOT-MANAGED block
5. Component → check `components/{entry}/prompts/{NAME}.snippet.md`
6. Section → check `templates/prompts/sections/{entry}.md`
7. Not found → log "missing" warning

---

## Part 7: Config → Assembly Mapping

### bruba-main AGENTS.md

```yaml
agents_sections:
  - header              # → templates/prompts/sections/header.md
  - http-api            # → components/http-api/prompts/AGENTS.snippet.md
  - first-run           # → templates/prompts/sections/first-run.md
  - session             # → components/session/prompts/AGENTS.snippet.md
  - continuity          # → components/continuity/prompts/AGENTS.snippet.md
  - memory              # → components/memory/prompts/AGENTS.snippet.md
  - distill             # → components/distill/prompts/AGENTS.snippet.md
  - safety              # → templates/prompts/sections/safety.md
  - bot:exec-approvals  # → mirror/bruba-main/prompts/AGENTS.md (BOT-MANAGED)
  - cc-packets          # → components/cc-packets/prompts/AGENTS.snippet.md
  - external-internal   # → templates/prompts/sections/external-internal.md
  - workspace           # → components/workspace/prompts/AGENTS.snippet.md
  - repo-reference      # → components/repo-reference/prompts/AGENTS.snippet.md
  - group-chats         # → components/group-chats/prompts/AGENTS.snippet.md
  - tools               # → templates/prompts/sections/tools.md
  - web-search          # → components/web-search/prompts/AGENTS.snippet.md
  - reminders           # → components/reminders/prompts/AGENTS.snippet.md
  - voice               # → components/voice/prompts/AGENTS.snippet.md
  - signal-media-filter # → components/signal-media-filter/prompts/AGENTS.snippet.md
  - signal              # → components/signal/prompts/AGENTS.snippet.md
```

### bruba-main TOOLS.md

```yaml
tools_sections:
  - base                # → templates/prompts/TOOLS.md
  - reminders           # → components/reminders/prompts/TOOLS.snippet.md
```

### bruba-manager

```yaml
agents_sections:
  - manager-base        # → templates/prompts/manager/AGENTS.md
tools_sections:
  - manager-base        # → templates/prompts/manager/TOOLS.md
heartbeat_sections:
  - manager-base        # → templates/prompts/manager/HEARTBEAT.md
```

### bruba-web

```yaml
agents_sections:
  - web-base            # → templates/prompts/web/AGENTS.md
```

---

## Part 8: Message Paths (File-Based Communication)

### Cron → Manager (via inbox/)

```
Cron job runs
    │
    ▼
inbox/reminder-check.json (written)
    │
    ▼
Manager heartbeat
    │
    ▼
Read → Process → Deliver to Signal
    │
    ▼
Delete inbox/reminder-check.json
```

### Manager → bruba-web → Manager (via results/)

```
Manager sends research request
    │
    ├── sessions_send to bruba-web
    │
    └── Writes state/pending-tasks.json
            {
              "tasks": [{
                "id": "task-abc",
                "expectedFile": "/Users/bruba/agents/bruba-web/results/..."
              }]
            }

bruba-web researches
    │
    ▼
Writes /Users/bruba/agents/bruba-web/results/YYYY-MM-DD-topic.md

Manager heartbeat (later)
    │
    ├── Reads state/pending-tasks.json
    │
    ├── Checks if expectedFile exists
    │
    ├── Reads result, forwards to Signal
    │
    └── Updates pending-tasks.json (marks complete)
```

### State Files

| File | Location | Purpose | Updated By |
|------|----------|---------|------------|
| `nag-history.json` | bruba-manager/state/ | Reminder escalation | Manager heartbeat |
| `staleness-history.json` | bruba-manager/state/ | Project warnings | Manager heartbeat |
| `pending-tasks.json` | bruba-manager/state/ | Async research tracking | Manager |

---

## Part 9: Memory Structure

### Current State (FLAT)

Bot memory uses **flat structure with prefix naming**:

```
/Users/bruba/agents/bruba-main/memory/
├── Claude Code Log - 2026-02-02-something.md
├── Transcript - 2026-01-31-descriptive-slug.md
├── Refdoc - Core - Profile.md
├── Doc - README.md
├── Summary - 2026-01-27-topic.md
├── 2026-02-02-daily-notes.md
└── archive/
    └── continuation-2026-02-02.md
```

### Naming Convention

| Prefix | Content Type |
|--------|--------------|
| `Claude Code Log -` | CC session exports |
| `Transcript -` | Conversation transcripts |
| `Refdoc -` | Reference documents |
| `Doc -` | General documents |
| `Summary -` | Conversation summaries |
| `YYYY-MM-DD-` | Daily logs |

### Why Flat?

- OpenClaw `memory_search` indexes the memory directory
- Flat structure ensures all files are indexed
- Nested directories may not be fully indexed (needs verification)
- Prefix naming provides organization without hierarchy

---

## Part 10: Quick Reference Commands

### Full Sync Pipeline

```bash
# 1. Mirror bot state (conflict detection)
./tools/mirror.sh

# 2. Assemble prompts
./tools/assemble-prompts.sh

# 3. Push to bot
./tools/push.sh

# Or all at once:
/sync   # Runs: mirror → assemble → push
```

### Content Pipeline

```bash
/pull       # Bot JSONL → sessions/ → intake/
/convert    # Add CONFIG blocks (AI-assisted)
/intake     # Canonicalize → reference/
/export     # Filter → exports/
/push       # Sync to bot
```

### Individual Operations

```bash
# Check for conflicts
./tools/detect-conflicts.sh

# Update tool permissions
./tools/update-agent-tools.sh

# Update exec allowlist
./tools/update-allowlist.sh

# SSH to bot
./tools/bot 'command here'
```

---

## Part 11: Known Issues & Discrepancies

### Stale Files to Fix

| Issue | Location | Action Needed |
|-------|----------|---------------|
| `active-helpers.json` in mirror | mirror/bruba-manager/state/ | Should be `pending-tasks.json` |
| `web-search` component | components/web-search/ | Update for v3.2 (bruba-web pattern) |
| `exports/bot/` empty | exports/bot/ | Verify export pipeline |

### Directory Naming

| Documentation Says | Reality | Notes |
|--------------------|---------|-------|
| `canonical/` | `reference/` | Reference is correct |
| `memory/prompts/` | Memory is flat | No subdirectories in memory |
| Prompts in `prompts/` subdir | Prompts at root | Bot has prompts at workspace root |

---

## Part 12: Node Host + Docker Sandboxing (PLANNED)

**Status:** Planning — not yet implemented. Details may change during migration.

### Why This Migration

**Current security gap:** Bruba can theoretically edit `~/.openclaw/exec-approvals.json` to self-escalate permissions. The allowlist lives in the same filesystem the agent has write access to.

**Solution:** Docker container isolation + node host for exec:
- Agents run in Docker container (can't access host filesystem)
- Exec commands run via node host process (outside container)
- Allowlist stays on host, out of agent's reach

### Mount Mapping

| Host Path | Container Path | Access | Purpose |
|-----------|----------------|--------|---------|
| `/Users/bruba/agents/bruba-main/workspace/` | `/workspace` | rw | Working files |
| `/Users/bruba/agents/bruba-main/memory/` | `/memory` | rw | PKM docs, transcripts |
| `/Users/bruba/agents/bruba-main/tools/` | `/tools` | **ro** | Scripts (CC edits, agent reads) |
| `/Users/bruba/.openclaw/media/` | `/media` | rw | Voice messages in/out |
| `/Users/bruba/agents/bruba-manager/inbox/` | `/inbox` | rw | Cron outputs |
| `/Users/bruba/agents/bruba-manager/state/` | `/state` | rw | Persistent tracking |
| `/Users/bruba/agents/bruba-manager/results/` | `/results` | rw | Manager reads bruba-web output |
| `/Users/bruba/agents/bruba-web/results/` | `/results` | rw | bruba-web writes research |

### Deliberately NOT Mounted (Security Boundary)

| Host Path | Why Excluded |
|-----------|--------------|
| `~/.openclaw/exec-approvals.json` | Prevents self-escalation |
| `~/.openclaw/openclaw.json` | Agent config shouldn't be agent-writable |
| `/Users/bruba/agents/*/tools/` | Read-only mount, not excluded but protected |

### Path References in Prompts

**Important:** After migration, prompts and agent code should reference **container paths**, not host paths.

| Reference | Pre-Docker | Post-Docker |
|-----------|------------|-------------|
| Memory files | `/Users/bruba/agents/bruba-main/memory/` | `/memory/` |
| Tool scripts | `/Users/bruba/agents/bruba-main/tools/` | `/tools/` |
| Research results | `/Users/bruba/agents/bruba-web/results/` | `/results/` |
| pending-tasks.json | Full host path in `expectedFile` | Container path |

**bruba-godo impact:** `push.sh` continues pushing to host paths — Docker bind mounts handle the translation automatically. No changes needed to push scripts.

### Per-Agent Container Strategy

**Option A: Shared container (simpler)**
```
┌─────────────────────────────────────┐
│         Docker Container            │
│  ┌─────────┐ ┌─────────┐ ┌───────┐ │
│  │  Main   │ │ Manager │ │  Web  │ │
│  └─────────┘ └─────────┘ └───────┘ │
│         network: bridge             │
└─────────────────────────────────────┘
```
- All agents share one container
- bruba-web needs bridge network for internet → all get it
- Simpler to manage

**Option B: Separate containers (better isolation)**
```
┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│  Main Container  │  │ Manager Container│  │  Web Container   │
│  network: none   │  │  network: none   │  │ network: bridge  │
└──────────────────┘  └──────────────────┘  └──────────────────┘
```
- Main/Manager get `network: none` (use node host for exec, no direct internet)
- bruba-web gets `network: bridge` (needs internet for web_search)
- Better security isolation
- More complex orchestration

**Likely choice:** Option A initially, Option B if security review requires it.

### bruba-godo Sync Behavior (Unchanged)

```
bruba-godo (operator)
       │
       │ push.sh (SSH + rsync)
       ▼
Host filesystem (/Users/bruba/agents/...)
       │
       │ Docker bind mount
       ▼
Container filesystem (/workspace, /memory, etc.)
```

- `push.sh` pushes to host paths as before
- Bind mounts make files visible inside container
- No changes needed to bruba-godo tooling

### Session Storage (Open Question)

**Question:** Where does `.openclaw/agents/*/sessions/` live?

| Option | Pros | Cons |
|--------|------|------|
| Host (mounted) | Persists across container rebuilds, accessible to bruba-godo pull | Agent can see other agents' sessions |
| Container volume | Better isolation | Lost on container rebuild unless volume persists |
| Host (not mounted) | Agent can't access raw sessions | Gateway needs host access |

**Likely:** Host filesystem, mounted read-only or via gateway process that runs on host.

### Node Host Exec Flow

```
Agent requests exec("whisper-clean.sh", args)
       │
       ▼
Container → system.run → Node Host (port 18789)
       │
       ▼
Node Host checks allowlist (on host, not mounted)
       │
       ├── Allowed → Execute on host → Return result
       │
       └── Denied → Return error
```

**Key:** Agent never directly executes commands. Node host is the gatekeeper.

### Trash Pattern for Safe Deletion

With Docker sandbox, we can enable full delete permissions with a safety net:

```
/Users/bruba/agents/bruba-main/
├── workspace/     ← full control (rw)
├── memory/        ← full control (rw)
├── tools/         ← read-only
└── .trash/        ← "deleted" files moved here
    └── 2026-02-02/
        └── old-file.md
```

- Delete = move to `.trash/YYYY-MM-DD/`
- Host cron purges files older than 7 days
- Provides undo without blocking cleanup

### Migration Checklist (Preview)

1. **Pre-migration**
   - [ ] Backup openclaw.json and exec-approvals.json
   - [ ] Document current allowlist entries
   - [ ] Update prompts to use container paths

2. **Docker setup**
   - [ ] Create docker-compose.yml or configure OpenClaw sandbox
   - [ ] Define bind mounts per agent
   - [ ] Test container starts

3. **Node host**
   - [ ] Install node host on dadmini
   - [ ] Transfer allowlist entries
   - [ ] Configure agents to use node host for exec

4. **Verification**
   - [ ] Security boundary tests (agent can't reach allowlist)
   - [ ] Functional tests (voice, web search, file ops)
   - [ ] bruba-godo sync tests (push still works)

### Open Questions

1. **OpenClaw Docker support:** Built-in or docker-compose ourselves?
2. **Node host CLI:** Verify `openclaw node install` syntax against current docs
3. **Tailscale access:** Does gateway bind work inside container?
4. **Multi-agent networking:** Can agents `sessions_send` across containers?

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.3.0 | 2026-02-02 | Moved shared resources to bruba-shared (repo/, packets/) |
| 1.2.1 | 2026-02-02 | Added guru cron job, expanded cronjobs listing |
| 1.2.0 | 2026-02-02 | Added bruba-guru and bruba-shared directories |
| 1.1.0 | 2026-02-02 | Added Part 12: Node Host + Docker Sandboxing |
| 1.0.0 | 2026-02-02 | Initial version from CC investigation |