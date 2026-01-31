# Distill Component

**Status:** Core — THE DIFFERENTIATOR

Transform conversations into searchable knowledge that feeds back to your bot.

## Overview

Without distill, bruba-godo is "Clawdbot installer with SSH access."

With distill, bruba-godo is **"A managed AI assistant where conversations become knowledge that feeds back in."**

The conversation → knowledge loop is what makes the system valuable:

```
/pull → intake/ → /convert → /intake → reference/ → /export → exports/ → /push
```

## What Distill Does

1. **Parse JSONL** — Convert raw Clawdbot sessions to delimited markdown
2. **Canonicalize** — Transform with CONFIG blocks into clean markdown with YAML frontmatter
3. **Generate variants** — Create transcript and summary versions with redaction
4. **Filter for export** — Apply sensitivity filters per exports.yaml profiles

## Key Concept: What Gets Removed vs Marked

**REMOVED from file (by `/convert`, AI-powered):**
- **Noise only** — heartbeats, exec denials, system errors, `HEARTBEAT_OK` responses
- These are deleted before canonicalize runs

**MARKED in CONFIG (applied later at `/export`):**
- `sections_remove` — debugging tangents, off-topic discussions, walls of text, large code blocks
- `sensitivity` — names, health info, personal details

Use `sections_remove` for anything you want replaced with a description (pasted docs, log dumps, large code blocks). The `description` field becomes the replacement text.

The **canonical file keeps all content** except noise. CONFIG just marks what to process at export time.

## Prerequisites

- Python 3.8+
- PyYAML (`pip install pyyaml`)

## Usage

### Full Pipeline (via Skills)

```bash
/pull              # Pull JSONL sessions, auto-convert to intake/*.md
/convert <file>    # AI-assisted: add CONFIG block + summary to intake file
/intake            # Batch canonicalize files WITH CONFIG → reference/transcripts/
/export            # Generate filtered exports per exports.yaml profiles
/push              # Push exports to bot memory
```

### CLI Commands

```bash
# Step 1: JSONL → Delimited Markdown (automatic with /pull)
python -m components.distill.lib.cli parse-jsonl sessions/*.jsonl -o intake/

# Step 2: Split large files (automatic with /intake, or manual)
python -m components.distill.lib.cli split intake/large-file.md -o intake/ --max-chars 60000

# Step 3: Canonicalize (requires CONFIG block in file)
python -m components.distill.lib.cli canonicalize intake/*.md -o reference/transcripts/ \
    -c components/distill/config/corrections.yaml

# Step 4: Generate Variants
python -m components.distill.lib.cli variants reference/transcripts/ -o exports/ \
    --redact health,names

# Step 5: Export with profile filtering
python -m components.distill.lib.cli export --profile bot

# Debug: Show parsed CONFIG block
python -m components.distill.lib.cli parse intake/some-file.md
```

## Configuration

### exports.yaml (in repo root)

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

  rag:
    description: "Content for external RAG systems"
    output_dir: exports/rag
    include:
      scope: [reference, transcripts]
```

### corrections.yaml (voice transcription fixes)

```yaml
# components/distill/config/corrections.yaml
corrections:
  - pattern: "bruba godo"
    replacement: "bruba-godo"
  - pattern: "clod bot"
    replacement: "Clawdbot"
```

## Directory Structure

```
components/distill/
├── README.md              # This file
├── setup.sh               # Setup script
├── validate.sh            # Validate configuration
├── config/
│   └── corrections.yaml   # Voice transcription fixes
├── prompts/
│   └── AGENTS.snippet.md  # Bot instructions for distill workflow
└── lib/
    ├── __init__.py
    ├── cli.py             # CLI entry point
    ├── clawdbot_parser.py # JSONL → delimited markdown
    ├── models.py          # Data classes (v1/v2 CONFIG)
    ├── parsing.py         # CONFIG block extraction
    ├── canonicalize.py    # Delimited → canonical with frontmatter
    ├── splitting.py       # Large file splitting along message boundaries
    ├── variants.py        # Generate transcript/summary + redaction
    ├── content.py         # Content manipulation utilities
    └── output.py          # Output formatting
