# Siri Async

HTTP API routing for Siri Shortcuts and automations. Uses variants for different agent roles.

## Variants

| Variant | Agent | Purpose |
|---------|-------|---------|
| `siri-async:router` | bruba-manager | Receives HTTP requests, forwards to Main |
| `siri-async:handler` | bruba-main | Processes forwarded requests, sends Signal response |

## How It Works

```
Siri → HTTP POST → bruba-manager (router)
                   └─→ sessions_send to bruba-main (fire-and-forget)
                   └─→ Returns "✓" to HTTP in <3s

bruba-main (handler) → processes request
                     → sends response to Signal via message tool
```

**Why two variants?** Siri has a 10-15 second HTTP timeout. Main (Opus) can take 20-30 seconds. Manager acts as a fast front door — accepts the request, forwards async, returns immediately.

## Usage

In `config.yaml`:

```yaml
agents:
  bruba-main:
    agents_sections:
      - siri-async:handler  # Handles forwarded requests

  bruba-manager:
    agents_sections:
      - siri-async:router   # Receives and forwards requests
```

Then run `/prompt-sync` to rebuild prompts.

## Prerequisites

- HTTP API enabled in OpenClaw
- Tailscale serve configured for HTTPS endpoint
- iOS Shortcut targeting Manager (model: `openclaw:manager`)

## Files

- `prompts/AGENTS.router.snippet.md` — Manager routing logic
- `prompts/AGENTS.handler.snippet.md` — Main handling logic
