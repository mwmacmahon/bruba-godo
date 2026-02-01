# Web Search Component

**Status:** Active

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

1. Copy scripts to bot:
   ```bash
   # Currently manual - component tool sync not yet implemented
   scp components/web-search/tools/*.sh bruba:~/clawd/tools/
   ssh bruba 'chmod +x ~/clawd/tools/web-search.sh ~/clawd/tools/ensure-web-reader.sh'
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

## TODO

- [ ] Component tool sync in `/push` (copy `components/*/tools/` to bot)
- [ ] AGENTS.snippet.md for web search instructions
- [ ] validate.sh for checking Docker/agent config
