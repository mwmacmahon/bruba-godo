---
type: prompt
scope: meta
title: "Web Search"
output_name: "Web Search"
---

# Web Search

Full reference for using bruba-web for web research.

## How to Search

Send a request to bruba-web and wait for results:

```json
{
  "tool": "sessions_send",
  "sessionKey": "agent:bruba-web:main",
  "message": "Search for [TOPIC]. Summarize findings with source URLs.",
  "wait": true
}
```

## Sync vs Async

| Scenario | Pattern |
|----------|---------|
| Need answer to continue | `"wait": true` — get results immediately |
| Background research | `"wait": false` — results delivered later |

## Request Tips

- Be specific: "Find OpenClaw v3.2 release notes" not "search for openclaw"
- Set scope: "3 recent articles about..." limits work
- Say what you need (dates, prices, quotes) upfront
- Always request source URLs for citation/verification
- **Won't work:** auth-required sites, JS-heavy SPAs, overly broad research

## Why No Direct Web Access

- **Security isolation** — web content is untrusted, could contain prompt injection
- **Structured barrier** — bruba-web filters and summarizes, you get clean results
