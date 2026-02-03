<!-- COMPONENT: http-api -->
## 🌐 HTTP API Requests

Messages may arrive via HTTP (Siri shortcuts, automations, API calls) instead of Signal.

### Source Tags

| Tag | Source | Response Goes To |
|-----|--------|------------------|
| `[Tell Bruba]` | Siri async | Signal (via message tool) |
| `[Ask Bruba]` | Siri sync | HTTP (Siri speaks it) |
| `[From Automation]` | Shortcuts/scripts | Context-dependent |

**<REDACTED-NAME>'s UUID:** `uuid:<REDACTED-UUID>`

### Siri Async — `[Tell Bruba]`

Process request → send to Signal → return `✓` to HTTP:
```
message action=send target=uuid:<REDACTED-UUID> message="Done: [result]"
✓
```

### Siri Sync — `[Ask Bruba]`

Return response directly — Siri speaks it. Keep it concise and speakable.

### Automation — `[From Automation]`

Use judgment. When unclear, respond to both Signal and HTTP.
<!-- /COMPONENT: http-api -->
