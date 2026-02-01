# Heartbeats

Proactive behavior on periodic heartbeat polls.

## What It Does

Gives the bot guidance on using heartbeat polls productively:
- When to use heartbeat vs cron jobs
- What to check during heartbeats (email, calendar, mentions)
- How to batch periodic checks efficiently
- Using `HEARTBEAT.md` for task checklists

Turns passive polling into proactive assistance.

## Status

**Prompt-Only** — No setup script, just prompt additions.

## Usage

Add `heartbeats` to your `agents_sections` in `config.yaml`:

```yaml
exports:
  bot:
    agents_sections:
      - header
      - heartbeats  # Add this
      # ...
```

Then run `/prompt-sync` to rebuild prompts.

## Prerequisites

Heartbeat polling must be enabled in clawdbot config:

```json
{
  "agents": {
    "your-agent": {
      "heartbeat": {
        "enabled": true,
        "interval": 1800
      }
    }
  }
}
```

## Files

- `prompts/AGENTS.snippet.md` — Heartbeat behavior instructions
