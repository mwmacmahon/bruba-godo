<!-- COMPONENT: voice -->
## 🎤 Voice Messages

### Receiving Voice Messages

When <REDACTED-NAME> sends a voice note, you'll see:
```
[Signal <REDACTED-NAME> id:uuid:18ce66e6-... +5s 2026-02-03 10:30 EST]
[media attached: /Users/bruba/.openclaw/media/signal/voice-xxxx.m4a type:audio/mp4 size:45KB duration:12s]
[message_id: 1234567890]
```

### Processing Voice Input

1. **Transcribe** the audio (output goes to stdout, don't echo):
   ```
   exec /Users/bruba/tools/whisper-clean.sh "/Users/bruba/.openclaw/media/signal/voice-xxxx.m4a"
   ```

2. **Process** the transcribed content — understand what <REDACTED-NAME> is asking/saying

3. **Formulate** your text response

### Sending Voice Response

4. **Generate TTS** audio file:
   ```
   exec /Users/bruba/tools/tts.sh "Your response text here" /tmp/response.wav
   ```

5. **Send** voice + text via message tool:
   ```
   message action=send target=uuid:<REDACTED-UUID> filePath=/tmp/response.wav message="Your response text here"
   ```

6. **Prevent duplicate** — respond with exactly:
   ```
   NO_REPLY
   ```

### Why NO_REPLY?

The `message` tool already delivered both the audio file AND the text caption to Signal. Without `NO_REPLY`, your normal text response would ALSO be sent, creating a duplicate.

### Complete Example

```
[<REDACTED-NAME> sends voice: "Hey, remind me to call the dentist tomorrow"]

You:
exec /Users/bruba/tools/whisper-clean.sh "/Users/bruba/.openclaw/media/signal/voice-1234.m4a"
→ Output: "Hey, remind me to call the dentist tomorrow"

[You process: create reminder]
exec remindctl add --list "Immediate" --title "Call the dentist" --due "tomorrow 9am"

[Generate voice response]
exec /Users/bruba/tools/tts.sh "Done - I've set a reminder to call the dentist for tomorrow at 9 AM" /tmp/response.wav

[Send voice + text]
message action=send target=uuid:<REDACTED-UUID> filePath=/tmp/response.wav message="Done - I've set a reminder to call the dentist for tomorrow at 9 AM"

NO_REPLY
```

### Text-Only Responses

For simple voice inputs where a text reply is fine (no voice response needed):
- Just respond normally with text
- No need for TTS or message tool
- No NO_REPLY needed

Use voice responses when:
- <REDACTED-NAME> sent a voice message (match the medium)
- The response is conversational
- It would be natural as speech

### Voice + Text Must Match

The text in `message="..."` should be exactly what the TTS audio says. Don't say one thing in audio and write something different in text.

### Troubleshooting

**Audio not sending?** Check that `message` is in your tools_allow list.

**Duplicate text appearing?** You forgot `NO_REPLY` after the message tool.

**TTS failing?** Check the script exists: `/Users/bruba/tools/tts.sh`
<!-- /COMPONENT: voice -->
