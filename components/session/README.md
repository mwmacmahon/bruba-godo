# Session

Session startup workflow and greeting behavior.

## What It Does

Defines the session start sequence:
1. Read core files (SOUL.md, USER.md)
2. Check for continuation packets
3. Load recent daily notes
4. Load MEMORY.md (main session only)
5. Skim inventories for available documents

Also includes:
- Session greeting pattern (greet → check continuation → summarize)
- Continuation packet creation on session end

## Status

**Prompt-Only** — No setup script, just prompt additions.

## Usage

Add `session` to your `agents_sections` in `config.yaml`:

```yaml
exports:
  bot:
    agents_sections:
      - header
      - session  # Add this
      # ...
```

Then run `/prompt-sync` to rebuild prompts.

## Files

- `prompts/AGENTS.snippet.md` — Session startup checklist and greeting flow
