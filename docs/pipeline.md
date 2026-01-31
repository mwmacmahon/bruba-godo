---
type: doc
scope: reference
title: "Prompts and Distillation Pipeline"
description: "Content processing pipeline: intake to export"
---

# Prompts and Distillation Pipeline

Comprehensive documentation for the bruba-godo content processing pipeline.

---

## Overview

bruba-godo manages content flow between your operator machine and the bot. Two main pipelines:

```
┌─────────────────────────────────────────────────────────────────────┐
│ PROMPT PIPELINE (prompts → bot AGENTS.md)                          │
│                                                                     │
│   components/*/prompts/AGENTS.snippet.md                           │
│   templates/prompts/sections/*.md          ───► assemble ───► push │
│   mirror/prompts/AGENTS.md (bot sections)                          │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ CONTENT PIPELINE (conversations → bot memory)                       │
│                                                                     │
│   sessions/*.jsonl → intake/*.md → reference/ → exports/ → push    │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Configuration Files

### config.yaml (Connection Settings)

Bot connection and local directory settings. **Gitignored** - machine-specific.

```yaml
version: 2

ssh:
  host: bruba                    # SSH host from ~/.ssh/config

remote:
  home: /Users/bruba             # Bot's home directory
  workspace: /Users/bruba/clawd  # Bot's workspace
  clawdbot: /Users/bruba/.clawdbot
  agent_id: bruba-main

local:
  mirror: mirror                 # Local mirror of bot files
  sessions: sessions             # Raw JSONL session files
  logs: logs                     # Script logs
  intake: intake                 # Delimited markdown awaiting CONFIG
  reference: reference           # Canonical processed content
  exports: exports               # Filtered output for sync
  assembled: assembled           # Assembled prompts
```

### exports.yaml (Export Profiles)

Defines how content is filtered, redacted, and synced. **Committed** to repo.

```yaml
version: 1

exports:
  bot:
    description: "Content synced to bot memory"
    output_dir: exports/bot
    remote_path: memory
    include:
      scope: [meta, reference, transcripts]
      type: [prompt, doc, refdoc]
    exclude:
      sensitivity: [sensitive, restricted]
    redaction: [names, health]
    # Prompt assembly configuration
    agents_sections:
      - header
      - http-api
      - first-run
      - session
      - continuity
      - memory
      - distill
      - safety
      - bot:exec-approvals
      - external-internal
      - workspace
      - group-chats
      - tools
      - voice
      - heartbeats
      - signal
      - make-it-yours

  claude:
    description: "Prompts for Claude Projects / Claude Code"
    output_dir: exports/claude
    include:
      type: [prompt, doc, refdoc]
      scope: [meta, reference, transcripts]

  tests:
    description: "Local testing profile"
    output_dir: exports/tests
    include:
      type: [prompt]
      scope: [meta, reference, transcripts]

defaults:
  redaction: []
