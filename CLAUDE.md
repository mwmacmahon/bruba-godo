# CLAUDE.md

Instructions for Claude Code when working in bruba-godo.

## What This Is

Operator workspace for managing a personal AI assistant bot running Clawdbot. This repo contains the tools and skills to control the bot from the operator's machine.

**On session start, show ONLY this skills list:**

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
├── config.yaml.example      # Bot connection settings template
├── bundles.yaml             # Bundle definitions for content sync
├── tools/
│   ├── bot                  # SSH wrapper
│   ├── lib.sh               # Shared functions
│   ├── mirror.sh            # Mirror bot files
│   ├── pull-sessions.sh     # Pull closed sessions
│   ├── push.sh              # Push content to bot
│   ├── setup-agent.sh       # Agent provisioning
│   └── helpers/
│       ├── parse-yaml.py    # YAML parsing for shell
│       └── parse-jsonl.py   # JSONL → markdown
├── .claude/
│   ├── settings.json        # Permission allowlists
│   └── commands/            # Skill definitions
├── templates/               # Bot starter files
│   ├── prompts/             # IDENTITY, AGENTS, TOOLS, etc.
│   ├── config/              # clawdbot.json, exec-approvals templates
│   └── tools/               # Sample scripts
├── intake/                  # Raw files awaiting processing (gitignored)
├── reference/               # Processed canonical files (gitignored)
├── bundles/                 # Generated output (gitignored)
├── mirror/                  # Local copy of bot files (gitignored)
├── sessions/                # Pulled transcripts (gitignored)
└── logs/                    # Script logs (gitignored)
```

## Configuration

Copy `config.yaml.example` to `config.yaml` and customize:

```yaml
ssh:
  host: <your-ssh-host>      # SSH host from ~/.ssh/config

remote:
  home: /Users/<bot-username>
  workspace: /Users/<bot-username>/clawd
  clawdbot: /Users/<bot-username>/.clawdbot
  agent_id: <your-agent-id>

local:
  mirror: mirror
  sessions: sessions
  logs: logs
  intake: intake
  reference: reference
  bundles: bundles
```

Bundle definitions in `bundles.yaml`:

```yaml
bundles:
  bot:
    description: "Content for bot memory"
    output_dir: bundles/bot
    remote_path: memory
    include:
      scope: [meta, reference]
    exclude:
      sensitivity: [sensitive, restricted]
    redaction: [names, health]
```

## Bot Commands

**Always try `./tools/bot` first.** It reads config.yaml for the host.

Two rules:
1. **NEVER use `~`** — expands locally to YOUR home. Always use full paths like `/Users/bruba`
2. **No quotes around the command** — breaks whitelist matching

```bash
# Good — full paths, no quotes
./tools/bot ls /Users/bruba/.clawdbot/agents/bruba-main/sessions/
./tools/bot cat /Users/bruba/clawd/MEMORY.md

# Bad — tilde expands locally
./tools/bot ls ~/.clawdbot/...

# Bad — quotes break whitelist
./tools/bot 'ls /Users/bruba/...'
```

Common paths (on bot machine):
- `/Users/bruba/clawd/` — workspace root
- `/Users/bruba/.clawdbot/` — clawdbot config/state
- `/Users/bruba/.clawdbot/agents/bruba-main/sessions/` — conversation transcripts

**Only use `ssh bruba` for:** multi-line scripts, pipes, or jq. That's it.

## Skills Reference

| Skill | Purpose |
|-------|---------|
| `/status` | Show daemon + local state |
| `/launch` | Start the daemon |
| `/stop` | Stop the daemon |
| `/restart` | Restart the daemon |
| `/mirror` | Pull bot files locally |
| `/pull` | Pull closed sessions |
| `/push` | Push content to bot memory |
| `/config` | Configure heartbeat, exec allowlist |
| `/update` | Update clawdbot version |
| `/code` | Review and migrate staged code |
| `/convo` | Load active conversation |

## State Files

- `sessions/.pulled` — List of session IDs already pulled
- `logs/mirror.log` — Mirror script log
- `logs/pull.log` — Pull script log
- `logs/push.log` — Push script log
- `logs/updates.md` — Update history

## Templates

The `templates/` directory contains starter files for new agents:

- `templates/prompts/` — IDENTITY.md, SOUL.md, USER.md, AGENTS.md, TOOLS.md, MEMORY.md, BOOTSTRAP.md, HEARTBEAT.md
- `templates/config/` — clawdbot.json.template, exec-approvals.json.template
- `templates/tools/` — example-tool.sh

Use `./tools/setup-agent.sh` to provision a new agent with these templates.

## Content Pipeline

For syncing content to bot memory:

1. Add markdown files to `reference/`
2. Generate bundle: `cp reference/*.md bundles/bot/` (or use full filtering)
3. Push to bot: `./tools/push.sh`

Bundles are filtered according to `bundles.yaml` definitions.

## Git Policy

Mirror, sessions, logs, intake, reference, and bundles are gitignored. Only commit tool/skill changes after review.
