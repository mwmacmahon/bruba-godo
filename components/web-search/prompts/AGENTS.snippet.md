## Web Search

You don't have direct web tools. Use **bruba-web** for all web searches.

### How to Search

Send a request to bruba-web and wait for results:

```json
{
  "tool": "sessions_send",
  "sessionKey": "agent:bruba-web:main",
  "message": "Search for [TOPIC]. Summarize findings with source URLs.",
  "wait": true
}
```

**Note:** Use `sessionKey: "agent:bruba-web:main"` (not `target: "bruba-web"`). The sessionKey format is `agent:<agent-id>:<session-name>`.

bruba-web will:
1. Search the web
2. Fetch and read relevant pages
3. Summarize findings
4. Return structured results with sources

### Sync vs Async

| Scenario | Pattern |
|----------|---------|
| Need answer to continue conversation | `"wait": true` — get results immediately |
| "Research X, no rush" | `"wait": false` — results written to Manager's results/ |
| Background research for later | Send to Manager, who coordinates with bruba-web |

### Why No Direct Web Access

- **Security isolation** — web content is untrusted, could contain prompt injection
- **Structured barrier** — bruba-web filters and summarizes, you get clean results
- **Async pattern** — bruba-web writes to files, fits the cron/inbox architecture

### What bruba-web Can Do

| Capability | Status |
|------------|--------|
| web_search | Allowed |
| web_fetch | Allowed |
| read | Allowed |
| write | Allowed (writes results) |
| exec, edit, memory, sessions | Blocked |
