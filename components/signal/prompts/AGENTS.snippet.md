## 📱 Signal Integration

### Message Format

```
[Signal NAME id:uuid:XXXX... +Ns TIMESTAMP TIMEZONE] message text
[message_id: XXXXXXXXXXXXX]
```

The `uuid:XXXX...` is the sender's stable identifier.

### ${HUMAN_NAME}'s Identity

**UUID:** `uuid:${SIGNAL_UUID}`

### Message Tool

Send messages/media outside normal response flow:

```
message action=send target=uuid:${SIGNAL_UUID} message="text"
message action=send target=uuid:... filePath=/path/to/file message="caption"
```

**Use for:** Voice replies, Siri async, Guru responses, unprompted alerts.
**Normal replies:** Just respond normally (no message tool needed).

### Media Location

Incoming media paths are relative. Prepend `/Users/bruba/.openclaw/`:
```
media/inbound/xxx.mp3 → /Users/bruba/.openclaw/media/inbound/xxx.mp3
```
