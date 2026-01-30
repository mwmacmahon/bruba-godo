# bruba-godo

Tooling for running a personal AI bot more safely — sandboxed on a dedicated machine, managed from your trusted operator machine through automation.

Currently supports [Clawdbot](https://github.com/moltbot/clawdbot), with potential for other bot/agent frameworks in the future.

## Why This Exists

Running an AI agent with tool access is powerful but risky. bruba-godo provides a framework for:

- **Sandboxed execution** — Bot runs on a separate machine with limited permissions. You manage it remotely via SSH from your more trusted operator machine.
- **Controlled tool promotion** — Let your bot build its own tools, but you review and approve before they get promoted to the allowlist.
- **Knowledge extraction** — Parse bot conversations with AI assistance and convert them to efficient reference docs for RAG. All those casual text exchanges become structured knowledge.
- **Always-on assistant** — Text or voice message your bot anytime to ask questions, dump knowledge, or do light vibecoding.
- **Convenience features** — Auto-continuation packets when you reset conversations, voice message transcripts forwarded to Signal chat, and more.
- **Modular components** — Use what you need. Signal integration, voice I/O, and other components are optional add-ons.

## Features

- **Daemon control**: Start, stop, restart the bot daemon
- **File sync**: Mirror bot files, pull sessions, push content to memory
- **Configuration**: Manage heartbeat, exec allowlist, clawdbot updates
- **Code review**: Review and migrate staged code from bot workspace
- **Templates**: Starter files for provisioning new agents
- **Components**: Optional add-ons (Signal, voice, reminders)

## Prerequisites

Before using bruba-godo, you need:

1. **A remote machine** to run the bot (Mac, Linux, or always-on server)
2. **SSH access** from your operator machine to the remote
3. **Clawdbot** installed on the remote machine
4. **Claude Code** on your operator machine (optional but recommended for skills)

For detailed setup instructions, see:
- [Quick start (new machine)](docs/quickstart-new-machine.md) — Condensed setup
- [Full setup guide](docs/full-setup-guide.md) — Comprehensive configuration
- [Setting up the remote machine](docs/setup-remote-machine.md) — Create service account, enable SSH
- [Setting up operator SSH access](docs/setup-operator-ssh.md) — SSH keys, config, troubleshooting

## Quick Start

### 1. Set Up the Remote Machine

```bash
# On the remote machine: create bot user and install clawdbot
sudo dscl . -create /Users/bruba  # macOS
npm install -g clawdbot
```

See [docs/setup-remote-machine.md](docs/setup-remote-machine.md) for full instructions.

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

See [docs/setup-operator-ssh.md](docs/setup-operator-ssh.md) for full instructions.

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
  Config:    /config, /update
  Code:      /code
  Convo:     /convo
  Setup:     (run tools/setup-agent.sh)
```

## Directory Structure

```
bruba-godo/
├── config.yaml.example      # Connection settings template
├── bundles.yaml             # Bundle definitions
├── config/                  # Configuration files
│   └── corrections.yaml     # Transcription corrections
├── docs/                    # Documentation
│   ├── full-setup-guide.md  # Comprehensive setup
│   ├── operations-guide.md  # Day-to-day operations
│   ├── security-model.md    # Security reference
│   ├── setup-remote-machine.md
│   ├── setup-operator-ssh.md
│   └── intake-pipeline.md
├── tools/
│   ├── bot                  # SSH wrapper
│   ├── lib.sh               # Shared functions
│   ├── mirror.sh            # Mirror bot files
│   ├── pull-sessions.sh     # Pull closed sessions
│   ├── push.sh              # Push content to bot
│   ├── provision-bot.sh     # Full bot provisioning
│   ├── setup-agent.sh       # Agent template setup
│   ├── snapshot.sh          # Config/memory backup
│   └── helpers/             # Python utilities
├── components/              # Optional add-ons
│   ├── signal/              # Signal messenger
│   ├── voice/               # Voice I/O (planned)
│   ├── reminders/           # Scheduled reminders (planned)
│   └── web-search/          # Web search (planned)
├── .claude/commands/        # Skill definitions
├── templates/               # Bot starter files
│   ├── prompts/             # IDENTITY, SOUL, USER, AGENTS, etc.
│   ├── config/              # clawdbot.json, exec-approvals templates
│   └── tools/               # Sample scripts
├── intake/                  # Raw files (gitignored)
├── reference/               # Processed files (gitignored)
├── bundles/                 # Generated output (gitignored)
├── mirror/                  # Local file backup (gitignored)
├── sessions/                # Pulled sessions (gitignored)
└── logs/                    # Script logs (gitignored)
```

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
| [Full Setup Guide](docs/full-setup-guide.md) | Complete setup from scratch |
| [Operations Guide](docs/operations-guide.md) | Day-to-day usage reference |
| [Security Model](docs/security-model.md) | Threat model, permissions, hardening |
| [Intake Pipeline](docs/intake-pipeline.md) | Session processing workflow |
| [Setup Remote Machine](docs/setup-remote-machine.md) | Bot machine preparation |
| [Setup Operator SSH](docs/setup-operator-ssh.md) | SSH configuration |

## License

MIT License
