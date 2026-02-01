# Continuity

Continuation packet handling for session handoffs.

## What It Does

Adds instructions for the bot to:
- Check for `memory/CONTINUATION.md` at session start
- Announce continuation status clearly ("Continuation packet loaded" or "not found")
- Archive old continuations before processing

This ensures context survives session resets and the user knows what's pending.

## Status

**Prompt-Only** — No setup script, just prompt additions.

## Usage

Add `continuity` to your `agents_sections` in `config.yaml`:

```yaml
exports:
  bot:
    agents_sections:
      - header
      - continuity  # Add this
      - session
      # ...
```

Then run `/prompt-sync` to rebuild prompts.

## Files

- `prompts/AGENTS.snippet.md` — Continuation announcement instructions
