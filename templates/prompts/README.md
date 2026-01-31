# Prompt Assembly System

This document explains how bot prompts (like AGENTS.md) are assembled from modular sections.

## Overview

The prompt assembly system uses **config-driven section ordering**:

- **Config defines order** — `config.yaml` lists sections in the exact order they appear
- **Three section types** — components, template sections, and bot-managed
- **Bot sections preserve position** — bot's own additions stay where they belong
- **Conflict detection** — automatically detects when bot adds/edits content

## Quick Start

```bash
# Check current state
./tools/detect-conflicts.sh

# Assemble prompts
./tools/assemble-prompts.sh

# Full sync (mirror → detect → assemble → push)
# Use /sync skill for guided process
```

## Section Types

| Type | Prefix | Source | Who Controls |
|------|--------|--------|--------------|
| Component | (none) | `components/{name}/prompts/AGENTS.snippet.md` | Operator |
| Template section | (none) | `templates/prompts/sections/{name}.md` | Operator |
| Bot-managed | `bot:` | Mirror's `<!-- BOT-MANAGED: name -->` blocks | Bot |

### Resolution Order

For each entry in `agents_sections`, the assembler checks:

1. **`bot:name`** → Extract from mirror's BOT-MANAGED sections
2. **Component** → `components/{name}/prompts/AGENTS.snippet.md`
3. **Template section** → `templates/prompts/sections/{name}.md`
4. **Error** if not found

## Config Structure

```yaml
# config.yaml
agents_sections:
  - header                # Template section (title + intro)
  - http-api              # Component (Message Triggers, HTTP API)
  - first-run             # Template section
  - session               # Component (Every Session, Greeting)
  - continuity            # Component
  - memory                # Component
  - distill               # Component (PKM resources)
  - safety                # Template section
  - bot:exec-approvals    # Bot-managed (preserved from remote)
  - bot:packets           # Bot-managed (preserved from remote)
  - external-internal     # Template section
  - workspace             # Component
  - group-chats           # Component
  - tools                 # Template section
  - voice                 # Component
  - heartbeats            # Component
  - signal                # Component
  - make-it-yours         # Template section
```

## File Structure

```
bruba-godo/
├── config.yaml                              # Section order defined here
├── templates/prompts/
│   ├── sections/                            # Template sections
│   │   ├── header.md
│   │   ├── first-run.md
│   │   ├── safety.md
│   │   ├── external-internal.md
│   │   ├── tools.md
│   │   └── make-it-yours.md
│   └── README.md                            # This file
├── components/
│   ├── session/prompts/AGENTS.snippet.md
│   ├── memory/prompts/AGENTS.snippet.md
│   ├── heartbeats/prompts/AGENTS.snippet.md
│   ├── group-chats/prompts/AGENTS.snippet.md
│   ├── workspace/prompts/AGENTS.snippet.md
│   ├── voice/prompts/AGENTS.snippet.md
│   ├── http-api/prompts/AGENTS.snippet.md
│   ├── distill/prompts/AGENTS.snippet.md
│   ├── continuity/prompts/AGENTS.snippet.md
│   └── signal/prompts/AGENTS.snippet.md
├── mirror/prompts/AGENTS.md                 # Remote state (has BOT-MANAGED sections)
├── exports/bot/core-prompts/AGENTS.md       # Assembled output
└── tools/
    ├── assemble-prompts.sh                  # Build assembled from config
    └── detect-conflicts.sh                  # Find new bot sections / edits
```

## Assembly Process

```bash
./tools/assemble-prompts.sh [--verbose] [--dry-run] [--force]
```

**Important:** Assembly automatically blocks if conflicts are detected. Use `--force` to override (overwrites bot changes).

1. Read `agents_sections` list from `exports.yaml` (under bot profile)
2. For each entry in order:
   - `bot:name` → extract from mirror's `<!-- BOT-MANAGED: name -->` blocks
   - Otherwise → try component, then template section
3. Wrap each section with markers
4. Write to `exports/bot/core-prompts/AGENTS.md`

## Conflict Detection

```bash
./tools/detect-conflicts.sh [--verbose]
./tools/detect-conflicts.sh --show-section NAME
./tools/detect-conflicts.sh --diff NAME
```

Detects:
- **New bot sections:** BOT-MANAGED blocks in mirror not in config
- **Bot edits:** Component content differs from mirror

### When Bot Adds a Section

