# Message Tool Component

Provides documentation for the `message` tool pattern for direct Signal delivery.

## Purpose

The `message` tool enables any agent to send messages/media directly to Signal, outside the normal response flow. This is used for:

- Voice replies (audio files)
- Siri async routing (HTTP→Signal)
- Guru direct responses (bypassing Main relay)
- Sending images or file attachments

## Files

- `prompts/AGENTS.snippet.md` - Documentation snippet for AGENTS.md assembly

## Usage

Add `message-tool` to any agent's `agents_sections` in config.yaml:

```yaml
agents_sections:
  - header
  - message-tool    # Add this
  - signal
  - ...
```

## Key Concepts

### NO_REPLY Pattern

Agents bound to Signal (like bruba-main) must follow message tool use with `NO_REPLY` to prevent duplicate delivery.

Agents NOT bound to Signal (like bruba-guru) don't need `NO_REPLY` — their normal response goes to the calling agent, not Signal.

### <REDACTED-NAME>'s Signal UUID

```
uuid:<REDACTED-UUID>
```

## Related Components

- `voice` - Voice message handling (uses message tool)
- `http-api` - Siri async routing (uses message tool)
- `signal` - Signal integration basics
- `guru-routing` - Guru direct response pattern (uses message tool)
