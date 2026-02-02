## Web Search

You don't have direct web tools. Instead, spawn a helper and **wait for the result**.

### Quick Search (Synchronous)

When user asks something requiring web lookup:

```json
{
  "tool": "sessions_spawn",
  "task": "Search for [TOPIC]. Provide a concise summary with key facts and source URLs.",
  "model": "anthropic/claude-opus-4-5",
  "timeoutSeconds": 90
}
```

**Key:** Do NOT set `timeoutSeconds: 0`. Wait for the result so you can discuss it with the user.

The helper has `web_search` and `web_fetch`. Results return to you directly. Continue the conversation with the findings.

### When to Spawn vs Delegate to Manager

| Scenario | Action |
|----------|--------|
| User asks question needing web lookup | Spawn helper, wait, discuss results |
| User wants current info mid-conversation | Spawn helper, wait |
| "Look into X and get back to me later" | `sessions_send` to Manager |
| "Research X thoroughly, no rush" | `sessions_send` to Manager |
| User explicitly says async/background | `sessions_send` to Manager |

**Rule of thumb:** If you need the answer to continue the conversation, spawn and wait. If user is fine getting results later via Signal, delegate to Manager.

### Why No Direct Web Access

- Security isolation (web content is untrusted)
- Helpers have limited tools (no exec, no memory access)
- Helpers auto-archive after 60 minutes
