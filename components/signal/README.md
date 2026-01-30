# Signal Component

Connect to your bot via Signal messenger.

## Overview

This component enables the Signal channel in Clawdbot, allowing you to message your bot via Signal. Messages can be text or voice (voice messages are transcribed by the bot).

## Prerequisites

1. **signal-cli installed on remote machine**

   ```bash
   # macOS
   brew install signal-cli

   # Linux (download from releases)
   # https://github.com/AsamK/signal-cli/releases
   ```

2. **A phone number for the bot**

   Signal requires a phone number. Options:
   - Google Voice number (free)
   - Dedicated SIM card
   - VoIP number that can receive SMS

3. **Bot already provisioned**

   Run `./tools/provision-bot.sh` first.

## Setup

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

### Manual Setup

If you prefer manual setup:

1. **Link signal-cli to a phone number:**

   ```bash
   # Register new number (will receive SMS verification)
   signal-cli -u +1PHONENUMBER register
   signal-cli -u +1PHONENUMBER verify CODE

   # Or link to existing Signal account
   signal-cli link -n "BotName"
   # Scan QR with your phone's Signal app
   ```

2. **Update clawdbot.json:**

   ```json
   {
     "channels": {
       "signal": {
         "enabled": true,
         "phoneNumber": "+1PHONENUMBER"
       }
     },
     "http": {
       "port": 8088
     }
   }
   ```

3. **Restart daemon:**

   ```bash
   clawdbot daemon restart
   ```

## Configuration Options

In `clawdbot.json` under `channels.signal`:

| Option | Type | Description |
|--------|------|-------------|
| `enabled` | boolean | Enable/disable Signal channel |
| `phoneNumber` | string | Bot's phone number (E.164 format: +1234567890) |

## Troubleshooting

### "signal-cli not found"

Install signal-cli:
```bash
# macOS
brew install signal-cli

# Linux - download from GitHub releases
```

### "Failed to send message"

Check signal-cli is properly linked:
```bash
signal-cli -u +1PHONENUMBER receive
```

### "QR code not scanning"

Use qr.io or a web-based QR generator. The `qrencode` tool often produces QR codes that Signal can't read.

### Port conflicts

If another service uses port 8088, edit clawdbot.json to use a different port.

## Files

- `setup.sh` — Interactive setup script
- `config.json` — Config fragment showing expected structure
- `README.md` — This file

## Notes

- Signal requires the daemon to be running to receive messages
- Voice messages are transcribed using whisper (if configured)
- Group chats work but bot should follow group etiquette (don't dominate)
- Signal rate limits sending — don't spam