1. Bot wraps new content with `<!-- BOT-MANAGED: name -->` on remote
2. You run `/mirror` to pull changes
3. `detect-conflicts.sh` reports: "New bot section: name"
4. You decide:
   - **Keep:** Add `bot:name` to config at correct position
   - **Discard:** Section removed on next push

### When Bot Edits a Component

1. Bot modifies content within a component section on remote
2. `detect-conflicts.sh` reports content differs
3. You decide:
   - **Keep bot's version:** Change `name` to `bot:name` in config, ensure mirror has BOT-MANAGED markers
   - **Use component:** Bot's changes overwritten on push

## Markers in Output

The assembled output includes markers for tracking:

```markdown
<!-- SECTION: header -->
# AGENTS.md - Your Workspace
This folder is home. Treat it that way.
<!-- /SECTION: header -->

<!-- COMPONENT: session -->
## Every Session
...content...
<!-- /COMPONENT: session -->

<!-- BOT-MANAGED: exec-approvals -->
## Exec Approvals
...bot's content...
<!-- /BOT-MANAGED: exec-approvals -->
```

## Common Operations

### Reorder Sections

Edit `agents_sections` in `config.yaml`:

```yaml
agents_sections:
  - header
  - session        # moved up
  - http-api       # moved down
```

### Disable a Section

Comment it out:

```yaml
agents_sections:
  - header
  # - http-api     # disabled
  - first-run
```

### Add a New Component

1. Create `components/my-component/prompts/AGENTS.snippet.md`
2. Add `my-component` to `agents_sections` at desired position
3. Run assembly

### Add a New Template Section

1. Create `templates/prompts/sections/my-section.md`
2. Add `my-section` to `agents_sections`
3. Run assembly

### Accept a Bot Section

When bot adds something you want to keep:

1. Run `./tools/detect-conflicts.sh` to see new sections
2. Add `bot:section-name` to config at reported position
3. Run assembly

### Convert Component to Bot-Managed

If bot customized a component and you want to preserve it:

1. Ensure mirror has `<!-- BOT-MANAGED: name -->` markers around content
2. Change `name` to `bot:name` in config
3. Run assembly (content now comes from mirror)

## Commands Reference

| Command | Description |
|---------|-------------|
| `./tools/assemble-prompts.sh` | Assemble AGENTS.md from config |
| `./tools/assemble-prompts.sh --verbose` | Show detailed output |
| `./tools/assemble-prompts.sh --dry-run` | Preview without writing |
| `./tools/assemble-prompts.sh --force` | Skip conflict check (overwrites bot changes) |
| `./tools/detect-conflicts.sh` | Check for new bot sections / edits |
| `./tools/detect-conflicts.sh --show-section X` | Show bot section content |
| `./tools/detect-conflicts.sh --diff X` | Diff component vs mirror |
| `./tools/mirror.sh` | Pull remote to local mirror |

## Skills

| Skill | Purpose |
|-------|---------|
| `/sync` | Full sync workflow with conflict detection |
| `/prompts` | Explain system, resolve conflicts, manage sections |
| `/mirror` | Pull remote files |
| `/push` | Push to remote |

## Troubleshooting

### "Missing section: X"

The entry in config doesn't resolve to anything:
- Bot section? → needs `bot:` prefix AND `<!-- BOT-MANAGED: X -->` in mirror
- Component? → needs `components/X/prompts/AGENTS.snippet.md`
- Template? → needs `templates/prompts/sections/X.md`

### Bot Section Not Appearing

1. Check mirror: `grep "BOT-MANAGED" mirror/prompts/AGENTS.md`
2. Check config has `bot:name` entry
3. Run `/mirror` to refresh

### Section in Wrong Position

Edit `agents_sections` in config, move entry to desired line.

### Conflict Detection Shows False Positive

If a "new" bot section is already in config:
- Check spelling matches exactly
- Check `bot:` prefix is present in config

## Testing

Run the test suite to verify the assembly system works correctly:

```bash
# Run all tests (requires SSH connectivity)
./tests/test-prompt-assembly.sh

# Quick mode (no SSH, skips sync cycle)
./tests/test-prompt-assembly.sh --quick

# Verbose output
./tests/test-prompt-assembly.sh --verbose
```

Tests cover:
- Basic assembly (section counts, order, bot sections)
- Conflict detection (no false positives)
- Bot section simulation (detection → config add → assembly)
- Component edit detection (single and multiple components)
- Full sync cycle (push → mirror → compare)

See `tests/prompt-assembly-tests.md` for detailed test protocols.