```

---

## Skills Reference

### Daemon Management

| Skill | Command | Purpose |
|-------|---------|---------|
| `/status` | `./tools/bot clawdbot status` | Show daemon state |
| `/launch` | `./tools/bot clawdbot launch` | Start daemon |
| `/stop` | `./tools/bot clawdbot stop` | Stop daemon |
| `/restart` | `./tools/bot clawdbot restart` | Restart daemon |

### File Sync

| Skill | Command | Purpose |
|-------|---------|---------|
| `/mirror` | `./tools/mirror.sh` | Pull bot files to local mirror/ |
| `/pull` | `./tools/pull-sessions.sh` | Pull closed sessions → intake/ |
| `/push` | `./tools/push.sh` | Sync exports/bot/ → bot memory/ |

### Content Processing

| Skill | Command | Purpose |
|-------|---------|---------|
| `/convert` | AI-assisted | Add CONFIG block to intake file |
| `/intake` | `python3 -m components.distill.lib.cli canonicalize` | Process intake → reference |
| `/export` | `python3 -m components.distill.lib.cli export` | Generate filtered exports |

### Prompt Management

| Skill | Command | Purpose |
|-------|---------|---------|
| `/prompt-sync` | `./tools/assemble-prompts.sh && push` | Full prompt sync |
| `/prompts` | Help skill | Explain/troubleshoot prompt system |

### Combined Operations

| Skill | Command | Purpose |
|-------|---------|---------|
| `/sync` | Full pipeline | Mirror + pull + process + export + push |

### Other

| Skill | Command | Purpose |
|-------|---------|---------|
| `/config` | Edit configs | Configure heartbeat, exec allowlist |
| `/component` | Component management | Enable/disable components |
| `/update` | Update clawdbot | Update bot software |
| `/code` | Code review | Review and migrate staged code |
| `/convo` | Load conversation | Load active bot conversation |

---

## Content Pipeline Detail

### Stage 1: Pull Sessions

```bash
/pull
```

1. Lists closed sessions on bot
2. Downloads JSONL to `sessions/`
3. Converts to delimited markdown in `intake/`
4. Records pulled sessions in `sessions/.pulled`

### Stage 2: Add CONFIG Block

```bash
/convert <file>
```

AI-assisted analysis of intake file to add frontmatter + backmatter CONFIG block.

**Frontmatter controls export routing:**

| type | Output directory | Prefix |
|------|-----------------|--------|
| `doc` | `exports/bot/docs/` | `Doc - ` |
| `refdoc` | `exports/bot/refdocs/` | `Refdoc - ` |
| `transcript` | `exports/bot/transcripts/` | `Transcript - ` |
| `prompt` | `exports/bot/prompts/` | `Prompt - ` |

Example frontmatter for a doc:
```yaml
---
type: doc
scope: reference
title: "My Document"
---
```

Example frontmatter for a transcript:
```yaml
---
title: "Pipeline Work Session"
slug: 2026-01-31-pipeline-work
date: 2026-01-31
source: claude
tags: [export-pipeline, testing]
---
```

### Stage 3: Canonicalize

```bash
/intake
```

Processes files with CONFIG blocks:
- Moves to `reference/transcripts/`
- Applies corrections from `components/distill/config/corrections.yaml`
- Original moved to `intake/processed/`

### Stage 4: Export

```bash
/export
```

Generates filtered exports per profile:
- Reads `exports.yaml` profiles
- Applies include/exclude filters
- Applies redaction rules
- Outputs to `exports/<profile>/`

### Stage 5: Push

```bash
/push
```

Syncs `exports/bot/` subdirectories to appropriate remote locations:
- `core-prompts/` → `~/clawd/` (workspace root)
- `prompts/` → `~/clawd/memory/prompts/`
- `transcripts/` → `~/clawd/memory/transcripts/`
- `refdocs/` → `~/clawd/memory/refdocs/`
- `docs/` → `~/clawd/memory/docs/`
- Triggers memory reindex on bot

---

## Prompt Pipeline Detail

### How Assembly Works

The `agents_sections` list in `exports.yaml` defines section order:

```yaml
agents_sections:
  - header              # → templates/prompts/sections/header.md
  - http-api            # → components/http-api/prompts/AGENTS.snippet.md
  - bot:exec-approvals  # → mirror's <!-- BOT-MANAGED: exec-approvals -->
```

Resolution order for each entry:
1. `bot:` prefix → bot-managed section from mirror
2. Component match → `components/{name}/prompts/AGENTS.snippet.md`
3. Template match → `templates/prompts/sections/{name}.md`
4. Error if not found

### Running Assembly

```bash
./tools/assemble-prompts.sh           # Basic assembly
./tools/assemble-prompts.sh --verbose # Show section resolution
./tools/assemble-prompts.sh --dry-run # Preview without writing
```

### Section Markers

Assembled output includes markers for debugging:

```markdown
<!-- COMPONENT: voice -->
...component content...
<!-- /COMPONENT: voice -->

