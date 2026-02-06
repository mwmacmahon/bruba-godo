## Session Control Tools

Scripts at `/Users/bruba/agents/bruba-shared/tools/`. All use `openclaw gateway call` (direct Gateway RPC, zero token cost).

### session-status.sh
```
exec session-status.sh [agent-id|all] [--json]
```
Shows per-agent: session key, total tokens, model, last update.
`--json` returns structured data for programmatic use.
Agents: `bruba-main bruba-manager bruba-guru bruba-rex bruba-web`

### session-reset.sh
```
exec session-reset.sh <agent-id|all> [--session <suffix>]
```
Resets session via `gateway call sessions.reset`. New sessionId, tokens → 0.
Default session suffix: `main`. Use `--session` for non-main sessions.
Output: `OK agent:<id>:main → <new-uuid>` or `FAIL` with error.

### session-compact.sh
```
exec session-compact.sh <agent-id|all> [--session <suffix>]
```
Forces compaction via `gateway call sessions.compact`.
Output: `OK agent:<id>:main compacted=true/false kept=N`
`compacted=false` means session was below threshold — not an error.

### session-broadcast.sh
```
exec session-broadcast.sh <message-file|string> [agent1 agent2 ...]
```
Sends message to multiple agents **in parallel** via `openclaw agent --message`.
⚠️ This DOES burn tokens (real agent turns). Use for prep/export/wake, not lifecycle ops.
Default targets: `bruba-main bruba-guru bruba-rex`.
Does NOT use `--deliver` (no Signal messages sent).

**Message templates:** `/Users/bruba/agents/bruba-shared/tools/messages/`
- `prep.txt` / `prep-technical.txt` — continuation packet request
- `export.txt` — nightly export trigger
- `wake.txt` / `wake-simple.txt` — post-reset wake messages

### Session Key Format
Pattern: `agent:<agent-id>:<suffix>`
Main sessions: `agent:bruba-main:main`
Cron sessions: `agent:bruba-main:cron:<job-uuid>`
All scripts default to `:main` suffix.
