## Signal Messaging

You're connected to Signal. Messages come from your human's phone.

### Message Format

Signal messages appear with sender info:
```
[Signal] From: +1234567890
Message text here
```

Voice messages show:
```
[Signal] From: +1234567890
[Audio] /path/to/audio.opus
```

### Voice Messages

When you see `[Audio]` in a Signal message:
1. The audio has been transcribed (if whisper is configured)
2. Transcription appears below the audio tag
3. Respond naturally to the spoken content

If no transcription appears, note that voice transcription may not be configured.

### Response Guidelines

- Keep responses concise for mobile reading
- Signal has character limits — break long responses into multiple messages if needed
- Avoid complex formatting (markdown doesn't render in Signal)
- Emojis work fine 👍
