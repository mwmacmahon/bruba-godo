# Full Setup Guide

Complete guide for setting up a personal AI assistant bot with Clawdbot. This guide covers everything from prerequisites to security hardening.

> **Quick start?** See [quickstart-new-machine.md](quickstart-new-machine.md) for the condensed version.
> **Already set up?** See the [Operations Guide](operations-guide.md) for day-to-day usage.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Create Service Account](#create-service-account)
3. [Install Clawdbot](#install-clawdbot)
4. [Configure SSH Access](#configure-ssh-access)
5. [Run Onboarding Wizard](#run-onboarding-wizard)
6. [Security Hardening](#security-hardening)
7. [Exec Lockdown](#exec-lockdown)
8. [Config File Protection](#config-file-protection)
9. [Config Architecture Reference](#config-architecture-reference)
10. [Memory Plugin](#memory-plugin)
11. [Project Context Setup](#project-context-setup)
12. [Multi-Agent Setup](#multi-agent-setup)
13. [Troubleshooting](#troubleshooting)
14. [Key Insights & Gotchas](#key-insights--gotchas)

---

## Prerequisites

**On the remote machine:**
- macOS or Linux
- Homebrew (macOS) or apt/yum (Linux)
- Docker Desktop (for sandboxed agents)

**On your operator machine:**
- SSH client
- Claude Code (optional but recommended)

### Install Required Tools

```bash
# macOS: Xcode Command Line Tools
xcode-select --install

# Install pnpm (preferred for Clawdbot)
npm install -g pnpm
pnpm setup
source ~/.zshrc

# Verify
pnpm --version
```

---

## Create Service Account

### macOS

```bash
# Pick a username (e.g., bruba, mybot)
BOT_USER="bruba"

# Create the user
sudo dscl . -create /Users/$BOT_USER
sudo dscl . -create /Users/$BOT_USER UserShell /bin/zsh
sudo dscl . -create /Users/$BOT_USER UniqueID 505  # Check unused: dscl . -list /Users UniqueID
sudo dscl . -create /Users/$BOT_USER PrimaryGroupID 20
sudo dscl . -create /Users/$BOT_USER NFSHomeDirectory /Users/$BOT_USER

# Create home directory
sudo mkdir -p /Users/$BOT_USER
sudo chown -R $BOT_USER:staff /Users/$BOT_USER

# Enable Remote Login
sudo systemsetup -setremotelogin on
sudo dseditgroup -o edit -a $BOT_USER -t user com.apple.access_ssh
```

### Linux

```bash
BOT_USER="bruba"
sudo useradd -m -s /bin/bash $BOT_USER
```

---

## Install Clawdbot

Clawdbot is installed directly on the bot account. SSH in as the bot user:

```bash
ssh bruba

# Clone repository (recommended over npm install)
mkdir -p ~/src
cd ~/src
git clone https://github.com/clawdbot/clawdbot.git
cd clawdbot

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
clawdbot --version

exit  # Back to your operator machine
```

> **Note:** Source lives at `~/src/clawdbot/` on the bot account. See Operations Guide for update procedures.

---

## Configure SSH Access

### On Your Operator Machine

```bash
# Generate key if needed
ssh-keygen -t ed25519 -C "$(whoami)@$(hostname)"

# Copy to bot machine
ssh-copy-id bruba@<ip-or-hostname>
```

### SSH Config

Add to `~/.ssh/config`:

```
Host bruba
    HostName 192.168.1.100    # Replace with actual IP
    User bruba
    IdentityFile ~/.ssh/id_ed25519
```

Test: `ssh bruba "clawdbot --version"`

### Setup Bot Account Environment

SSH in and configure non-interactive commands:

```bash
ssh bruba

# Enable non-interactive SSH commands
cat > ~/.zshenv << 'EOF'
source ~/.zshrc
EOF

exit

# Verify from operator
ssh bruba "clawdbot --version"
```

---

## Run Onboarding Wizard

```bash
ssh bruba
clawdbot onboard --install-daemon
```

**Key wizard answers:**

| Prompt | Recommended Answer |
|--------|-------------------|
| Auth method | Anthropic token (Claude API key) |
| Default model | anthropic/claude-opus-4-5-20250514 |
| Gateway bind | Loopback (127.0.0.1) |
| Channel | Signal (recommended) or Telegram |
| DM policy | Pairing (recommended) |

---

## Security Hardening

Edit `~/.clawdbot/clawdbot.json` to restrict agent permissions:

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
chmod 700 ~/.clawdbot

# Validate
clawdbot status
clawdbot security audit
```

---

## Exec Lockdown

**Critical:** With `sandbox.mode: "off"`, exec-approvals.json is ignored unless you explicitly enable gateway exec with allowlist security.

```bash
ssh bruba 'clawdbot config set tools.exec.host gateway'
ssh bruba 'clawdbot config set tools.exec.security allowlist'
ssh bruba 'clawdbot daemon restart'
```

**Why:** Without these settings, the bot can run arbitrary commands. The allowlist only enforces when `host: gateway` + `security: allowlist` are set.

### Exec Allowlist Structure

Allowlists are **per-agent**. If your agent ID is `bruba-main`, entries must be in `agents.bruba-main.allowlist`:

**~/.clawdbot/exec-approvals.json:**
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

**Adding entries:**
```bash
ssh bruba 'cat ~/.clawdbot/exec-approvals.json | jq ".agents[\"bruba-main\"].allowlist += [{\"pattern\": \"/path/to/binary\", \"id\": \"my-entry\"}]" > /tmp/exec-approvals.json && mv /tmp/exec-approvals.json ~/.clawdbot/exec-approvals.json'
```

**Verify structure:**
```bash
ssh bruba 'cat ~/.clawdbot/exec-approvals.json | jq ".agents | keys"'
# Should return: ["bruba-main"]
```

### Pattern Matching Behavior

**Important:** Patterns match the **binary path only**, not the full command string.

| Pattern | Matches | Does NOT Match |
|---------|---------|----------------|
| `/usr/bin/grep` | `/usr/bin/grep "test" file.md` | `grep "test" file.md` |

**Requirements:**
- Full paths required — bot must call `/usr/bin/grep`, not `grep`
- Each command in a pipe must use full path
- Redirections (`2>/dev/null`) break allowlist mode

---

## Config File Protection

The agent can use `edit` and `write` tools to modify config files. Two ownership models exist:

### Option A: Bot-Owned (Simpler)

```bash
ssh bruba "chmod 600 ~/.clawdbot/clawdbot.json"
ssh bruba "chmod 600 ~/.clawdbot/exec-approvals.json"
```

**Protection:** Medium — agent could still modify via write/edit tools, but 600 prevents other users from reading.

### Option B: Root-Owned (Hardened)

```bash
sudo chown root:staff /Users/bruba/.clawdbot/clawdbot.json
sudo chmod 644 /Users/bruba/.clawdbot/clawdbot.json
```

**Protection:** High — agent cannot modify clawdbot.json.

**Why exec-approvals.json stays bot-owned:**
- Daemon writes `lastUsedAt` timestamps on each command execution
- Root ownership breaks exec functionality

**Modifying root-owned config:**
```bash
# 1. Unlock
sudo chown bruba:staff /Users/bruba/.clawdbot/clawdbot.json

# 2. Make changes
ssh bruba 'clawdbot config set tools.deny ...'

# 3. Re-lock
sudo chown root:staff /Users/bruba/.clawdbot/clawdbot.json
```

---

## Config Architecture Reference

### Top-Level Sections

| Section | Purpose |
|---------|---------|
| `meta` | Version tracking, timestamps |
| `auth` | Authentication profiles (API keys) |
| `agents` | Agent definitions (defaults + list) |
| `tools` | Global tool configuration |
| `channels` | Channel configs (signal, telegram) |
| `gateway` | Gateway server settings |
| `plugins` | Plugin configurations |

### agents.defaults vs agents.list[]

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

### Tool Configuration Layers

Multiple layers control tool access (evaluated in order):

| Layer | Location | Effect |
|-------|----------|--------|
| 1. Global deny | `tools.deny` | Blocked for all agents |
| 2. Global allow | `tools.allow` | Allowed if not denied |
| 3. Sandbox tools | `tools.sandbox.tools.allow/deny` | For sandboxed sessions |
| 4. Agent deny | `agents.list[].tools.deny` | Agent-specific blocks |
| 5. Agent allow | `agents.list[].tools.allow` | Agent-specific grants |
| 6. Exec allowlist | `exec-approvals.json` | Binary whitelist |

---

## Memory Plugin

### Enable Memory Plugin

Edit `~/.clawdbot/clawdbot.json`:

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

### Enable Memory Tools in Sandbox

If using sandboxed sessions, add to `~/.clawdbot/clawdbot.json`:

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

### Initialize Embeddings

```bash
# Restart to download model (~600MB)
clawdbot daemon restart

# Watch progress
tail -f ~/.clawdbot/logs/gateway.log
# Wait for "Model loaded successfully"
```

### Memory Indexing Constraints

- **Predefined sources only** — `memory` maps to `~/clawd/memory/*.md` + `MEMORY.md`
- **No subdirectory recursion** — Only direct children are indexed
- **Symlinks not followed** — Files must be actual files, not symlinks

### Check Index Status

```bash
ssh bruba "clawdbot memory status"
ssh bruba "clawdbot memory status --verbose"
ssh bruba "clawdbot memory index --verbose"  # Force reindex
```

---

## Project Context Setup

### Create Workspace

```bash
ssh bruba
mkdir -p ~/clawd/memory
mkdir -p ~/clawd/tools
```

### Create Core Context Files

| File | Purpose |
|------|---------|
| `~/clawd/SOUL.md` | Personality definition |
| `~/clawd/USER.md` | Info about you |
| `~/clawd/IDENTITY.md` | Who the bot is |
| `~/clawd/AGENTS.md` | Operational instructions |
| `~/clawd/TOOLS.md` | Local setup notes |
| `~/clawd/MEMORY.md` | Curated long-term memory |

### Configure Project Context

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

### Test Memory System

```bash
# Create test file
cat > ~/clawd/memory/test.md << 'EOF'
# Memory Test
The answer to the universe is 42.
EOF

# Index
clawdbot memory index --verbose

# Search
clawdbot memory search "universe"
# Should find the test file
```

---

## Multi-Agent Setup

For security isolation, you may want multiple agents with different permission profiles.

### Example: Main + Web Reader

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

### Migration from Single to Multi-Agent

| Setting | Single-Agent | Multi-Agent |
|---------|--------------|-------------|
| Agent ID | `main` (default) | `bruba-main` (explicit) |
| Exec allowlist | `agents.main.allowlist` | `agents.bruba-main.allowlist` |
| Workspace | `agents.defaults.workspace` | Per-agent `agents.list[].workspace` |

**Key migration steps:**
1. Rename exec-approvals namespace from `agents.main` to `agents.bruba-main`
2. Set explicit agent ID in `agents.list[]`
3. Review per-agent tool permissions

---

## Troubleshooting

### Memory Tools Not Appearing

**Symptom:** Memory tools missing from available tools

**Check:**
1. Plugin loaded? `clawdbot status | grep Memory`
2. Sandbox tools configured? `cat ~/.clawdbot/clawdbot.json | jq '.tools.sandbox.tools'`
3. Restart after config change? `clawdbot daemon restart`

### Memory Search Fails: "database is not open"

**Fix:**
```bash
clawdbot memory index --verbose
clawdbot memory status --deep  # Should show Dirty: no
```

**Nuclear option:**
```bash
clawdbot daemon stop
rm -f ~/.clawdbot/memory/*.sqlite
clawdbot daemon start
clawdbot memory index --verbose
```

### Exec Command Denied

**Check:**
1. `tools.exec.host` is `"gateway"`
2. `tools.exec.security` is `"allowlist"`
3. Binary path in `exec-approvals.json` under correct agent ID
4. Using full path in command

### Non-Interactive SSH Commands Fail

**Symptom:** `ssh bruba "clawdbot status"` shows "command not found"

**Fix:**
```bash
ssh bruba
cat > ~/.zshenv << 'EOF'
source ~/.zshrc
EOF
exit
```

### Files Not Being Indexed

**Check:**
1. Files directly in `~/clawd/memory/`? (no subdirectories)
2. Real files, not symlinks? (`ls -la`)
3. Valid source name? Only `memory` works

---

## Key Insights & Gotchas

### Installation & Config

1. **npm link doesn't work reliably** — Manual symlink may be needed: `ln -sf ~/src/clawdbot/dist/entry.js ~/.npm-global/bin/clawdbot`

2. **Phone numbers need `--json` flag** — `+1...` gets parsed as a number otherwise:
   ```bash
   clawdbot config set --json channels.signal.account '"+12025551234"'  # Correct
   clawdbot config set channels.signal.account +12025551234             # Wrong
   ```

3. **Daemon doesn't load .zshrc** — Use FULL PATH to binaries in clawdbot config

4. **Source install > npm global** — Better for dev/debugging, easier to update

### Signal Setup

5. **qrencode doesn't work for Signal linking** — Use https://qr.io with "Text mode" instead; qrencode mishandles URL-encoded base64

6. **Signal requires three-step setup:**
   1. Configure clawdbot (enable channel, set account, cliPath, httpPort)
   2. Link signal-cli to phone (via QR code)
   3. Approve pairing in clawdbot

7. **Signal daemon port conflict** — Default 8080 may conflict with other services; use `httpPort: 8088`

### Sandbox & Permissions

8. **Sandbox mode "all" breaks CLI tool access** — Use `sandbox.mode: "off"` for host CLI access. exec-approvals.json is still the security boundary.

9. **TCC permissions are per-binary** — Running `remindctl authorize` in Terminal grants permission to Terminal, but Clawdbot uses Node.js. Have the bot execute the command to grant permission to Node.js.

10. **exec-approvals.json requires explicit gateway mode** — With `sandbox.mode: "off"`, the allowlist is ignored unless you also set `tools.exec.host: "gateway"` and `tools.exec.security: "allowlist"`

### Shell Config

Working shell config for the bot account:

**~/.zshrc:**
```bash
# PATH setup - order matters
export PATH="$HOME/.npm-global/bin:$PATH"    # npm globals (clawdbot)
export PATH="/opt/homebrew/bin:$PATH"         # Homebrew
export PATH="$HOME/.local/bin:$PATH"          # Local binaries
```

**~/.zshenv:**
```bash
source ~/.zshrc
```

**~/.npmrc:**
```
prefix=/Users/bruba/.npm-global
```

### Debug Commands

```bash
# Check daemon environment
ssh bruba "launchctl getenv PATH"

# Watch logs for issues
ssh bruba "tail -f /tmp/clawdbot/clawdbot-$(date +%Y-%m-%d).log"

# Check if binary accessible
ssh bruba "sudo -u bruba /bin/zsh -c 'which clawdbot'"
```

---

## Testing Checklist

After setup, verify:

| Test | Command/Action | Expected |
|------|----------------|----------|
| Daemon running | `ssh bruba "clawdbot status"` | Shows status |
| Memory loads | Ask about your MEMORY.md | Mentions content |
| Memory search | Ask to search memory | Returns results |
| File reading | Ask to read a file | Can read ~/clawd/ |
| Exec working | Allowlisted command | Executes |
| Exec blocked | Non-allowlisted command | Denied |

---

## File Locations

| Path | Purpose |
|------|---------|
| `~/.clawdbot/clawdbot.json` | Main config |
| `~/.clawdbot/exec-approvals.json` | Exec command allowlist |
| `~/.clawdbot/.env` | API keys |
| `~/.clawdbot/agents/<id>/sessions/` | Session JSONL files |
| `~/clawd/` | Workspace root |
| `~/clawd/memory/` | Memory files (indexed) |
| `~/clawd/MEMORY.md` | Curated long-term memory |
| `~/.cache/node-llama-cpp/` | Embedding model cache |

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-01-30 | Initial version |
