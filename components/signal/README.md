# Signal Component

Connect to your bot via Signal messenger with voice support.

## Overview

This component enables the Signal channel in Clawdbot, allowing you to message your bot via Signal. Messages can be text or voice (voice messages are transcribed by the bot).

> **Framework vs Bot Name:** This guide uses "Clawdbot" for the framework software. Your bot's name (e.g., "Bruba") is yours to choose.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Quick Setup](#quick-setup)
3. [Manual Setup](#manual-setup)
4. [Voice Message Handling](#voice-message-handling)
5. [Agent Configuration](#agent-configuration)
6. [Troubleshooting](#troubleshooting)
7. [Security Notes](#security-notes)
8. [Migration Notes](#migration-notes)
9. [Quick Reference](#quick-reference)

---

## Prerequisites

- Clawdbot installed and daemon running (`clawdbot daemon status`)
- Java 17+ installed (required for signal-cli)
- A phone number for Signal (see options below)

### Phone Number Options

Signal requires a phone number. Options for your bot:

| Option | Pros | Cons |
|--------|------|------|
| **Google Voice** (free) | Free, easy to set up | US only, may need existing number to create |
| **Dedicated SIM** | Real number, reliable | Costs money, need device |
| **VoIP provider** | Cheap, disposable | Some blocked by Signal |
| **Your existing number** | Already have it | Bot shares your number (confusing) |

**Recommended:** Google Voice or dedicated SIM for clarity.

---

## Quick Setup

Run the setup script from the bruba-godo root:

```bash
./components/signal/setup.sh
```

The script will:
1. Check signal-cli is installed
2. Prompt for the bot's phone number
3. Generate a QR code for linking (if new account)
4. Update clawdbot.json to enable Signal channel
5. Set httpPort to 8088 (avoids conflicts)
6. Restart the daemon

---

## Manual Setup

### Part 1: Install signal-cli

signal-cli is the bridge between Signal and Clawdbot.

#### macOS (Homebrew)

```bash
brew install signal-cli
which signal-cli
# Should return: /opt/homebrew/bin/signal-cli
```

#### Linux

```bash
# Download latest release
VERSION="0.13.5"  # Check https://github.com/AsamK/signal-cli/releases
curl -LO "https://github.com/AsamK/signal-cli/releases/download/v${VERSION}/signal-cli-${VERSION}.tar.gz"
tar xf signal-cli-${VERSION}.tar.gz
sudo mv signal-cli-${VERSION} /opt/signal-cli
sudo ln -sf /opt/signal-cli/bin/signal-cli /usr/local/bin/signal-cli

# Verify
signal-cli --version
```

### Part 2: Link signal-cli to Your Phone

This links Clawdbot as a "linked device" to a Signal account (like Signal Desktop).

#### Critical: Use the Bot's Signal Account

**You must be logged into Signal on your phone with the BOT'S phone number**, not your personal account. The QR code scanning happens from within Signal, so you need to be logged into the account you want to link.

**Steps:**
1. Log out of your personal Signal account on your phone (or use a second device)
2. Log into Signal with the bot's phone number (Google Voice, dedicated SIM, etc.)
3. THEN proceed with linking below

#### Step 2.1: Generate the Linking URI

On the bot machine:

```bash
signal-cli link -n "YourBotName"
# Example: signal-cli link -n "Bruba"
```

This outputs a `sgnl://` URI. **Do not close this terminal** — it's waiting for you to scan.

#### Step 2.2: Generate QR Code

**CRITICAL: Do NOT use `qrencode` command** — it mishandles URL-encoded characters (`%3D`, `%2F`, `%2B`) and produces broken QR codes that Signal cannot read.

**Use https://qr.io instead:**
1. Go to https://qr.io
2. Select **"Text"** mode (NOT URL mode)
3. Paste the entire `sgnl://linkdevice?uuid=...` URI
4. Generate and scan with Signal app

#### Step 2.3: Approve on Your Phone

1. Open Signal on your phone (logged in as the **bot's account**)
2. Settings → Linked Devices → Link New Device
3. Scan the QR code
4. Approve the link

The terminal running `signal-cli link` should complete successfully.

#### Step 2.4: Verify Link

```bash
signal-cli -a +1XXXXXXXXXX receive
# Should return without error (may show pending messages)
```

Replace `+1XXXXXXXXXX` with your bot's phone number in E.164 format.

### Part 3: Configure Clawdbot

#### Step 3.1: Enable Signal Channel

```bash
# Enable the channel
clawdbot config set channels.signal.enabled true

# Set your bot's phone number (MUST use --json for proper quoting)
clawdbot config set --json channels.signal.account '"+1XXXXXXXXXX"'

# Set signal-cli path (MUST be full path - daemon doesn't load shell PATH)
clawdbot config set --json channels.signal.cliPath '"/opt/homebrew/bin/signal-cli"'
# Linux: '"/usr/local/bin/signal-cli"'

# Set DM policy (pairing = unknown senders get a code to approve)
clawdbot config set channels.signal.dmPolicy pairing

# Set HTTP port (default 8080 often conflicts with other services)
clawdbot config set channels.signal.httpPort 8088
```

#### Step 3.2: Add Yourself to Allowlist

```bash
clawdbot config set --json channels.signal.allowFrom '["+1XXXXXXXXXX"]'
```

#### Step 3.3: Restart Daemon

```bash
clawdbot daemon restart
```

#### Step 3.4: Verify Configuration

```bash
clawdbot config get channels.signal
```

Should show:
```json
{
  "enabled": true,
  "account": "+1XXXXXXXXXX",
  "cliPath": "/opt/homebrew/bin/signal-cli",
  "dmPolicy": "pairing",
  "httpPort": 8088,
  "allowFrom": ["+1XXXXXXXXXX"]
}
```

### Part 4: Test

Send a message to Clawdbot via Signal:

1. Open Signal on your phone (can switch back to your personal account now)
2. Start a chat with the **bot's phone number**
3. Send: "Hello"
4. You should receive a response within ~10 seconds

**If using pairing mode and you're not in allowFrom:**
- You'll receive a 6-digit pairing code
- Approve: `clawdbot pairing approve signal <code>`
- Then resend your message

---

## Voice Message Handling

Signal voice messages arrive as `.m4a` audio files. This section covers the portable, tool-agnostic approach to voice handling.

### Architecture: Prompt-Driven (Not Auto)

Clawdbot's built-in audio transcription (`tools.media.audio`) doesn't work reliably with custom wrapper scripts. The config is accepted but the wrapper is never invoked.

**Our approach:**
- Agent explicitly checks for voice messages in each incoming message
- Agent manually invokes transcription wrapper scripts
- No dependency on Clawdbot's media pipeline

**Why this is better:**
- Portable — works with any Clawdbot version or future framework
- Controllable — agent decides when/how to transcribe
- Flexible — can use any STT engine (we use openai-whisper)

### Install Whisper

Python Whisper (not whisper-cpp) handles `.m4a` format natively:

```bash
pip install openai-whisper

# Verify
whisper --help
```

### Create Wrapper Scripts

Create these in your bot's workspace (e.g., `~/clawd/tools/`):

**whisper-clean.sh** (Speech-to-Text):
```bash
#!/bin/bash
# ~/clawd/tools/whisper-clean.sh
# Wrapper for whisper that outputs clean text only

MODEL="${WHISPER_MODEL:-base}"
INPUT="$1"
OUTPUT_DIR=$(/usr/bin/mktemp -d)

# Run whisper
whisper "$INPUT" \
  --model "$MODEL" \
  --language en \
  --output_format txt \
  --output_dir "$OUTPUT_DIR" \
  >/dev/null 2>&1

# Output just the text
BASENAME=$(/usr/bin/basename "$INPUT" | /usr/bin/sed "s/\.[^.]*$//")
RESULT=$(/bin/cat "${OUTPUT_DIR}/${BASENAME}.txt" 2>/dev/null)

# Output to stdout
echo "$RESULT"

# Cleanup
/bin/rm -rf "$OUTPUT_DIR"
```

**tts.sh** (Text-to-Speech, using sherpa-onnx):
```bash
#!/bin/bash
# ~/clawd/tools/tts.sh
# TTS wrapper using sherpa-onnx
# Usage: tts.sh "text to speak" output.wav

set -e

TEXT="${1:-Hello, this is a test.}"
OUTPUT="${2:-/tmp/tts-output.wav}"

RUNTIME_DIR="${SHERPA_ONNX_RUNTIME_DIR:-$HOME/.clawdbot/tools/sherpa-onnx-tts/runtime}"
MODEL_DIR="${SHERPA_ONNX_MODEL_DIR:-$HOME/.clawdbot/tools/sherpa-onnx-tts/models/vits-piper-en_US-lessac-high}"

# Expand ~ in paths
RUNTIME_DIR="${RUNTIME_DIR/#\~/$HOME}"
MODEL_DIR="${MODEL_DIR/#\~/$HOME}"

# Find model files
MODEL_ONNX=$(find "$MODEL_DIR" -name "*.onnx" -not -name "*.json" | head -1)
TOKENS="$MODEL_DIR/tokens.txt"
ESPEAK_DATA="$MODEL_DIR/espeak-ng-data"

if [ ! -f "$MODEL_ONNX" ]; then
    echo "Error: Model not found in $MODEL_DIR" >&2
    exit 1
fi

# Run TTS
"$RUNTIME_DIR/bin/sherpa-onnx-offline-tts" \
    --vits-model="$MODEL_ONNX" \
    --vits-tokens="$TOKENS" \
    --vits-data-dir="$ESPEAK_DATA" \
    --output-filename="$OUTPUT" \
    "$TEXT" > /dev/null 2>&1

echo "$OUTPUT"
```

Make executable:
```bash
chmod +x ~/clawd/tools/whisper-clean.sh
chmod +x ~/clawd/tools/tts.sh
```

### Add to Exec Allowlist

If using exec allowlist mode, add entries to `~/.openclaw/exec-approvals.json`:

```json
{
  "agents": {
    "your-agent-id": {
      "allowlist": [
        { "pattern": "/Users/yourbot/clawd/tools/whisper-clean.sh", "id": "whisper-clean" },
        { "pattern": "/Users/yourbot/clawd/tools/tts.sh", "id": "tts" },
        { "pattern": "/usr/bin/afplay", "id": "afplay" }
      ]
    }
  }
}
```

**Note:** Patterns must be full paths. The agent must call `/Users/yourbot/clawd/tools/whisper-clean.sh`, not just `whisper-clean.sh`.

---

## Agent Configuration

Configure your agent to handle voice messages. Add these sections to your agent's prompt files.

### AGENTS.md: Message Start Check

Add this to your AGENTS.md to force voice detection on every message:

```markdown
## Message Start Check

On **EVERY user message**, run this echo FIRST (before any response):

/bin/echo "🎤 No | 📬 No"

Adjust based on what's in the message:
- 🎤 Yes if message contains `<media:audio>` → follow Voice Messages section
- 📬 Yes if message starts with `[From ...]` → HTTP API message

This forces you to check. Don't skip it.
```

**Why echo?** The echo forces the agent to explicitly evaluate the message type. It's shell output (not sent to user) and visible in logs for debugging.

### AGENTS.md: Voice Messages Section

```markdown
## Voice Messages

When you receive a voice note (`<media:audio>`):

1. **Extract audio path** from `[media attached: /path/to/file.m4a ...]` line
2. **Transcribe:** `/path/to/clawd/tools/whisper-clean.sh /path/to/file.m4a`
3. **Respond to the content**
4. **Reply with voice:**
   - Generate: `/path/to/clawd/tools/tts.sh "your response" /tmp/response.wav`
   - Send: `MEDIA:/tmp/response.wav`
5. **Include text version** for reference/accessibility

**Voice/text must match 1:1:** Write your text response first, then TTS that exact text.
For things that don't dictate well (code, file paths), say "details in the written message."

Auto-transcription is disabled — always manually transcribe `<media:audio>` messages.
```

### TOOLS.md: Voice Tools Section

```markdown
## Voice Tools

**Location:** ~/clawd/tools/

### Speech-to-Text (Whisper)

**Wrapper:** ~/clawd/tools/whisper-clean.sh (allowlisted)

Using `base` model. Runs ~3.5x faster than real-time on M-series Macs.

The wrapper:
- Writes output to temp directory
- Suppresses stderr noise
- Returns clean text only (no timestamps)

### Text-to-Speech (sherpa-onnx)

**Wrapper:** ~/clawd/tools/tts.sh
**Voice:** vits-piper-en_US-lessac-high

Generate and play:
/path/to/clawd/tools/tts.sh "Hello world" /tmp/output.wav
/usr/bin/afplay /tmp/output.wav
```

---

## Troubleshooting

### "signal daemon not ready (HTTP 401)"

signal-cli isn't responding. Check:

```bash
# Is signal-cli accessible?
which signal-cli

# Can it receive messages?
signal-cli -a +1XXXXXXXXXX receive

# Check Clawdbot logs
clawdbot logs --follow | grep -i signal
```

### Port Conflict (8080 in Use)

```bash
lsof -i :8080  # See what's using it
clawdbot config set channels.signal.httpPort 8088
clawdbot daemon restart
```

### QR Code Won't Scan

You probably used `qrencode` which breaks the URI. Use https://qr.io with **Text mode** instead.

### Messages Not Being Received

1. Check daemon is running: `clawdbot daemon status`
2. Check signal-cli can receive: `signal-cli -a +1XXXXXXXXXX receive`
3. Check allowFrom includes your number: `clawdbot config get channels.signal.allowFrom`

### "Unknown" Sender with UUID

If pairing shows `uuid:<long-string>` instead of phone number:
- This is normal for some Signal versions
- The UUID is stored in allowFrom and works fine

### Voice Transcription Fails

1. Check whisper is installed: `whisper --help`
2. Check script is executable: `ls -la ~/clawd/tools/whisper-clean.sh`
3. Check allowlist includes the script (if using allowlist mode)
4. Try running manually: `~/clawd/tools/whisper-clean.sh /path/to/audio.m4a`

### Voice Message Not Detected

- Agent must check for `<media:audio>` tag in message
- Ensure AGENTS.md has the Message Start Check section
- The echo pattern forces the check — don't skip it

---

## Security Notes

### DM Policy Options

| Policy | Behavior |
|--------|----------|
| `pairing` | Unknown senders get a code, can be approved later |
| `allowlist` | Unknown senders silently ignored, no code |
| `open` | Anyone can message (dangerous for production) |

**Recommended:** Start with `pairing`, then switch to `allowlist` once set up:

```bash
clawdbot config set channels.signal.dmPolicy allowlist
clawdbot daemon restart
```

### Same Phone Number Warning

If you use your personal Signal number for the bot:
- Clawdbot ignores messages from itself (loop protection)
- You message "yourself" and Clawdbot responds
- Works fine, but can be confusing

**Alternative:** Use a separate phone number (Google Voice, etc.) for clarity.

---

## Migration Notes

When moving to a new machine:

### signal-cli Data

```
~/.local/share/signal-cli/
```

**Option A: Copy data directory**
```bash
# On old machine
tar czf signal-cli-data.tar.gz ~/.local/share/signal-cli/

# On new machine
tar xzf signal-cli-data.tar.gz -C ~/
```

**Option B: Re-link**
1. Run `signal-cli link -n "YourBotName"` on new machine
2. Generate QR code via qr.io
3. Scan with Signal app (logged into bot's account)

### Voice Scripts

Copy your wrapper scripts:
```bash
scp -r oldmachine:~/clawd/tools/ ~/clawd/tools/
```

---

## Quick Reference

| Item | Value |
|------|-------|
| Clawdbot config | `~/.openclaw/openclaw.json` |
| Exec allowlist | `~/.openclaw/exec-approvals.json` |
| signal-cli data | `~/.local/share/signal-cli/` |
| Attachments | `~/.local/share/signal-cli/attachments/` |
| Default HTTP port | 8080 (recommend 8088) |
| QR generator | https://qr.io (Text mode) |

### Key Gotchas

1. **qrencode doesn't work** — Use qr.io with Text mode
2. **Phone numbers need `--json`** — `clawdbot config set --json channels.signal.account '"+1..."'`
3. **cliPath must be full path** — Daemon doesn't load shell PATH
4. **Port 8080 often conflicts** — Use 8088
5. **Python whisper for m4a** — whisper-cpp doesn't handle m4a
6. **Log into bot's Signal account** — QR scanning happens from that account, not yours
7. **Full paths in exec allowlist** — Pattern matching is literal

---

## Files

- `setup.sh` — Interactive setup script
- `config.json` — Config fragment showing expected structure
- `prompts/AGENTS.snippet.md` — Signal-specific agent prompts
- `README.md` — This file

---

## Related Resources

- [signal-cli GitHub](https://github.com/AsamK/signal-cli)
- [OpenAI Whisper](https://github.com/openai/whisper)
- [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx)
