# /config-sync - Sync OpenClaw Config

Sync config.yaml settings to bot's openclaw.json and restart gateway.

## Instructions

### 1. Check Current Status

See what's different between local config and bot:

```bash
./tools/sync-openclaw-config.sh --check
```

### 2. Sync Changes

Apply config.yaml settings to openclaw.json:

```bash
./tools/sync-openclaw-config.sh
```

### 3. Restart Gateway

Changes require a gateway restart to take effect:

```bash
./tools/bot openclaw gateway restart
```

## Arguments

$ARGUMENTS

Options:
- `--check` — Show discrepancies without changing anything
- `--dry-run` — Show what would change without applying
- `--section=NAME` — Only sync specific section (defaults, agents, subagents, voice, bindings)
- `--agent=NAME` — Only sync specific agent
- `--verbose` — Show detailed output

## What Gets Synced

**Global defaults** (`openclaw:` section):
- Model (primary + fallbacks)
- Compaction settings
- Context pruning
- Memory search
- Sandbox mode
- Max concurrent sessions

**Per-agent settings** (`agents:` section):
- Model
- Heartbeat (interval, active hours, target)
- Tools allow/deny lists
- Memory search (per-agent override)

**Subagent settings** (`subagents:` section):
- Model
- Max concurrent
- Archive timeout
- Tools allow/deny

**Voice settings** (`openclaw.voice:` section):
- STT (speech-to-text via Groq)
- TTS (text-to-speech via ElevenLabs)

**Bindings** (`bindings:` section):
- Channel → agent routing

## What's Preserved (Not Synced)

These sections in openclaw.json are never touched:
- `auth` — API keys and auth profiles
- `wizard` — Setup wizard state
- `channels` — Channel configurations (signal, bluebubbles, etc.)
- `gateway` — Gateway server settings
- `env.vars` — Environment variables
- `plugins` — Plugin configurations
- `skills` — Skill definitions

## Quick Sync

For a quick sync + restart:

```bash
./tools/sync-openclaw-config.sh && ./tools/bot openclaw gateway restart
```

## Example Flow

```
User: /config-sync

Claude: [checks status]
$ ./tools/sync-openclaw-config.sh --check

Checking global defaults...
Checking agent settings...
  agents.bruba-manager.heartbeat:
    current: {"every":"15m","activeHours":{"start":"07:00","end":"22:00"}}
    desired: {"every":"0m"}

Config: discrepancies found

Claude: Found 1 change. Apply it?

User: yes

Claude: [applies changes]
$ ./tools/sync-openclaw-config.sh
Config: updated

$ ./tools/bot openclaw gateway restart
Restarted LaunchAgent: gui/502/ai.openclaw.gateway

Done. Manager heartbeat disabled.
```

## Common Tasks

### Disable an agent's heartbeat

In config.yaml:
```yaml
agents:
  bruba-manager:
    heartbeat: false
```

Then run `/config-sync`.

### Change an agent's model

In config.yaml:
```yaml
agents:
  bruba-guru:
    model: opus
```

Then run `/config-sync`.

### Update tool permissions

In config.yaml:
```yaml
agents:
  bruba-main:
    tools_allow:
      - read
      - write
      - exec
    tools_deny:
      - browser
      - canvas
```

Then run `/config-sync`.

### Add a channel binding

In config.yaml:
```yaml
bindings:
  - agent: bruba-main
    channel: signal
  - agent: bruba-main
    channel: bluebubbles
    peer:
      kind: dm
      id: "<REDACTED-PHONE>"
```

Then run `/config-sync`.

## Related Skills

- `/prompt-sync` — Assemble and push prompts
- `/sync` — Full pipeline sync (prompts + config + content)
- `/status` — Check bot status
- `/restart` — Restart bot daemon
