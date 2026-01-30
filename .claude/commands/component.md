# /component - Manage Bot Components

Manage optional bot components (Signal, voice, reminders, etc.).

## Instructions

### Parse Arguments

Check $ARGUMENTS for action and component name:
- `list` or (empty) → Show available components
- `setup <name>` → Run interactive setup
- `validate <name>` → Run validation checks
- `status <name>` → Show current config

### Action: list (default)

Show available components and their status.

```bash
ls components/*/README.md 2>/dev/null | sed 's|components/||;s|/README.md||'
```

For each component, check if it's configured:

```bash
./tools/bot cat /Users/bruba/.clawdbot/clawdbot.json | jq -r '.channels.signal.enabled // false'
```

Display as:
```
Available Components:

  signal      ✅ configured    Signal messaging channel
  voice       ⚪ not ready     Voice transcription + TTS (no setup.sh)
  reminders   ⚪ not ready     Apple Reminders integration (no setup.sh)
  web-search  ⚪ not ready     Web search via reader subagent (no setup.sh)

Use: /component setup <name>     Run interactive setup
     /component validate <name>  Check configuration
     /component status <name>    View current config
```

Check if setup.sh exists to determine if component is ready:
```bash
test -f components/signal/setup.sh && echo "ready" || echo "not ready"
```

### Action: setup <name>

Run the component's interactive setup script.

First verify the component exists and has a setup script:
```bash
test -f components/<name>/setup.sh || echo "No setup script"
```

If exists, run it:
```bash
./components/<name>/setup.sh
```

If no setup.sh, tell user the component isn't ready yet and show README location.

### Action: validate <name>

Run the component's validation script.

First verify the component exists and has a validate script:
```bash
test -f components/<name>/validate.sh || echo "No validate script"
```

If exists, run it with --fix flag:
```bash
./components/<name>/validate.sh --fix
```

If validation fails, offer to help troubleshoot based on the output.

If no validate.sh exists, check if component is at least configured in clawdbot.json.

### Action: status <name>

Show the component's current configuration from the bot.

For signal:
```bash
./tools/bot cat /Users/bruba/.clawdbot/clawdbot.json | jq '.channels.signal'
```

Display formatted:
```
Signal Configuration:
  Enabled:     true
  CLI Path:    /opt/homebrew/bin/signal-cli
  HTTP Port:   8088
  Phone:       +1234567890
```

Also show binary info if relevant:
```bash
./tools/bot file /opt/homebrew/bin/signal-cli
./tools/bot /opt/homebrew/bin/signal-cli --version 2>&1 | head -1
```

## Arguments

$ARGUMENTS

## Component Directory Structure

Each component in `components/<name>/` should have:

```
components/<name>/
├── README.md       # Documentation, prerequisites, gotchas
├── setup.sh        # Interactive setup (required for /component setup)
├── validate.sh     # Validation checks (required for /component validate)
└── config.json     # Default config fragment
```

## Available Components

| Component | Status | Description |
|-----------|--------|-------------|
| signal | Ready | Signal messaging channel |
| distill | Core | Conversation → knowledge pipeline |
| voice | Planned | Voice transcription + TTS |
| reminders | Planned | Apple Reminders integration |
| web-search | Planned | Web search via reader subagent |
| http-api | Planned | Siri/Shortcuts integration |
| calendar | Planned | Apple Calendar integration |
| continuity | Planned | Session reset with context |

## Examples

```
/component
→ Lists all components with status

/component setup signal
→ Runs interactive Signal setup

/component validate signal
→ Checks Signal configuration, shows fixes

/component status signal
→ Shows current Signal config from bot
```

## Related Skills

- `/status` - Overall bot status
- `/config` - Other bot configuration
- `/restart` - Restart daemon after config changes
