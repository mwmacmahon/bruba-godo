# CLAUDE.md

Instructions for Claude Code when working in bruba-godo.

## What This Is

Operator workspace for managing a personal AI assistant bot running Clawdbot. This repo contains the tools and skills to control the bot from the operator's machine.

## Local Context

If any files matching `LOCAL*.md` exist in the repo root, read them at session start and briefly acknowledge to the user. These contain machine-specific context that isn't committed to the repo.

Common patterns:
- `LOCAL.md` — primary local context (includes migration docs)

**For development tasks:** If the user is working on bruba-godo tooling/features (not just operating the bot), check `LOCAL.md` for links to migration planning docs in PKM. These explain what's being extracted from PKM, current status, and design decisions.

**On session start, show ONLY this skills list:**

```
Bot Skills:
  Daemon:    /status, /launch, /stop, /restart
  Files:     /mirror, /pull, /push, /sync
  Config:    /config, /update, /component, /prompts
  Code:      /code
  Convo:     /convo
  Setup:     (run tools/setup-agent.sh)
```

## Directory Structure

```
bruba-godo/
├── config.yaml.example      # Bot connection settings template
├── exports.yaml             # Export definitions for content sync
├── tools/
│   ├── bot                  # SSH wrapper
│   ├── lib.sh               # Shared functions
│   ├── mirror.sh            # Mirror bot files
│   ├── pull-sessions.sh     # Pull closed sessions
│   ├── push.sh              # Push content to bot
│   ├── assemble-prompts.sh  # Assemble prompts from templates + components
│   ├── setup-agent.sh       # Agent provisioning
│   └── helpers/
│       ├── parse-yaml.py    # YAML parsing for shell
│       └── parse-jsonl.py   # JSONL → markdown
├── .claude/
│   ├── settings.json        # Permission allowlists
│   └── commands/            # Skill definitions
├── templates/               # BASE PROMPTS (committed)
│   ├── prompts/             # IDENTITY, AGENTS, TOOLS, etc.
│   ├── config/              # clawdbot.json, exec-approvals templates
│   └── tools/               # Sample scripts
├── components/              # OPTIONAL CAPABILITIES (committed)
│   ├── signal/              # Signal messaging channel
│   ├── voice/               # Voice input/output (planned)
│   ├── distill/             # Conversation → knowledge pipeline
│   └── ...                  # Other components
├── user/                    # USER CUSTOMIZATIONS (gitignored)
│   ├── prompts/             # Personal prompt additions
│   └── exports.yaml         # Personal export profiles
├── assembled/               # ASSEMBLED PROMPTS (gitignored)
│   └── prompts/             # Final AGENTS.md, TOOLS.md, etc.
├── mirror/                  # BOT STATE (gitignored)
│   └── prompts/             # Current bot prompts
├── sessions/                # RAW SESSIONS (gitignored)
│   ├── *.jsonl              # JSONL files from bot
│   └── converted/           # Markdown conversions
├── reference/               # PROCESSED CONTENT (gitignored)
│   └── transcripts/         # Canonicalized conversations
├── exports/                 # SYNC OUTPUTS (gitignored)
│   └── bot/                 # Content ready to push to bot memory
├── intake/                  # Raw files awaiting processing (gitignored)
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
  exports: exports
  assembled: assembled
```

Export definitions in `exports.yaml`:

```yaml
exports:
  bot:
    description: "Content synced to bot memory"
    output_dir: exports/bot
    remote_path: memory
    include:
      scope: [meta, reference, transcripts]
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
| `/sync` | Assemble prompts + push (with conflict detection) |
| `/config` | Configure heartbeat, exec allowlist |
| `/component` | Manage optional components (signal, voice, distill, etc.) |
| `/prompts` | Manage prompt assembly, resolve conflicts, explain config |
| `/update` | Update clawdbot version |
| `/code` | Review and migrate staged code |
| `/convo` | Load active conversation |

## Prompt Assembly Pipeline

Prompts are assembled from **config-driven section order**. The `agents_sections` list in `config.yaml` defines exactly what sections appear and in what order.

**Section types:**
- `name` → component (`components/{name}/prompts/AGENTS.snippet.md`)
- `name` → template section (`templates/prompts/sections/{name}.md`)
- `bot:name` → bot-managed section (from mirror's `<!-- BOT-MANAGED: name -->`)

**Example config:**
```yaml
agents_sections:
  - header              # template section
  - http-api            # component
  - first-run           # template section
  - session             # component
  - bot:exec-approvals  # bot-managed (preserved from remote)
  - safety              # template section
  ...
```

**Run assembly:**
```bash
./tools/assemble-prompts.sh
./tools/assemble-prompts.sh --verbose  # show details
```

**Section markers in output:**
```markdown
<!-- COMPONENT: voice -->
...component content...
<!-- /COMPONENT: voice -->

<!-- BOT-MANAGED: exec-approvals -->
...bot's content (preserved)...
<!-- /BOT-MANAGED: exec-approvals -->
```

See `templates/prompts/README.md` for full documentation, or use `/prompts` for help.

## State Files

- `sessions/.pulled` — List of session IDs already pulled
- `logs/mirror.log` — Mirror script log
- `logs/pull.log` — Pull script log
- `logs/push.log` — Push script log
- `logs/assemble.log` — Assembly log
- `logs/updates.md` — Update history

## Templates

The `templates/` directory contains starter files for new agents:

- `templates/prompts/` — IDENTITY.md, SOUL.md, USER.md, AGENTS.md, TOOLS.md, MEMORY.md, BOOTSTRAP.md, HEARTBEAT.md
- `templates/config/` — clawdbot.json.template, exec-approvals.json.template
- `templates/tools/` — example-tool.sh

Use `./tools/setup-agent.sh` to provision a new agent with these templates.

## Components

Optional capabilities in `components/`:

| Component | Status | Description |
|-----------|--------|-------------|
| signal | Ready | Signal messaging channel |
| voice | Planned | Voice input/output (whisper, TTS) |
| distill | Core | Conversation → knowledge pipeline |
| reminders | Planned | Apple Reminders integration |
| web-search | Planned | Web search capability |

Each component can contribute:
- `setup.sh` — Interactive setup
- `validate.sh` — Configuration validation
- `prompts/*.snippet.md` — Prompt additions

## Content Pipeline

For syncing content to bot memory:

1. Add markdown files to `reference/`
2. Generate export: `cp reference/*.md exports/bot/` (or use full filtering)
3. Push to bot: `./tools/push.sh`

Exports are filtered according to `exports.yaml` definitions.

## Git Policy

Mirror, sessions, logs, intake, reference, exports, assembled, and user are gitignored. Only commit tool/skill/component changes after review.
