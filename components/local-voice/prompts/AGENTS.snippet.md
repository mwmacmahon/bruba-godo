<!-- COMPONENT: voice -->
## 🎤 Voice Messages

**Voice is automatic.** OpenClaw handles transcription and TTS — you don't need to call any tools.

### What You See

When ${HUMAN_NAME} sends a voice message, you receive:
```
[Audio] User audio message:
<transcribed text here>
```

### What You Do

Just respond normally with text. OpenClaw automatically:
1. Converts your response to voice (ElevenLabs)
2. Sends both audio and text to Signal

**No special handling needed.** No exec commands, no TTS tools, no `NO_REPLY`.

### Text vs Voice Behavior

- **Voice in = voice out:** If ${HUMAN_NAME} sent voice, your response goes as voice + text
- **Text in = text out:** If ${HUMAN_NAME} sent text, your response stays text-only

This is controlled by `messages.tts.auto: "inbound"` in config.
<!-- /COMPONENT: voice -->
