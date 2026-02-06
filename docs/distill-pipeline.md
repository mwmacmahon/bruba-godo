---
type: doc
scope: reference
title: "Distill Pipeline Reference"
tags: [bruba, distill, content-pipeline, architecture]
---

# Distill Pipeline Reference

Distill is the core differentiator of bruba-godo. Without it, the system is "OpenClaw installer with SSH access." With it, **conversations become searchable knowledge that feeds back to the bot**.

## Pipeline Overview

```
Bot sessions (JSONL)
  ↓ parse-jsonl (automatic with /pull)
agents/{agent}/intake/*.md (delimited markdown, no CONFIG)
  ↓ /convert (AI-assisted, context-isolated)
  │  1. Removes noise (heartbeats, exec denials, system errors)
  │  2. Marks content in CONFIG (sections_remove, sensitivity)
  │  3. Adds backmatter summary
agents/{agent}/intake/*.md (has CONFIG block)
  ↓ /intake (canonicalize, NOT AI)
  │  - CONFIG → YAML frontmatter
  │  - Applies corrections.yaml
  │  - Strips Signal/Telegram wrappers
  │  - Content stays intact (marks are in frontmatter only)
reference/transcripts/*.md (canonical with YAML frontmatter)
  ↓ /export (NOT AI)
  │  - Applies sections_remove (actually removes content)
  │  - Applies redaction per profile
  │  - Filters by type/tags/agents/users
  │  - Stale file reconciliation
agents/{agent}/exports/ + exports/claude-*/ (filtered, redacted)
  ↓ /push
Bot memory (per agent)
```

## CLI Commands

All commands run from the bruba-godo root via `python -m components.distill.lib.cli`.

### parse-jsonl

Convert raw OpenClaw JSONL sessions to delimited markdown.

```bash
python -m components.distill.lib.cli parse-jsonl sessions/*.jsonl -o intake/
```

### split

Split large files along message boundaries. Automatic during `/intake` for files over 60k chars.

```bash
python -m components.distill.lib.cli split intake/large-file.md -o intake/ --max-chars 60000
```

### canonicalize

Transform delimited markdown (with CONFIG block) into canonical format with YAML frontmatter.

```bash
python -m components.distill.lib.cli canonicalize intake/*.md -o reference/transcripts/ \
    -c components/distill/config/corrections.yaml --agent bruba-main
```

Options:
- `-o` — Output directory
- `-c` — Path to corrections.yaml
- `-m` — Move source files to this directory after success
- `-a` / `--agent` — Agent name for frontmatter routing

### variants

Generate transcript and summary variants with redaction.

```bash
python -m components.distill.lib.cli variants reference/transcripts/ -o exports/ \
    --redact health,names
```

### export

Generate filtered exports per config.yaml profiles. The primary command for the export step.

```bash
python -m components.distill.lib.cli export --verbose
python -m components.distill.lib.cli export --profile claude-gus --verbose
python -m components.distill.lib.cli export --profile agent:bruba-rex --verbose
```

### parse

Debug command — show parsed CONFIG/frontmatter from a file.

```bash
python -m components.distill.lib.cli parse intake/some-file.md
```

### auto-config

Generate CONFIG block automatically (non-interactive mode for cron).

```bash
python -m components.distill.lib.cli auto-config intake/file.md
```

## Data Model: CanonicalConfig

The `CanonicalConfig` dataclass (`components/distill/lib/models.py`) is the V2 frontmatter schema for canonical files.

### Identity Fields

| Field | Type | Description |
|-------|------|-------------|
| `title` | str | Conversation/document title |
| `slug` | str | URL-safe identifier (e.g., `2026-01-24-topic-slug`) |
| `date` | str | YYYY-MM-DD |
| `source` | str | `claude`, `bruba`, `claude-projects`, `claude-code`, `voice-memo`, `manual` |
| `tags` | List[str] | Categorization tags |
| `type` | str | `doc`, `refdoc`, `transcript`, `prompt`, `artifact`, `claude_code_log` |
| `scope` | str | *(Legacy, not used for filtering)* `reference`, `meta`, `transcripts` |
| `description` | str | One-line summary for inventory display |

### Routing Fields

| Field | Type | Description |
|-------|------|-------------|
| `users` | List[str] | Which human's profiles receive this file. Also auto-derives agent routing. |
| `agents` | List[str] | *(Optional override)* Which bot agents receive this file. Auto-derived from `users` if omitted. |

### Processing Fields

| Field | Type | Description |
|-------|------|-------------|
| `sections_remove` | List[SectionSpec] | Anchor-based section removal |
| `sections_lite_remove` | List[SectionSpec] | Lighter removal (with replacement text) |
| `code_blocks` | List[CodeBlockSpec] | Code block processing instructions |
| `transcription_fixes_applied` | List[TranscriptionFix] | Applied corrections |
| `sensitivity` | Sensitivity | Term-level and section-level sensitivity markers |

## Frontmatter Reference

