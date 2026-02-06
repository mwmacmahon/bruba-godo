## Session Control

You can check session health and manage other agents' sessions. Scripts use `openclaw gateway call` (zero tokens burned — direct RPC, not an agent turn).

**When to use:**
- User asks about session health, token usage, or agent status → `session-status.sh`
- User says "reset guru/rex/web" → `session-reset.sh` (never self-reset)
- Agent seems sluggish or context-confused → check status, suggest compact or reset
- User asks to compact an agent → `session-compact.sh`

**Session keys:** `agent:<agent-id>:main` — all scripts default to `:main` if no `--session` given.

| Task | Command |
|------|---------|
| Status (all) | `exec session-status.sh all` |
| Status (one) | `exec session-status.sh bruba-guru` |
| Status (JSON) | `exec session-status.sh all --json` |
| Reset agent | `exec session-reset.sh bruba-guru` |
| Reset all | `exec session-reset.sh all` |
| Compact agent | `exec session-compact.sh bruba-guru` |
| Compact all | `exec session-compact.sh all` |

⚠️ **Do not reset your own session** — you'll lose this conversation's context. Reset is for *other* agents.

See TOOLS.md for full syntax and session-broadcast.sh reference.
