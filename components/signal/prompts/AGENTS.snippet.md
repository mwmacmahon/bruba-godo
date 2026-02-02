<!-- COMPONENT: signal -->
## 📱 Signal Integration

### Message Format

Signal messages arrive with metadata in the header:

```
[Signal NAME id:uuid:XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX +Ns TIMESTAMP TIMEZONE] message text
[message_id: XXXXXXXXXXXXX]
```

**Components:**
- `NAME` — Sender's Signal display name
- `uuid:XXXX...` — Sender's unique Signal identifier (stable, doesn't change)
- `+Ns` — Seconds since conversation started
- `TIMESTAMP` — When message was sent
- `message_id` — Unique ID for this message

### <REDACTED-NAME>'s Identity

- **Name:** <REDACTED-NAME> (or variations)
- **UUID:** `uuid:<REDACTED-UUID>`

This UUID is stable across sessions. It only changes if <REDACTED-NAME> re-registers his Signal account.

### Using the Message Tool

To send messages or media to Signal outside the normal response flow:

**Text only:**
```
message action=send target=uuid:<REDACTED-UUID> message="Your message here"
```

**With media (image, audio, file):**
```
message action=send target=uuid:<REDACTED-UUID> filePath=/path/to/file message="Caption text"
```

### When to Use Message Tool vs Normal Response

| Scenario | Use |
|----------|-----|
| Normal reply to Signal message | Normal response |
| Voice reply (audio file) | Message tool + NO_REPLY |
| Siri async (HTTP→Signal) | Message tool |
| Guru direct response | Message tool |
| Sending unprompted alert | Message tool |

### NO_REPLY Pattern

When you use the `message` tool AND you're bound to Signal (like bruba-main), follow with `NO_REPLY` to prevent duplicate delivery:

```
message action=send target=uuid:... message="response"
NO_REPLY
```

Without `NO_REPLY`, both the message tool delivery AND your normal response would go to Signal.

**Exception:** If you're NOT bound to Signal (like bruba-guru), you don't need `NO_REPLY` — your normal response goes back to the calling agent, not to Signal.

### Media Locations

Incoming media is stored at:
```
/Users/bruba/.openclaw/media/signal/
```

Files are named with timestamps and random suffixes for uniqueness.
<!-- /COMPONENT: signal -->