Canonical files use YAML frontmatter with these fields:

```yaml
---
title: "Conversation Title"
slug: 2026-01-28-topic-slug
date: 2026-01-28
source: bruba
description: "One-line summary"
tags: [voice, technical]
type: transcript
users: [gus]                  # Routes to gus's profiles + auto-derives agents: [bruba-main]
# agents: [bruba-main]       # Optional — auto-derived from users

sections_remove:
  - start: "First words of section..."
    end: "End of section..."
    description: "Debugging tangent"

sensitivity:
  terms:
    names: [Michael]
    health: [condition]
  sections:
    - start: "Start of sensitive section..."
      end: "End of sensitive section..."
      tags: [health]
---
```

### Users Field

Controls per-user document routing:

| Value | Meaning |
|-------|---------|
| *(empty/omitted)* | Goes to everyone |
| `[gus]` | Only Gus's agents and profiles |
| `[rex]` | Only Rex's agents and profiles |
| `[gus, rex]` | Both users |
| `[only-gus]` | Exclusively Gus — profiles with multiple users are excluded |

## Configuration

### corrections.yaml

Voice transcription fixes applied during canonicalization.

```yaml
# components/distill/config/corrections.yaml
corrections:
  - pattern: "bruba godo"
    replacement: "bruba-godo"
  - pattern: "clod bot"
    replacement: "Clawdbot"
```

### Export Profiles (config.yaml)

Agent profiles are auto-generated from agents with `content_pipeline: true`. Standalone profiles are defined in the `exports:` section.

```yaml
agents:
  bruba-main:
    content_pipeline: true
    include:
      type: [prompt, doc, refdoc]
      users: [gus]
    exclude:
      sensitivity: [sensitive, restricted]
      tags: [legacy, do-not-sync]
    redaction: [names, health]

exports:
  claude-gus:
    include:
      type: [prompt, doc, refdoc]
      users: [gus]
    exclude:
      sensitivity: [sensitive, restricted]
      tags: [legacy, do-not-sync]
    redaction: [names, health]
```

### Filter Rules

The export system has **two distinct paths** with different filtering logic: standalone profiles (e.g. `claude-gus`) and agent profiles (e.g. `bruba-main`). Understanding the difference is critical for getting files to route correctly.

#### Standalone Profile Path (`exports:` in config.yaml)

Standalone profiles (e.g. `claude-gus`, `claude-rex`) apply **one filter pass** using `_matches_filters()`:

1. Check `exclude.sensitivity` — reject if file has excluded sensitivity tags
2. Check `exclude.tags` — reject if file has any excluded tags
3. Check `include.type` — file's `type` must be in the list (e.g. `[prompt, doc, refdoc]`)
4. Check `include.tags` — file must have at least one listed tag (if specified)
5. Check `include.users` — file's `users` must match profile's `users`

If all checks pass, the file is exported.

#### Agent Profile Path (agents with `content_pipeline: true`)

Agent profiles (e.g. `bruba-main`, `bruba-rex`) apply **two filter passes**:

**Pass 1: Agent routing** — Determines which agents should see this file:
- Explicit `agents` field → used as-is
- No `agents`, has `users` → auto-derived from user→agent mapping in config (e.g. `users: [rex]` → `agents: [bruba-rex]`)
- No `agents`, no `users` → defaults to `['bruba-main']` with a warning

**Pass 2: Include/exclude filters** — Same `_matches_filters()` as standalone profiles. This is where `type`, `tags`, and `users` are checked against the agent's config.

Both passes must succeed for the file to be exported.

#### What Each Filter Does

| Filter | Purpose | Example |
|--------|---------|---------|
| `users` | **Who is this for?** Routes to the right human's profiles. | `users: [gus]` → only gus's profiles |
| `agents` | **Which bot agents?** Optional override for agent routing. Usually auto-derived from `users`. | `agents: [bruba-main, bruba-rex]` |
| `type` | **What kind of content?** Each profile picks which types it wants. | bruba-main accepts `[prompt, doc, refdoc]` but not `transcript` |
| `tags` | **Exclusion only.** Keeps out unwanted content categories. | `exclude.tags: [legacy, do-not-sync]` |
| `sensitivity` | **Exclusion only.** Redacts or skips sensitive content. | `exclude.sensitivity: [sensitive, restricted]` |

#### Frontmatter Fields for Filtering

| Frontmatter Field | Required? | Used By | Purpose |
|-------------------|-----------|---------|---------|
| `type` | Yes | Both paths | Content type: `doc`, `refdoc`, `transcript`, `prompt`, `artifact`, `claude_code_log` |
| `users` | Recommended | Both paths | Which human's profiles receive the file. Auto-derives agent routing. |
| `tags` | Optional | Both paths | Freeform categorization tags |
| `agents` | Optional | Agent path only | Override: which bot agents receive the file. Auto-derived from `users` if omitted. |
| `sensitivity` | Optional | Both paths (exclude) | Section/term-level sensitivity markers |

