# Components

Optional add-ons for extending your bot's capabilities.

## Available Components

| Component | Status | Description |
|-----------|--------|-------------|
| [Signal](signal/) | **Ready** | Connect via Signal messenger (setup, validate, config) |
| [Distill](distill/) | **Ready** | Conversation-to-knowledge pipeline (full Python lib) |
| [Reminders](reminders/) | Partial | Scheduled reminders (tools, allowlist, prompts) |
| [Local Voice](local-voice/) | Partial | Voice input/output (tools, allowlist, prompts) |
| [Guru Routing](guru-routing/) | Prompt Ready | Technical deep-dive routing to -guru agent |
| [Snippets](snippets/) | **Ready** | 13 prompt-only snippets (session, memory, continuity, etc.) |

**Status key:**
- **Ready** — Full setup.sh, validate.sh, or self-contained prompt library
- **Partial** — Some pieces (tools or prompts) but not complete
- **Prompt Ready** — Prompt snippet only, may grow into full component

## Component Types

### Full components (setup, tools, config)

These have `setup.sh`, `validate.sh`, tools, or config fragments:
- `signal/` — Signal messaging channel
- `distill/` — Full Python pipeline for conversation processing
- `reminders/` — Reminder tools with exec allowlist
- `local-voice/` — Voice tools with exec allowlist

### Standalone prompt components

These contribute prompt snippets and may grow into full components:
- `guru-routing/` — Routing logic for technical specialist agent

### Snippets catch-all

Prompt-only additions consolidated in `snippets/` using variant naming:
- Use `snippets:variant-name` in config.yaml section lists
- See [snippets/README.md](snippets/README.md) for full variant list

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

components/snippets/
└── prompts/
    ├── AGENTS.session.snippet.md      # snippets:session
    ├── AGENTS.memory.snippet.md       # snippets:memory
    └── ...                            # 13 variants total
```

Snippets are assembled into final prompts by the prompt assembly system. See `templates/prompts/README.md` for details, or use the `/prompts` skill.

## Usage

```bash
# From bruba-godo root directory
./components/signal/setup.sh

# Or use the /component skill
/component setup signal
/component validate signal

# Validate all components
./tools/validate-components.sh
```

## Creating New Components

For prompt-only additions, add a variant to `snippets/`:
1. Create `components/snippets/prompts/AGENTS.{name}.snippet.md`
2. Add `snippets:{name}` to agents' section lists in config.yaml

For full components with code/tools/setup:
1. Create directory under `components/`
2. Add README.md, setup.sh, validate.sh, config.json as needed
3. Add `prompts/` directory with snippet files
4. Add component name to agents' section lists in config.yaml

## Component Tools

Some components include executable tools in `tools/` directories. These are automatically synced to the bot's shared tools during `/push`:

```bash
# Sync all component tools
./tools/push.sh --tools-only

# Or as part of regular push (content + tools)
./tools/push.sh
```

Components with tools:
- `local-voice/tools/` — TTS, transcription, voice status
- `reminders/tools/` — Reminder cleanup utilities

## Notes

- Components are optional — base bot works without them
- Each component is self-contained with its own docs
- Setup scripts are idempotent — safe to re-run
- Components may require additional software on the remote machine
- Prompt snippets are assembled by `/sync` into final prompts
- Component tools are synced by `/push` with executable permissions
