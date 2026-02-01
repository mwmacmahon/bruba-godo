# bruba-godo

Tooling for running a personal AI bot more safely — sandboxed on a dedicated machine, managed from your trusted operator machine through automation.

Currently supports [Clawdbot](https://github.com/moltbot/clawdbot), with potential for other bot/agent frameworks in the future.

## Why This Exists

Running an AI agent with tool access is powerful but risky. bruba-godo provides a framework for:

- **Sandboxed execution** — Bot runs on a separate machine with limited permissions. You manage it remotely via SSH from your more trusted operator machine.
- **Controlled tool promotion** — Let your bot build its own tools, but you review and approve before they get promoted to the allowlist.
- **Knowledge extraction** — Parse bot conversations with AI assistance and convert them to efficient reference docs for RAG. All those casual text exchanges become structured knowledge, and transcripts become reference documents stripped of bloat and with sensitive information redacted.
- **Convenience features** — Auto-continuation packets for smoother context rollover when you reset conversations, full TTS/STT integration, and more.
- **Modular components** — Use what you need. Signal integration, voice I/O, and other components are optional add-ons.

## Features

- **Daemon control**: Start, stop, restart the bot daemon
- **File sync**: Mirror bot files, pull sessions, push content to memory
- **Prompt assembly**: Config-driven prompt building with conflict detection
- **Configuration**: Manage heartbeat, exec allowlist, clawdbot updates
- **Code review**: Review and migrate staged code from bot workspace
- **Templates**: Starter files for provisioning new agents
- **Components**: Optional add-ons (Signal, voice, reminders)
- **Test suite**: Automated tests for verifying prompt assembly

## Prerequisites

Before using bruba-godo, you need:

1. **A remote machine** to run the bot (Mac, Linux, or always-on server)
2. **SSH access** from your operator machine to the remote
3. **Clawdbot** installed on the remote machine
4. **Claude Code** on your operator machine (optional but recommended for skills)

For detailed setup instructions, see [Setup Guide](docs/setup.md).

## Quick Start

### 1. Set Up the Remote Machine

```bash
# On the remote machine: create bot user and install clawdbot
sudo dscl . -create /Users/bruba  # macOS
npm install -g clawdbot
```

See [Setup Guide](docs/setup.md#part-1-remote-machine-setup) for full instructions.

### 2. Configure SSH Access

```bash
# On your operator machine
ssh-keygen -t ed25519
ssh-copy-id bruba@<remote-ip>

# Add to ~/.ssh/config:
# Host bruba
#     HostName <remote-ip>
#     User bruba
```

See [Setup Guide](docs/setup.md#part-2-operator-machine-setup) for full instructions.

### 3. Clone and Provision

```bash
git clone https://github.com/<your-username>/bruba-godo.git
cd bruba-godo

# Copy and edit config with your bot's details
cp config.yaml.example config.yaml
vim config.yaml

# Provision the bot
./tools/provision-bot.sh
```

### 4. Test Connection

```bash
./tools/bot clawdbot status
```

## Usage with Claude Code

Open in Claude Code and use the skills:

```
Bot Skills:
  Daemon:    /status, /launch, /stop, /restart
  Files:     /mirror, /pull, /push
  Sync:      /sync (full pipeline), /prompt-sync (prompts only)
  Config:    /config, /update, /component, /prompts
  Pipeline:  /convert, /intake, /export
  Code:      /code
  Convo:     /convo
  Setup:     (run tools/setup-agent.sh)
```

## Directory Structure

| Directory | Purpose |
|-----------|---------|
| `docs/` | Documentation (setup, operations, security, pipeline) |
| `tools/` | Scripts for bot management (mirror, push, pull, etc.) |
| `components/` | Optional add-ons (signal, voice, distill, etc.) |
| `templates/` | Starter files for new agents (prompts, config) |
| `.claude/commands/` | Claude Code skill definitions |
| `tests/` | Test suite for prompt assembly |
| `mirror/` | Local copy of bot files (gitignored) |
| `sessions/` | Pulled session transcripts (gitignored) |
| `intake/` | Raw conversations awaiting CONFIG (gitignored) |
| `reference/` | Processed content (transcripts, refdocs) (gitignored) |
| `exports/` | Filtered content ready for sync (gitignored) |
| `logs/` | Script execution logs (gitignored) |

## Manual Tool Usage

```bash
# SSH wrapper (reads host from config.yaml)
./tools/bot clawdbot status
./tools/bot cat /Users/bruba/clawd/MEMORY.md

# Mirror bot files
./tools/mirror.sh --verbose

# Pull closed sessions
./tools/pull-sessions.sh --verbose

# Push content to bot memory
./tools/push.sh --verbose

# Setup a new agent
./tools/setup-agent.sh --agent-id my-agent --user-name "Your Name"

# Create a backup snapshot
./tools/snapshot.sh --verbose
```

## Provisioning a New Bot

Use the provision script for full setup:

```bash
./tools/provision-bot.sh

# Or with options:
./tools/provision-bot.sh \
  --bot-name "My Bot" \
  --agent-id my-bot \
  --user-name "Your Name"
```

The script will:
1. Check prerequisites (SSH, clawdbot, jq)
2. Gather configuration interactively
3. Create remote workspace and directories
4. Copy and customize prompt templates
5. Configure clawdbot.json and exec-approvals
6. Apply security hardening
7. Verify installation

### Adding Components

After provisioning, add optional features:

```bash
# Connect via Signal
./components/signal/setup.sh

# More components coming soon
```

## Requirements

| Dependency | Required | Purpose |
|------------|----------|---------|
| SSH | Yes | Remote bot access |
| Python 3 | Yes | YAML/JSON parsing |
| jq | Recommended | JSON manipulation (Python fallback) |
| rsync | Yes | File sync |
| Clawdbot | On remote | Bot runtime |

## Documentation

| Document | Purpose |
|----------|---------|
| [Setup Guide](docs/setup.md) | Complete setup from scratch |
| [Operations Guide](docs/operations-guide.md) | Day-to-day usage reference |
| [Security Model](docs/security-model.md) | Threat model, permissions, hardening |
| [Troubleshooting](docs/troubleshooting.md) | Common issues and solutions |
| [Pipeline](docs/pipeline.md) | Content processing workflow |

## License

MIT License


## Acknowledgement

Recall the prophetic words of Gil Ozeri
"Bruba go do"
