<!-- COMPONENT: message-tool -->
## 📤 Direct Message Tool

The `message` tool sends content directly to Signal, outside the normal response flow.

### Basic Syntax

**Text only:**
```
message action=send target=uuid:<recipient-uuid> message="Your message"
```

**With media (audio, image, file):**
```
message action=send target=uuid:<recipient-uuid> filePath=/path/to/file message="Caption"
```

### ${HUMAN_NAME}'s Signal UUID

```
uuid:${SIGNAL_UUID}
```

### NO_REPLY Pattern

If you're bound to Signal (like bruba-main), follow message tool with `NO_REPLY`:

```
message action=send target=uuid:${SIGNAL_UUID} message="response"
NO_REPLY
```

**Why?** Your normal response also goes to Signal. Without NO_REPLY = duplicate.

**Exception:** Agents NOT bound to Signal (bruba-guru, bruba-web) don't need NO_REPLY — their normal response goes back to the calling agent, not Signal.

### Common Patterns

**Siri async (HTTP→Signal):**
```
message action=send target=uuid:${SIGNAL_UUID} message="response"
✓
```
(No NO_REPLY needed — HTTP responses don't go to Signal)

**Guru direct response:**
```
message action=send target=uuid:${SIGNAL_UUID} message="[full technical response]"
Summary: [one-liner for Main's tracking]
```
(No NO_REPLY — Guru returns to Main via sessions_send, not Signal)

### When to Use

| Scenario | Use Message Tool? | NO_REPLY? |
|----------|-------------------|-----------|
| Normal text reply | No | N/A |
| Voice reply | Yes | Yes |
| Siri async | Yes | No |
| Guru technical response | Yes | No |
| Sending image/file | Yes | Yes |
| Alert from Manager | No (via Main) | N/A |
<!-- /COMPONENT: message-tool -->
