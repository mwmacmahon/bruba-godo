---
type: doc
scope: reference
title: "Vision: Bot-Agnostic Operator Design"
---

# Vision: Bot-Agnostic Operator Design

**Version:** 2.0.0
**Last Updated:** 2026-01-30

---

## The Value Proposition

bruba-godo isn't just "Clawdbot installer with SSH access." The real value is:

**"A managed AI assistant where conversations become knowledge that feeds back in."**

The component setup (signal, voice, etc.) is table stakes. The **conversation→knowledge loop** is the differentiator.

The distill component doesn't just help your bot learn — it produces **condensed records usable by any modern AI ecosystem**. Your conversations become RAG-ready knowledge for:
- Your bot's memory
- Claude Code sessions
- Other AI assistants
- Your own reference

---

## Core vs Components

bruba-godo has two layers:

### Core: Managing the Bot

The fundamental operator-bot relationship:

| Capability | Skills | Purpose |
|------------|--------|---------|
| Daemon control | `/status`, `/launch`, `/stop`, `/restart` | Bot lifecycle |
| Prompt sync | `/mirror`, `/push` | Bidirectional config management |
| Conflict detection | `/review` | Review bot's changes before overwrite |
| Code review | `/code` | Review bot's drafted scripts |
| Session access | `/convo` | Load active conversation |
| Configuration | `/config`, `/update` | Settings and updates |

Core is about **managing the bot**.

### Components: What the Bot Can Do

Optional capabilities that extend the bot:

```
components/
├── signal/      # Messaging channel
├── voice/       # Audio I/O (adds 🎤 check)
├── http-api/    # Siri/Shortcuts (adds 📬 check)
├── reminders/   # Apple Reminders
├── calendar/    # Apple Calendar
├── distill/     # Conversation→knowledge loop
├── continuity/  # Session reset with context (lightweight)
└── web-search/  # Research capability
```

Components are about **what the bot can do**.

**How components work:** Each component contributes:
- Setup scripts (`setup.sh`, `validate.sh`)
- Prompt snippets (additions to AGENTS.md, TOOLS.md, etc.)
- Config fragments (for clawdbot.json)

Some components are heavyweight (distill has a full pipeline). Others are lightweight — continuity just adds a few lines to AGENTS.md telling the bot to write/read a context file on session reset.

The `/component` skill manages all of these: `list`, `setup`, `validate`, `status`.

---

## The Core Insight

We use Clawdbot/Moltbot as the current bot of choice, but **the entire system is designed to be bot-adaptable, ideally bot-agnostic**.

Bot frameworks evolve rapidly. Built-in features break, change APIs, or don't work as expected. Our scripts and prompts should outlive any specific framework.

### What Is vs. What Isn't

**The bot is:**
- Prompts (SOUL, AGENTS, USER, IDENTITY, MEMORY)
- Processes (triage, intake pipeline, memory curation, continuation packets)
- Philosophy (light touch, operator-controlled, persistent identity)

**The bot is not:**
- OpenClaw/Clawdbot
- Signal
- macOS
- Any specific runtime

The implementation is substrate. If tomorrow there's a better framework, the prompts port over. The processes adapt. The philosophy stays.

bruba-godo is more implementation-coupled (SSH to a specific daemon, specific CLI commands), but even that's just a convenience layer. **The real value is in the patterns.**

You're not building on Clawdbot — you're building on ideas that happen to run on it today.

---

## The Portable Layer

```
┌─────────────────────────────────────────┐
│           Your Bot Framework            │
│    (Clawdbot, Moltbot, or future)       │
├─────────────────────────────────────────┤
│         Exec Control Layer              │
│  (allowlist, permissions, sandbox)      │
├─────────────────────────────────────────┤
│     Lightweight Custom Scripts          │
│  (whisper-clean.sh, tts.sh, etc.)       │
├─────────────────────────────────────────┤
│      Prompts (AGENTS.md, TOOLS.md)      │
│   (Agent instructions, workflows)       │
├─────────────────────────────────────────┤
│         bruba-godo Operator             │
│    (SSH tools, sync, management)        │
└─────────────────────────────────────────┘
```

**What survives framework changes:**
- Shell scripts (just executable files)
- Prompt documents (markdown)
- Operator tools (SSH-based, framework-independent)

**What's framework-specific (minimize this):**
- Config file format (clawdbot.json)
- Daemon commands (`clawdbot daemon restart`)
- Channel setup (signal-cli integration)

