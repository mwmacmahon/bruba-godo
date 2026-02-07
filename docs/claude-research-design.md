---
type: doc
scope: reference
title: "Claude Research Design"
---

# Claude Research — Design Document

## Overview

The `claude-sync` component enables bruba-main and bruba-rex to delegate research questions to Claude.ai Project conversations via Playwright browser automation. This is the first feature using claude-sync infrastructure (persistent Chromium profile, Python venv, externalized selectors).

## Architecture

```
Operator (bruba-godo)                          Bot (/Users/bruba/)
========================                       ========================
components/claude-sync/                        /Users/bruba/claude-sync/
  tools/                                         .venv/
    claude-research.sh  --push→ SHARED_TOOLS       claude-research.py
  bot-deploy/                                      common.py
    claude-research.py  --setup.sh deploys→        selectors.json
    common.py                                      profile/  (Chromium)
    selectors.json                                 results/  (output)
    requirements.txt
  setup.sh, validate.sh
  allowlist.json
  prompts/
    AGENTS.snippet.md
    Claude Research.md
```

### Key Design Decisions

1. **Synchronous exec** — The tool runs as a blocking `exec` call. Bot sends question, waits for response, reads result file. Simple, no polling needed.

2. **Persistent Chromium profile** — Auth cookies survive across invocations. No need to log in per-request. Auth expires periodically; exit code 2 signals this.

3. **Externalized selectors** — CSS selectors live in `selectors.json`, not hardcoded. When claude.ai UI changes, update selectors without touching Python code. Discover new selectors via `setup.sh --inspect`.

4. **Bot-deploy pattern** — Python code deploys to `/Users/bruba/claude-sync/` via `setup.sh`, NOT via the normal push pipeline. This keeps automation code separate from agent workspace content.

5. **Shell wrapper in SHARED_TOOLS** — `claude-research.sh` syncs to SHARED_TOOLS via normal push. It activates the venv and delegates to the Python script. This matches the pattern used by reminders and other exec tools.

6. **Research prefix for auto-titling** — Questions are prefixed with `[Research: topic]` so conversations in the Claude.ai project get meaningful titles automatically.

7. **Artifact suppression** — Appends "respond in plain markdown without using Artifacts" since we can only extract text content, not artifact panels.

## Data Flow

```
Bot exec → claude-research.sh
  → activates /Users/bruba/claude-sync/.venv
  → runs claude-research.py
    → loads selectors.json
    → launches Chromium with persistent profile
    → navigates to project URL
    → starts new chat
    → types question + submits
    → waits for response (streaming complete)
    → extracts response text
    → writes markdown result with YAML frontmatter
    → prints output path to stdout
  → bot reads result file
```

## Exit Codes

| Code | Meaning | Bot Action |
|------|---------|------------|
| 0 | Success | Read output file path from stdout |
| 1 | Error | Report error, check stderr |
| 2 | Auth expired | Tell user to run `setup.sh --login` |

## Security Considerations

- Browser runs on bot machine (same trust domain as all exec tools)
- Persistent profile contains auth cookies — profile directory should be user-readable only
- No credentials stored in code — auth is via browser session
- Selectors.json contains no secrets

## Future Extensions

- Additional tools beyond research (e.g., claude-review for code review projects)
- Multiple browser profiles for different accounts
- Response caching for repeated queries
- Health check cron job for auth status
