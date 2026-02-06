# CLAUDE.md

Instructions for Claude Code when working in bruba-godo.

## What This Is

Operator workspace for managing a personal AI assistant bot running OpenClaw. This repo contains the tools and skills to control the bot from the operator's machine.

## General Info

For now, docs/architecture-masterdoc.md  is the best reference for how the system works and is put together. Also searching recent logs in docs/cc_logs, where for any long plan you should log your results.

## Directory Structure

see docs/filesystem-guide.md

## Configuration

Copy `config.yaml.example` to `config.yaml` and customize:

```yaml
ssh:
  host: <your-ssh-host>      # SSH host from ~/.ssh/config

remote:
  home: /Users/<bot-username>
  workspace: /Users/<bot-username>/clawd
  openclaw: /Users/<bot-username>/.openclaw
  agent_id: <your-agent-id>

local:
  agents: agents
  logs: logs
  reference: reference

# Copy repo code to bot workspace during push
clone_repo_code: false

# Export definitions (profiles for content filtering/syncing)
agents:
  bruba-main:
    workspace: /Users/bruba/agents/bruba-main
    agents_sections:
      - header
      - http-api
      # ... section order for AGENTS.md assembly
```

## Bot Commands

**Always use `./tools/bot`** — it handles transport abstraction automatically.

### Transport Options

Transport is configured in `config.yaml`:

```yaml
transport: sudo  # Options: sudo, tailscale-ssh, ssh
```

| Transport | Use Case | Speed |
|-----------|----------|-------|
| `sudo` | Same machine, different user | Fastest |
| `tailscale-ssh` | Remote via Tailscale SSH | Fast |
| `ssh` | Remote via regular SSH (default) | Normal |

Override per-command if needed: `BOT_TRANSPORT=ssh ./tools/bot ...`

### Rules

1. **Use full paths** — `/Users/bruba/...` not `~`
2. **Or quote for tilde** — `'ls ~/agents'` works (tilde expands on bot side)
3. **No quotes around full paths** — breaks whitelist matching

```bash
# Good — full paths
./tools/bot ls /Users/bruba/.openclaw/agents/bruba-main/sessions/
./tools/bot cat /Users/bruba/agents/bruba-main/MEMORY.md

# Good — quoted tilde (expands on bot side)
./tools/bot 'ls ~/agents/'

# Bad — unquoted tilde (expands locally to YOUR home)
./tools/bot ls ~/.openclaw/...
```

### Common Paths

- `/Users/bruba/agents/bruba-main/` — workspace root
- `/Users/bruba/.openclaw/` — openclaw config/state
- `/Users/bruba/.openclaw/agents/bruba-main/sessions/` — conversation transcripts

**Always use `./tools/bot`** — never use `ssh bruba` directly. The wrapper handles transport (sudo vs SSH) automatically based on config.yaml.

> **Note (2026-02-05):** Many skill files in `.claude/commands/` were migrated from `ssh bruba` to `./tools/bot`. Some tool scripts (`test-permissions.sh`, `test-sandbox.sh`, `fix-message-tool.sh`) still use `ssh bruba` due to multiline heredoc compatibility issues. If a skill fails unexpectedly, check if reverting to `ssh bruba` fixes it.

For multi-line scripts:
```bash
./tools/bot 'cd ~/agents && ls -la && cat AGENTS.md'
```

For pipes/jq, run jq locally on the output:
```bash
./tools/bot 'cat ~/.openclaw/config.json' | jq '.agents'
```

## Skills Reference

| Skill | Purpose |
|-------|---------|
| `/status` | Show daemon + local state |
| `/launch` | Start the daemon |
| `/stop` | Stop the daemon |
| `/restart` | Restart the daemon |
| `/wake` | Wake all agents |
| `/morning-check` | Verify post-reset wake |
| `/mirror` | Pull bot files locally |
| `/pull` | Pull closed sessions + convert to agents/{agent}/intake/ |
| `/push` | Push content to bot memory |
| `/sync` | Full pipeline sync (prompts + config + content + vault commit) |
| `/prompt-sync` | Assemble prompts + push (with conflict detection) |
| `/config-sync` | Sync config.yaml settings to openclaw.json |
| `/config` | Configure heartbeat, exec allowlist (interactive) |
| `/component` | Manage optional components (signal, voice, distill, etc.) |
| `/prompts` | Manage prompt assembly, resolve conflicts, explain config |
| `/update` | Update openclaw version |
| `/code` | Review and migrate staged code |
| `/convo` | Load active conversation |
| `/convert` | Add CONFIG block to intake file (AI-assisted) |
| `/intake` | Batch canonicalize files with CONFIG |
| `/export` | Generate filtered exports from canonical files |
| `/vault-sync` | Commit vault repo changes (when vault mode enabled) |
| `/test` | Run test suite |

