# Components

Optional add-ons for extending your bot's capabilities.

## Available Components

| Component | Status | Description |
|-----------|--------|-------------|
| [Signal](signal/) | **Ready** | Connect via Signal messenger |
| [Voice](voice/) | Planned | Voice input/output (whisper, TTS) |
| [Reminders](reminders/) | Planned | Scheduled reminders and notifications |
| [Web Search](web-search/) | Planned | Web search integration |

## How Components Work

Each component provides:

1. **README.md** — What it does, prerequisites, how to use
2. **setup.sh** — Interactive setup script (run from bruba-godo root)
3. **config.json** — Config fragment to merge into clawdbot.json

## Usage

```bash
# From bruba-godo root directory
./components/signal/setup.sh

# Or if a /setup skill exists
/setup signal
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
4. Add config.json with the config fragment

### Template

```
components/
└── my-component/
    ├── README.md        # Documentation
    ├── setup.sh         # Setup script
    └── config.json      # Config to merge
```

## Notes

- Components are optional — base bot works without them
- Each component is self-contained with its own docs
- Setup scripts are idempotent — safe to re-run
- Components may require additional software on the remote machine