<!-- BOT-MANAGED: exec-approvals -->
...bot's content...
<!-- /BOT-MANAGED: exec-approvals -->
```

### Conflict Detection

```bash
./tools/detect-conflicts.sh
```

Detects:
- New bot sections not in config
- Modified components (bot edited)
- Missing sections

---

## Directory Structure

```
bruba-godo/
├── config.yaml              # Connection settings (gitignored)
├── config.yaml.example      # Template for config.yaml
├── exports.yaml             # Export profiles + agents_sections
│
├── components/              # COMMITTED - Component definitions
│   ├── distill/
│   │   ├── prompts/         # Exportable prompts (Export.md, Transcription.md)
│   │   ├── config/          # corrections.yaml
│   │   └── lib/             # Python processing code
│   ├── voice/
│   │   └── prompts/         # AGENTS.snippet.md
│   └── .../
│
├── templates/               # COMMITTED - Base prompt templates
│   ├── prompts/
│   │   ├── sections/        # header.md, safety.md, etc.
│   │   └── README.md
│   └── config/
│
├── user/                    # GITIGNORED - Personal customizations
│   ├── prompts/
│   └── exports.yaml
│
├── mirror/                  # GITIGNORED - Local copy of bot files
│   └── prompts/AGENTS.md
│
├── sessions/                # GITIGNORED - Raw JSONL from bot
├── intake/                  # GITIGNORED - Awaiting CONFIG
├── reference/               # GITIGNORED - Canonical content
│   ├── transcripts/
│   └── refdocs/
├── exports/                 # GITIGNORED - Filtered output
│   ├── bot/
│   │   ├── core-prompts/    # AGENTS.md → syncs to ~/clawd/
│   │   ├── prompts/         # Prompt - *.md → ~/clawd/memory/prompts/
│   │   ├── transcripts/     # Transcript - *.md → ~/clawd/memory/transcripts/
│   │   ├── refdocs/         # Refdoc - *.md → ~/clawd/memory/refdocs/
│   │   └── docs/            # Doc - *.md → ~/clawd/memory/docs/
│   └── claude/
│       └── prompts/         # Prompt - *.md for Claude Projects/Code
│
├── tools/                   # COMMITTED - Shell scripts
├── .claude/commands/        # COMMITTED - Skill definitions
├── docs/                    # COMMITTED - Documentation
└── tests/                   # COMMITTED - Test suite
```

---

## Common Workflows

### Full Sync (Everything)

```bash
/sync
# Or manually:
./tools/mirror.sh
./tools/pull-sessions.sh
# ... process intake files ...
python3 -m components.distill.lib.cli export --profile bot
./tools/push.sh
```

### Prompt-Only Sync

```bash
/prompt-sync
# Or manually:
./tools/mirror.sh
./tools/assemble-prompts.sh
./tools/push.sh
```

### Process New Sessions

```bash
/pull                    # Get sessions from bot
/convert intake/file.md  # Add CONFIG block
/intake                  # Canonicalize
/export                  # Generate exports
/push                    # Sync to bot
```

### Add New Component

1. Create `components/{name}/prompts/AGENTS.snippet.md`
2. Add `{name}` to `exports.yaml` → `agents_sections` at desired position
3. Run `/prompt-sync`

### Keep Bot's Section Changes

When bot modifies a section and you want to keep it:

1. Ensure bot wrapped section with `<!-- BOT-MANAGED: name -->`
2. Change `name` to `bot:name` in `exports.yaml` agents_sections
3. Run `/prompt-sync`

---

## Troubleshooting

### "No sections found in exports.yaml"

The `agents_sections` key is missing from exports.yaml under the bot profile.

### Assembly Missing Section

Check resolution order:
1. For `bot:X` - does mirror have `<!-- BOT-MANAGED: X -->`?
2. For component - does `components/X/prompts/AGENTS.snippet.md` exist?
3. For template - does `templates/prompts/sections/X.md` exist?

### Export Not Including Files

Check frontmatter matches profile filters:
- `type` must match `include.type` (e.g., `doc`, `refdoc`, `prompt`)
- `scope` must match `include.scope` (e.g., `reference`, `meta`, `transcripts`)
- `sensitivity` must not match `exclude.sensitivity`

### Export Going to Wrong Directory

The `type` field in frontmatter controls output routing:
- `type: doc` → `docs/` with `Doc - ` prefix
- `type: refdoc` → `refdocs/` with `Refdoc - ` prefix
- `type: transcript` → `transcripts/` with `Transcript - ` prefix

If files go to wrong directory, check frontmatter has correct `type` field.

### Push Not Syncing

1. Verify `config.yaml` exists with SSH settings
2. Run `./tools/bot echo test` to verify connection
3. Check `exports/bot/` has files to sync

---

## Testing

```bash
# Python tests (variants, canonicalization)
python3 tests/run_tests.py -v

# Shell tests (export prompts)
./tests/test-export-prompts.sh

# Shell tests (prompt assembly)
./tests/test-prompt-assembly.sh --quick

# E2E pipeline test (intake → reference → exports)
./tests/test-e2e-pipeline.sh

# Full test suite
python3 tests/run_tests.py -v && \
  ./tests/test-export-prompts.sh && \
  ./tests/test-prompt-assembly.sh --quick && \
  ./tests/test-e2e-pipeline.sh
```

---

## Related Documentation

- `templates/prompts/README.md` - Detailed prompt assembly docs
- `tests/README.md` - Testing documentation
- `CLAUDE.md` - Quick reference for Claude Code