---

## Design Principles

### 1. Custom Scripts Over Built-In Tools

**Principle:** Write lightweight shell scripts rather than relying on bot framework's built-in tools.

**Example:** We use `whisper-clean.sh` rather than Clawdbot's `tools.media.audio` pipeline.

**Rationale:**
- Built-in tools don't work reliably across framework versions
- Custom scripts are debuggable, modifiable, portable
- Shell scripts work regardless of what bot is running them

### 2. Prompt-Driven Over Auto

**Principle:** Use explicit prompt instructions rather than automatic framework features.

**Example:** Agent checks for `<media:audio>` tags manually rather than relying on auto-detection.

**Rationale:**
- Explicit control means predictable behavior
- Easier to debug when something goes wrong
- Prompts transfer between bot frameworks; auto-detection doesn't

### 3. Exec Allowlist as Security Boundary

**Principle:** The bot framework provides exec gating; our scripts are the trusted executables.

**Pattern:**
```
Bot framework → exec allowlist → our scripts → actual work
```

**Why this works:**
- Any bot with exec control can use this pattern
- Security boundary is consistent across frameworks
- We own the scripts, not the framework

### 4. SSH Wrapper Pattern

**Principle:** Operator never touches framework internals directly.

**Example:** `./tools/bot ls /path` instead of `ssh bruba ls /path`.

**Benefits:**
- `tools/bot` abstracts framework-specific paths
- Easy to adapt for different frameworks (just update config)
- Permission whitelisting in one place

---

## Current Implementation

### Framework: Clawdbot/Moltbot

We currently use Clawdbot (or its fork, Moltbot) as the bot runtime. This is the **current choice**, not a requirement.

**Framework-specific pieces:**
- `clawdbot.json` — config format
- `clawdbot daemon start/stop/restart` — lifecycle commands
- `~/.clawdbot/` — config directory location

See the setup guides for current framework details.

### Framework-Independent Pieces

Everything else:
- All `tools/*.sh` scripts
- All `templates/prompts/*.md` files
- Operator workflows (mirror, push, pull, snapshot)
- Content pipeline (exports, intake, reference)
- Security model (exec allowlist pattern)

---

## Migration Path

If we switched to a new bot framework, here's what changes:

### Must Adapt

| Component | Work Required |
|-----------|---------------|
| Config file format | Write new config template |
| Daemon commands | Update lifecycle scripts |
| Channel setup | New integration scripts |
| Directory paths | Update `config.yaml` |

### Stays the Same

| Component | Why It Works |
|-----------|-------------|
| Custom scripts | Just executables, any bot can call them |
| Prompts | Markdown files, framework-independent |
| SSH wrapper | Just reads paths from YAML |
| Operator tools | Shell scripts that use SSH |
| Content pipeline | Just file operations |

The ratio should be heavily weighted toward "stays the same."

---

## Anti-Patterns

### Don't: Rely on Built-In Bot Features

```
# Bad: Use framework's transcription
tools.media.audio.transcribe(file)

# Good: Use our script
whisper-clean.sh "$file"
```

Framework features are convenient until they break.

### Don't: Use Framework-Specific Config Everywhere

```
# Bad: Read clawdbot.json directly in scripts
jq '.agent.name' ~/.clawdbot/clawdbot.json

# Good: Read from our config.yaml
./tools/bot get-config agent_id
```

Keep framework coupling in one place.

### Don't: Skip the Exec Allowlist

```
# Bad: Give bot unrestricted exec
"exec": { "allowed": ["*"] }

# Good: Explicit allowlist
"exec": { "allowed": ["/path/to/scripts/*"] }
```

The allowlist is our security boundary.

---

## Pre-Response Check Pattern

A key behavior pattern baked into AGENTS.md: before responding to any message, the bot runs a quick check.

**The pattern is core.** Every agent does this check — it's the forcing function that makes the assistant reliable.

**The content is component-driven.** What the check includes depends on which components are installed:

| Component | Adds to Check | Example |
|-----------|---------------|---------|
| voice | 🎤 audio detection | "Is there a new voice message?" |
| http-api | 📬 HTTP log relay | "Are there recent API messages?" |
| (future) | other triggers | Continuation packets, etc. |

This pattern ensures the bot doesn't miss async inputs that arrived between messages.

---

## Bidirectional Sync

**The problem:** Bot edits AGENTS.md. Operator pushes updates from bruba-godo. Whose version wins? Changes get lost.

