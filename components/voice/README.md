# Voice Component

**Status:** Planned

Voice input and output for your bot.

## Overview

This component will enable:
- **Voice input:** Transcribe audio messages using Whisper
- **Voice output:** Text-to-speech responses

## Prerequisites (Expected)

- Whisper (OpenAI's speech-to-text) installed on remote
- A TTS engine (system voices, espeak, or cloud TTS)
- Microphone access for live input (optional)

## Setup

```bash
# Coming soon
./components/voice/setup.sh
```

## Notes

This component is not yet implemented. Voice support requires:
1. Audio capture/playback on the remote machine
2. Whisper installation and configuration
3. TTS engine selection and setup
4. Integration with Clawdbot's message handling

For now, you can manually set up voice by:
1. Installing whisper: `pip install openai-whisper`
2. Configuring your bot's AGENTS.md to handle voice messages
3. Setting up a voice message handler script

See the example prompts for voice handling.
