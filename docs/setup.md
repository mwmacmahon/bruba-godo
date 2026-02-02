---
type: doc
scope: reference
title: "Setup Guide"
description: "Complete guide for setting up OpenClaw from scratch"
---

# Setup Guide

Complete guide for setting up a personal AI assistant bot with OpenClaw. Covers remote machine preparation, operator configuration, and bot setup.

> **Already set up?** See the [Operations Guide](operations-guide.md) for day-to-day usage.
> **Having issues?** See [Troubleshooting](troubleshooting.md).

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Prerequisites](#prerequisites)
3. [Part 1: Remote Machine Setup](#part-1-remote-machine-setup)
4. [Part 2: Operator Machine Setup](#part-2-operator-machine-setup)
5. [Part 3: Bot Configuration](#part-3-bot-configuration)
6. [Verification](#verification)
7. [Next Steps](#next-steps)

---

## Quick Start

For users who just need to get connected to an existing bot:

### Quick Checklist

- [ ] Bot user created on remote machine
- [ ] SSH enabled and accessible
- [ ] OpenClaw installed (`openclaw --version` works)
- [ ] API key set (`echo $ANTHROPIC_API_KEY`)
- [ ] SSH key copied and config updated
- [ ] config.yaml updated with new host
- [ ] `./tools/bot echo ok` returns "ok"
- [ ] Daemon started

### Minimal Steps

```bash
# 1. Clone bruba-godo (if not already)
git clone <repo-url>
cd bruba-godo

# 2. Copy and edit config
cp config.yaml.example config.yaml
# Edit: set ssh.host, remote.* paths, remote.agent_id

# 3. Add SSH config (~/.ssh/config)
Host bruba
    HostName <ip>
    User bruba

# 4. Test connection
./tools/bot echo ok

# 5. First sync
./tools/mirror.sh
./tools/bot openclaw status
```

For full setup from scratch, continue below.

---

## Prerequisites

### On the Remote Machine (Bot)

- macOS or Linux
- Homebrew (macOS) or apt/yum (Linux)
- Docker Desktop (for sandboxed agents)
- Node.js 18+

### On Your Operator Machine

- SSH client
- Claude Code (optional but recommended)
- Git

### Install Required Tools (Remote)

```bash
# macOS: Xcode Command Line Tools
xcode-select --install

# Install Homebrew (if not present)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install Node.js
brew install node

# Install pnpm (preferred for OpenClaw)
npm install -g pnpm
pnpm setup
source ~/.zshrc

# Install jq and signal-cli
brew install jq signal-cli

# Verify
pnpm --version
node --version
```

---

## Part 1: Remote Machine Setup

### 1.1 Create Service Account

#### macOS

```bash
# Pick a username (e.g., bruba, mybot)
BOT_USER="bruba"

# Create the user
sudo dscl . -create /Users/$BOT_USER
sudo dscl . -create /Users/$BOT_USER UserShell /bin/zsh
sudo dscl . -create /Users/$BOT_USER RealName "Bruba Bot"
sudo dscl . -create /Users/$BOT_USER UniqueID 502  # Check unused: dscl . -list /Users UniqueID
sudo dscl . -create /Users/$BOT_USER PrimaryGroupID 20  # staff group
sudo dscl . -create /Users/$BOT_USER NFSHomeDirectory /Users/$BOT_USER

# Create home directory
sudo mkdir -p /Users/$BOT_USER
sudo chown $BOT_USER:staff /Users/$BOT_USER

# Optional: Set password (for sudo if needed)
sudo dscl . -passwd /Users/$BOT_USER "temporary-password"
```

#### Linux

```bash
BOT_USER="bruba"

# Create user with home directory
sudo useradd -m -s /bin/bash $BOT_USER

# Optional: set password
sudo passwd $BOT_USER
```

### 1.2 Enable SSH Access

#### macOS

```bash
# Enable SSH (System Preferences → Sharing → Remote Login)
sudo systemsetup -setremotelogin on

# Add bot user to allowed SSH users
sudo dseditgroup -o edit -a $BOT_USER -t user com.apple.access_ssh
```

Or via GUI: System Preferences → Sharing → Remote Login → Allow access for specific users → Add the bot user.

#### Linux

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

### 1.3 Install OpenClaw

SSH in as the bot user:

```bash
ssh bruba

# Clone repository (recommended over npm install)
mkdir -p ~/src
cd ~/src
git clone https://github.com/openclaw/openclaw.git
cd openclaw

# Checkout latest release (not main!)
git tag -l | grep 2026 | tail -1
git checkout v2026.1.24-1  # Use actual latest

# Install and build
pnpm install
pnpm approve-builds        # Select node-llama-cpp
pnpm rebuild node-llama-cpp
pnpm build
pnpm link --global

# Verify
openclaw --version

exit  # Back to your operator machine
```

> **Note:** Source lives at `~/src/openclaw/` on the bot account. See Operations Guide for update procedures.

### 1.4 Set API Key

On the remote machine:

```bash
# Add to ~/.zshrc
echo 'export ANTHROPIC_API_KEY="sk-ant-..."' >> ~/.zshrc
source ~/.zshrc
```

Or create `~/.openclaw/.env`:

```
ANTHROPIC_API_KEY=sk-ant-...
```

### 1.5 Create Workspace Directories

```bash
mkdir -p ~/clawd/{memory,memory/archive,tools,tools/helpers,output}
```

### Home Directory Structure

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
├── .openclaw/                # Created by OpenClaw installer
│   ├── openclaw.json         # Main config
│   ├── exec-approvals.json   # Allowed executables
│   └── agents/               # Per-agent data
│       └── <agent-id>/
│           ├── sessions/     # Conversation transcripts
│           └── workspace/    # Agent's working area
│
└── .zshrc or .bashrc         # Shell config (API key here)
```

---

## Part 2: Operator Machine Setup

### 2.1 Generate SSH Key

If you don't already have an SSH key (check `~/.ssh/id_ed25519`):

```bash
# Generate ed25519 key (recommended)
ssh-keygen -t ed25519 -C "your-email@example.com"

# Or RSA if ed25519 isn't supported
ssh-keygen -t rsa -b 4096 -C "your-email@example.com"
```

Accept the default path and optionally set a passphrase.

### 2.2 Copy Key to Remote

#### Option A: Using ssh-copy-id (easiest)

```bash
ssh-copy-id bruba@<remote-ip-or-hostname>
```

#### Option B: Manual copy

```bash
# On your local machine
cat ~/.ssh/id_ed25519.pub

# Copy the output, then on the remote machine:
mkdir -p ~/.ssh
chmod 700 ~/.ssh
echo "paste-the-public-key-here" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

### 2.3 Configure SSH Client

Add to `~/.ssh/config`:

```
Host bruba
    HostName 192.168.1.100    # Replace with actual IP or hostname
    User bruba                 # Bot user account
    Port 22                    # Default SSH port
    IdentityFile ~/.ssh/id_ed25519
```

**Common configurations:**

```
# Local machine on same network
Host bruba
    HostName 192.168.1.100
    User bruba

# Machine behind router (port forwarded)
Host bruba
    HostName your-domain.com
    User bruba
    Port 2222

# Via jump host / bastion
Host bruba
    HostName 10.0.0.50
    User bruba
    ProxyJump bastion.example.com

# Tailscale / ZeroTier (use Tailscale IP)
Host bruba
    HostName 100.x.y.z
    User bruba
```

### 2.4 Test Connection

```bash
# Simple test
ssh bruba echo "Connection successful"

# Check openclaw
ssh bruba openclaw --version

# Test the tools/bot wrapper (from bruba-godo directory)
./tools/bot echo ok
```

### 2.5 Setup Bot Account Environment

SSH in and configure non-interactive commands:

```bash
ssh bruba

# Enable non-interactive SSH commands
cat > ~/.zshenv << 'EOF'
source ~/.zshrc
EOF

exit

# Verify from operator
ssh bruba "openclaw --version"
```

### 2.6 Clone bruba-godo

```bash
cd /path/to/your/projects
git clone <repo-url>
cd bruba-godo
```

### 2.7 Configure bruba-godo

```bash
cp config.yaml.example config.yaml
```

Edit `config.yaml`:

```yaml
ssh:
  host: bruba  # Must match SSH config

remote:
  home: /Users/bruba
  workspace: /Users/bruba/clawd
  openclaw: /Users/bruba/.openclaw
  agent_id: bruba-main
```

### SSH Security Best Practices

#### Disable Password Authentication

After confirming key auth works, disable passwords on the remote:

Edit `/etc/ssh/sshd_config`:

```
PasswordAuthentication no
ChallengeResponseAuthentication no
```

Reload: `sudo systemctl reload sshd`

#### Use a Passphrase

Protect your private key with a passphrase. Use `ssh-agent` to avoid retyping:

```bash
# Start agent
eval "$(ssh-agent -s)"

# Add key (will prompt for passphrase once)
ssh-add ~/.ssh/id_ed25519

# macOS: store in Keychain
ssh-add --apple-use-keychain ~/.ssh/id_ed25519
```

Add to `~/.ssh/config`:

```
Host *
    AddKeysToAgent yes
    UseKeychain yes  # macOS only
```

---

## Part 3: Bot Configuration

### 3.1 Run Onboarding Wizard

```bash
ssh bruba
openclaw onboard --install-daemon
```

**Key wizard answers:**

| Prompt | Recommended Answer |
|--------|-------------------|
| Auth method | Anthropic token (Claude API key) |
| Default model | anthropic/claude-opus-4-5 |
| Gateway bind | Loopback (127.0.0.1) |
| Channel | Signal (recommended) or Telegram |
| DM policy | Pairing (recommended) |

### 3.2 Security Hardening

Edit `~/.openclaw/openclaw.json` to restrict agent permissions:

```json
{
  "agents": {
    "defaults": {
      "workspace": "/Users/bruba/clawd",
      "sandbox": {
        "mode": "off",
        "scope": "session",
        "workspaceAccess": "rw"
      }
    }
  },
  "tools": {
    "deny": ["process", "browser", "canvas", "nodes", "cron", "gateway"]
  }
}
```

**Sandbox modes:**

| Mode | Behavior | Use When |
|------|----------|----------|
| `"off"` | Host access, exec allowlist enforced | Need CLI tools (reminders, calendar) |
| `"non-main"` | Main DM on host, groups sandboxed | Mixed access needs |
| `"all"` | Everything in Docker | Maximum isolation |

```bash
# Restrict config permissions
chmod 700 ~/.openclaw

# Validate
openclaw status
openclaw security audit
```

### 3.3 Exec Lockdown

**Critical:** With `sandbox.mode: "off"`, exec-approvals.json is ignored unless you explicitly enable gateway exec with allowlist security.

```bash
ssh bruba 'openclaw config set tools.exec.host gateway'
ssh bruba 'openclaw config set tools.exec.security allowlist'
ssh bruba 'openclaw daemon restart'
```

**Why:** Without these settings, the bot can run arbitrary commands. The allowlist only enforces when `host: gateway` + `security: allowlist` are set.

#### Exec Allowlist Structure

Allowlists are **per-agent**. If your agent ID is `bruba-main`, entries must be in `agents.bruba-main.allowlist`:

**~/.openclaw/exec-approvals.json:**
```json
{
  "agents": {
    "bruba-main": {
      "allowlist": [
        { "pattern": "/usr/bin/wc", "id": "wc" },
        { "pattern": "/bin/ls", "id": "ls" },
        { "pattern": "/usr/bin/head", "id": "head" },
        { "pattern": "/usr/bin/tail", "id": "tail" },
        { "pattern": "/usr/bin/grep", "id": "grep" },
        { "pattern": "/usr/bin/du", "id": "du" },
        { "pattern": "/bin/cat", "id": "cat" },
        { "pattern": "/usr/bin/find", "id": "find" }
      ]
    }
  }
}
```

**Verify structure:**
```bash
ssh bruba 'cat ~/.openclaw/exec-approvals.json | jq ".agents | keys"'
# Should return: ["bruba-main"]
```

#### Pattern Matching Behavior

**Important:** Patterns match the **binary path only**, not the full command string.

| Pattern | Matches | Does NOT Match |
|---------|---------|----------------|
| `/usr/bin/grep` | `/usr/bin/grep "test" file.md` | `grep "test" file.md` |

**Requirements:**
- Full paths required — bot must call `/usr/bin/grep`, not `grep`
- Each command in a pipe must use full path
- Redirections (`2>/dev/null`) break allowlist mode

### 3.4 Config File Protection

The agent can use `edit` and `write` tools to modify config files. Two ownership models exist:

#### Option A: Bot-Owned (Simpler)

```bash
ssh bruba "chmod 600 ~/.openclaw/openclaw.json"
ssh bruba "chmod 600 ~/.openclaw/exec-approvals.json"
```

**Protection:** Medium — agent could still modify via write/edit tools, but 600 prevents other users from reading.

#### Option B: Root-Owned (Hardened)

```bash
sudo chown root:staff /Users/bruba/.openclaw/openclaw.json
sudo chmod 644 /Users/bruba/.openclaw/openclaw.json
```

**Protection:** High — agent cannot modify openclaw.json.

**Why exec-approvals.json stays bot-owned:**
- Daemon writes `lastUsedAt` timestamps on each command execution
- Root ownership breaks exec functionality

**Modifying root-owned config:**
```bash
# 1. Unlock
sudo chown bruba:staff /Users/bruba/.openclaw/openclaw.json

# 2. Make changes
ssh bruba 'openclaw config set tools.deny ...'

# 3. Re-lock
sudo chown root:staff /Users/bruba/.openclaw/openclaw.json
```

### 3.5 Config Architecture Reference

#### Top-Level Sections

| Section | Purpose |
|---------|---------|
| `meta` | Version tracking, timestamps |
| `auth` | Authentication profiles (API keys) |
| `agents` | Agent definitions (defaults + list) |
| `tools` | Global tool configuration |
| `channels` | Channel configs (signal, telegram) |
| `gateway` | Gateway server settings |
| `plugins` | Plugin configurations |

#### agents.defaults vs agents.list[]

**agents.defaults** — Base settings inherited by ALL agents:
```json
{
  "agents": {
    "defaults": {
      "model": { "primary": "opus", "fallbacks": [...] },
      "workspace": "/Users/bruba/clawd",
      "memorySearch": { "enabled": true, ... },
      "sandbox": { "mode": "off", ... },
      "maxConcurrent": 4
    }
  }
}
```

**agents.list[]** — Per-agent overrides (higher priority):
```json
{
  "agents": {
    "list": [
      {
        "id": "bruba-main",
        "name": "My Bot",
        "default": true,
        "workspace": "~/clawd",
        "tools": {
          "allow": ["read", "exec"],
          "deny": ["web_fetch"]
        }
      }
    ]
  }
}
```

#### Tool Configuration Layers

Multiple layers control tool access (evaluated in order):

| Layer | Location | Effect |
|-------|----------|--------|
| 1. Global deny | `tools.deny` | Blocked for all agents |
| 2. Global allow | `tools.allow` | Allowed if not denied |
| 3. Sandbox tools | `tools.sandbox.tools.allow/deny` | For sandboxed sessions |
| 4. Agent deny | `agents.list[].tools.deny` | Agent-specific blocks |
| 5. Agent allow | `agents.list[].tools.allow` | Agent-specific grants |
| 6. Exec allowlist | `exec-approvals.json` | Binary whitelist |

### 3.6 Memory Plugin

#### Enable Memory Plugin

Edit `~/.openclaw/openclaw.json`:

```json
{
  "plugins": {
    "memory-core": {
      "enabled": true
    }
  },
  "agents": {
    "defaults": {
      "memorySearch": {
        "enabled": true,
        "provider": "local",
        "local": {
          "modelPath": "hf:ggml-org/embeddinggemma-300M-GGUF/embeddinggemma-300M-Q8_0.gguf"
        },
        "sources": ["memory"],
        "sync": { "watch": true },
        "query": {
          "hybrid": {
            "enabled": true,
            "vectorWeight": 0.7,
            "textWeight": 0.3
          }
        }
      }
    }
  }
}
```

#### Enable Memory Tools in Sandbox

If using sandboxed sessions, add to `~/.openclaw/openclaw.json`:

```json
{
  "tools": {
    "allow": ["memory_search", "memory_get", "group:memory"],
    "sandbox": {
      "tools": {
        "allow": ["group:memory", "group:fs", "group:sessions", "image"],
        "deny": []
      }
    }
  }
}
```

#### Initialize Embeddings

```bash
# Restart to download model (~600MB)
openclaw daemon restart

# Watch progress
tail -f ~/.openclaw/logs/gateway.log
# Wait for "Model loaded successfully"
```

#### Memory Indexing Constraints

- **Predefined sources only** — `memory` maps to `~/clawd/memory/*.md` + `MEMORY.md`
- **No subdirectory recursion** — Only direct children are indexed
- **Symlinks not followed** — Files must be actual files, not symlinks

#### Check Index Status

```bash
ssh bruba "openclaw memory status"
ssh bruba "openclaw memory status --verbose"
ssh bruba "openclaw memory index --verbose"  # Force reindex
```

### 3.7 Project Context Setup

#### Create Core Context Files

| File | Purpose |
|------|---------|
| `~/clawd/SOUL.md` | Personality definition |
| `~/clawd/USER.md` | Info about you |
| `~/clawd/IDENTITY.md` | Who the bot is |
| `~/clawd/AGENTS.md` | Operational instructions |
| `~/clawd/TOOLS.md` | Local setup notes |
| `~/clawd/MEMORY.md` | Curated long-term memory |

#### Configure Project Context

```json
{
  "project": {
    "directory": "~/clawd",
    "contextFiles": [
      "SOUL.md",
      "USER.md",
      "IDENTITY.md",
      "AGENTS.md",
      "TOOLS.md"
    ]
  }
}
```

#### Test Memory System

```bash
# Create test file
cat > ~/clawd/memory/test.md << 'EOF'
# Memory Test
The answer to the universe is 42.
EOF

# Index
openclaw memory index --verbose

# Search
openclaw memory search "universe"
# Should find the test file
```

### 3.8 Multi-Agent Setup (Optional)

For security isolation, you may want multiple agents with different permission profiles.

#### Example: Main + Web Reader

```json
{
  "agents": {
    "list": [
      {
        "id": "bruba-main",
        "name": "Main Bot",
        "default": true,
        "workspace": "~/clawd",
        "tools": {
          "allow": ["read", "write", "edit", "exec", "memory_search", "memory_get"],
          "deny": ["web_fetch", "web_search", "browser"]
        }
      },
      {
        "id": "web-reader",
        "name": "Web Reader",
        "workspace": "~/web-reader",
        "sandbox": { "mode": "all" },
        "tools": {
          "allow": ["web_fetch", "web_search", "read"],
          "deny": ["exec", "write", "edit", "memory_search"]
        }
      }
    ]
  },
  "tools": {
    "agentToAgent": {
      "enabled": true,
      "allow": ["web-reader"]
    }
  }
}
```

**Security properties:**
- Main agent cannot access web tools directly
- Reader agent has web_search + web_fetch only (no exec/write/edit)
- Reader runs sandboxed in Docker
- Agents communicate via `sessions_send` or exec wrappers

---

## Verification

### Testing Checklist

| Test | Command/Action | Expected |
|------|----------------|----------|
| Daemon running | `ssh bruba "openclaw status"` | Shows status |
| Memory loads | Ask about your MEMORY.md | Mentions content |
| Memory search | Ask to search memory | Returns results |
| File reading | Ask to read a file | Can read ~/clawd/ |
| Exec working | Allowlisted command | Executes |
| Exec blocked | Non-allowlisted command | Denied |

### File Locations

| Path | Purpose |
|------|---------|
| `~/.openclaw/openclaw.json` | Main config |
| `~/.openclaw/exec-approvals.json` | Exec command allowlist |
| `~/.openclaw/.env` | API keys |
| `~/.openclaw/agents/<id>/sessions/` | Session JSONL files |
| `~/clawd/` | Workspace root |
| `~/clawd/memory/` | Memory files (indexed) |
| `~/clawd/MEMORY.md` | Curated long-term memory |
| `~/.cache/node-llama-cpp/` | Embedding model cache |

---

## Next Steps

1. **Set up Signal channel** — See `components/signal/README.md` for Signal messaging setup
2. **Configure heartbeat** — Use `/config` for proactive messages
3. **Set up content sync** — See [Operations Guide](operations-guide.md) for `/mirror`, `/pull`, `/push`
4. **Add exec-approvals** — Add tools the bot can run to the allowlist
5. **Customize prompts** — Edit `~/clawd/` context files

For troubleshooting, see [Troubleshooting Guide](troubleshooting.md).

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 2.0.0 | 2026-02-01 | Consolidated from 4 setup docs |
| 1.0.0 | 2026-01-30 | Initial version (full-setup-guide.md) |