**The solution:** Conflict detection that extends the `/code` review pattern.

```
┌─────────────────────────────────────────────────────────────────────┐
│                     BIDIRECTIONAL SYNC                               │
│                                                                      │
│   bruba-godo/mirror/          ◄── /mirror ──►      Bot's ~/clawd/   │
│   (operator's copy)                                (bot's live)      │
│                                                                      │
│   templates/prompts/          ─── /push ───►      (only if clean)   │
│   (canonical source)                                                 │
│                                                                      │
│   WORKFLOW:                                                          │
│   1. /mirror pulls latest                                            │
│   2. Compare mirror/ to last-known state                            │
│   3. If bot changed files → flag for review                         │
│   4. /review shows diffs, operator decides                          │
│   5. /push only after conflicts resolved                            │
└─────────────────────────────────────────────────────────────────────┘
```

This is what `/code` already does for bot-drafted scripts. Extend the same pattern to prompts and config.

---

## The Distill Component

The flagship component that makes bruba-godo more than a bot manager.

**Purpose:** Transform sprawling conversations into manageable, referenceable knowledge.

```
conversations  →  distill  →  knowledge  →  bot memory
(raw JSONL)       (process)    (curated)     (pushed back)
```

Two modes:

| Mode | Who | What |
|------|-----|------|
| **Simple** | Most users | Pull → parse → review → push |
| **Full** | Advanced | Pull → canonicalize → redact → mine → export → push |

Without distill, conversations are write-only. With distill, **your bot learns from its own history**.

---

## Prompt Management Pipeline

The core infrastructure that makes everything work.

### The Problem

Your bot's prompts (AGENTS.md, TOOLS.md, etc.) come from multiple sources:
- Base templates (shipped with bruba-godo)
- Component snippets (each component adds its own sections)
- User customizations (your personal additions)
- Bot's own edits (changes made during operation)

How do you assemble these into final prompts without losing anyone's changes?

### The Solution

The `/sync` command assembles final prompts from layered sources:

```
templates/prompts/AGENTS.md     (base)
    + components/voice/prompts/AGENTS.snippet.md
    + components/http-api/prompts/AGENTS.snippet.md
    + user/prompts/AGENTS.snippet.md
    = final AGENTS.md pushed to bot
```

**With conflict detection:**
1. `/mirror` pulls bot's current prompts
2. Compare to last-pushed version
3. If bot made changes → preserve them or prompt for review
4. Assemble new version incorporating all sources
5. `/push` the result

This pipeline recreates your current setup once all components are in place. Add a component → its snippets get woven into the prompts automatically.

---

## User Customization

bruba-godo separates "repo proper" from "user files":

| Directory | Purpose | Committed? |
|-----------|---------|------------|
| `templates/` | Base prompts shipped with bruba-godo | Yes |
| `components/` | Optional capabilities | Yes |
| `user/` | Your personal customizations | No (gitignored) |

**Where to put your stuff:**

- `user/prompts/` — Extra snippets to add to AGENTS.md, TOOLS.md, etc.
- `user/exports.yaml` — Custom export configurations
- `user/config.yaml` — Override default settings (if needed)

This keeps your personal stuff separate from upstream updates.

---

## Future: Multi-Bot

bruba-godo is designed for one operator managing **multiple bots**:

- **Work bot** — Professional context, work calendar, formal tone
- **Home bot** — Personal context, family reminders, casual tone
- **Local bot** — Runs on local LLM, privacy-sensitive tasks

### How It Will Work

```bash
# Different config files
./tools/bot --config config-work.yaml status
./tools/bot --config config-home.yaml push

# Or environment variable
BRUBA_CONFIG=config-work.yaml ./tools/bot status
```

Each config points to a different:
- SSH host
- Remote paths
- Agent ID
- Component set

The prompts, scripts, and components are shared. Only the config differs.

**Not implemented yet** — but the architecture supports it.

---

## Summary

Build for portability:
1. **Lightweight scripts** that any bot can execute
2. **Good prompts** that work regardless of framework
3. **Exec allowlist** as the universal security pattern
4. **SSH wrapper** that abstracts framework paths

The bot framework is just a runtime. The real value is in the scripts, prompts, and operator tools that sit on top of it.

Build for value:
1. **Core skills** manage the bot relationship
2. **Components** extend what the bot can do
3. **Distill** closes the conversation→knowledge loop
4. **Bidirectional sync** preserves bot's changes
