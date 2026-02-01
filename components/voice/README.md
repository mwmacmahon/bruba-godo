# Voice Component

**Status:** Partial

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
# Sync voice tools to bot
./tools/push.sh --tools-only

# Or as part of regular push
./tools/push.sh
```

Tools are synced to `~/clawd/tools/` with executable permissions.

## Notes

**What exists:**
- `prompts/AGENTS.snippet.md` — Voice handling instructions for the bot
- `tools/` — Three voice processing scripts (dictation, transcription, TTS)
- `allowlist.json` — Exec-approvals entries for voice tools

**TODO:**
- `setup.sh` — Interactive setup script
- `validate.sh` — Configuration validation
