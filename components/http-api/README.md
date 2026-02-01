# HTTP API

Message handling for Siri Shortcuts and HTTP API integrations.

## What It Does

Adds a message-type detection pattern for HTTP API messages:
- Identifies `[From Siri]` and similar prefixes
- Forces explicit check on every message (the echo pattern)
- Includes HTTP API log auto-relay for missed messages
- Integrates with voice message detection

## Status

**Prompt-Only** — No setup script, just prompt additions.

## Usage

Add `http-api` to your `agents_sections` in `config.yaml`:

```yaml
exports:
  bot:
    agents_sections:
      - header
      - http-api  # Add this
      # ...
```

Then run `/prompt-sync` to rebuild prompts.

## Prerequisites

HTTP API must be enabled in clawdbot. The bot receives messages via `clawdbot gateway send`.

## Files

- `prompts/AGENTS.snippet.md` — Message detection pattern and HTTP API log handling
