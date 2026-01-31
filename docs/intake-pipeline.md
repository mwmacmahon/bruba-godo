# Intake Pipeline

How conversation sessions flow from raw JSONL to bot memory.

## Overview

```
/pull                    Pull JSONL, convert to intake/*.md
  ↓
/convert <file>          AI-assisted: add CONFIG block + summary
  ↓
/intake                  Canonicalize → reference/transcripts/
  ↓
/export                  Filter + redact → exports/bot/
  ↓
/push                    Sync to bot memory
```

## The Full Pipeline

### Step 1: Pull Sessions

Use `/pull` to download closed sessions from the bot:

```bash
./tools/pull-sessions.sh --verbose
```

This:
1. Copies closed JSONL files to `sessions/` (archived)
2. Converts each to delimited markdown in `intake/`
3. Tracks pulled session IDs in `sessions/.pulled`

**Output format in intake/:**
```markdown
=== MESSAGE 1 | ASSISTANT ===
Hey! What's on your mind?

=== MESSAGE 2 | USER ===
[Transcript] Let's work on the new feature...

=== MESSAGE 3 | ASSISTANT ===
Sure, I can help with that.
```

### Step 2: Convert (Add CONFIG)

Use `/convert <file>` for AI-assisted CONFIG block generation.

**`/convert` does TWO things:**

1. **REMOVES noise from the file:**
   - Heartbeat interrupts (exec denials + `HEARTBEAT_OK`)
   - System error messages
   - These are deleted before canonicalize runs

2. **MARKS content in CONFIG block (applied later at export):**
   - **Metadata:** title, slug, date, source, tags
   - **Sections to remove:** debugging tangents, off-topic content
   - **Sensitivity markers:** names, health info, personal details
   - **Code blocks:** walls of text, artifacts with keep/summarize/remove actions
   - **Summary backmatter:** what was discussed, decisions made

**CRITICAL:** Only noise is removed from the file. Everything else stays — CONFIG just marks it for processing at `/export` time.

**CONFIG block format:**
```yaml
=== EXPORT CONFIG ===
title: "Implementing User Authentication"
slug: 2026-01-28-user-auth
date: 2026-01-28
source: bruba
tags: [auth, backend, voice]
description: "Built JWT auth system"

sections_remove:
  - start: "Let me check the error logs"
    end: "Okay the logs show it's a path issue"
    description: "Debugging session"

sensitivity:
  terms:
    names: [Michael]
=== END CONFIG ===
```

### Step 3: Intake (Canonicalize)

Use `/intake` to batch process files WITH CONFIG blocks.

**`/intake` is NOT AI-powered.** It does deterministic processing:

```bash
python -m components.distill.lib.cli canonicalize intake/*.md \
    -o reference/transcripts/ \
    -c components/distill/config/corrections.yaml
```

This:
1. Parses the CONFIG block → YAML frontmatter
2. Applies transcription corrections from `corrections.yaml`
3. Strips Signal/Telegram wrappers (`[Signal Michael id:...]`)
4. **Content stays intact** — sections_remove, sensitivity are just in frontmatter
5. Moves processed files to `intake/processed/`

**Output in reference/transcripts/:**
```yaml
---
title: "Implementing User Authentication"
slug: 2026-01-28-user-auth
date: 2026-01-28
type: canonical
tags: [auth, backend, voice]
---

[Clean conversation content with sections removed per CONFIG]

---
<!-- === BACKMATTER === -->

## Summary
...
```

### Step 4: Export (Filter + Redact)

Use `/export` to generate filtered exports per profile:

```bash
python -m components.distill.lib.cli export --profile bot
```

Profiles defined in `exports.yaml`:
```yaml
exports:
  bot:
    description: "Content synced to bot memory"
    output_dir: exports/bot
    include:
      scope: [transcripts]
    exclude:
      sensitivity: [sensitive, restricted]
    redaction: [names, health]
```

This:
1. Finds canonical files matching include/exclude rules
2. Applies redaction (replaces sensitive terms with [REDACTED])
3. Generates transcript variants in `exports/bot/`

### Step 5: Push to Bot

Use `/push` to sync exports to bot memory:

```bash
./tools/push.sh --verbose
```

This rsyncs `exports/bot/` to the bot's memory directory.

---

## Quick Reference

### Skills

| Skill | What it does |
|-------|-------------|
| `/pull` | Pull JSONL + convert to intake/ |
| `/convert` | Add CONFIG block (AI-assisted) |
| `/intake` | Batch canonicalize files with CONFIG |
| `/export` | Generate filtered exports |
| `/push` | Sync to bot memory |

### CLI Commands

```bash
# Parse JSONL to delimited markdown (automatic with /pull)
python -m components.distill.lib.cli parse-jsonl sessions/*.jsonl -o intake/

# Canonicalize with CONFIG
python -m components.distill.lib.cli canonicalize intake/*.md -o reference/transcripts/

# Generate variants with redaction
python -m components.distill.lib.cli variants reference/transcripts/ --redact health,names

# Export per profile
python -m components.distill.lib.cli export --profile bot

# Debug: show parsed CONFIG
python -m components.distill.lib.cli parse intake/file.md
```

### Directory Structure

| Directory | Contents |
|-----------|----------|
| `sessions/*.jsonl` | Raw JSONL from bot (archived) |
| `sessions/.pulled` | Tracking file for pulled IDs |
| `intake/*.md` | Delimited markdown (awaiting CONFIG) |
| `intake/processed/` | Originals after canonicalization |
| `reference/transcripts/` | Canonical files with frontmatter |
| `exports/bot/` | Filtered + redacted for bot |
| `exports/rag/` | Filtered for RAG systems |

---

## Tips

### Sessions are Immutable After Close

Once a session is closed (via `/reset`), the JSONL file won't change. Safe to pull once.

### Active Session

The active session is still being written. `/pull` skips it automatically. Use `/convo` to view active content.

### Transcription Corrections

Voice messages often have transcription errors. The canonicalize step applies corrections from `components/distill/config/corrections.yaml`:

```yaml
corrections:
  - pattern: "bruba godo"
    replacement: "bruba-godo"
  - pattern: "clod bot"
    replacement: "Clawdbot"
```

### Sensitivity Categories

Define what gets redacted per export profile:

- `names` — Personal names
- `health` — Medical/health content
- `personal` — Addresses, phone numbers
- `financial` — Financial details

Mark sensitive content in the CONFIG block, and it gets redacted automatically during export.

---

## Notes (2026-01-31)

### Walls of Text and Large Code Blocks

Use `sections_remove` for walls of text, pasted docs, and large code blocks you want to summarize. The `description` field becomes the replacement text.

Example CONFIG:
```yaml
sections_remove:
  - start: "does this look right? --- ## 2.5 Session Continuity"
    end: "can you tdraft that change"
    description: "[Pasted documentation: Section 2.5 Session Continuity — continuation file pattern]"
```

Output in export:
```
[Removed: [Pasted documentation: Section 2.5 Session Continuity — continuation file pattern]]
```

This approach works for any content type (documentation, logs, debug output, large code blocks).
