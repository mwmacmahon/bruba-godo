# bruba-godo

Control center for running a personal AI assistant on a dedicated machine, managed remotely from your main workstation.

## The Vision

An AI assistant that actually accumulates knowledge and capabilities over time. Every conversation feeds back into its memory. It can build its own tools, and you approve the good ones. It runs sandboxed on a separate machine so when it screws up (and it will), the blast radius is contained.

The endgame: a persistent, evolving AI collaborator that knows your projects, remembers your preferences, and gets more capable the longer you work with it.

## Where It's At

The core architecture is working. I use this daily.

**What's solid:**
- **Two-machine setup** — Bot runs sandboxed on one Mac, you control it via SSH from another. Clean separation.
- **Prompt assembly** — Modular system for building the bot's personality and capabilities. Templates + components + config-driven assembly. Detects when the bot modifies its own prompts so you can merge changes.
- **Content pipeline** — This is the big one. Conversations get pulled, converted to clean markdown, noise stripped, sensitive info redacted, then pushed back as searchable reference material. Your chats become institutional memory.
- **Tool promotion** — Bot can write scripts in a staging area. You review, approve, and they get added to its execution allowlist. It grows capabilities over time.
- **Daemon management** — Start/stop/restart, status checks, the basics.
- **Claude Code integration** — Skill commands (`/sync`, `/push`, `/pull`, etc.) for common operations.
- **Voice I/O** — Speech-to-text input, text-to-speech output.
- **Reminders integration** — Apple Reminders access.
- **Web search** — Search capability for the bot.

**Not built yet:**
- Multi-bot support (architecture could handle it, nothing built)

**Current limitations:**
- Currently macOS on both machines, but Linux (EC2, etc.) should be a small lift for either side
- Only integrates with Clawdbot as the bot runtime
- **Setup is the shakiest part** — I've documented what I've tried and where I've hit issues, but it's nowhere near streamlined yet. Expect to debug.

## The Architecture

```
Your laptop  ──────SSH──────►  Bot machine
(operator)                     (sandboxed)

bruba-godo tools               Clawdbot daemon
Review & approve               Tool execution
Content pipeline               Memory/RAG
```

The operator machine has all the control tooling. The bot machine just runs the agent. You sync prompts, content, and approved tools between them.

## What You Need

- Two machines (or a VM for the bot)
- SSH access between them
- [Clawdbot](https://github.com/moltbot/clawdbot) on the bot machine
- Python 3, rsync, jq
- Claude Code (optional but recommended)

## Quick Start

1. Set up a dedicated user on the bot machine, install Clawdbot
2. Configure SSH from your machine to the bot
3. Clone this repo, `cp config.yaml.example config.yaml`, edit it
4. Run `./tools/provision-bot.sh`
5. Test: `./tools/bot clawdbot status`

Full walkthrough in [docs/setup.md](docs/setup.md).

## Usage

Best used with Claude Code. Open this directory and use skills:

**Daemon control:**
| Skill | What it does |
|-------|--------------|
| `/status` | Show daemon state, active session, local file counts |
| `/launch` | Start the bot daemon |
| `/stop` | Stop the daemon |
| `/restart` | Restart the daemon |

**File sync:**
| Skill | What it does |
|-------|--------------|
| `/mirror` | Pull bot's prompt files locally for diffing/review |
| `/pull` | Download closed session transcripts, auto-convert to markdown |
| `/push` | Push content (prompts, transcripts, docs) to bot memory |
| `/sync` | Full pipeline: mirror → assemble prompts → push content |
| `/prompt-sync` | Just the prompt assembly + push (skip content pipeline) |

**Content pipeline:**
| Skill | What it does |
|-------|--------------|
| `/convert` | Add CONFIG metadata to an intake file (AI-assisted) |
| `/intake` | Batch canonicalize files that have CONFIG blocks |
| `/export` | Generate filtered exports from canonical files |

**Other:**
| Skill | What it does |
|-------|--------------|
| `/config` | Manage bot settings (heartbeat, exec allowlist) |
| `/component` | Enable/disable optional components |
| `/update` | Update Clawdbot version on bot machine |
| `/code` | Review staged code from bot, migrate to approved tools |
| `/convo` | Load the bot's active conversation for context |

Or use the shell scripts directly:
```bash
./tools/bot clawdbot status
./tools/mirror.sh
./tools/push.sh
```

## Project Structure

| Directory | What's There |
|-----------|--------------|
| `tools/` | Shell scripts for everything |
| `components/` | Optional add-ons (signal, voice, distill, etc.) |
| `templates/` | Base prompt files for new agents |
| `docs/` | Setup, operations, security, pipeline docs |
| `.claude/commands/` | Claude Code skill definitions |
| `tests/` | Test suite |

Runtime directories (gitignored): `mirror/`, `sessions/`, `intake/`, `reference/`, `exports/`, `logs/`

## Documentation

- [Setup Guide](docs/setup.md) — Full installation walkthrough
- [Operations Guide](docs/operations-guide.md) — Daily usage
- [Security Model](docs/security-model.md) — Threat model, hardening
- [Pipeline](docs/pipeline.md) — Content processing flow

## License

MIT

---

*"Bruba go do" — Gil Ozeri*
