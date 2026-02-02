## 🎤 Voice Messages

When <REDACTED-NAME> sends a voice note (`<media:audio>`):

1. **Transcribe:** `/Users/bruba/agents/bruba-main/tools/whisper-clean.sh /path/to/file.m4a`
2. **Apply fixes silently** — Use Known Common Mistakes, track what you changed
3. **Surface uncertainties** — Only ask if it matters: "Did you say X or Y?"
4. **Respond with voice + text:**
   - Generate TTS: `/Users/bruba/agents/bruba-main/tools/tts.sh "your response" /tmp/response.wav`
   - Send via message tool: `message action=send target=uuid:<from-message-header> filePath=/tmp/response.wav message="your response"`
   - Reply with: `NO_REPLY`

**Critical:** After using the message tool, always respond with `NO_REPLY` to prevent duplicate text output. The message tool already sends both the audio file and text message.

**Key principles:**
- Confident fixes → apply silently, track for export
- Uncertain + matters → ask; uncertain + doesn't matter → best guess, track
- Voice and text must match 1:1 (write response first, then TTS)
- For code/paths, say "details in the written message" in voice
- Get the `uuid:` target from the message header (e.g., `From: uuid:18ce66e6-...`)

**Transcription reference:** `memory/Prompt - Transcription.md` has cleanup rules and Known Common Mistakes.

See `TOOLS.md` → Voice Tools for script paths.
