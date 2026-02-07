# Claude Sync Component

**Status:** In Development

Research delegation via Claude.ai Project conversations using Playwright browser automation. Lets bruba-main and bruba-rex send research questions to persistent Claude.ai Projects and get structured markdown results back.

## Architecture

```
Operator (bruba-godo)                          Bot (/Users/bruba/)
========================                       ========================
components/claude-sync/                        /Users/bruba/claude-sync/
  tools/                                         .venv/
    claude-research.sh  --push--> SHARED_TOOLS     claude-research.py
  bot-deploy/                                      common.py
    claude-research.py  --setup.sh deploys-->       selectors.json
    common.py                                      profile/  (Chromium)
    selectors.json                                 results/  (output)
    requirements.txt
  setup.sh, validate.sh
  allowlist.json
  prompts/
    AGENTS.snippet.md
    Claude Research.md
```

- **`tools/claude-research.sh`** syncs to `${SHARED_TOOLS}` via normal push
- **`bot-deploy/*`** deployed to `/Users/bruba/claude-sync/` via `setup.sh` (NOT auto-synced)
- **Persistent Chromium profile** keeps auth across sessions
- **Externalized selectors** (`selectors.json`) for easy updates when claude.ai UI changes

## Setup

```bash
# Deploy infrastructure to bot
./components/claude-sync/setup.sh

# Login to claude.ai (launches visible browser)
./components/claude-sync/setup.sh --login

# Discover/update CSS selectors
./components/claude-sync/setup.sh --inspect

# Validate installation
./components/claude-sync/validate.sh
```

## Usage

Add `claude-sync` to `agents_sections` and `allowlist_sections` in config.yaml:

```yaml
agents:
  my-agent:
    agents_sections:
      # ...
      - claude-sync
    allowlist_sections:
      # ...
      - claude-sync
```

## Files

```
components/claude-sync/
├── README.md
├── bot-deploy/
│   ├── claude-research.py    # Main Playwright automation
│   ├── common.py             # Shared utilities
│   ├── selectors.json        # Externalized CSS selectors
│   └── requirements.txt      # Python dependencies
├── tools/
│   └── claude-research.sh    # Shell wrapper (syncs to SHARED_TOOLS)
├── prompts/
│   ├── AGENTS.snippet.md     # Consumer snippet for main/rex
│   └── Claude Research.md    # Full on-demand prompt
├── allowlist.json            # Exec allowlist entries
├── setup.sh                  # Deploy to bot
└── validate.sh               # Validate installation
```
