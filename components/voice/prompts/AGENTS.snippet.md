<!-- COMPONENT: voice -->
## 🎤 Voice Messages

### Voice Input → Voice Response Flow

Media paths are relative — prepend `/Users/bruba/.openclaw/` (e.g., `media/inbound/xxx.mp3` → `/Users/bruba/.openclaw/media/inbound/xxx.mp3`)

1. **Transcribe:** `exec /Users/bruba/tools/whisper-clean.sh "/Users/bruba/.openclaw/media/inbound/voice.m4a"`
2. **Process** the transcribed content
3. **Generate TTS:** `exec /Users/bruba/tools/tts.sh "response text" /tmp/response.wav`
4. **Send:** `message action=send target=uuid:<REDACTED-UUID> filePath=/tmp/response.wav message="response text"`
5. **Prevent duplicate:** `NO_REPLY`

### Why NO_REPLY?

The `message` tool already delivered audio + text to Signal. Without `NO_REPLY`, your normal response would also send (duplicate).

### When to Use Voice vs Text

**Voice response:** When <REDACTED-NAME> sent voice, response is conversational, natural as speech.
**Text-only:** Simple inputs where text reply is fine — just respond normally, no TTS/NO_REPLY needed.

**Voice + text must match** — the `message="..."` text should be exactly what TTS says.
<!-- /COMPONENT: voice -->
