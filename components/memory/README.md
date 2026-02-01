# Memory

Memory management workflow and file conventions.

## What It Does

Establishes the bot's memory system:
- `MEMORY.md` — Long-term curated memory (main session only, not shared contexts)
- `memory/YYYY-MM-DD.md` — Daily notes and raw logs
- "Write it down" culture — no mental notes, everything in files
- Security boundaries for personal context

## Status

**Prompt-Only** — No setup script, just prompt additions.

## Usage

Add `memory` to your `agents_sections` in `config.yaml`:

```yaml
exports:
  bot:
    agents_sections:
      - header
      - memory  # Add this
      # ...
```

Then run `/prompt-sync` to rebuild prompts.

## Files

- `prompts/AGENTS.snippet.md` — Memory file conventions and security rules
