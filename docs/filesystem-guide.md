---
version: 1.6.0
updated: 2026-02-03
type: refdoc
project: planning
tags: [bruba, filesystem, data-flow, bruba-godo, operations, guru, message-tool]
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
│   │   ├── guru/               # Guru agent templates
│   │   │   ├── AGENTS.md       # Technical specialist instructions
│   │   │   ├── TOOLS.md        # Guru tools (includes message)
│   │   │   └── IDENTITY.md     # Guru identity
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
│   ├── http-api/               # Siri async/sync routing
│   ├── web-search/             # ⚠️ NEEDS UPDATE per v3.2
│   ├── voice/                  # Voice message handling (message tool pattern)
│   ├── reminders/
│   ├── signal/                 # Signal UUID extraction
│   ├── signal-media-filter/
│   ├── workspace/
│   ├── repo-reference/
│   ├── group-chats/
│   ├── cc-packets/
│   ├── heartbeats/
│   ├── session/
│   ├── guru-routing/           # Main→Guru routing logic
│   │   ├── README.md
│   │   └── prompts/AGENTS.snippet.md
│   └── message-tool/           # Direct Signal messaging patterns
│       └── prompts/AGENTS.snippet.md
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
│   ├── bruba-guru/
│   │   ├── prompts/
│   │   └── memory/
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
│   ├── filesystem-guide.md     # This document
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
│   │   ├── TOOLS.md            # Assembled prompt (includes message tool)
│   │   ├── HEARTBEAT.md        # Assembled prompt
│   │   ├── IDENTITY.md         # Pushed directly (not assembled)
│   │   ├── SOUL.md             # Bot-managed
│   │   ├── USER.md             # Bot-managed (user context, includes Signal UUID)
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
│   │   │   ├── whisper-clean.sh    # Voice transcription
│   │   │   ├── tts.sh              # Text-to-speech generation
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
│   ├── bruba-guru/             # Technical specialist agent
│   │   ├── AGENTS.md           # Assembled (includes direct-message pattern)
│   │   ├── TOOLS.md            # Assembled (includes message, TTS, sessions_send)
│   │   ├── IDENTITY.md         # Pushed directly
│   │   │
│   │   ├── workspace/          # Working files, analysis artifacts
│   │   ├── memory/             # Persistent technical notes
│   │   └── results/            # Technical analysis outputs
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
│   └── bruba-shared/           # Shared handoff zone (Main ↔ Guru)
│       ├── packets/            # Work handoff packets
│       └── context/            # Shared context files
│
├── .openclaw/
│   ├── openclaw.json           # Agent configs, tool policies
│   ├── exec-approvals.json     # Allowlisted commands
│   │
│   ├── agents/
│   │   ├── bruba-main/
│   │   │   └── sessions/       # Session transcripts (~90 JSONL files)
│   │   ├── bruba-guru/
│   │   │   └── sessions/
│   │   ├── bruba-manager/
│   │   │   └── sessions/
│   │   ├── bruba-web/
│   │   │   └── sessions/
│   │   └── main/               # Legacy (can be cleaned up)
│   │
│   ├── sandboxes/              # Runtime copies + installed skills
│   │   └── agent-main-main-{hash}/
│   │       ├── IDENTITY.md, SOUL.md, etc.
│   │       └── skills/
│   │           └── [~20 skills]
│   │
│   └── media/
│       ├── inbound/            # Voice messages in (~128 items)
│       └── outbound/           # Voice messages out (~56 items)
│
└── .clawdbot/
    └── agents/
        ├── bruba-main/
        │   └── auth-profiles.json
        ├── bruba-guru/
        │   └── auth-profiles.json   # Copied from bruba-main
        ├── bruba-manager/
        │   └── auth-profiles.json
        └── bruba-web/
            └── auth-profiles.json
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
│    guru-base    → templates/prompts/guru/{NAME}.md           │
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
│    - results/*.md (guru only)                                │
└─────────────────────────────────────────────────────────────┘
       │
       ▼
mirror/{agent}/
  prompts/    - Current bot prompts (for conflict detection)
  memory/     - Bot's memory files (subset)
  config/     - openclaw.json, exec-approvals.json
  tools/      - Bot's tool scripts
  state/      - Manager state files
  results/    - Guru analysis outputs
```

### Pipeline 4: Guru Direct Response

```
User sends technical question via Signal
       │
       ▼
bruba-main detects technical content
       │
       ├── Tracks: "Routing to Guru: [topic]"
       │
       ▼
sessions_send to bruba-guru
       │
       ▼
bruba-guru analyzes (may generate 40K+ tokens)
       │
       ├── message action=send target=uuid:... → Signal (direct to user)
       │           │
       │           └──────────────────────────────────► User sees full response
       │
       └── Returns to Main: "Summary: [one-liner]"
               │
               ▼
bruba-main updates tracking (summary only, not payload)
       │
       └── Main's context stays lightweight
```

**Key insight:** Guru's full response goes directly to Signal via the `message` tool. Main only receives a one-sentence summary for context tracking. This prevents Main's context from bloating with technical payloads.

### Pipeline 5: Voice Message Response

```
User sends voice message via Signal
       │
       ▼
bruba-main receives [media attached: /path/to/audio.m4a]
       │
       ▼
┌─────────────────────────────────────────────────────────────┐
│  1. Transcribe                                               │
│     exec whisper-clean.sh "/path/to/audio.m4a"               │
│                                                              │
│  2. Process transcribed content                              │
│                                                              │
│  3. Generate TTS response                                    │
│     exec tts.sh "response text" /tmp/response.wav            │
│                                                              │
│  4. Send voice + text                                        │
│     message action=send target=uuid:... filePath=... msg=... │
│                                                              │
│  5. Respond: NO_REPLY (prevents duplicate)                   │
└─────────────────────────────────────────────────────────────┘
       │
       ▼
User receives voice message with text caption in Signal
```

### Pipeline 6: Siri Async (HTTP → Signal)

```
Siri: "Tell Bruba to remind me about laundry"
       │
       ▼
HTTP API → bruba-main
       │
       ├── Detects [From Siri async] or [From Siri async] tag
       │
       ▼
┌─────────────────────────────────────────────────────────────┐
│  1. Process request (create reminder, look up info, etc.)    │
│                                                              │
│  2. Send to Signal                                           │
│     message action=send target=uuid:... message="Done..."    │
│                                                              │
│  3. Return to HTTP: ✓                                        │
└─────────────────────────────────────────────────────────────┘
       │
       ├──► Signal: User sees response
       │
       └──► Siri: Gets minimal "✓" acknowledgment
```

**Note:** NO_REPLY not needed here — HTTP responses don't go to Signal.

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
| `results/*.md` | bruba-web/guru | Never synced | Read by Manager heartbeat / direct output |

### Config Files

| File | Source | Sync Direction | Notes |
|------|--------|----------------|-------|
| `openclaw.json` | update-agent-tools.sh | push → bot | Tool permissions |
| `exec-approvals.json` | update-allowlist.sh | push → bot | Command allowlist |

### Tool Permissions (message tool)

| Agent | message tool | Use Case |
|-------|--------------|----------|
| bruba-main | ✅ | Voice replies, Siri async routing |
| bruba-guru | ✅ | Direct technical responses to Signal |
| bruba-manager | ❌ | Routes via sessions_send to Main |
| bruba-web | ❌ | Passive service, no outbound messaging |

---

## Part 6: Section Type Reference

| Section Type | Config Entry | Source Location | Resolution |
|--------------|--------------|-----------------|------------|
| `base` | `base` | `templates/prompts/{NAME}.md` | Full file copy |
| `manager-base` | `manager-base` | `templates/prompts/manager/{NAME}.md` | Full file for manager |
| `web-base` | `web-base` | `templates/prompts/web/{NAME}.md` | Full file for web agent |
| `guru-base` | `guru-base` | `templates/prompts/guru/{NAME}.md` | Full file for guru agent |
| `component` | `component-name` | `components/{name}/prompts/{NAME}.snippet.md` | Wrapped in `<!-- COMPONENT: name -->` |
| `section` | `section-name` | `templates/prompts/sections/{name}.md` | Wrapped in `<!-- SECTION: name -->` |
| `bot-managed` | `bot:section-name` | `mirror/{agent}/prompts/{NAME}.md` | Extracted from `<!-- BOT-MANAGED: name -->` |

### Resolution Priority (in assemble-prompts.sh)

1. `base` → check `templates/prompts/{NAME}.md`
2. `manager-base` → check `templates/prompts/manager/{NAME}.md`
3. `web-base` → check `templates/prompts/web/{NAME}.md`
4. `guru-base` → check `templates/prompts/guru/{NAME}.md`
5. `bot:*` → extract from mirror's BOT-MANAGED block
6. Component → check `components/{entry}/prompts/{NAME}.snippet.md`
7. Section → check `templates/prompts/sections/{entry}.md`
8. Not found → log "missing" warning

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
  - guru-routing        # → components/guru-routing/prompts/AGENTS.snippet.md
```

### bruba-main TOOLS.md

```yaml
tools_sections:
  - base                # → templates/prompts/TOOLS.md
  - reminders           # → components/reminders/prompts/TOOLS.snippet.md
  - message-tool        # → components/message-tool/prompts/TOOLS.snippet.md (if separate)
```

### bruba-guru AGENTS.md

```yaml
agents_sections:
  - guru-base           # → templates/prompts/guru/AGENTS.md
  - continuity          # → components/continuity/prompts/AGENTS.snippet.md
```

### bruba-guru TOOLS.md

```yaml
tools_sections:
  - guru-base           # → templates/prompts/guru/TOOLS.md
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

## Part 8: Message Paths (File-Based & Direct)

### File-Based: Cron → Manager (via inbox/)

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

### File-Based: Manager → bruba-web → Manager (via results/)

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

### Direct Signal Messaging (via message tool)

Agents with the `message` tool can send directly to Signal, outside the normal response flow:

**Syntax:**
```
message action=send target=uuid:<recipient-uuid> message="text"
message action=send target=uuid:<recipient-uuid> filePath=/path/to/file message="caption"
```

**<REDACTED-NAME>'s Signal UUID:** `uuid:<REDACTED-UUID>`

**Patterns:**

| Source | Flow | NO_REPLY? |
|--------|------|-----------|
| Voice reply (Main) | whisper → tts → message tool → NO_REPLY | Yes |
| Siri async (Main) | process → message tool → return `✓` to HTTP | No |
| Guru response | message tool → return summary to Main | No |

**Why NO_REPLY?**
- Required when the agent is **bound to Signal** (bruba-main)
- Without it, both the message tool delivery AND the normal response go to Signal (duplicate)
- Not needed for Guru (returns to Main via sessions_send callback, not Signal)
- Not needed for HTTP responses (HTTP doesn't go to Signal anyway)

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

## Part 12: Node Host + Docker Sandboxing

**Status:** ⚠️ DISABLED (2026-02-03). Sandbox mode turned off due to agent-to-agent session visibility issues.

**Problem:** With `sandbox.scope: "agent"`, `sessions_send` cannot see other agents' sessions. Breaks guru routing with error: "Session not visible from this sandboxed agent session".

**Current state:** `sandbox.mode: "off"` — agents run directly on host. Security relies on exec-approvals allowlist and tools.allow/deny lists (both still enforced).

**TODO:** Re-enable when OpenClaw fixes cross-agent visibility in sandboxed mode.

### Security Model (When Sandbox Re-enabled)

**Security gap (currently open):** Agents could theoretically edit `~/.openclaw/exec-approvals.json` to self-escalate. When sandbox is re-enabled, this file would exist only on the host filesystem, which containers cannot access.

**Exec flow:**
```
Agent (container) → exec tool → Gateway → Node Host (on HOST) → checks allowlist → executes
```

### File Access Architecture

**Key principle:** All file access goes through `/workspace/`. Memory is at `/workspace/memory/` (synced by operator). Discovery via `memory_search`.

**Directory Layout:**

| Directory | Container Path | Access | Purpose |
|-----------|----------------|--------|---------|
| **Workspace root** | `/workspace/` | Read-write | Prompts, memory, working files |
| **Memory** | `/workspace/memory/` | Read-write | Docs, transcripts, repos (synced by operator) |
| **Tools** | `/workspace/tools/` | Read-only | Scripts (exec uses host paths) |
| Shared packets | `/workspaces/shared/packets/` | Read-write | Main↔Guru handoff |

**Memory Structure (`/workspace/memory/`):**
```
/workspace/memory/
├── transcripts/          # Transcript - *.md
├── docs/                 # Doc - *.md, Refdoc - *.md, CC Log - *.md
├── repos/bruba-godo/     # bruba-godo mirror (updated on sync)
└── workspace-snapshot/   # Copy of workspace/ at last sync
```

**Workspace Structure (`/workspace/`):**
```
/workspace/
├── memory/              # Synced content (searchable via memory_search)
├── output/              # Working outputs
├── drafts/              # Work in progress
├── temp/                # Temporary files
└── continuation/        # CONTINUATION.md and archive/
```

### File Tools vs Exec

| Task | Tool | Example |
|------|------|---------|
| **Read file** | `read` | `read /Users/bruba/agents/bruba-main/memory/docs/Doc - setup.md` |
| **Write file** | `write` | `write /Users/bruba/agents/bruba-main/workspace/output/result.md` |
| **Edit file** | `edit` | `edit /Users/bruba/agents/bruba-main/workspace/drafts/draft.md` |
| **List files** | `exec` | `exec /bin/ls /Users/bruba/agents/bruba-main/memory/` |
| **Find files** | `exec` | `exec /usr/bin/find /Users/bruba/agents/bruba-main/ -name "*.md"` |
| **Search content** | `exec` | `exec /usr/bin/grep -r "pattern" /Users/bruba/agents/bruba-main/` |
| **Run script** | `exec` | `exec /Users/bruba/agents/bruba-main/tools/tts.sh "text" /tmp/out.wav` |
| **Discover in memory** | `memory_search` | `memory_search "topic"` |

**Key distinction:**
- `read/write/edit` = use when you need that exact file operation
- `exec` = use for shell utilities (ls, find, grep — read-only discovery)
- All paths are full host paths (`/Users/bruba/...`)

**Note:** `ls`, `find`, `grep` are available via `exec` with full paths (e.g., `exec /bin/ls /Users/bruba/...`). For indexed content, `memory_search` is more efficient.

### Configuration

**agents.defaults.sandbox** in `~/.openclaw/openclaw.json`:

```json
{
  "mode": "all",
  "scope": "agent",
  "workspaceAccess": "rw",
  "docker": {
    "readOnlyRoot": true,
    "network": "none",
    "memory": "512m",
    "binds": [
      "/Users/bruba/agents/bruba-shared/packets:/workspaces/shared/packets:rw",
      "/Users/bruba/agents/bruba-shared/context:/workspaces/shared/context:rw",
      "/Users/bruba/agents/bruba-shared/repo:/workspaces/shared/repo:ro"
    ]
  }
}
```

**Per-agent config** (each agent needs `sandbox.workspaceRoot`):

```json
{
  "id": "bruba-main",
  "workspace": "/Users/bruba/agents/bruba-main",
  "sandbox": {
    "workspaceRoot": "/Users/bruba/agents/bruba-main"
  }
}
```

**Key settings:**
- `sandbox.workspaceRoot` = agent's `workspace` path (tells OpenClaw file tools where `/workspace/` is)
- Tools are at `/Users/bruba/agents/{agent}/tools/` (per-agent, read-only in sandbox)

**Per-agent overrides:**
- `bruba-main`, `bruba-guru`, `bruba-manager`: `workspaceRoot` only
- `bruba-web`: `workspaceRoot` + bridge network for web access

### Sandbox Tool Policy (IMPORTANT)

**There's a sandbox-level tool ceiling** — tools must be allowed here for containerized agents:

```json
{
  "tools": {
    "sandbox": {
      "tools": {
        "allow": ["group:memory", "group:media", "group:sessions", "exec", "group:web", "message"]
      }
    }
  }
}
```

**Gotcha:** If a tool is allowed at global and agent level but NOT in `tools.sandbox.tools.allow`, containerized agents won't have it. After sandbox migration, check that all needed tools (especially `message`) are in this list.

### Path Mapping (All Agents)

| Host Path | Container Path | Access | Notes |
|-----------|----------------|--------|-------|
| `/Users/bruba/agents/{agent}/` | `/workspace/` | rw | Each agent's workspace |
| `~/agents/bruba-shared/packets/` | `/workspaces/shared/packets/` | rw | All agents |
| `~/agents/bruba-shared/context/` | `/workspaces/shared/context/` | rw | All agents |
| `~/agents/bruba-shared/repo/` | `/workspaces/shared/repo/` | **ro** | All agents |
| `{agent}/tools/` | `/workspace/tools/` | **ro** | Per-agent tools (read-only in sandbox) |

### Per-Agent Access Matrix

#### bruba-main Access

| Resource | Container Path | Access | Notes |
|----------|----------------|--------|-------|
| Prompts (*.md) | `/workspace/*.md` | **rw** | AGENTS.md, TOOLS.md, etc. |
| memory/ | `/workspace/memory/` | **rw** | PKM docs, transcripts (synced by operator) |
| tools/ | `/workspace/tools/` | **ro** | Scripts (read-only overlay) |
| workspace/ | `/workspace/workspace/` | **rw** | Working files |
| artifacts/ | `/workspace/artifacts/` | **rw** | Generated artifacts |
| output/ | `/workspace/output/` | **rw** | Script outputs |
| Shared packets | `/workspaces/shared/packets/` | **rw** | Main↔Guru handoff |
| Shared context | `/workspaces/shared/context/` | **rw** | Shared context |
| Shared repo | `/workspaces/shared/repo/` | **ro** | bruba-godo reference |
| exec-approvals.json | — | **none** | Not mounted |
| openclaw.json | — | **none** | Not mounted |
| Host filesystem | — | **none** | Not accessible |
| Network | — | **none** | No outbound |

#### bruba-guru Access

| Resource | Container Path | Access | Notes |
|----------|----------------|--------|-------|
| Prompts (*.md) | `/workspace/*.md` | **rw** | AGENTS.md, TOOLS.md, etc. |
| workspace/ | `/workspace/workspace/` | **rw** | Technical analysis |
| memory/ | `/workspace/memory/` | **rw** | Persistent notes |
| tools/ | `/workspace/tools/` | **ro** | Scripts (defense-in-depth) |
| results/ | `/workspace/results/` | **rw** | Analysis outputs |
| Shared packets | `/workspaces/shared/packets/` | **rw** | Main↔Guru handoff |
| Shared context | `/workspaces/shared/context/` | **rw** | Shared context |
| Shared repo | `/workspaces/shared/repo/` | **ro** | bruba-godo reference |
| exec-approvals.json | — | **none** | Not mounted |
| Host filesystem | — | **none** | Not accessible |
| Network | — | **none** | No outbound |

#### bruba-manager Access

| Resource | Container Path | Access | Notes |
|----------|----------------|--------|-------|
| Prompts (*.md) | `/workspace/*.md` | **rw** | AGENTS.md, TOOLS.md, etc. |
| inbox/ | `/workspace/inbox/` | **rw** | Cron job outputs |
| state/ | `/workspace/state/` | **rw** | Persistent tracking (nag-history, etc.) |
| tools/ | `/workspace/tools/` | **ro** | Scripts (defense-in-depth) |
| results/ | `/workspace/results/` | **rw** | Research outputs |
| memory/ | `/workspace/memory/` | **rw** | Agent memory |
| Shared packets | `/workspaces/shared/packets/` | **rw** | Work packets |
| Shared context | `/workspaces/shared/context/` | **rw** | Shared context |
| Shared repo | `/workspaces/shared/repo/` | **ro** | bruba-godo reference |
| exec-approvals.json | — | **none** | Not mounted |
| Host filesystem | — | **none** | Not accessible |
| Network | — | **none** | No outbound |

#### bruba-web Access

| Resource | Container Path | Access | Notes |
|----------|----------------|--------|-------|
| Prompts (*.md) | `/workspace/*.md` | **rw** | AGENTS.md only |
| tools/ | `/workspace/tools/` | **ro** | Scripts (defense-in-depth) |
| results/ | `/workspace/results/` | **rw** | Research outputs |
| Shared packets | `/workspaces/shared/packets/` | **rw** | (rarely used) |
| Shared context | `/workspaces/shared/context/` | **rw** | (rarely used) |
| Shared repo | `/workspaces/shared/repo/` | **ro** | bruba-godo reference |
| exec-approvals.json | — | **none** | Not mounted |
| Host filesystem | — | **none** | Not accessible |
| **Network** | via bridge | **yes** | **Only agent with internet** |

### NOT Mounted (Security Boundary)

These resources are explicitly excluded from ALL containers:

| Host Path | Why Protected |
|-----------|---------------|
| `~/.openclaw/exec-approvals.json` | **Critical:** Prevents privilege self-escalation |
| `~/.openclaw/openclaw.json` | Config shouldn't be agent-writable |
| `~/.clawdbot/agents/*/auth-profiles.json` | API keys stay on host |
| `/Users/bruba/` (general) | No arbitrary host filesystem access |
| Other agents' workspaces | Cross-agent isolation |

### Network Access Matrix

| Agent | Network Mode | Can Reach |
|-------|--------------|-----------|
| bruba-main | none | Gateway only (internal) |
| bruba-guru | none | Gateway only (internal) |
| bruba-manager | none | Gateway only (internal) |
| bruba-web | **bridge** | Internet + Gateway |

### Security Verification

From inside container, these should FAIL:
```bash
# Cannot access exec-approvals
docker exec <container> cat ~/.openclaw/exec-approvals.json
# → No such file

