---
version: 1.4.1
updated: 2026-01-28
type: refdoc
project: planning
tags: [bruba, voice, integration]
description: "Voice interaction for Bruba: local STT/TTS setup, model benchmarks, and future Signal call exploration"
---

# Bruba Voice Integration

Current state and setup for voice interaction with Bruba.

> **Claude Code:** If you discover new voice tools, better models, or updated setup/testing/benchmarking/etc procedures while working on voice features, update this document. Include benchmark results, script changes, or new integration approaches. If <REDACTED-NAME> decides he has new opinions about how voice integration should work different or expanded from what's here, please update this document as well. Version bump accordingly.

Make sure to notify <REDACTED-NAME> about these changes with a loud callout in your output text, but you don't have to ask permission (he validates git diffs).


## Current State

### Working

**Inbound (voice → text):**
- **Manual/prompt-driven:** Bruba runs `whisper-clean.sh` when it receives audio
- Auto-transcription disabled (Clawdbot's media pipeline doesn't work with wrapper scripts)
- `whisper-clean.sh` outputs clean text only (no timestamps, no warnings)
- Apple dictation → paste into chat → works fine

**Outbound (text → voice):**
- Local TTS via sherpa-onnx + Piper voice models ✓
- Wrapper script at `/Users/bruba/clawd/tools/tts.sh`
- Clean output (verbose sherpa-onnx noise suppressed)
- Bruba invokes explicitly (no auto-reply)

**Utility scripts (allowlisted in exec-approvals.json):**
- `/Users/bruba/clawd/tools/whisper-clean.sh` — transcribe audio (STT wrapper)
- `/Users/bruba/clawd/tools/tts.sh` — generate speech from text
- `/Users/bruba/clawd/tools/voice-status.sh` — show current config
- `/usr/bin/afplay` — play audio files

### Known Gaps

**Voice Memos:** Shared audio files from Voice Memos app come through as `<media:unknown>` and don't auto-transcribe. Bruba can manually transcribe any audio file path it receives.

**No auto-transcription:** Clawdbot's `tools.media.audio` pipeline doesn't work with wrapper scripts — the wrapper gets configured but never invoked. Workaround: Bruba handles voice manually via prompt instructions.

---

## Immediate Solution: Async Voice Loop

Simple turn-based voice conversation:

1. <REDACTED-NAME> sends Signal voice note → Whisper transcribes locally
2. Bruba responds → TTS generates audio → sends voice note back
3. <REDACTED-NAME> plays response, records next message
4. Repeat

**Why this works:**
- No VAD (voice activity detection) issues — explicit turn-taking
- No getting cut off mid-thought
- Privacy preserved with local Whisper + local TTS (Piper)
- Works today with existing infrastructure

### Setup Status

- [x] Set up Piper for local TTS (sherpa-onnx-tts skill + runtime)
- [x] Benchmark Whisper models on M4 Mac Mini
- [x] Document voice response behavior for Bruba

### How Voice Response Works (Prompt-Driven)

**Inbound (manual):** Auto-transcription is disabled. When <REDACTED-NAME> sends audio, Bruba sees `<media:audio>` with the file path and manually transcribes it.

**Outbound (manual):** Bruba explicitly invokes TTS. There's no automatic "reply with voice when voice received" behavior.

**Why manual/prompt-driven?**
- Clawdbot's `tools.media.audio` pipeline doesn't invoke wrapper scripts (tested extensively — configured but never called)
- Clawdbot's `messages.tts.auto` only supports ElevenLabs (cloud)
- Manual invocation gives Bruba full control and is easier to debug

**What Bruba does when receiving audio:**
1. Extract the audio path from the `[media attached: ...]` line
2. Run: `/Users/bruba/clawd/tools/whisper-clean.sh <audio-path>`
3. Respond to the transcribed content
4. Optionally reply with voice via tts.sh

**What Bruba does to reply with voice:**
1. Compose text response
2. Run: `/Users/bruba/clawd/tools/tts.sh "response text" /tmp/response.wav`
3. Send the audio file back (use `MEDIA:/tmp/response.wav` in reply)
4. Include text version for accessibility

This is documented in `/Users/bruba/clawd/TOOLS.md`.

### Installed Components

| Component | Location |
|-----------|----------|
| Whisper wrapper | `/Users/bruba/clawd/tools/whisper-clean.sh` |
| sherpa-onnx runtime | `~/.clawdbot/tools/sherpa-onnx-tts/runtime/` |
| Piper voice model | `~/.clawdbot/tools/sherpa-onnx-tts/models/vits-piper-en_US-lessac-high/` |
| TTS wrapper script | `/Users/bruba/clawd/tools/tts.sh` |
| Exec allowlist | `~/.clawdbot/exec-approvals.json` |

### Config Files Modified

