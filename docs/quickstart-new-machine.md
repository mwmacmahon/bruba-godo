---
type: doc
scope: reference
title: "Quick Start: Setting Up a New Bot Machine"
description: "Fast-track guide for new bot machine setup"
---

# Quick Start: Setting Up a New Bot Machine

Step-by-step guide for getting a new bot running quickly.

---

## Overview

You'll set up:
1. The **remote machine** (where the bot runs)
2. **SSH access** from your operator machine
3. **Clawdbot** and the bot itself
4. **Signal** for messaging (optional)

Estimated time: 15-30 minutes

---

## Part 1: Remote Machine Setup

On the new machine (Mac mini, server, etc.):

### 1.1 Create Bot User Account

```bash
# macOS
BOT_USER="bruba"  # or whatever name you want

sudo dscl . -create /Users/$BOT_USER
sudo dscl . -create /Users/$BOT_USER UserShell /bin/zsh
sudo dscl . -create /Users/$BOT_USER RealName "Bot"
sudo dscl . -create /Users/$BOT_USER UniqueID 502
sudo dscl . -create /Users/$BOT_USER PrimaryGroupID 20
sudo dscl . -create /Users/$BOT_USER NFSHomeDirectory /Users/$BOT_USER
sudo mkdir -p /Users/$BOT_USER
sudo chown $BOT_USER:staff /Users/$BOT_USER
```

### 1.2 Enable SSH

```bash
# macOS
sudo systemsetup -setremotelogin on
sudo dseditgroup -o edit -a $BOT_USER -t user com.apple.access_ssh
```

### 1.3 Install Node.js and Clawdbot

```bash
# Install Homebrew if not present
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install Node.js
brew install node

# Install Clawdbot
npm install -g clawdbot

# Verify
clawdbot --version
```

### 1.4 Install Dependencies

```bash
brew install jq signal-cli
```

### 1.5 Set API Key

```bash
# Add to ~/.zshrc
echo 'export ANTHROPIC_API_KEY="sk-ant-..."' >> ~/.zshrc
source ~/.zshrc
```

---

## Part 2: Operator SSH Setup

On your operator machine (laptop/desktop):

### 2.1 Generate SSH Key (if needed)

```bash
ssh-keygen -t ed25519 -C "your-email@example.com"
```

### 2.2 Copy Key to Remote

```bash
ssh-copy-id bruba@<mac-mini-ip>
```

### 2.3 Configure SSH

Add to `~/.ssh/config`:

```
Host newbot
    HostName <mac-mini-ip>
    User bruba
```

### 2.4 Test Connection

```bash
ssh newbot echo "Connection works"
```

---

## Part 3: Provision the Bot

On your operator machine:

### 3.1 Clone or Navigate to bruba-godo

```bash
cd /path/to/bruba-godo
# or
git clone <repo-url>
cd bruba-godo
```

### 3.2 Update config.yaml

Edit `config.yaml` to point to your new machine:

```yaml
ssh:
  host: newbot  # Must match SSH config

remote:
  home: /Users/bruba
  workspace: /Users/bruba/clawd
  clawdbot: /Users/bruba/.clawdbot
  agent_id: newbot-main
```

### 3.3 Run Provisioning

```bash
./tools/provision-bot.sh
```

Follow the prompts:
- Bot name: "NewBot" (or your choice)
- Agent ID: "newbot-main"
- Your name: "YourName"

### 3.4 Verify

```bash
./tools/bot clawdbot status
```

---

## Part 4: Set Up Signal (Optional)

### 4.1 Run Signal Setup

```bash
./components/signal/setup.sh
```

### 4.2 Link Account

Choose option 2 (Link to existing Signal account):
1. The script gives you a URI
2. Go to qr.io and paste the URI to generate a QR code
3. Open Signal on your phone → Settings → Linked Devices → Link New Device
4. Scan the QR code

### 4.3 Test

Send a message from Signal to the bot's number. It should respond.

---

## Part 5: Start the Bot

```bash
# Start daemon
ssh newbot 'clawdbot daemon start'

# Check status
./tools/bot clawdbot status
```

---

## Quick Checklist

- [ ] Bot user created on remote machine
- [ ] SSH enabled and accessible
- [ ] Clawdbot installed (`clawdbot --version` works)
- [ ] API key set (`echo $ANTHROPIC_API_KEY`)
- [ ] SSH key copied and config updated
- [ ] config.yaml updated with new host
- [ ] `./tools/bot echo ok` returns "ok"
- [ ] `./tools/provision-bot.sh` completed
- [ ] Daemon started
- [ ] (Optional) Signal connected

---

## Troubleshooting

### "Permission denied (publickey)"
SSH key not copied. Run `ssh-copy-id bruba@<ip>` again.

### "clawdbot: command not found"
Node.js or clawdbot not installed. Run `npm install -g clawdbot`.

### Signal QR code won't scan
Use qr.io to generate the QR code — don't use `qrencode`.

### Daemon won't start
Check API key: `ssh newbot 'echo $ANTHROPIC_API_KEY'`

---

## Next Steps

1. Customize prompts in `~/clawd/` on the remote
2. Set up `/mirror` to pull files locally
3. Add exec-approvals for tools the bot can run
4. Configure heartbeat for proactive messages

See the full docs:
- [setup-remote-machine.md](setup-remote-machine.md)
- [setup-operator-ssh.md](setup-operator-ssh.md)
- [intake-pipeline.md](intake-pipeline.md)
