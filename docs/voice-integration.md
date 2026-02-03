# Voice Integration Guide

How voice messages work in the Bruba system, from Signal to agent and back. Also covers Siri integration for hands-free interaction.

---

## Overview

Voice handling is **automatic**. When a user sends a voice message:

1. OpenClaw transcribes it (Groq Whisper)
2. Agent receives text with `[Audio]` prefix
3. Agent responds with text
4. OpenClaw converts response to voice (ElevenLabs)
5. User receives audio + text in Signal

Agents are voice-agnostic — they just see text and respond with text.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         INBOUND VOICE                                │
│                                                                      │
│  User speaks → Signal → Voice file (.m4a)                           │
│                              ↓                                       │
│                    OpenClaw Gateway                                  │
│                         ↓                                            │
│              ┌─────────────────────┐                                │
│              │   Groq Whisper API  │  ← GROQ_API_KEY                │
│              │   (STT ~200ms)      │                                │
│              └──────────┬──────────┘                                │
│                         ↓                                            │
│              "[Audio] User audio message:                           │
│               <transcribed text>"                                   │
│                         ↓                                            │
│                    Agent (Bruba)                                     │
│                         ↓                                            │
│              Agent responds with text                                │
│                         ↓                                            │
│              ┌─────────────────────┐                                │
│              │   ElevenLabs API    │  ← ELEVENLABS_API_KEY          │
│              │   (TTS ~300ms)      │                                │
│              └──────────┬──────────┘                                │
│                         ↓                                            │
│              Audio file + text message                               │
│                         ↓                                            │
│                      Signal                                          │
│                         ↓                                            │
│              User hears voice response                               │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Configuration

### Managing Voice via config.yaml (Recommended)

Voice settings can be managed from `config.yaml` and synced to the bot:

```yaml
openclaw:
  voice:
    stt:
      enabled: true
      max_bytes: 20971520
      timeout_seconds: 120
      language: en
      models:
        - provider: groq
          model: whisper-large-v3-turbo
    tts:
      auto: inbound
      provider: elevenlabs
      max_text_length: 4000
      timeout_ms: 30000
      elevenlabs:
        voice_id: "M7ya1YbaeFaPXljg9BpK"
        model_id: "eleven_multilingual_v2"
        voice_settings:
          stability: 0.5
          similarity_boost: 0.75
          speed: 1.0
```

**Sync voice settings:**
```bash
./tools/sync-openclaw-config.sh --section=voice
```

**Note:** API keys (`GROQ_API_KEY`, `ELEVENLABS_API_KEY`) must be set directly in `openclaw.json` — they are not synced from config.yaml for security.

### openclaw.json Settings (Direct)

Voice config lives in the bot's `/Users/bruba/.openclaw/openclaw.json`:

```json
{
  "env": {
    "vars": {
      "GROQ_API_KEY": "gsk_...",
      "ELEVENLABS_API_KEY": "sk_..."
    }
  },
  "tools": {
    "media": {
      "audio": {
        "enabled": true,
        "maxBytes": 20971520,
        "timeoutSeconds": 120,
        "language": "en",
        "models": [
          { "provider": "groq", "model": "whisper-large-v3-turbo" }
        ]
      }
    }
  },
  "messages": {
    "tts": {
      "auto": "inbound",
      "provider": "elevenlabs",
      "maxTextLength": 4000,
      "timeoutMs": 30000,
      "elevenlabs": {
        "voiceId": "M7ya1YbaeFaPXljg9BpK",
        "modelId": "eleven_multilingual_v2",
        "voiceSettings": {
          "stability": 0.5,
          "similarityBoost": 0.75,
          "speed": 1.0
        }
      }
    }
  }
}
```

### Setting Reference

#### STT Settings (`tools.media.audio`)

| Setting | Default | Description |
|---------|---------|-------------|
| `enabled` | `true` | Master switch for automatic transcription |
| `maxBytes` | `20971520` | Max audio file size (20MB) |
| `timeoutSeconds` | `120` | Transcription timeout |
| `language` | `"en"` | Language hint (improves accuracy) |
| `models[].provider` | `"groq"` | STT provider |
| `models[].model` | `"whisper-large-v3-turbo"` | Whisper model variant |

#### TTS Settings (`messages.tts`)

| Setting | Default | Description |
|---------|---------|-------------|
| `auto` | `"inbound"` | When to auto-generate voice |
| `provider` | `"elevenlabs"` | TTS provider |
| `maxTextLength` | `4000` | Truncate responses longer than this |
| `timeoutMs` | `30000` | TTS generation timeout |

#### ElevenLabs Settings (`messages.tts.elevenlabs`)

