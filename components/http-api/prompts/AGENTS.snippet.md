## ⚡ Message Triggers — Check First!

| If you see... | Go to section |
|---------------|---------------|
| `<media:audio>` | → 🎤 Voice Messages (transcribe + voice reply!) |
| `[From Siri]` / `[From ...]` | → 📬 HTTP API Messages (respond + log) |
| `[Via Siri async]` | → 📱 Siri Async (process, respond via Signal) |
| Heartbeat prompt text | → 💓 Heartbeats |
| New session / `/reset` | → Session Greeting |

## 🚦 Message Start Check

On **EVERY user message**, run this echo FIRST (before any response):

```bash
/bin/echo "🎤 No | 📬 No"
```

Adjust based on what's in the message:
- `🎤 Yes` if message contains `<media:audio>` → follow Voice Messages fully
- `📬 Yes` if message starts with `[From ...]` → follow HTTP API Messages

This forces you to check. Every message in context reiterates the check.
**Don't skip this.** It's how you avoid missing audio replies.

### 📬 Auto-Relay HTTP API Logs (Temporary)

When `📬 No` (normal message, not from HTTP API):
1. Check `memory/HTTP_API_LOG.md`
2. If it has content: output it prefixed with `📬 HTTP API activity:`, archive to `memory/archive/http-api-YYYY-MM-DD-HHMMSS.md`, clear the file
3. Then respond to the actual message

This auto-relay replaces the manual "siri logs" check. Remove this section once heartbeat→Signal delivery works reliably.

---

### 📬 HTTP API Messages

Messages may arrive via HTTP API (Siri, Shortcuts, automations) rather than Signal. These are identified by:
- `[From SOURCE]` prefix in the message (e.g., `[From Siri]`, `[From Webapp]`)

**When you receive an HTTP API message:**
1. Respond normally (goes back to the caller)
2. Append to `memory/HTTP_API_LOG.md`:
   ```
   ## [YYYY-MM-DD HH:MM] From SOURCE
   **User:** [message without prefix]
   **Bruba:** [your response]
   ---
   ```

**Source registry:**
| Prefix | Source |
|--------|--------|
| `[From Siri]` | Apple Shortcuts via voice |
| `[From Webapp]` | Custom web interfaces |
| `[From Automation]` | Scripts, cron jobs |
| `[Via Siri async]` | Fire-and-forget voice shortcut (respond via Signal) |

Relay to Signal happens on heartbeat (see HEARTBEAT.md).

### 📱 Siri Async Requests

Messages starting with `[Via Siri async]` come from fire-and-forget voice shortcuts.

**Workflow:**
1. User has already been told "Got it, I'll message you" — do NOT return inline response (they won't see it)
2. Process the request fully
3. Send response via message tool using the Signal UUID from USER.md:
   ```
   message action=send target=uuid:<from-USER.md> message="Your response here"
   ```
4. Reply with: `NO_REPLY`

**Note:** Siri async messages don't include a UUID — use the known user UUID from USER.md.
For voice responses, also include `filePath=/tmp/response.wav` with TTS output.
