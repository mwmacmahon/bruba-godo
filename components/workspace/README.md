# Workspace

Generated content paths and write permissions.

## What It Does

Documents the bot's workspace directory structure:
- `workspace/code/` — Scripts and tools for review
- `workspace/output/artifacts/` — Generated docs and data

Establishes that:
- All generated content goes to workspace
- Write permissions are scoped to this directory
- Human reviews and promotes files to production

## Status

**Prompt-Only** — No setup script, just prompt additions.

## Usage

Add `workspace` to your `agents_sections` in `config.yaml`:

```yaml
exports:
  bot:
    agents_sections:
      - header
      - workspace  # Add this
      # ...
```

Then run `/prompt-sync` to rebuild prompts.

## Files

- `prompts/AGENTS.snippet.md` — Workspace path conventions
