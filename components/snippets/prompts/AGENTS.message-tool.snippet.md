<!-- COMPONENT: message-tool -->
## 📤 Direct Message Tool

The `message` tool sends content directly to messaging channels, outside the normal response flow.

### Signal Syntax

**Text only:**
```
message action=send target=uuid:<recipient-uuid> message="Your message"
```

**With media (audio, image, file):**
```
message action=send target=uuid:<recipient-uuid> filePath=/path/to/file message="Caption"
```

### BlueBubbles/iMessage Syntax

**Text only:**
```json
{ "action": "send", "channel": "bluebubbles", "target": "<phone-or-email>", "message": "Your message" }
```

**With attachment:**
```json
{ "action": "sendAttachment", "channel": "bluebubbles", "target": "<phone-or-email>", "path": "/path/to/file", "caption": "Caption" }
```

Target accepts E.164 phone number (e.g. `+15551234567`), email, or `chat_guid:...`.

### NO_REPLY Pattern

If you're bound to a messaging channel (like bruba-main → BlueBubbles), follow message tool with `NO_REPLY`:

```json
{ "action": "send", "channel": "bluebubbles", "target": "+1...", "message": "response" }
NO_REPLY
```

**Why?** Your normal response also goes to the channel. Without NO_REPLY = duplicate.

**Exception:** Agents NOT directly bound to a channel (bruba-guru, bruba-web) don't need NO_REPLY — their normal response goes back to the calling agent, not the channel.

### When to Use

| Scenario | Use Message Tool? | NO_REPLY? |
|----------|-------------------|-----------|
| Normal text reply | No | N/A |
| Voice reply | Yes | Yes |
| Siri async (HTTP) | Yes | No |
| Guru technical response | Yes | No |
| Sending image/file | Yes | Yes |
| Alert from Manager | No (via Main) | N/A |
<!-- /COMPONENT: message-tool -->
