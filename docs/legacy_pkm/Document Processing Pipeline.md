---
version: 2.0.0
updated: 2026-01-26
type: reference
tags: [meta, reference, pkm-system, convo-processor]
description: "Complete pipeline reference for PKM document processing from intake to bundle output"
---
# Document Processing Pipeline

> Complete reference for how documents flow through the PKM system, from raw input to bundle output.

---

## Table of Contents

1. [Pipeline Overview](#pipeline-overview)
2. [Stage 1: Intake Sources](#stage-1-intake-sources)
3. [Stage 2: Convert](#stage-2-convert)
4. [Stage 3: Canonicalize](#stage-3-canonicalize)
5. [Stage 4: Sync & Variants](#stage-4-sync--variants)
6. [Export CONFIG Reference](#export-config-reference)
7. [Sensitivity System](#sensitivity-system)
8. [Bundle System](#bundle-system)
9. [How It All Fits Together](#how-it-all-fits-together)
10. [CLI Reference](#cli-reference)
11. [Testing](#testing)
12. [Appendix: Module Structure](#appendix-module-structure)

---

## Pipeline Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         DOCUMENT PROCESSING PIPELINE                         │
│                                                                              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌───────────┐ │
│  │   INTAKE     │    │   CONVERT    │    │ CANONICALIZE │    │   SYNC    │ │
│  │              │───►│              │───►│              │───►│           │ │
│  │ Raw files    │    │ Add CONFIG   │    │ Parse CONFIG │    │ Generate  │ │
│  │ arrive here  │    │ block        │    │ Create       │    │ variants  │ │
│  │              │    │              │    │ canonical    │    │ per bundle│ │
│  └──────────────┘    └──────────────┘    └──────────────┘    └─────┬─────┘ │
│                                                                      │      │
│                                                                      ▼      │
│                                                              ┌───────────┐  │
│                                                              │  BUNDLES  │  │
│                                                              │           │  │
│                                                              │ work/     │  │
│                                                              │ home/     │  │
│                                                              │ personal/ │  │
│                                                              │ meta/     │  │
│                                                              │ bruba/    │  │
│                                                              └───────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Key principle:** AI runs once at convert/canonicalize. Variant generation and redaction are deterministic Python operations.

---

## Stage 1: Intake Sources

Raw files arrive in `intake/` from various sources:

| Source | Method | Typical Content |
|--------|--------|-----------------|
| Claude Projects | Bookmarklet export | Conversations with CONFIG block |
| Bruba/Signal | `/bruba:pull` or manual | Voice transcripts, chat logs |
| Voice memos | Manual copy | Dictation, notes |
| Manual paste | Copy-paste | Any text content |

### Directory Structure

```
intake/
├── *.md                    # Files awaiting processing
├── bruba/                  # Bruba-specific imports
├── claude-projects/        # Claude Projects exports
├── voice/                  # Voice memo transcripts
└── processed/              # Originals after processing (archived)
```

### What Happens

1. Files land in `intake/` or subdirectories
2. `/intake` skill discovers them
3. Files WITH CONFIG block → Stage 3 (Canonicalize)
4. Files WITHOUT CONFIG block → Stage 2 (Convert)

### Supported Input Formats

**Claude Projects exports:**
```markdown
=== MESSAGE 1 | USER ===
User message content

=== MESSAGE 2 | ASSISTANT ===
Assistant response

=== EXPORT CONFIG ===
title: "..."
...
=== END CONFIG ===
```

- Delimited format with `=== MESSAGE N | ROLE ===` markers
- CONFIG block between `=== EXPORT CONFIG ===` markers
- Backmatter after `<!-- === BACKMATTER === -->`
- CONFIG can be at end (Claude Projects) or beginning (Bruba) — auto-detected

**Bruba/Clawdbot JSONL:**
```bash
# First convert JSONL to delimited markdown
python cli.py parse-jsonl session.jsonl -o intake/bruba/

# Then add CONFIG block via /convert skill
# Then canonicalize normally
```

JSONL filtering skips: session metadata, custom events, delivery-mirror duplicates, system messages, thinking blocks.

---

## Stage 2: Convert

The `/project:convert` skill adds CONFIG blocks to raw files.

**Input:** Raw file without CONFIG block
**Output:** File with CONFIG block ready for canonicalization

### What Convert Does

1. Analyzes content (conversation? notes? voice memo?)
2. Detects transcription issues (mishearings, dictation artifacts)
3. Identifies sensitive content
4. Generates CONFIG block with:
   - Metadata (title, slug, date, tags)
   - Transcription fixes
   - Sections to remove
   - Code block handling
   - Sensitivity definitions
5. Generates summary section

### File Handling

Convert does NOT edit in-place:

```
Before:  intake/raw-file.md
After:   intake/processed/original-raw-file.md  (preserved)
         intake/converted-raw-file.md           (ready for intake)
```

---

## Stage 3: Canonicalize

The `convo-processor canonicalize` command creates canonical files.

**Input:** File with CONFIG block
**Output:** Canonical file with rich frontmatter in `reference/transcripts/`

### What Canonicalize Does

1. Parses CONFIG block (YAML between `=== EXPORT CONFIG ===` markers)
2. Applies transcription corrections (`transcription.fixes_applied`)
3. Removes specified sections (`sections_remove`)
4. Cleans Bruba/Whisper artifacts (if applicable)
5. Generates canonical frontmatter from CONFIG
6. Writes to `reference/transcripts/YYYY-MM/transcript-{source}-{DD}-{topic}.md`

### Canonical File Naming

**Format:** `transcript-{source}-{DD}-{topic}.md`

| Source | Example Filename |
|--------|------------------|
| claude | `transcript-claude-26-voice-test.md` |
| bruba | `transcript-bruba-26-v2-migration.md` |
| manual | `transcript-manual-26-meeting-notes.md` |

Files live in `reference/transcripts/YYYY-MM/` directories, so the year-month is in the path.

### Canonical File Structure

```markdown
---
title: "Descriptive Title"
slug: 2026-01-26-topic-slug
date: 2026-01-26
source: claude
tags: [transcript, meta, internal]

transcription:
  fixes_applied:
    - original: "mishearing"
      corrected: "correct text"

sensitivity:
  terms:
    health: term1, term2
    names: Person Name
  sections:
    - start: "BEGIN SENSITIVE"
      end: "END SENSITIVE"
      tags: [health]
      description: "health discussion"
---

[Clean transcript content]

---

<!-- === BACKMATTER === -->

## Summary
...
```

### Processing Details

**Transcription Corrections:**
- Built-in corrections for common mishearings (ChatGPT, OpenAI, Lambda, SAML, etc.)
- Applied at canonicalize time
- Logged in frontmatter for auditability

**Section Removal:**
- Uses anchor-based identification (not line numbers)
- `start` and `end` are exact text matches with fuzzy fallback
- Anchors survive content edits, reflows, whitespace changes
- `description` preserved for documentation

**Code Block Handling:**
| Action | Result |
|--------|--------|
| `keep` | Preserved in all variants |
| `summarize` | Replaced with `[Code: {lines} lines {lang} - {description}]` |
| `extract` | Moved to separate file, reference inserted |
| `remove` | Removed entirely |

**Bruba/Whisper Cleanup:**
- Signal message wrappers stripped
- Whisper language detection noise removed
- Timestamp markers cleaned
- File system errors filtered

---

## Stage 4: Sync & Variants

The `/project:bundle` skill generates variants for each bundle. This is **deterministic Python** — no AI involved.

Note: `/project:sync` runs the full 6-step workflow (iCloud → bruba:pull → intake → bundle → bruba:push → iCloud). Use `/project:bundle` for bundle generation only.

**Input:** Canonical files in `reference/transcripts/`
**Output:** Redacted variants in `bundles/{bundle-name}/`

### What Sync Does

1. Loads bundle configuration from `config/bundles.yaml`
2. For each bundle:
   - Finds matching files based on tag filters (see [Bundle System](#bundle-system))
   - Generates variants with bundle-specific redaction (per `redaction` field)
   - Copies reference docs and prompts

### Variant Types

| Variant | Filename | Content |
|---------|----------|---------|
| Transcript | `transcript-{slug}.md` | Full cleaned transcript (redacted per profile) |
| Summary | `summary-{slug}.md` | Summary section from backmatter |

---

## Export CONFIG Reference

The CONFIG block is the source of truth for document processing. It's embedded in exported files and parsed during canonicalization.

### CONFIG Block Format

```yaml
=== EXPORT CONFIG ===
```yaml
# Required fields
title: "Human-Readable Title"
slug: YYYY-MM-DD-short-topic      # 3-5 word topic after date
date: YYYY-MM-DD
source: claude | bruba | manual   # determines filename prefix

# Tags for filtering
tags: [transcript, scope, internal]

# Transcription corrections (applied during canonicalize)
transcription:
  fixes_applied:
    - original: "mishearing text"
      corrected: "correct text"
      context: "optional context"

# Sections to remove entirely
sections_remove:
  - start: "exact anchor text where section begins"
    end: "exact anchor text where section ends"
    description: "reason for removal"
    replacement: "[Section removed: reason]"

# Code block handling
code_blocks:
  - id: 1
    language: python
    lines: 45
    description: "what this code does"
    action: keep | summarize | remove | extract

# Sensitivity definitions (see Sensitivity System section)
sensitivity:
  terms:
    health: [term1, term2]
    personal: [detail1]
    names: [Person Name, Company Name]
    financial: [$amount]
  sections:
    - start: "BEGIN SENSITIVE SECTION"
      end: "END SENSITIVE SECTION"
      tags: [health, personal]
      description: "description for replacement text"
```
=== END CONFIG ===
```

### Field Reference

| Field | Required | Purpose |
|-------|----------|---------|
| `title` | Yes | Human-readable document title |
| `slug` | Yes | URL-safe identifier, format: `YYYY-MM-DD-topic` |
| `date` | Yes | Document date |
| `source` | Yes | Origin: `claude-projects`, `bruba`, `voice`, `manual` |
| `tags` | Yes | Filtering tags (must include scope) |
| `transcription.fixes_applied` | No | Corrections applied during canonicalize |
| `sections_remove` | No | Anchor-based section removal |
| `code_blocks` | No | Per-block handling instructions |
| `sensitivity` | No | Redaction definitions (see below) |

### Source Values

The `source` field identifies where the conversation originated:

| Value | Meaning | Typical Intake Path |
|-------|---------|---------------------|
| `claude` | Claude Projects (claude.ai) | `intake/claude-projects/` |
| `bruba` | Bruba/Clawdbot sessions | `intake/bruba/` |
| `manual` | Manually created/pasted | `intake/` |
| `voice-memo` | Transcribed voice recording | `intake/voice/` |

The `/convert` skill infers source from the intake subdirectory when generating CONFIG blocks.

### Backmatter Format

Summary and continuation context go in **backmatter** (after main content), not in frontmatter YAML:

```markdown
---
# FRONTMATTER (metadata, sensitivity, etc.)
---

[MAIN CONTENT]

---

<!-- === BACKMATTER === -->

## Summary

Brief description of what was discussed...

## Continuation Context

Context for continuing the conversation later...
```

---

## Sensitivity System

The sensitivity system controls what content gets redacted and where. It operates at two levels:

1. **Definition** — What to redact (in canonical file frontmatter)
2. **Application** — Where to redact it (per-profile settings)

### Sensitivity Categories

Standard categories that can appear in `sensitivity.terms`:

| Category | Content Type | Example Terms |
|----------|--------------|---------------|
| `health` | Medical, mental health, medications | `Zoloft`, `therapy session`, `anxiety` |
| `personal` | Private details, relationships | `my cat`, `divorce`, `dating` |
| `names` | People and company names | `Dr. Smith`, `Acme Corp` |
| `financial` | Money, accounts, salaries | `$150k salary`, `account 1234` |

### Two Redaction Methods

#### 1. Term-Based Redaction

Individual words or phrases replaced with `[REDACTED]`.

**Definition (in CONFIG/frontmatter):**
```yaml
sensitivity:
  terms:
    health: Zoloft 50mg, anxiety, therapist
    names: Dr. Sarah Chen, Acme Corp
    personal: Mr. Whiskers, my cat
```

**Result (when category is in bundle's redaction list):**
```
Original: "I talked to Dr. Sarah Chen about my anxiety."
Redacted: "I talked to [REDACTED] about my [REDACTED]."
```

#### 2. Section-Based Redaction

Entire sections between anchors replaced with description.

**Definition (in CONFIG/frontmatter):**
```yaml
sensitivity:
  sections:
    - start: "BEGIN SENSITIVE HEALTH SECTION"
      end: "END SENSITIVE HEALTH SECTION"
      tags: [health, personal]
      description: "detailed health and therapy discussion"
```

**Result (when any tagged category is in bundle's redaction list):**
```
Original:
  BEGIN SENSITIVE HEALTH SECTION
  So I've been taking Zoloft for my anxiety...
  [multiple paragraphs of health discussion]
  END SENSITIVE HEALTH SECTION

Redacted:
  [Redacted: detailed health and therapy discussion]
```

### Sensitivity Tags vs Redaction Categories

**Important distinction:**

| Concept | Where Defined | Purpose |
|---------|---------------|---------|
| `sensitivity.terms` categories | Canonical frontmatter | WHAT can be redacted |
| `sensitivity.sections[].tags` | Canonical frontmatter | Which categories trigger section redaction |
| `redaction` | Bundle config (bundles.yaml) | WHICH categories TO redact for this bundle |

A term is only redacted if:
1. It's listed under a category in `sensitivity.terms`, AND
2. That category is in the bundle's `redaction` list

A section is only redacted if:
1. It has `tags` in `sensitivity.sections`, AND
2. ANY of those tags is in the bundle's `redaction` list

### Sensitivity in Frontmatter Format

After canonicalization, sensitivity appears in frontmatter:

```yaml
---
title: "Example Transcript"
# ... other fields ...

sensitivity:
  terms:
    health: Zoloft 50mg, anxiety, therapist, therapy session
    personal: Mr. Whiskers, my cat
    names: Dr. Sarah Chen, Acme Corp, Dr. Williams
  sections:
    - start: "BEGIN SENSITIVE HEALTH SECTION"
      end: "END SENSITIVE HEALTH SECTION"
      tags: [health, personal]
      description: "detailed health and therapy discussion"
---
```

**Note:** If there's no sensitive content, the `sensitivity` block is omitted entirely (no empty blocks).

---

## Bundle System

Bundles control **both file selection AND content redaction**. Each bundle defines which files to include (via tags) and what to redact within those files.

### Configuration Location

`config/bundles.yaml`

### Bundle Selection Logic

```python
# Pseudocode for file selection
def should_include_file(file_tags, bundle_config):
    include = bundle_config.get('include', {})
    exclude = bundle_config.get('exclude', {})

    # EXCLUDE: File rejected if ANY tag matches ANY exclude value
    for category, values in exclude.items():
        if any(tag in file_tags for tag in values):
            return False

    # INCLUDE: File must have AT LEAST ONE tag from EACH include category
    for category, values in include.items():
        if not any(tag in file_tags for tag in values):
            return False

    return True
```

### Bundle Configuration

```yaml
bundles:
  work:
    description: "Work-related content"
    output_dir: "bundles/work"
    include:
      scope: [work]                 # Must have work scope tag
    exclude:
      sensitivity: [nsfw]           # Reject if tagged nsfw
    redaction: [health, personal, names, financial]  # Categories to redact
    options:
      flatten: true
      include_prompts: true
      include_reference: true
      include_transcripts: true
```

### Current Bundles

| Bundle | Includes Scope | Excludes | Redacts |
|--------|----------------|----------|---------|
| `work` | work | nsfw | health, personal, names, financial |
| `home` | home | nsfw | health, financial |
| `personal` | personal | (nothing) | (nothing) |
| `meta` | meta | nsfw | (nothing) |
| `bruba` | meta, home, work | nsfw | names, health, financial, personal |

### File Selection vs Content Redaction

Both are configured in bundles.yaml, but serve different purposes:

| Field | Controls | Mechanism |
|-------|----------|-----------|
| `include`/`exclude` | Which FILES go to bundle | Tag-based filtering |
| `redaction` | What CONTENT is redacted | Category-based term/section replacement |

**Anti-pattern:** Don't use `exclude: sensitivity: [sensitive]` to filter sensitive content. That excludes entire FILES. Use `redaction` to handle sensitive CONTENT within files.

### How Redaction Works

1. `sync.py` loads bundle config from `bundles.yaml`
2. For each matching file, `redaction` categories passed to `convo-processor variants --redact`
3. Variant generation applies redaction based on canonical file's `sensitivity` block

### Redaction Flow

```
Canonical File                    Bundle Config               Output
─────────────                    ─────────────               ──────
sensitivity:                     redaction:
  terms:                           - health
    health: [Zoloft]      +        - names          →    [REDACTED] for both
    names: [Dr. Chen]              (personal not    →    [REDACTED]
    personal: [my cat]              listed)          →    my cat (kept)
```

---

## How It All Fits Together

### Complete Example

**1. Raw file arrives** (`intake/voice-memo.md`):
```
Hey, so I talked to Dr. Chen today about my Zoloft dosage...
```

**2. Convert adds CONFIG** (`intake/converted-voice-memo.md`):
```yaml
=== EXPORT CONFIG ===
title: "Health Discussion"
slug: 2026-01-26-health-discussion
tags: [transcript, personal, internal]
sensitivity:
  terms:
    health: Zoloft
    names: Dr. Chen
=== END CONFIG ===

Hey, so I talked to Dr. Chen today about my Zoloft dosage...
```

**3. Canonicalize creates canonical file** (`reference/transcripts/2026-01/transcript-claude-26-health-discussion.md`):
```yaml
---
title: "Health Discussion"
slug: 2026-01-26-health-discussion
tags: [transcript, personal, internal]
sensitivity:
  terms:
    health: Zoloft
    names: Dr. Chen
---

Hey, so I talked to Dr. Chen today about my Zoloft dosage...
```

**4. Sync generates variants per bundle:**

| Bundle | File Selection | Redaction | Output |
|--------|----------------|-----------|--------|
| personal | ✓ (scope: personal) | None | "...talked to Dr. Chen...Zoloft..." |
| work | ✗ (scope mismatch) | — | (not synced) |
| home | ✗ (scope mismatch) | — | (not synced) |

If the file had `tags: [transcript, work, internal]`:

| Bundle | File Selection | Redaction | Output |
|--------|----------------|-----------|--------|
| work | ✓ (scope: work) | health, names | "...talked to [REDACTED]...[REDACTED]..." |
| personal | ✗ (scope mismatch) | — | (not synced) |

### Decision Tree

```
File arrives in intake/
         │
         ▼
    Has CONFIG block?
     /          \
   Yes           No
    │             │
    ▼             ▼
Canonicalize    Convert
    │             │
    ▼             │
reference/       │
transcripts/     │
    │            │
    └──────┬─────┘
           │
           ▼
    For each bundle:
           │
           ▼
    Tags match include?
     /          \
   Yes           No
    │             │
    ▼             ▼
Tags match exclude?  Skip
     /          \
   Yes           No
    │             │
    ▼             ▼
  Skip        Apply bundle's
              redaction config
                   │
                   ▼
              Write to
              bundles/
```

---

## Quick Reference

### Skills

| Skill | Stage | Purpose |
|-------|-------|---------|
| `/project:convert` | 2 | Add CONFIG block to raw files |
| `/project:intake` | 3 | Canonicalize files with CONFIG |
| `/project:bundle` | 4 | Generate variants into bundles |
| `/project:sync` | All | Full workflow: iCloud → bruba:pull → intake → bundle → bruba:push → iCloud |

### Key Files

| File | Purpose |
|------|---------|
| `config/bundles.yaml` | Bundle definitions (file selection + redaction) |
| `tools/convo-processor/cli.py` | Processing tool |
| `.claude/commands/*.md` | Skill definitions |

### Commands

```bash
# Manual canonicalize
python tools/convo-processor/cli.py canonicalize intake/file.md -o reference/transcripts/2026-01/

# Manual variant generation with redaction
python tools/convo-processor/cli.py variants canonical.md -o /tmp/test/ --redact health,names

# Sync specific bundle
python scripts/sync.py --bundle work --verbose

# Dry run (preview)
python scripts/sync.py --dry-run
```

---

## CLI Reference

The `convo-processor` tool (`tools/convo-processor/cli.py`) provides the core processing commands.

### Commands

| Command | Purpose | Example |
|---------|---------|---------|
| `canonicalize` | Raw file → canonical | `cli.py canonicalize intake/file.md -o reference/transcripts/2026-01/` |
| `variants` | Canonical → transcript + summary | `cli.py variants canonical.md -o output/ --redact health,names` |
| `process` | Combined canonicalize + variants | `cli.py process intake/file.md -o output/` |
| `parse-jsonl` | JSONL → delimited markdown | `cli.py parse-jsonl session.jsonl -o parsed.md` |
| `parse` | Debug: show parsed CONFIG | `cli.py parse file.md` |

### Common Options

```bash
-o, --output DIR       # Output directory
--redact CATEGORIES    # Comma-separated redaction categories
--dry-run              # Preview without writing
-v, --verbose          # Detailed output
--no-summary           # Skip summary generation
--corrections FILE     # Custom corrections YAML file
```

### Examples

```bash
# Full intake workflow
cd tools/convo-processor
python cli.py canonicalize ../../intake/file.md -o ../../reference/transcripts/2026-01/

# Generate variants with work-profile redaction
python cli.py variants canonical.md -o /tmp/test/ --redact health,personal,names,financial

# Debug: see what CONFIG block was parsed
python cli.py parse intake/file.md

# Process Bruba JSONL session
python cli.py parse-jsonl ~/.clawdbot/agents/bruba-main/sessions/abc123.jsonl -o intake/bruba/
```

---

## Testing

See `docs/Testing.md` for complete testing documentation.

### Quick Test Run

```bash
cd tools/convo-processor
pytest -v
```

**Current status:** 74 tests, 9 fixtures

### Test Categories

1. **Canonicalization tests** — CONFIG parsing, transcription, frontmatter structure
2. **Variant tests** — Section removal, code blocks, lite generation
3. **Redaction tests** — Term-based, section-based, verify no leaks
4. **Round-trip tests** — Canonical → variants → should match expectations
5. **Edge cases** — Missing CONFIG, malformed anchors, nested code blocks

### Fixtures

Each fixture is a complete scenario in `tests/fixtures/`:

| Fixture | Focus |
|---------|-------|
| 001-ui-artifacts | UI/artifact config handling |
| 002-section-removal | Anchor-based removal |
| 003-transcription-corrections | Voice mishearing fixes |
| 004-code-blocks | All code block actions |
| 005-full-export | Complete export with all features |
| 006-v1-migration | Legacy format conversion |
| 007-paste-and-export | Paste workflow handling |
| 008-clawdbot-session | Bruba/Clawdbot format |
| 009-claude-projects | Claude Projects export |

---

## Appendix: Module Structure

```
tools/convo-processor/
├── cli.py                  # CLI entry point
├── src/
│   ├── models.py           # Data structures (DocumentConfig, etc.)
│   ├── parsing.py          # CONFIG block extraction and parsing
│   ├── canonicalize.py     # Step 1: raw → canonical
│   ├── variants.py         # Step 2: canonical → outputs
│   ├── redaction.py        # Sensitivity term/section redaction
│   ├── cleaning.py         # Bruba/Whisper artifact cleanup
│   ├── clawdbot_parser.py  # JSONL session preprocessing
│   ├── content.py          # Legacy v1 operations
│   └── output.py           # File writing utilities
├── config/
│   └── corrections.yaml    # Built-in transcription corrections
├── tests/
│   ├── test_parsing.py     # CONFIG parsing tests
│   ├── test_canonicalize.py
│   ├── test_variants.py
│   ├── test_clawdbot.py    # JSONL parser tests
│   └── fixtures/           # 9 test fixtures
│       └── FIXTURES.md     # Fixture documentation
└── prompts/
    └── export.md           # Export prompt template
```

### Key Dependencies

- **PyYAML** — YAML parsing for frontmatter and CONFIG
- **pytest** — Test framework
- Standard library only for core functionality

### Integration Points

| Script | How It Uses convo-processor |
|--------|----------------------------|
| `/project:intake` | Calls `canonicalize` on files with CONFIG |
| `/project:sync` | Calls `variants --redact` per bundle config |
| `/bruba:pull` | Calls `parse-jsonl` on Bruba sessions |
