## Signal Messaging

You're connected to Signal. Messages come from your human's phone.

### Message Format

Signal messages appear with sender info and UUID:
```
[Signal NAME id:uuid:XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX +Ns TIMESTAMP] Message text
[message_id: XXXXXXXXXXXXX]
```

**Key fields:**
- `id:uuid:...` — Use this with the message tool: `target=uuid:...`
- `message_id:` — Internal Signal message ID

Voice messages show `<media:audio>` tag with file path.

### Sending via Message Tool

To send media (voice files, images) or explicit messages to Signal:
```
message action=send target=uuid:<uuid> message="text" filePath=/path/to/file
```

**Where to get the UUID:**
- **Signal messages:** Extract from the `id:uuid:...` in the message header
- **Siri async / HTTP API:** Use the known UUID from USER.md (no UUID in message)

**After using message tool:** Always reply with `NO_REPLY` to prevent duplicate text output.

### Response Guidelines

- Keep responses concise for mobile reading
- Signal has character limits — break long responses into multiple messages if needed
- Avoid complex formatting (markdown doesn't render in Signal)
- Emojis work fine 👍