# Cannot access host filesystem
docker exec <container> ls /Users/bruba/
# → No such file

# Cannot write to tools (ALL agents have tools/:ro)
docker exec openclaw-sandbox-bruba-main touch /workspace/tools/test.sh
docker exec openclaw-sandbox-bruba-guru touch /workspace/tools/test.sh
docker exec openclaw-sandbox-bruba-manager touch /workspace/tools/test.sh
docker exec openclaw-sandbox-bruba-web touch /workspace/tools/test.sh
# → All should fail: Read-only file system
```

### Container Lifecycle

- Containers are created automatically on first agent use
- Gateway LaunchAgent (`ai.openclaw.gateway.plist`) auto-starts on system boot
- `openclaw sandbox recreate --all` to force container refresh
- Containers auto-prune after 24h idle (configurable)

### Debugging Commands

```bash
# Check sandbox status
openclaw sandbox explain

# List containers
openclaw sandbox list

# Recreate containers (after config change)
openclaw sandbox recreate --all

# Exec into container for debugging
docker exec -it openclaw-sandbox-bruba-main /bin/sh

# Run verification tests (from bruba-godo)
./tools/test-sandbox.sh               # All tests
./tools/test-sandbox.sh --security    # Security only
./tools/test-sandbox.sh --functional  # Functional only
./tools/test-sandbox.sh --status      # Container status
```

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.7.0 | 2026-02-03 | **Sandbox disabled:** Agent-to-agent session visibility broken in sandbox mode. Set `sandbox.mode: "off"` until OpenClaw fixes. |
| 1.6.0 | 2026-02-03 | **File access architecture:** `/memory/` read-only (docs, transcripts, repos), `/workspace/` read-write (outputs, continuation). Discovery via `memory_search`. Updated Part 12 with new structure. |
| 1.5.2 | 2026-02-03 | Added sandbox tool policy ceiling documentation (tools.sandbox.tools.allow) |
| 1.5.1 | 2026-02-03 | Defense-in-depth: ALL agents now have tools/:ro (not just bruba-main) |
| 1.5.0 | 2026-02-03 | Part 12 expanded: per-agent access matrix, network access matrix, detailed security boundaries |
| 1.4.1 | 2026-02-03 | Added test-sandbox.sh to debugging commands |
| 1.4.0 | 2026-02-03 | Part 12 IMPLEMENTED: Docker sandbox enabled for all agents, exec/file path split documented |
| 1.3.0 | 2026-02-03 | Added message tool patterns, guru direct response pipeline, voice/Siri pipelines, tool permissions matrix, guru assembly mapping |
| 1.2.1 | 2026-02-02 | Added guru cron job, expanded cronjobs listing |
| 1.2.0 | 2026-02-02 | Added bruba-guru and bruba-shared directories |
| 1.1.0 | 2026-02-02 | Added Part 12: Node Host + Docker Sandboxing |
| 1.0.0 | 2026-02-02 | Initial version from CC investigation |