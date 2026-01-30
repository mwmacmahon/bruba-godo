# Components

Optional add-ons for extending your bot's capabilities.

## Available Components

| Component | Status | Description |
|-----------|--------|-------------|
| [Signal](signal/) | **Ready** | Connect via Signal messenger |
| [Voice](voice/) | Planned | Voice input/output (whisper, TTS) |
| [Reminders](reminders/) | Planned | Scheduled reminders and notifications |
| [Web Search](web-search/) | Planned | Web search integration |
| [Distill](distill/) | **Core** | Conversation → knowledge pipeline |
| [HTTP-API](http-api/) | Planned | Siri/Shortcuts integration |
| [Calendar](calendar/) | Planned | Apple Calendar integration |
| [Continuity](continuity/) | Planned | Session reset with context preservation |

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

Snippets are assembled into final prompts by the `/sync` skill.

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