## Prompt Assembly Pipeline

All prompt files (AGENTS.md, TOOLS.md, MEMORY.md, etc.) are assembled from **config-driven section order**. Each prompt file has a `{name}_sections` list in `config.yaml`.

**Section types:**
- `base` → full template (`templates/prompts/{NAME}.md`)
- `name` → component snippet (`components/{name}/prompts/{NAME}.snippet.md`)
- `name` → template section (`templates/prompts/sections/{name}.md`) — AGENTS.md only
- `bot:name` → bot-managed section (from mirror's `<!-- BOT-MANAGED: name -->`)

**Example config (in config.yaml):**
```yaml
agents:
  bruba-main:
    workspace: /Users/bruba/agents/bruba-main
    agents_sections:
      - header              # template section
      - http-api            # component
      - bot:exec-approvals  # bot-managed (preserved from remote)
      ...
    tools_sections:
      - base                # full template
      - reminders           # component snippet
    memory_sections:
      - base
    identity_sections:
      - base
```

**Run assembly:**
```bash
./tools/assemble-prompts.sh              # assemble all prompt files
./tools/assemble-prompts.sh --verbose    # show details
./tools/assemble-prompts.sh --force      # skip conflict check
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

**Conflict detection:** Run `./tools/detect-conflicts.sh` to check all prompt files for bot changes before pushing.

See `templates/prompts/README.md` for full documentation, or use `/prompts` for help.

## State Files

- `agents/{agent}/sessions/.pulled` — List of session IDs already pulled
- `logs/mirror.log` — Mirror script log
- `logs/pull.log` — Pull script log
- `logs/push.log` — Push script log
- `logs/assemble.log` — Assembly log
- `logs/updates.md` — Update history

## Templates

The `templates/` directory contains starter files for new agents:

- `templates/prompts/` — IDENTITY.md, SOUL.md, USER.md, AGENTS.md, TOOLS.md, MEMORY.md, BOOTSTRAP.md, HEARTBEAT.md
- `templates/config/` — openclaw.json.template, exec-approvals.json.template
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

Full pipeline for processing conversations to bot memory:

```
/pull                    # Pull JSONL sessions, convert to agents/{agent}/intake/*.md
  ↓
/convert <file>          # AI-assisted: add CONFIG block + summary
  ↓
/intake                  # Canonicalize → reference/transcripts/
  ↓
/export                  # Filter + redact → agents/{agent}/exports/
  ↓
/push                    # Sync exports to bot memory
```

**Quick reference:**
- `agents/{agent}/intake/` — Delimited markdown awaiting CONFIG
- `agents/{agent}/intake/processed/` — Originals after canonicalization
- `reference/transcripts/` — Canonical conversation files
- `reference/refdocs/` — Reference documents (synced to bot memory)
- `agents/{agent}/exports/core-prompts/` — AGENTS.md (syncs to ~/agents/{agent}/)
- `agents/{agent}/exports/prompts/` — Prompt files (syncs to ~/agents/{agent}/memory/prompts/)
- `agents/{agent}/exports/transcripts/` — Transcripts (syncs to ~/agents/{agent}/memory/transcripts/)

**Note:** `/export` scans all of `reference/` recursively. Files need YAML frontmatter with `scope` tags to be included.

Export profiles in `config.yaml` control filtering and redaction per destination.

## Git Policy

Per-agent directories (agents/*/exports/, agents/*/mirror/, agents/*/sessions/, agents/*/intake/), logs, and reference are gitignored. Only commit tool/skill/component changes after review.

## Output Conventions

### Work Logs (Large Plans Only)

For **large plan executions** (multi-step implementations, major refactors), write a work log to `docs/cc_logs/`. Do NOT create logs for routine tasks, quick fixes, or simple changes.

**Filename format:** `YYYY-MM-DD-<descriptive-slug>.md`

**Required frontmatter:**
```yaml
---
type: claude_code_log
scope: reference
title: "<Descriptive Title>"
---
```

This frontmatter ensures logs get exported to Bruba's memory as "Claude Code Log - <title>.md".

### Incoming Packets from Bruba

When the user asks to check for a Bruba packet, look here:

`/Users/bruba/agents/bruba-shared/packets/YYYY-MM-DD-<packet-name>.md`

This is on the **bot's filesystem**, so use `./tools/bot cat` to read it.

Packets include:
- Clear goal
- Context/background
- Specific deliverables
- Verification steps

After completing the packet's plan, offer to archive it to `/Users/bruba/agents/bruba-shared/packets/archive/`.