#### Filter Summary Table

| Filter | Section | Behavior |
|--------|---------|----------|
| `include.type` | include | File must match one of the listed types |
| `include.tags` | include | File must have at least one listed tag |
| `include.users` | include | File's `users` must match profile's `users` (see user semantics) |
| `exclude.sensitivity` | exclude | Skip files with these sensitivity levels |
| `exclude.tags` | exclude | Skip files with any of these tags |

#### Users Field Semantics

The `users` field on files controls per-user document routing. Matching logic in `_matches_user_filter()`:

| File `users` | Profile `include.users` | Result | Why |
|-------------|------------------------|--------|-----|
| *(empty)* | anything | **Match** | No users = goes to everyone |
| anything | *(empty)* | **Match** | Profile accepts all users |
| `[gus]` | `[gus]` | **Match** | Intersection: `{gus} & {gus}` |
| `[gus, rex]` | `[gus]` | **Match** | Intersection: `{gus, rex} & {gus} = {gus}` |
| `[gus, rex]` | `[rex]` | **Match** | Intersection: `{gus, rex} & {rex} = {rex}` |
| `[gus]` | `[rex]` | **No match** | No intersection |
| `[only-gus]` | `[gus]` | **Match** | Subset: `{gus} ⊆ {gus}` |
| `[only-gus]` | `[gus, rex]` | **No match** | Not subset: `{gus, rex} ⊄ {gus}` |

The `only-` prefix means "exclusively this user" — profiles serving multiple users won't receive it.

#### How Routing Works: `users` is All You Need

In most cases, **you only need to set `users`**. The export system auto-derives which agents to route to based on the `identity.human_name` mapping in config.yaml:

| `identity.human_name` | Agent | Result |
|------------------------|-------|--------|
| `"Gus"` | `bruba-main` | `users: [gus]` → routes to bruba-main |
| `"Rex"` | `bruba-rex` | `users: [rex]` → routes to bruba-rex |

**Resolution order for agent routing:**
1. Explicit `agents` field in frontmatter (if present, used as-is)
2. Auto-derived from `users` field via user→agent mapping
3. Default: `['bruba-main']` with a warning (if neither field is set — add `users` to fix)

**Example: Route a refdoc to both Gus and Rex:**
```yaml
---
type: refdoc
users: [gus, rex]
---
```

This reaches all 4 targets automatically:
- `claude-gus` — standalone profile, `users` matches gus
- `claude-rex` — standalone profile, `users` matches rex
- `bruba-main` — auto-derived from `users` (gus → bruba-main), then `users` filter passes
- `bruba-rex` — auto-derived from `users` (rex → bruba-rex), then `users` filter passes

**Example: Route only to Gus (most common case):**
```yaml
---
type: refdoc
users: [gus]
---
```

**The `agents` field is optional** — only needed to override auto-derivation. For example, to send a gus-specific file to bruba-rex too:
```yaml
---
users: [gus]
agents: [bruba-main, bruba-rex]   # Override: also send to rex's agent
---
```

### Variant Generation

The `variants` command generates different versions of canonical files:

- **Transcript variant** — Full conversation with sections_remove applied
- **Summary variant** — Backmatter summary only
- **Redacted variant** — Sensitivity terms replaced per redaction categories

### Redaction Categories

| Category | Examples |
|----------|----------|
| `names` | Personal names, companies |
| `health` | Medical conditions, medications |
| `personal` | Private life, relationships |
| `financial` | Dollar amounts, accounts |

## File Splitting

Files over 60,000 characters are split along message boundaries during `/intake`.

- **Threshold:** 60,000 characters (configurable with `--max-chars`)
- **Minimum:** 5 messages per chunk (configurable with `--min-messages`)
- **Splits on:** `=== MESSAGE N | ROLE ===` boundaries only
- **Output:** Each chunk gets updated slug (`-part-N`), part metadata, continuation notes

## Directory Structure

```
components/distill/
├── README.md
├── setup.sh / validate.sh
├── config/
│   └── corrections.yaml
├── prompts/
│   ├── AGENTS.snippet.md
│   ├── Export.md
│   └── Transcription.md
└── lib/
    ├── cli.py              # CLI entry point + export logic
    ├── clawdbot_parser.py  # JSONL → delimited markdown
    ├── models.py           # Data classes (CanonicalConfig, etc.)
    ├── parsing.py          # CONFIG/frontmatter extraction
    ├── canonicalize.py     # Delimited → canonical with frontmatter
    ├── splitting.py        # Large file splitting
    ├── variants.py         # Variant generation + redaction
    ├── content.py          # Content manipulation utilities
    └── output.py           # Output formatting
```

## Related Skills

- `/pull` — Pull sessions + auto-convert to intake/
- `/convert` — AI-assisted CONFIG generation (context-isolated)
- `/intake` — Batch canonicalization
- `/export` — Generate filtered exports
- `/push` — Push to bot memory
