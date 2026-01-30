# Vision: Bot-Agnostic Operator Design

**Version:** 1.0.0
**Last Updated:** 2026-01-30

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
- Content pipeline (bundles, intake, reference)
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

## Summary

Build for portability:
1. **Lightweight scripts** that any bot can execute
2. **Good prompts** that work regardless of framework
3. **Exec allowlist** as the universal security pattern
4. **SSH wrapper** that abstracts framework paths

The bot framework is just a runtime. The real value is in the scripts, prompts, and operator tools that sit on top of it.