**clawdbot.json** — audio transcription DISABLED (Clawdbot doesn't invoke wrapper scripts):
```json
{
  "tools": {
    "media": {
      "audio": {
        "enabled": false
      }
    }
  }
}
```

**clawdbot.json** — TTS skill environment:
```json
{
  "skills": {
    "entries": {
      "sherpa-onnx-tts": {
        "enabled": true,
        "env": {
          "SHERPA_ONNX_RUNTIME_DIR": "~/.clawdbot/tools/sherpa-onnx-tts/runtime",
          "SHERPA_ONNX_MODEL_DIR": "~/.clawdbot/tools/sherpa-onnx-tts/models/vits-piper-en_US-lessac-high"
        }
      }
    }
  }
}
```

**exec-approvals.json** — allowlisted commands (Bruba invokes these manually):
```json
{
  "agents": {
    "main": {
      "allowlist": [
        {"pattern": "/Users/bruba/clawd/tools/whisper-clean.sh"},
        {"pattern": "/Users/bruba/clawd/tools/tts.sh"},
        {"pattern": "/Users/bruba/clawd/tools/voice-status.sh"},
        {"pattern": "/usr/bin/afplay"}
      ]
    }
  }
}
```

**Why manual, not auto:**
- `tools.media.audio` with CLI provider: configured but never invoked (tested extensively)
- `tools.media.tts` is NOT a valid Clawdbot config key
- Auto-reply (`messages.tts.auto`) only supports ElevenLabs (cloud)
- Prompt-driven approach works and is easier to debug

---

## TTS Options

| Provider | Local | Quality | Privacy | Status |
|----------|-------|---------|---------|--------|
| **sherpa-onnx + Piper** | ✅ Yes | Good | ✅ Full | ✓ Installed |
| Edge TTS | ❌ No | Good | ⚠️ MS cloud | Available |
| ElevenLabs | ❌ No | Excellent | ⚠️ Cloud | Clawdbot `talk` node |
| OpenAI | ❌ No | Very good | ⚠️ Cloud | Available |
| macOS `say` | ✅ Yes | Basic | ✅ Full | Too robotic |

**Current setup:** sherpa-onnx with Piper `en_US-lessac-high` voice. Generates ~2x faster than playback on M4 (RTF ~0.5).

**Additional voices:** More Piper models available at [sherpa-onnx tts-models releases](https://github.com/k2-fsa/sherpa-onnx/releases). Download `.tar.bz2`, extract to `~/.clawdbot/tools/sherpa-onnx-tts/models/`, then update `SHERPA_ONNX_MODEL_DIR` in clawdbot.json.

---

## Whisper Model

Using `base` model only. Benchmarked all models on M4 Mac Mini (~9s audio):

| Model | RTF | Notes |
|-------|-----|-------|
| tiny | 0.20 | 5x faster, lower quality |
| **base** | 0.28 | **3.5x faster, good quality** ✓ |
| small | 1.9 | Slower than real-time |
| medium | 5.3 | Much slower |

RTF = Real-Time Factor. <1.0 is faster than real-time.

**Decision:** `base` is the sweet spot — fast enough for conversation, good enough quality. Other models deleted to save disk space (~2GB).

---

## North Star: Signal Voice Calls

Ideal future state:

1. Signal call Bruba → live voice conversation
2. Configurable VAD with generous silence thresholds
3. On hangup → full transcript drops into chat

### Blockers

- Signal voice calls are P2P encrypted WebRTC (RingRTC)
- signal-cli doesn't expose call audio (by design)
- No third-party API for Signal calls exists

### Potential Future Paths

- VoIP/SIP bridge
- Virtual audio device routing
- Alternative platform with call API (Telegram, custom app)
- Web-based voice interface

**Status:** Parked. The async voice loop solves the immediate need.

---

## Research Notes

**Clawdbot iOS/macOS apps:**
- Require building from source (Xcode + sideloading)
- Not on App Store or TestFlight
- Skipping for now — adds complexity without clear benefit over Signal workflow

**Signal's built-in TTS:**
- Terrible (robotic Windows 95 voice, too fast, breaks on formatting)
- The name "Bruba" originates from a comedy skit featuring this exact voice
- Not usable for actual responses

---

## Privacy Priorities

All voice processing is local:

| Component | Status | Privacy |
|-----------|--------|---------|
| Whisper STT | ✅ Installed | Full |
| Piper TTS | ✅ Installed | Full |
| Cloud TTS | Available | Acceptable as upgrade if vetted |

---

## Hardware

M4 Mac Mini provides capacity for:
- Larger Whisper models (small/medium)
- Local TTS (Piper)
- Potentially local LLM for some tasks

---

## Changelog

| Date | Change |
|------|--------|
| 2026-01-28 | v1.4.0: Switched to prompt-driven voice (auto-transcription disabled), cleaned up tts.sh output, documented why Clawdbot media pipeline doesn't work with wrappers |
| 2026-01-28 | v1.3.0: Added whisper-clean.sh wrapper for clean transcription output |
| 2026-01-27 | v1.2.0: Added exec allowlist config, full paths, removed invalid tools.media.tts |
| 2026-01-27 | v1.1.0: TTS installed (sherpa-onnx), benchmark results, clarified voice response behavior |
| 2025-01-27 | Initial doc created from planning session |