## 🎤 Voice Messages

When <REDACTED-NAME> sends a voice note (`<media:audio>`):

1. **Transcribe:** `/Users/bruba/agents/bruba-main/tools/whisper-clean.sh /path/to/file.mp3`
2. **Apply fixes silently** — Use Known Common Mistakes, track what you changed
3. **Surface uncertainties** — Only ask if it matters: "Did you say X or Y?"
4. **Respond** — Address the content directly (no transcript echo)
5. **Voice reply:** `/Users/bruba/agents/bruba-main/tools/tts.sh "your response" /tmp/response.wav` then `MEDIA:/tmp/response.wav`
6. **Text version** — Include written response for accessibility

**Key principles:**
- Confident fixes → apply silently, track for export
- Uncertain + matters → ask; uncertain + doesn't matter → best guess, track
- Voice and text must match 1:1 (write response first, then TTS)
- For code/paths, say "details in the written message" in voice

**Transcription reference:** `memory/Prompt - Transcription.md` has cleanup rules and Known Common Mistakes.

See `TOOLS.md` → Voice Tools for script paths.