```

## Pipeline Data Flow

```
sessions/*.jsonl              (raw from bot, archived)
    ↓ parse-jsonl (automatic with /pull)
intake/*.md                   (delimited markdown, no CONFIG)
    ↓ /convert (AI-assisted)
    │   1. REMOVES noise (heartbeats, exec denials) from file
    │   2. MARKS content in CONFIG (sections_remove, sensitivity)
    │   3. Adds backmatter summary
intake/*.md                   (noise removed, has CONFIG block)
    ↓ /intake (canonicalize, NOT AI)
    │   - Reads CONFIG → YAML frontmatter
    │   - Applies corrections.yaml
    │   - Strips Signal wrappers [Signal ...]
    │   - Content stays intact (sections_remove etc just in frontmatter)
reference/transcripts/*.md    (canonical with YAML frontmatter, full content)
    ↓ /export (NOT AI)
    │   - Applies sections_remove (actually removes)
    │   - Applies redaction per exports.yaml profile
exports/bot/*.md              (filtered + redacted for bot)
    ↓ /push
bot memory
```

## CONFIG Block Format (v2)

The `/convert` skill generates this structure:

```yaml
title: "Conversation Title"
slug: 2026-01-28-topic-slug
date: 2026-01-28
source: bruba
tags: [voice, technical]
description: "One-line summary"

sections_remove:
  - start: "First words of section to remove..."
    end: "First words of section end..."
    description: "Debugging tangent"
  - start: "does this look right? --- ## 2.5"
    end: "can you draft that change"
    description: "[Pasted documentation: Section 2.5 — topic summary]"
  - start: "```bash\n# Debug output"
    end: "```"
    description: "[Code: 45 lines bash - debug output]"

sensitivity:
  terms:
    names: [Michael, Jane]
    health: [condition, medication]
  sections:
    - start: "Start of sensitive section..."
      end: "End of sensitive section..."
      tags: [health]
```

The `description` field in `sections_remove` becomes the replacement text in exports. Use patterns like:
- `[Pasted documentation: topic]` for walls of pasted text
- `[Code: N lines lang - what it does]` for large code blocks
- `[Log output: N lines - what it shows]` for log dumps

## Large File Handling

Files over 60,000 characters are automatically split by `/intake` along message boundaries.

### Split Behavior

- **Threshold:** 60,000 characters (configurable with `--max-chars`)
- **Minimum per chunk:** 5 messages (configurable with `--min-messages`)
- **Splits on:** `=== MESSAGE N | ROLE ===` boundaries only (never mid-message)
- **Even distribution:** Messages distributed roughly equally across chunks

### Split Output

Each chunk gets:
- Updated CONFIG block with part metadata (`part: 1`, `total_parts: 3`)
- Updated slug (`original-slug-part-1`)
- Continuation notes between parts

**Example:**
```markdown
**[Continued from Part 1 of 3]**

=== MESSAGE 5 | USER ===
...

---
**[Conversation continues in Part 3 of 3]**

=== EXPORT CONFIG ===
title: "Original Title"
slug: "2026-01-31-topic-part-2"
part: 2
total_parts: 3
messages: "5-8"
...
=== END CONFIG ===
```

### Manual Splitting

```bash
python -m components.distill.lib.cli split intake/large-file.md \
    --max-chars 60000 \
    --min-messages 5 \
    -o intake/
```

## Troubleshooting

### "No module named components.distill"

Run from the bruba-godo root directory, or set PYTHONPATH:
```bash
export PYTHONPATH=/path/to/bruba-godo
```

### "No EXPORT CONFIG block found"

The file needs a CONFIG block. Run `/convert <file>` to add one.

### "Error: exports.yaml not found"

Create exports.yaml in repo root (see Configuration above).

## Related Skills

- `/pull` — Pull sessions + auto-convert to intake/
- `/convert` — AI-assisted CONFIG generation
- `/intake` — Batch canonicalization
- `/export` — Generate filtered exports
- `/push` — Push to bot memory
