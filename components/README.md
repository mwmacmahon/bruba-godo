# Components

Optional add-ons for extending your bot's capabilities.

## Available Components

| Component | Status | Prompts | Description |
|-----------|--------|---------|-------------|
| [Signal](signal/) | **Ready** | ✅ | Connect via Signal messenger |
| [Voice](voice/) | Prompt Ready | ✅ | Voice input/output (whisper, TTS) |
| [Session](session/) | Prompt Ready | ✅ | Every Session, Greeting, Continuation |
| [Memory](memory/) | Prompt Ready | ✅ | Memory management workflow |
| [Heartbeats](heartbeats/) | Prompt Ready | ✅ | Proactive behavior on heartbeat polls |
| [Group-chats](group-chats/) | Prompt Ready | ✅ | Social behavior in group contexts |
| [Workspace](workspace/) | Prompt Ready | ✅ | Generated content paths |
| [HTTP-API](http-api/) | Prompt Ready | ✅ | Siri/Shortcuts integration |
| [Continuity](continuity/) | Prompt Ready | ✅ | Continuation packet announce |
| [CC-Packets](cc-packets/) | Prompt Ready | ✅ | Claude Code packet exchange |
| [Distill](distill/) | **Ready** | ✅ | Conversation → knowledge pipeline (full) |
| [Reminders](reminders/) | Planned | — | Scheduled reminders |
| [Web Search](web-search/) | Planned | — | Web search integration |
| Calendar | Planned | — | Apple Calendar integration |

**Status key:**
- **Ready** — Full setup.sh, validate.sh, prompts, and working code
- **Prompt Ready** — Prompt snippet extracted, setup TBD
- **Planned** — README only

## How Components Work

Each component provides:

1. **README.md** — What it does, prerequisites, how to use
2. **setup.sh** — Interactive setup script (run from bruba-godo root)
3. **validate.sh** — Validation checks (run after setup to verify)
4. **config.json** — Config fragment to merge into clawdbot.json
5. **prompts/** — (Optional) Prompt snippets that extend AGENTS.md, TOOLS.md, etc.

## Prompt Snippets

Components can contribute to the bot's prompts via snippet files:

```
components/voice/
├── setup.sh
├── validate.sh
├── config.json
└── prompts/
    ├── AGENTS.snippet.md    # Added to AGENTS.md
    └── TOOLS.snippet.md     # Added to TOOLS.md
```

Snippets are assembled into final prompts by the prompt assembly system. See `templates/prompts/README.md` for details, or use the `/prompts` skill.

## Usage

```bash
# From bruba-godo root directory
./components/signal/setup.sh

# Or use the /component skill
/component setup signal
/component validate signal
```

## Creating New Components

1. Create directory under `components/`
2. Add README.md with:
   - Overview
   - Prerequisites
   - Setup steps
   - Configuration options
   - Troubleshooting
3. Add setup.sh with:
   - Prerequisite checks
   - Interactive configuration
   - Config file updates
   - Verification
4. Add validate.sh with:
   - Configuration checks
   - Dependency verification
   - `--fix` flag for remediation hints
   - `--quick` flag to skip slow checks
5. Add config.json with the config fragment
6. (Optional) Add prompts/ directory with snippet files

### Template

```
components/
└── my-component/
    ├── README.md        # Documentation
    ├── setup.sh         # Setup script
    ├── validate.sh      # Validation checks
    ├── config.json      # Config to merge
    └── prompts/         # Optional prompt additions
        └── AGENTS.snippet.md
```

## Notes

- Components are optional — base bot works without them
- Each component is self-contained with its own docs
- Setup scripts are idempotent — safe to re-run
- Components may require additional software on the remote machine
- Prompt snippets are assembled by `/sync` into final prompts
