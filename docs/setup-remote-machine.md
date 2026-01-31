---
type: doc
scope: reference
title: "Setting Up the Remote Machine"
description: "Prepare macOS/Linux machine for Clawdbot"
---

# Setting Up the Remote Machine

This guide covers preparing a macOS or Linux machine to run Clawdbot.

## Overview

You'll create a dedicated service account (recommended) and enable SSH access. The bot runs under this account with its own home directory.

---

## macOS Setup

### 1. Create a Service Account

Using `dscl` (Directory Service command line):

```bash
# Pick a short username (e.g., bruba, mybot)
BOT_USER="bruba"

# Create the user (requires admin)
sudo dscl . -create /Users/$BOT_USER
sudo dscl . -create /Users/$BOT_USER UserShell /bin/zsh
sudo dscl . -create /Users/$BOT_USER RealName "Bruba Bot"
sudo dscl . -create /Users/$BOT_USER UniqueID 502  # Pick unused ID (check: dscl . -list /Users UniqueID)
sudo dscl . -create /Users/$BOT_USER PrimaryGroupID 20  # staff group
sudo dscl . -create /Users/$BOT_USER NFSHomeDirectory /Users/$BOT_USER

# Create home directory
sudo mkdir -p /Users/$BOT_USER
sudo chown $BOT_USER:staff /Users/$BOT_USER

# Set a password (for sudo access if needed)
sudo dscl . -passwd /Users/$BOT_USER "temporary-password"
```

**Note:** The account doesn't need a password for SSH if you use key-based auth (recommended).

### 2. Enable Remote Login (SSH)

```bash
# Enable SSH (System Preferences → Sharing → Remote Login)
sudo systemsetup -setremotelogin on

# Add bot user to allowed SSH users
sudo dseditgroup -o edit -a $BOT_USER -t user com.apple.access_ssh
```

Or via GUI: System Preferences → Sharing → Remote Login → Allow access for specific users → Add the bot user.

### 3. Verify SSH Access

From another machine:

```bash
ssh -o PreferredAuthentications=password bruba@<machine-ip>
```

### 4. Create Workspace Directories

As the bot user (or via SSH):

```bash
mkdir -p ~/clawd/{memory,memory/archive,tools,tools/helpers,output}
```

---

## Linux Setup

### 1. Create a Service Account

```bash
BOT_USER="bruba"

# Create user with home directory
sudo useradd -m -s /bin/bash $BOT_USER

# Optional: set password (not needed for key auth)
sudo passwd $BOT_USER
```

### 2. Enable SSH Access

SSH is usually enabled by default. If not:

```bash
# Debian/Ubuntu
sudo apt install openssh-server
sudo systemctl enable ssh
sudo systemctl start ssh

# RHEL/Fedora
sudo dnf install openssh-server
sudo systemctl enable sshd
sudo systemctl start sshd
```

### 3. Configure SSH for the Bot User

Edit `/etc/ssh/sshd_config` if you need to restrict access:

```
# Allow specific users
AllowUsers bruba youruser

# Or use groups
AllowGroups ssh-users
```

Reload SSH after changes:

```bash
sudo systemctl reload sshd  # or ssh on Debian
```

### 4. Create Workspace Directories

```bash
sudo -u $BOT_USER mkdir -p /home/$BOT_USER/clawd/{memory,memory/archive,tools,tools/helpers,output}
```

---

## Home Directory Structure

After setup, the bot's home should have:

```
~/
├── clawd/                    # Workspace root
│   ├── memory/               # Long-term memory files
│   │   └── archive/          # Archived memory
│   ├── tools/                # Bot's scripts and utilities
│   │   └── helpers/          # Helper scripts
│   └── output/               # Generated files
│
├── .clawdbot/                # Created by Clawdbot installer
│   ├── clawdbot.json         # Main config
│   ├── exec-approvals.json   # Allowed executables
│   └── agents/               # Per-agent data
│       └── <agent-id>/
│           ├── sessions/     # Conversation transcripts
│           └── workspace/    # Agent's working area
│               ├── code/     # Staged code for review
│               └── output/   # Generated files
│
└── .zshrc or .bashrc         # Shell config (optional API key here)
```

---

## Install Clawdbot

On the remote machine:

```bash
# Using npm (requires Node.js)
npm install -g clawdbot

# Verify
clawdbot --version
```

If Node.js isn't installed:

```bash
# macOS
brew install node

# Ubuntu/Debian
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt install nodejs

# Or use nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
nvm install --lts
```

---

## Set API Key

The bot needs an Anthropic API key. Add to shell profile:

```bash
# Add to ~/.zshrc or ~/.bashrc
export ANTHROPIC_API_KEY="sk-ant-..."
```

Or create a `.env` file in the Clawdbot config directory (check Clawdbot docs for location).

---

## Security Notes

1. **Use key-based SSH auth** — Disable password auth after setting up keys
2. **Limit sudo access** — Bot shouldn't need sudo for normal operation
3. **Firewall** — Limit SSH access to trusted IPs if possible
4. **Separate account** — Don't run the bot as your main user

---

## Next Steps

1. [Set up operator SSH access](setup-operator-ssh.md) — Configure your local machine to connect
2. Run `provision-bot.sh` to complete the setup
