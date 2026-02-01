# Group Chats

Social behavior guidelines for group chat contexts.

## What It Does

Teaches the bot appropriate group chat etiquette:
- When to speak vs stay silent (quality > quantity)
- Using emoji reactions naturally
- Not sharing the user's private info
- Participating without dominating

Prevents the bot from responding to every message in busy group chats.

## Status

**Prompt-Only** — No setup script, just prompt additions.

## Usage

Add `group-chats` to your `agents_sections` in `config.yaml`:

```yaml
exports:
  bot:
    agents_sections:
      - header
      - group-chats  # Add this
      # ...
```

Then run `/prompt-sync` to rebuild prompts.

## Files

- `prompts/AGENTS.snippet.md` — Group chat participation guidelines
