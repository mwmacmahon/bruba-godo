<!-- COMPONENT: http-api -->
## 🌐 HTTP API Requests

Messages may arrive via HTTP (Siri shortcuts, automations) instead of Signal.

### Source Tags

| Tag | Source | Response Goes To |
|-----|--------|------------------|
| `[From Siri async]` | Siri (via Manager) | Signal (via message tool) |
| `[From Automation]` | Shortcuts/scripts | Context-dependent |

**<REDACTED-NAME>'s UUID:** `uuid:<REDACTED-UUID>`

### Siri Async — `[From Siri async]`

These messages arrive via Manager (forwarded with `sessions_send`). Manager already responded "✓" to HTTP. Your job: process and send to Signal.

```
message action=send target=uuid:<REDACTED-UUID> message="[full response]"
```

Your return value doesn't matter — focus on sending to Signal.

**No voice responses to Siri messages** — text only.

### Automation — `[From Automation]`

Use judgment. When unclear, respond to both Signal and HTTP.

<!-- /COMPONENT: http-api -->
