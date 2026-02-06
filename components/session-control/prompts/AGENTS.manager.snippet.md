## Session Control

Session lifecycle scripts for monitoring and maintaining all agents. These use `openclaw gateway call` — zero tokens burned, direct RPC to Gateway.

**Nightly cycle uses these automatically.** Manual use when:
- Checking agent health between cycles
- An agent is stuck or context-bloated mid-day
- Gus asks for a status report or manual reset

| Task | Command |
|------|---------|
| Dashboard | `exec session-status.sh all` |
| Single agent | `exec session-status.sh bruba-guru` |
| JSON output | `exec session-status.sh all --json` |
| Reset one | `exec session-reset.sh bruba-guru` |
| Reset all | `exec session-reset.sh all` |
| Compact one | `exec session-compact.sh bruba-guru` |
| Compact all | `exec session-compact.sh all` |
| Broadcast msg | `exec session-broadcast.sh /path/to/message.txt bruba-main bruba-guru` |

**Broadcast templates:** Message templates are at the path shown in TOOLS.md.

See TOOLS.md for full syntax including `--session` targeting and broadcast details.
