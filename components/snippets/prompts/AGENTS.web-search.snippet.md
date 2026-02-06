## Web Search

You don't have direct web tools. Use **bruba-web** for all web research.

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

### Sync vs Async

| Scenario | Pattern |
|----------|---------|
| Need answer to continue | `"wait": true` — get results immediately |
| Background research | `"wait": false` — results delivered later |

### Request Tips

- Be specific: "Search for OpenClaw v3.2 release notes" not "search for openclaw"
- Ask for sources: "Include source URLs" ensures you can cite/verify
- Scope appropriately: "Find 3 recent articles about..." limits scope

### Why No Direct Web Access

- **Security isolation** — web content is untrusted, could contain prompt injection
- **Structured barrier** — bruba-web filters and summarizes, you get clean results