| Setting | Default | Description |
|---------|---------|-------------|
| `voiceId` | — | Voice to use (from ElevenLabs dashboard) |
| `modelId` | `"eleven_multilingual_v2"` | ElevenLabs model |
| `voiceSettings.stability` | `0.5` | Lower = more expressive, higher = more consistent |
| `voiceSettings.similarityBoost` | `0.75` | How closely to match original voice |
| `voiceSettings.speed` | `1.0` | Playback speed (0.5-2.0) |

#### Auto Modes

| Mode | Behavior |
|------|----------|
| `"inbound"` | Voice reply only when user sent voice (recommended) |
| `"always"` | Always reply with voice, even to text messages |
| `"off"` | Never auto-TTS; use manual message tool if needed |

---

## API Keys

### Where Keys Are Stored

Keys are in two places:

1. **Local `.env`** (bruba-godo repo, gitignored):
   ```
   GROQ_API_KEY=gsk_...
   ELEVENLABS_API_KEY=sk_...
   ```

2. **Bot's openclaw.json** (`env.vars` section):
   ```json
   "env": {
     "vars": {
       "GROQ_API_KEY": "gsk_...",
       "ELEVENLABS_API_KEY": "sk_..."
     }
   }
   ```

The bot uses the keys in openclaw.json. The local `.env` is the source of truth for the operator.

### Getting API Keys

#### Groq (STT)

1. Go to https://console.groq.com/keys
2. Create new API key
3. Copy the `gsk_...` key

**Free tier:** Generous limits, more than enough for personal use.

#### ElevenLabs (TTS)

1. Go to https://elevenlabs.io/
2. Sign up / log in
3. Go to Profile → API Keys
4. Copy the `sk_...` key

**Pricing:** $5/month starter plan, ~$0.30 per 1000 characters.

### Updating Keys

To update keys on the bot:

```bash
# Update via jq
./tools/bot 'jq --arg key "NEW_KEY_HERE" ".env.vars.GROQ_API_KEY = \$key" /Users/bruba/.openclaw/openclaw.json > /tmp/oc.json && mv /tmp/oc.json /Users/bruba/.openclaw/openclaw.json'

# Restart gateway to pick up changes
./tools/bot 'openclaw gateway restart'
```

Or update both at once:

```bash
./tools/bot 'jq --arg groq "gsk_NEW" --arg eleven "sk_NEW" ".env.vars.GROQ_API_KEY = \$groq | .env.vars.ELEVENLABS_API_KEY = \$eleven" /Users/bruba/.openclaw/openclaw.json > /tmp/oc.json && mv /tmp/oc.json /Users/bruba/.openclaw/openclaw.json && openclaw gateway restart'
```

---

## Configuring Voices

### Finding Voice IDs

1. Go to ElevenLabs → Voices
2. Click on a voice
3. Copy the Voice ID from the URL or settings panel

**Current voice:** `M7ya1YbaeFaPXljg9BpK`

### Changing the Voice

```bash
./tools/bot 'jq ".messages.tts.elevenlabs.voiceId = \"NEW_VOICE_ID\"" /Users/bruba/.openclaw/openclaw.json > /tmp/oc.json && mv /tmp/oc.json /Users/bruba/.openclaw/openclaw.json && openclaw gateway restart'
```

### Voice Settings Tuning

| Setting | Effect |
|---------|--------|
| `stability: 0.3` | More expressive, varied intonation |
| `stability: 0.7` | More consistent, robotic |
| `similarityBoost: 0.5` | Less like original voice |
| `similarityBoost: 0.9` | Very close to original voice |
| `speed: 0.8` | Slower speech |
| `speed: 1.2` | Faster speech |

**Recommended starting point:**
- `stability: 0.5` — balanced
- `similarityBoost: 0.75` — recognizable but not uncanny
- `speed: 1.0` — normal

### Creating Custom Voices

ElevenLabs supports voice cloning:

1. Go to ElevenLabs → Voices → Add Voice
2. Upload audio samples (clean speech, 1-5 minutes total)
3. Name your voice
4. Copy the new Voice ID
5. Update openclaw.json

---

## Rollback to Manual Voice

If automatic voice has issues, you can disable it and use the old manual approach.

### Disable Automatic Voice

```bash
# Disable STT (agent will receive raw audio attachment)
./tools/bot 'jq ".tools.media.audio.enabled = false" /Users/bruba/.openclaw/openclaw.json > /tmp/oc.json && mv /tmp/oc.json /Users/bruba/.openclaw/openclaw.json'

# Disable TTS (agent responses stay as text)
./tools/bot 'jq ".messages.tts.auto = \"off\"" /Users/bruba/.openclaw/openclaw.json > /tmp/oc.json && mv /tmp/oc.json /Users/bruba/.openclaw/openclaw.json'

# Restart gateway
./tools/bot 'openclaw gateway restart'
```

