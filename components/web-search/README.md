# Web Search Component

**Status:** Partial

Provides web search capability through a sandboxed sub-agent architecture. The main agent cannot access web tools directly; instead it invokes a restricted `web-reader` agent that runs in a Docker sandbox.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Main Agent (bruba-main)                                    │
│  - No web_fetch/web_search tools                            │
│  - Calls web-search.sh via exec allowlist                   │
└─────────────────┬───────────────────────────────────────────┘
                  │ exec
                  ▼
┌─────────────────────────────────────────────────────────────┐
│  web-search.sh wrapper                                      │
│  - Invokes web-reader agent with query                      │
│  - Returns JSON response                                    │
└─────────────────┬───────────────────────────────────────────┘
                  │ clawdbot agent --agent web-reader
                  ▼
┌─────────────────────────────────────────────────────────────┐
│  Web Reader Agent (web-reader)                              │
│  - Runs in Docker sandbox (sandbox.mode: "all")             │
│  - Has web_fetch, web_search, read tools only               │
│  - No exec, write, edit, memory access                      │
└─────────────────────────────────────────────────────────────┘
```

## Security Properties

- **Tool isolation:** Main agent cannot directly access web tools
- **Sandboxed execution:** Reader runs in Docker with no network access to local services
- **Minimal permissions:** Reader has read-only access, no exec/write/edit
- **Controlled interface:** Only the allowlisted wrapper script can invoke the reader

## Scripts

### `tools/web-search.sh`

Wrapper script that invokes the web-reader agent. Add to main agent's exec-approvals:

```json
{
  "pattern": "/Users/bruba/clawd/tools/web-search.sh",
  "id": "web-search-wrapper"
}
```

### `tools/ensure-web-reader.sh`

Ensures the web-reader Docker container is running. The sandbox stops when idle, so this script starts it by sending a ping to the agent.

Use cases:
- Run at login via launchd (see full-setup-guide.md)
- Health check before web searches
- Manual container recovery

## Prerequisites

1. **Docker Desktop** running and configured to start at login
2. **Multi-agent setup** in `~/.clawdbot/clawdbot.json`:

```json
{
  "agents": {
    "list": [
      {
        "id": "web-reader",
        "name": "Web Reader",
        "workspace": "~/bruba-reader",
        "sandbox": { "mode": "all" },
        "tools": {
          "allow": ["web_fetch", "web_search", "read"],
          "deny": ["exec", "write", "edit", "memory_search"]
        }
      }
    ]
  },
  "tools": {
    "agentToAgent": {
      "enabled": true,
      "allow": ["web-reader"]
    }
  }
}
```

3. **Brave Search API** configured in clawdbot for web_search tool

## Setup

1. Sync scripts to bot:
   ```bash
   # Sync all component tools (including web-search)
   ./tools/push.sh --tools-only

   # Or as part of regular push
   ./tools/push.sh
   ```

2. Add to exec-approvals on bot:
   ```bash
   ssh bruba 'cat ~/.clawdbot/exec-approvals.json | jq ".agents[\"bruba-main\"].allowlist += [
     {\"pattern\": \"/Users/bruba/clawd/tools/web-search.sh\", \"id\": \"web-search-wrapper\"},
     {\"pattern\": \"/Users/bruba/clawd/tools/ensure-web-reader.sh\", \"id\": \"ensure-web-reader\"}
   ]" > /tmp/ea.json && mv /tmp/ea.json ~/.clawdbot/exec-approvals.json'
   ```

3. (Optional) Set up auto-start - see `docs/full-setup-guide.md` "Web Reader Auto-Start" section

## Usage

From the main agent, web searches are triggered via:

```bash
/Users/bruba/clawd/tools/web-search.sh "search query here"
```

The script returns JSON with the reader's response.

## Notes

**What exists:**
- `prompts/AGENTS.snippet.md` — Web search instructions for the bot
- `tools/web-search.sh` — Wrapper script for web reader agent
- `tools/ensure-web-reader.sh` — Container management script
- `allowlist.json` — Exec-approvals entries

**TODO:**
- `setup.sh` — Interactive setup script
- `validate.sh` — Docker/agent config validation
