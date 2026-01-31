## 🎤 Voice Messages

When <REDACTED-NAME> sends a voice note (`<media:audio>`):

1. **Extract audio path** from `[media attached: /path/to/file.mp3 ...]` line
2. **Transcribe:** `/Users/bruba/clawd/tools/whisper-clean.sh /path/to/file.mp3`
3. **Respond to the content**
4. **Reply with voice:**
   - Generate: `/Users/bruba/clawd/tools/tts.sh "your response" /tmp/response.wav`
   - Send: `MEDIA:/tmp/response.wav`
5. **Include text version** for reference/accessibility

**Voice/text must match 1:1:** Write your text response first, then TTS that exact text. Don't compose different content for voice vs text. For things that don't dictate well (code blocks, raw output, file paths), say "code omitted" or "details in the written message" in the voice version.

**Transcription cleanup:** When handling transcriptions (voice messages or pasted transcripts), load `memory/Prompt - Transcription.md` if not already in context. It contains cleanup rules and common Whisper mistakes (e.g., "brew bug" → "Bruba").

Auto-transcription is disabled — always manually transcribe `<media:audio>` messages.

See `TOOLS.md` → Voice Tools for script paths and technical details.