### Restore Manual Voice Component

The old voice component snippet is in git history. To restore:

```bash
# Check out old version
git show HEAD~5:components/voice/prompts/AGENTS.snippet.md > components/voice/prompts/AGENTS.snippet.md

# Push to bot
./tools/assemble-prompts.sh && /push
```

### Manual Voice Workflow (Old System)

With automatic voice disabled, agents handle voice manually:

```
1. Transcribe: exec /Users/bruba/tools/whisper-clean.sh "/path/to/audio.m4a"
2. Process transcript
3. Generate TTS: exec /Users/bruba/tools/tts.sh "response" /tmp/response.wav
4. Send: message action=send target=uuid:... filePath=/tmp/response.wav message="response"
5. Suppress duplicate: NO_REPLY
```

---

## Troubleshooting

### Voice Not Being Transcribed

**Symptoms:** Agent receives `[Attachment: voice.m4a]` instead of `[Audio] User audio message:`

**Check:**
```bash
# Is STT enabled?
./tools/bot 'jq ".tools.media.audio.enabled" /Users/bruba/.openclaw/openclaw.json'

# Is Groq key set?
./tools/bot 'jq ".env.vars.GROQ_API_KEY" /Users/bruba/.openclaw/openclaw.json'

# Check logs for errors
./tools/bot 'grep -i "groq\|whisper\|transcri" /tmp/openclaw/openclaw-*.log | tail -20'
```

**Common causes:**
- `enabled: false`
- Missing or invalid GROQ_API_KEY
- Audio file too large (>20MB)
- Timeout (>120s)

### TTS Not Working

**Symptoms:** Agent responds with text only, no voice

**Check:**
```bash
# Is TTS auto enabled?
./tools/bot 'jq ".messages.tts.auto" /Users/bruba/.openclaw/openclaw.json'

# Is ElevenLabs key set?
./tools/bot 'jq ".env.vars.ELEVENLABS_API_KEY" /Users/bruba/.openclaw/openclaw.json'

# Check logs
./tools/bot 'grep -i "elevenlabs\|tts" /tmp/openclaw/openclaw-*.log | tail -20'
```

**Common causes:**
- `auto: "off"`
- Missing or invalid ELEVENLABS_API_KEY
- Invalid voiceId
- Response too long (truncated silently)
- Inbound wasn't voice (with `auto: "inbound"`)

### Response Truncated

**Symptoms:** Voice cuts off mid-sentence

**Cause:** Response exceeded `maxTextLength` (default 4000 chars)

**Solutions:**
1. Increase limit: `jq ".messages.tts.maxTextLength = 8000" ...`
2. Agent guidance: Keep voice responses concise

### Voice Quality Issues

**Symptoms:** Voice sounds robotic, unnatural, or garbled

**Try:**
1. Adjust stability (lower = more natural, higher = more consistent)
2. Try different voice
3. Check ElevenLabs model (`eleven_multilingual_v2` is best quality)

### Checking Logs

```bash
# All voice-related logs
./tools/bot 'grep -iE "audio|tts|whisper|groq|elevenlabs|voice" /tmp/openclaw/openclaw-*.log | tail -50'

# Just errors
./tools/bot 'grep -iE "error|fail" /tmp/openclaw/openclaw-*.log | grep -iE "audio|tts|voice" | tail -20'
```

---

## Cost Estimates

| Service | Cost | Usage Pattern | Monthly Estimate |
|---------|------|---------------|------------------|
| Groq Whisper | Free tier | ~10 voice messages/day | $0 |
| ElevenLabs | $0.30/1000 chars | ~500 chars/response, 10/day | ~$4.50 |

**Total:** ~$5-10/month for moderate voice usage

---

## Provider Alternatives

### STT Alternatives

| Provider | Speed | Quality | Cost |
|----------|-------|---------|------|
| **Groq** (current) | 216x realtime | Excellent | Free tier |
| OpenAI Whisper API | ~1x realtime | Excellent | $0.006/min |
| Local Whisper | Varies | Good | Free (CPU cost) |

To switch STT provider, update `tools.media.audio.models[0].provider`.

### TTS Alternatives

| Provider | Quality | Latency | Cost |
|----------|---------|---------|------|
| **ElevenLabs** (current) | Best | 200-500ms | $0.30/1000 chars |
| OpenAI TTS | Good | 100-300ms | $0.015/1000 chars |
| Sherpa-ONNX (local) | Okay | 50-100ms | Free |

