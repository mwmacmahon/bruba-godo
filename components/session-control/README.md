# Session Control Component

**Status:** Ready

Session management scripts for the Bruba multi-agent system. Provides real session reset, compaction, status checking, and message broadcasting — replacing the broken `sessions_send "/reset"` approach.

## Overview

- **session-status.sh** — Show session health (tokens, model, session ID) for one or all agents
- **session-reset.sh** — Reset sessions via `openclaw gateway call sessions.reset` (the only working method)
- **session-compact.sh** — Force compaction via `openclaw gateway call sessions.compact`
- **session-broadcast.sh** — Send templated messages to agent groups (prep, export, wake)

All scripts are deployed to `/Users/bruba/agents/bruba-shared/tools/` on the bot.

## Why This Exists

`sessions_send "/reset"` does not trigger real OpenClaw operations. Agents interpret slash commands as text and respond conversationally ("Session cleared.") — no actual reset occurs. Same for `/compact` and `/status`.

The only confirmed working methods use `openclaw gateway call`:
- `sessions.reset` — real reset (new session ID, tokens to 0)
- `sessions.compact` — real compaction
- `sessions.list` — real session data

## Usage

```bash
# Via ./tools/bot from operator machine
./tools/bot '/Users/bruba/agents/bruba-shared/tools/session-status.sh all'
./tools/bot '/Users/bruba/agents/bruba-shared/tools/session-reset.sh bruba-web'
./tools/bot '/Users/bruba/agents/bruba-shared/tools/session-compact.sh bruba-guru'

# From agents via exec (in exec-approvals allowlist)
exec /Users/bruba/agents/bruba-shared/tools/session-reset.sh all
exec /Users/bruba/agents/bruba-shared/tools/session-status.sh bruba-main
```

## Files

```
components/session-control/
├── README.md
├── allowlist.json            # Exec-approval entries for agents
├── tools/
│   ├── session-status.sh     # Show session health
│   ├── session-reset.sh      # Reset via gateway call
│   ├── session-compact.sh    # Compact via gateway call
│   └── session-broadcast.sh  # Send messages to agent groups
└── messages/
    ├── prep.txt              # Standard continuation packet request
    ├── prep-technical.txt    # Technical continuation packet request (guru)
    ├── export.txt            # Export trigger message
    ├── wake.txt              # Wake message with CONTINUATION.md hint
    └── wake-simple.txt       # Wake message without CONTINUATION.md hint
```

## Nightly Cron Integration

The `nightly-reset` cron job (4:08 AM ET) runs:
```
exec /Users/bruba/agents/bruba-shared/tools/session-reset.sh all
```

This resets all agents including Manager, replacing the previous broken 7-job, 2-cycle architecture with a single working command.

## Exec Approvals

The `allowlist.json` provides entries for:
- All 4 session-control scripts (with and without args)
- Direct `openclaw gateway call` commands for sessions.reset, sessions.compact, sessions.list

Added to `allowlist_sections` for: bruba-main, bruba-manager, bruba-rex.