To switch TTS provider, update `messages.tts.provider`.

---

## Siri Integration

Siri provides hands-free access to Bruba via iOS Shortcuts. All Siri requests are **async-only** — Siri acknowledges immediately, and responses arrive in Signal.

### How It Works

```
User: "Hey Siri, tell Bruba..."
     ↓
iOS Shortcut → HTTP POST to OpenClaw
     ↓ (model: openclaw:manager)
Manager receives: "[From Siri async] <user's message>"
     ↓
Manager: sessions_send to Main (timeoutSeconds=0, fire-and-forget)
     ↓
Manager returns "✓" to HTTP (~2-3 seconds)
     ↓
Siri says: "Got it, I'll message you"

[Meanwhile, async:]
Main processes request (20-30 seconds, full Opus thinking)
     ↓
Main: message tool → Signal
     ↓
User sees response in Signal
```

### Why This Architecture?

**Problem:** Siri has a 10-15 second HTTP timeout. Main (Opus) takes 20-30 seconds for thoughtful responses.

**Solution:** Manager acts as a fast HTTP front door:
1. Manager (Sonnet) finishes in ~2 seconds — just forwards and returns "✓"
2. Main (Opus) processes async with no time pressure
3. Response goes to Signal, not back through HTTP

### iOS Shortcut Setup

Create a Shortcut with these actions:

```
1. Ask for Input (or accept Siri dictation)
   - Type: Text
   - Prompt: "What do you want to tell Bruba?"

2. Get Contents of URL
   - URL: https://your-bruba.ts.net/v1/chat/completions
   - Method: POST
   - Headers:
     - Content-Type: application/json
   - Request Body: JSON
     {
       "model": "openclaw:manager",
       "messages": [{
         "role": "user",
         "content": "[From Siri async] [Input from Step 1]"
       }]
     }

3. Speak Text
   - Text: "Got it, I'll message you"
```

**Important:** The model must be `openclaw:manager` (not `openclaw:main`) to get fast HTTP response.

### Tag Convention

Single tag: `[From Siri async]`
- Signals to Manager: forward to Main, return immediately
- Signals to Main: respond via Signal message tool (HTTP already responded)

### Removed: Synchronous Siri ("Ask Bruba")

Previously there was a sync pattern where Siri would wait for a response:

```
[Ask Bruba] → Manager answers directly → HTTP response → Siri speaks it
```

**Why removed:**
1. **Timeout risk:** Even Sonnet can exceed Siri's timeout on complex questions
2. **Quality tradeoff:** Quick answers sacrifice depth for speed
3. **Inconsistent UX:** Sometimes fast enough, sometimes timeout
4. **Complexity:** Two patterns to maintain, two Shortcuts to create

The async pattern is simpler and more reliable — always acknowledge fast, always respond fully.

### No Voice in Siri Responses

Siri responses go to Signal as **text only** — no voice/TTS.

**Why:**
- User initiated via voice (Siri), doesn't need voice response
- Signal text is easier to reference later
- TTS adds latency and cost for no benefit

### Troubleshooting Siri

**Siri times out:**
- Verify Shortcut uses `model: openclaw:manager`
- Check Manager is running: `./tools/bot openclaw sessions list --agent bruba-manager`
- Check HTTP endpoint is reachable: `curl https://your-bruba.ts.net/v1/models`

**No response in Signal:**
- Check Main received the message: `./tools/bot openclaw sessions history --agent bruba-main | tail -20`
- Check Main can message: verify `message` tool in Main's config
- Check Signal UUID is correct in http-api component

**Manager returns error instead of "✓":**
- Check `siri-async` component is in Manager's config
- Run `/prompt-sync` to ensure prompts are deployed

---

## Related Files

| File | Purpose |
|------|---------|
| `.env` | Local API key storage (gitignored) |
| `components/voice/prompts/AGENTS.snippet.md` | Agent prompt for voice handling |
| `components/siri-async/prompts/AGENTS.snippet.md` | Manager prompt for Siri async routing |
| `components/http-api/prompts/AGENTS.snippet.md` | Main prompt for HTTP/Siri requests |
| `reference/refdocs/openclaw-voice-handling.md` | Bot memory reference |
| `docs/architecture-masterdoc.md` | Part 4: Voice Messages, Siri Integration sections |

---

## Version History

| Date | Change |
|------|--------|
| 2026-02-03 | Added Siri async via Manager pattern; removed sync "Ask Bruba" |
| 2026-02-03 | Migrated to automatic voice (Groq STT + ElevenLabs TTS) |
| Pre-2026-02 | Manual voice via whisper-clean.sh + tts.sh + message tool |
