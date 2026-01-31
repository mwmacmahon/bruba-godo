---
version: 5.17.0
updated: 2026-01-28
type: sop
tags: [bruba, clawdbot, setup, pkm-integration]
description: "Bruba setup and PKM integration procedure"
---
# Bruba Setup SOP v5.16.0

Standard Operating Procedure for Bruba (Clawdbot instance) setup and PKM integration.

> **Prerequisites:** macOS, Homebrew, Docker Desktop, Telegram account
> **For day-to-day operations:** See `Bruba Usage SOP.md` — daemon management, sessions, sync architecture
> **Time:** 1.5-2 hours for full setup

> **Claude Code:** If you encounter setup issues, discover workarounds, or find that documented steps are outdated, update this SOP. Add to "Key Insights" for hard-won lessons, or fix procedures inline. Also, if <REDACTED-NAME> deprecates or changes part of the process, edit text accordingly (e.g. Telegram is no longer used, so this document should no longer cover it by name, but it can contain a summary of the removed content). Version bump accordingly.

Make sure to notify <REDACTED-NAME> about these changes with a loud callout in your output text, but you don't have to ask permission (he validates git diffs).


---

## Recent Changes

**v5.17.0** (current) — Added "Single to Multi-Agent Migration" subsection to § 1.10

**v5.16.0** — Rewrote section 1.9 Config File Protection with two ownership models (bruba-owned vs root-owned), added doctor warning guidance

**v5.15.1** — Clarified clawdbot source install is on bruba account (not main)

**v5.14.0** — Split out `Bruba Usage SOP.md` for day-to-day operations

**v5.10-5.13** — Web search (isolated reader subagent), config architecture reference, exec-approvals consolidation

**v5.5-5.9** — Exec lockdown, filesystem access, config file protection, voice handling

**v5.0-5.4** — Major consolidation: Key Insights, Signal setup, Reminders/Calendar, sandbox mode

See Version History table for full changelog.

---

## Part 1: Initial Clawdbot Setup

### 1.1 Install Prerequisites

```bash
# Xcode Command Line Tools
xcode-select --install

# Install pnpm
npm install -g pnpm
pnpm setup
source ~/.zshrc

# Verify
pnpm --version
```

### 1.2 Install Clawdbot from Source

Clawdbot is installed directly on the bruba account (not on main). This keeps the installation self-contained.

```bash
# First, create the bruba account (see 1.3), then SSH in:
ssh bruba

# Clone repository
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

exit  # Back to main account
```

> **Note:** Source lives at `~/src/clawdbot/` on bruba. Updates via `/bruba:update` skill.

### 1.3 Create Bruba Service Account

```bash
# Create isolated user for Bruba
sudo dscl . -create /Users/bruba
sudo dscl . -create /Users/bruba UserShell /bin/zsh
sudo dscl . -create /Users/bruba UniqueID 505
sudo dscl . -create /Users/bruba PrimaryGroupID 20
sudo dscl . -create /Users/bruba NFSHomeDirectory /Users/bruba
sudo mkdir -p /Users/bruba
sudo chown -R bruba:staff /Users/bruba

# Enable Remote Login (System Settings → Sharing → Remote Login)
# Add bruba to allowed users
sudo dseditgroup -o edit -a bruba -t user com.apple.access_ssh

# Setup SSH key access
ssh-keygen -t ed25519 -C "$(whoami)@mac"  # If you don't have one
ssh-copy-id bruba@localhost
```

### 1.4 Configure SSH Alias

Add to `~/.ssh/config`:
```
Host bruba
    HostName localhost
    User bruba
    IdentityFile ~/.ssh/id_ed25519
```

Add to `~/.zshrc`:
```bash
alias ssh-bruba="ssh bruba@localhost"
```

Test: `ssh bruba "echo hello"`

### 1.5 Setup Bruba Account Environment

```bash
# SSH to bruba
ssh bruba

# Install pnpm for bruba
npm install -g pnpm
pnpm setup

# Enable non-interactive SSH commands
cat > ~/.zshenv << 'EOF'
source ~/.zshrc
EOF

# Verify clawdbot (installed in 1.2)
clawdbot --version

exit  # Back to main account
ssh bruba "clawdbot --version"
```

> **Note:** Clawdbot source is at `~/src/clawdbot/` on bruba (installed in 1.2), not linked from main account.

### 1.6 Run Onboarding Wizard

```bash
ssh bruba
clawdbot onboard --install-daemon
```

**Key wizard answers:**
| Prompt | Answer |
|--------|--------|
| Auth method | Anthropic token (Claude Code CLI) |
| Default model | anthropic/claude-opus-4-5-20250514 |
| Gateway bind | Loopback (127.0.0.1) |
| Channel | Telegram (Bot API) |
| DM policy | Pairing (recommended) |

**Telegram bot setup during wizard:**
1. Open Telegram, find `@BotFather`
2. Send `/newbot`
3. Name: `bruba`, Username: `your_bruba_bot`
4. Copy token to wizard

### 1.7 Security Hardening

Edit `~/.clawdbot/clawdbot.json`:

```json
{
  "agents": {
    "defaults": {
      "workspace": "/Users/bruba/clawd",
      "sandbox": {
        "mode": "all",
        "scope": "session",
        "workspaceAccess": "ro",
        "docker": {
          "network": "none",
          "memory": "512m",
          "readOnlyRoot": true
        }
      }
    }
  },
  "tools": {
    "deny": ["exec", "process", "browser", "canvas", "nodes", "cron", "gateway", "write", "edit", "apply_patch"]
  }
}
```

```bash
# Restrict permissions
chmod 700 ~/.clawdbot

# Validate
clawdbot status
clawdbot security audit
```

### 1.8 Exec Lockdown (REQUIRED)

With `sandbox.mode: "off"`, exec-approvals.json is **ignored by default**. You must explicitly enable gateway exec with allowlist security:

```bash
ssh bruba 'clawdbot config set tools.exec.host gateway'
ssh bruba 'clawdbot config set tools.exec.security allowlist'
ssh bruba 'clawdbot daemon restart'
```

**Why:** Without these settings, Bruba can run arbitrary commands as the bruba user. The allowlist only enforces when `host: gateway` + `security: allowlist` are set.

**Verify lockdown:**
1. Ask Bruba to run `cat /etc/passwd` — should be blocked or prompt for approval
2. Ask Bruba to check reminders — should work (remindctl is allowlisted)

### 1.8.1 Exec Allowlist Structure

**Critical:** Allowlists in `exec-approvals.json` are **per-agent**. Bruba's agent ID is `bruba-main`, so all entries must be in `agents.bruba-main.allowlist`:

```json
{
  "agents": {
    "bruba-main": {
      "allowlist": [
        { "pattern": "/opt/homebrew/bin/remindctl", "id": "remindctl" },
        { "pattern": "/opt/homebrew/bin/icalBuddy", "id": "icalbuddy" },
        { "pattern": "/usr/bin/wc", "id": "wc" },
        { "pattern": "/bin/ls", "id": "ls" },
        { "pattern": "/usr/bin/head", "id": "head" },
        { "pattern": "/usr/bin/tail", "id": "tail" },
        { "pattern": "/usr/bin/grep", "id": "grep" },
        { "pattern": "/usr/bin/du", "id": "du" },
        { "pattern": "/bin/cat", "id": "cat" },
        { "pattern": "/usr/bin/find", "id": "find" },
        { "pattern": "/usr/bin/afplay", "id": "afplay" },
        { "pattern": "/Users/bruba/clawd/tools/whisper-clean.sh", "id": "whisper" },
        { "pattern": "/Users/bruba/clawd/tools/tts.sh", "id": "tts" },
        { "pattern": "/Users/bruba/clawd/tools/voice-status.sh", "id": "voice-status" },
        { "pattern": "/Users/bruba/bin/web-search.sh", "id": "web-search" },
        { "pattern": "/Users/bruba/.npm-global/bin/clawdbot", "id": "clawdbot-cli" }
      ]
    }
  }
}
```

**Important:** Only `agents.bruba-main` should exist. Do NOT create `agents.main` — it won't work for the bruba-main agent.

**Adding to the allowlist:**
```bash
ssh bruba 'cat ~/.clawdbot/exec-approvals.json | jq ".agents[\"bruba-main\"].allowlist += [{\"pattern\": \"/path/to/binary\", \"id\": \"my-entry\"}]" > /tmp/exec-approvals.json && mv /tmp/exec-approvals.json ~/.clawdbot/exec-approvals.json'
```

**Verify structure:**
```bash
ssh bruba 'cat ~/.clawdbot/exec-approvals.json | jq ".agents | keys"'
# Should return: ["bruba-main"]
```

**Full security config summary:**
```json
{
  "agents": {
    "defaults": {
      "sandbox": { "mode": "off" }
    }
  },
  "tools": {
    "exec": {
      "host": "gateway",
      "security": "allowlist"
    }
  }
}
```

### 1.9 Config File Protection

The agent can use `edit` and `write` tools to modify any file the bruba user can access — including security-critical config files:
- `exec-approvals.json` — the command allowlist
- `clawdbot.json` — contains `tools.deny` list

**Two ownership models:**

| Model | clawdbot.json | Protection Level | Use Case |
|-------|---------------|------------------|----------|
| **Bruba-owned** | bruba:wheel, 600 | Medium | Simpler setup, bruba can modify via CLI |
| **Root-owned** | root:staff, 644 | High | Agent cannot modify config at all |

#### Option A: Bruba-Owned (Simpler)

Config owned by bruba with restricted permissions:

```bash
ssh bruba "chmod 600 ~/.clawdbot/clawdbot.json"
ssh bruba "chmod 600 ~/.clawdbot/exec-approvals.json"
```

**Verify:**
```bash
ssh bruba "ls -la ~/.clawdbot/*.json"
# -rw-------  bruba  wheel  clawdbot.json
# -rw-------  bruba  wheel  exec-approvals.json
```

**Security:** Agent could still modify via write/edit tools, but 600 prevents other users from reading credentials.

#### Option B: Root-Owned (Hardened)

Config owned by root, readable by bruba:

```bash
sudo chown root:staff /Users/bruba/.clawdbot/clawdbot.json
sudo chmod 644 /Users/bruba/.clawdbot/clawdbot.json
```

**Verify:**
```bash
ls -la /Users/bruba/.clawdbot/*.json
# -rw-r--r--  root  staff  clawdbot.json
# -rw-------  bruba wheel  exec-approvals.json (must remain bruba-owned)
```

**Security:** Agent cannot modify clawdbot.json (root-owned), protecting tools.deny list.

**Why exec-approvals.json stays bruba-owned:**
- Daemon writes `lastUsedAt` timestamps on each command execution
- Root ownership breaks exec functionality
- This is a known gap (see Security Overview)

**Modifying root-owned config:**
```bash
# 1. Unlock
sudo chown bruba:staff /Users/bruba/.clawdbot/clawdbot.json

# 2. Make changes
ssh bruba 'clawdbot config set tools.deny ...'

# 3. Re-lock
sudo chown root:staff /Users/bruba/.clawdbot/clawdbot.json
```

#### Doctor Warning: "Config file is group/world readable"

`clawdbot doctor` will warn about readable config. Response depends on your ownership model:

| Ownership | Doctor Suggestion | Action |
|-----------|-------------------|--------|
| bruba:wheel | chmod 600 | ✅ Safe to apply |
| root:staff | chmod 600 | ❌ Do NOT apply (would break daemon) |

**Check before applying:** `ls -la ~/.clawdbot/clawdbot.json`

#### Known Gap: Agent Self-Escalation

Agent can edit `exec-approvals.json` to add binaries to the allowlist. Mitigation requires either:
- Clawdbot feature: separate read-only allowlist from writable metadata
- Wrapper approach: move allowlist to root-owned file, have daemon read from there

### 1.10 Config Architecture Reference

**Overview:** Clawdbot configuration uses a hierarchical JSON structure with inheritance. Understanding this is critical for multi-agent setups like Bruba.

#### Top-Level Sections

| Section | Purpose |
|---------|---------|
| `meta` | Version tracking, timestamps |
| `wizard` | Onboarding wizard state |
| `auth` | Authentication profiles (API keys) |
| `agents` | Agent definitions (defaults + list) |
| `tools` | Global tool configuration |
| `messages` | Message handling settings |
| `commands` | Command/skill configuration |
| `session` | Session behavior (agent-to-agent limits) |
| `channels` | Channel configs (signal, telegram) |
| `gateway` | Gateway server settings |
| `skills` | Installed skills and their env vars |
| `plugins` | Plugin slot assignments |

#### agents.defaults vs agents.list[]

Configuration inheritance works as follows:

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
        "id": "bruba-main",           // Critical: namespace for exec-approvals
        "name": "Bruba",
        "default": true,
        "workspace": "~/clawd",       // Override default
        "tools": {
          "allow": ["read", "exec"],  // Agent-specific permissions
          "deny": ["web_fetch"]
        }
      },
      {
        "id": "web-reader",
        "sandbox": { "mode": "all" }  // Override to Docker isolation
      }
    ]
  }
}
```

**Key insight:** The `id` field in agents.list[] determines:
1. The agent's CLI identifier (`clawdbot agent --agent bruba-main`)
2. The namespace in exec-approvals.json (`agents.bruba-main.allowlist`)
3. The session storage directory (`~/.clawdbot/agents/bruba-main/sessions/`)

#### exec-approvals.json Namespacing

**Critical:** Allowlists are per-agent, keyed by agent ID.

```json
{
  "version": 1,
  "defaults": { "security": "allowlist", "ask": "never" },
  "agents": {
    "bruba-main": {           // Must match agents.list[].id exactly
      "allowlist": [
        { "pattern": "/opt/homebrew/bin/remindctl", "id": "remindctl" },
        { "pattern": "/usr/bin/grep", "id": "grep" }
      ]
    }
  }
}
```

**Common mistake:** Using `agents.main` instead of `agents.bruba-main`. The agent ID includes the instance prefix.

**Auto-populated fields:** When a command executes, Clawdbot adds:
- `lastUsedAt` — Unix timestamp
- `lastUsedCommand` — Full command string
- `lastResolvedPath` — Resolved binary path

#### Tool Configuration Layers

Multiple layers control tool access (evaluated in order):

| Layer | Location | Effect |
|-------|----------|--------|
| 1. Global deny | `tools.deny` | Blocked for all agents |
| 2. Global allow | `tools.allow` | Allowed if not denied |
| 3. Sandbox tools | `tools.sandbox.tools.allow/deny` | For sandboxed sessions |
| 4. Agent deny | `agents.list[].tools.deny` | Agent-specific blocks |
| 5. Agent allow | `agents.list[].tools.allow` | Agent-specific grants |
| 6. Exec allowlist | `exec-approvals.json` | Binary whitelist (when exec allowed) |

**exec** tool special case:
- Must be in `tools.allow` AND agent's allow list
- Requires `tools.exec.host: "gateway"` for allowlist enforcement
- Requires `tools.exec.security: "allowlist"` for validation
- Without these, exec-approvals.json is ignored

#### Multi-Agent Communication

Bruba uses two agents with distinct permission profiles:

```
┌─────────────────────────────────────────────┐
│ bruba-main (sandbox: off)                   │
│ ├─ read, write, edit, exec (allowlisted)    │
│ ├─ memory_*, group:memory                   │
│ └─ DENIED: web_fetch, web_search, browser   │
├─────────────────────────────────────────────┤
│ web-reader (sandbox: all, Docker)           │
│ ├─ web_search, web_fetch, read              │
│ └─ DENIED: exec, write, edit, memory_*      │
└─────────────────────────────────────────────┘
```

**Inter-agent communication:**
```json
{
  "tools": {
    "agentToAgent": {
      "enabled": true,
      "allow": ["web-reader"]
    }
  },
  "session": {
    "agentToAgent": { "maxPingPongTurns": 2 }
  }
}
```

The main agent invokes the reader via:
```bash
# Via exec wrapper (current approach)
/Users/bruba/bin/web-search.sh "query"

# Which internally runs:
clawdbot agent --agent web-reader --local --json "query"
```

**See also:** `Bruba Security Overview.md` for detailed permission architecture and threat model.

#### Single to Multi-Agent Migration

When transitioning from a single-agent setup to multi-agent (e.g., adding web-reader):

| Setting | Single-Agent Location | Multi-Agent Location |
|---------|----------------------|---------------------|
| Agent ID | `main` (default) | `bruba-main` (explicit in `agents.list[]`) |
| Exec allowlist | `agents.main.allowlist` | `agents.bruba-main.allowlist` |
| Workspace | `agents.defaults.workspace` | Per-agent in `agents.list[].workspace` |
| Sandbox mode | `agents.defaults.sandbox.mode` | Per-agent override in `agents.list[].sandbox` |
| Tool permissions | `tools.allow`/`tools.deny` | Per-agent `agents.list[].tools.allow/deny` |

**Key migration steps:**

1. **Rename exec-approvals namespace:** Move entries from `agents.main.allowlist` to `agents.bruba-main.allowlist`
2. **Set explicit agent ID:** Add `"id": "bruba-main"` to primary agent in `agents.list[]`
3. **Review tool permissions:** Per-agent `tools.allow/deny` overrides global settings
4. **Test session paths:** Sessions move to `~/.clawdbot/agents/bruba-main/sessions/`

**Common pitfall:** Orphan sessions in `agents/bruba-main/sessions/` from CLI testing. These appear as `agent:main:main` in status output — safe to ignore or delete.

---

## Part 2: Memory Plugin Configuration

### 2.1 Enable Memory Plugin

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
        "fallback": "none",
        "sources": ["memory"],
        "sync": {
          "watch": true
        },
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

### 2.2 Enable Memory Tools in Sandbox (CRITICAL)

**This is required for memory tools to appear in Telegram sessions.**

Add to `~/.clawdbot/clawdbot.json`:

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

**Why:** Sandboxed sessions have separate tool allowlists. Without `group:memory` in `tools.sandbox.tools.allow`, memory tools won't appear even when the plugin loads successfully.

### 2.3 Initialize Embeddings

```bash
# Restart to download model (~600MB)
clawdbot daemon restart

# Watch progress
tail -f ~/.clawdbot/logs/gateway.log
# Wait for "Model loaded successfully"
```

### 2.4 Memory Indexing Behavior

**Key constraints:**
- **Predefined sources only** — Valid sources include `memory` (maps to `~/clawd/memory/*.md` + `MEMORY.md`). Custom source names don't work.
- **No subdirectory recursion** — The glob `~/clawd/memory/*.md` only matches direct children. Files in subdirectories are NOT indexed.
- **Symlinks not followed** — Clawdbot doesn't follow symlinks when indexing. Files must be actual files.
- **Must copy files directly** — To get content indexed, copy files into `~/clawd/memory/`.

### 2.5 Checking Index Status

```bash
# Quick status
ssh bruba "clawdbot memory status"

# Verbose status (shows chunk counts, vector status)
ssh bruba "clawdbot memory status --verbose"

# Key indicators:
# - Indexed: X/Y files · Z chunks
# - Dirty: yes/no (yes = should reindex, not a problem if you do)
# - Vector: ready (embeddings loaded)

# Force reindex
ssh bruba "clawdbot memory index --verbose"
```

### 2.6 Verify Memory Tools

1. Restart Clawdbot: `clawdbot restart`
2. In Telegram, send: `/context detail`
3. Verify `memory_search` and `memory_get` appear in Tools list

**Troubleshooting:** If tools missing:
```bash
# Check plugin loaded
clawdbot status | grep -i memory

# Check config structure
cat ~/.clawdbot/clawdbot.json | jq '.tools.sandbox.tools'

# Should show: {"allow": ["group:memory", ...], "deny": []}
```

---

## Part 3: Project Context Setup

### 3.1 Create Workspace

```bash
ssh bruba
mkdir -p ~/clawd/memory
mkdir -p ~/clawd/docs
```

### 3.2 Create Core Context Files

| File | Purpose |
|------|---------|
| `~/clawd/SOUL.md` | Personality definition |
| `~/clawd/USER.md` | Info about <REDACTED-NAME> |
| `~/clawd/IDENTITY.md` | Who Bruba is |
| `~/clawd/AGENTS.md` | Operational instructions |
| `~/clawd/TOOLS.md` | Local setup notes |
| `~/clawd/MEMORY.md` | Curated long-term memory |

**Example MEMORY.md:**
```markdown
# Bruba's Memory

I am bruba, a self-hosted AI assistant for <REDACTED-NAME>.

## Core Identity
- I run on <REDACTED-NAME>'s Mac in a sandboxed Docker environment
- I'm accessible via Telegram only
- My workspace is at ~/clawd/
- I cannot execute shell commands (security restriction)
- I have read-only access to my workspace
- I use local embeddings for privacy (no data leaves this Mac)

## Key Capabilities
- Daily conversation logging to memory/YYYY-MM-DD.md
- Searchable memory via hybrid semantic + keyword search
- Access to PKM knowledge in memory/
- Can read files from workspace

## Important Limitations
- No shell execution (exec tools denied)
- No file writing (workspace is read-only)
- No external network access (Docker network disabled)
- Telegram only (no other channels)
```

### 3.3 Configure Project Context

Edit `~/.clawdbot/clawdbot.json`:

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

### 3.4 Test Memory System

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

## Part 4: PKM Integration

### 4.1 Three Data Flows

```
PKM ──push──► Bruba     (bundles/bruba/ → ~/clawd/memory/)
PKM ◄─mirror─ Bruba     (reference/bruba-mirror/ ← ~/clawd/)
PKM ◄─import─ Bruba     (reference/transcripts/ ← sessions/*.jsonl)
```

| Flow | Direction | Source of Truth | Processing |
|------|-----------|-----------------|------------|
| **Push** | PKM → Bruba | PKM | Bundle, filter, rsync, reindex |
| **Mirror** | Bruba → PKM | Bruba | Copy files, no processing |
| **Import** | Bruba → PKM | Bruba sessions | parse-jsonl → /convert → /intake |

### 4.2 Setup PKM Scripts

Create in PKM repo `tools/`:

**mirror-bruba.sh:**
```bash
#!/bin/bash
# Mirror Bruba's files to PKM
DEST="reference/bruba-mirror"
mkdir -p "$DEST"

# Core context files
rsync -av bruba:~/clawd/*.md "$DEST/"

# Dated journals only (YYYY-MM-DD.md pattern)
rsync -av --include='????-??-??.md' --exclude='*' \
  bruba:~/clawd/memory/ "$DEST/journals/"
```

**sync-to-bruba.sh:**
```bash
#!/bin/bash
# Push PKM bundle to Bruba
BUNDLE="bundles/bruba"

if [ ! -d "$BUNDLE" ]; then
  echo "No bundle found. Run /bruba:push first."
  exit 1
fi

rsync -av --delete "$BUNDLE/" bruba:~/clawd/memory/
ssh bruba "clawdbot memory reindex"
echo "Sync complete and reindexed."
```

**pull-bruba-sessions.sh:**
```bash
#!/bin/bash
# Pull closed sessions for import
STATE_FILE="$HOME/.pkm-state/pulled-bruba-sessions.txt"
DEST="intake/bruba"
SESSIONS_DIR="~/.clawdbot/agents/bruba-main/sessions"

mkdir -p "$DEST"
touch "$STATE_FILE"

# Get active session to skip
ACTIVE=$(ssh bruba "cat $SESSIONS_DIR/sessions.json" | jq -r '.sessionId')

# Pull each closed session not already pulled
for session in $(ssh bruba "ls $SESSIONS_DIR/*.jsonl"); do
  name=$(basename "$session")
  id="${name%.jsonl}"

  if [ "$id" = "$ACTIVE" ]; then
    continue  # Skip active
  fi

  if grep -q "$id" "$STATE_FILE"; then
    continue  # Already pulled
  fi

  echo "Pulling $id..."
  scp "bruba:$session" "$DEST/"
  echo "$id" >> "$STATE_FILE"
done
```

```bash
chmod +x tools/*.sh
```

### 4.3 Setup State Tracking

```bash
mkdir -p ~/.pkm-state
touch ~/.pkm-state/pulled-bruba-sessions.txt
```

### 4.4 Bundle Configuration

The Bruba bundle configuration is in `config/bundles.yaml`:

**Bruba bundle settings:**
- **Include:** meta scope only
- **Exclude:** work, personal, home, sensitive
- **Redact:** names, health, financial, personal

This ensures only PKM system documentation reaches Bruba, with sensitive details removed.

### 4.5 File Permissions

Files synced to Bruba need to be readable. The rsync over SSH handles this automatically since files are created as the bruba user.

If permission issues occur:
```bash
ssh bruba "chmod 644 ~/clawd/memory/*.md"
```

### 4.6 Why Direct Copy (Not Symlinks/Bridge)

Originally designed a shared bridge directory (`/Users/Shared/pkm-bridge/`), but:
- Symlinks don't work with clawdbot indexer
- Direct copy to Bruba's memory is simpler
- For inbound, can pull directly from Bruba's filesystem

A bridge directory is unnecessary — rsync over SSH is the cleanest approach.

### 4.7 Test Integration

```bash
# From PKM directory
./tools/mirror-bruba.sh      # Should copy files to reference/bruba-mirror/
./tools/sync-to-bruba.sh     # Should sync bundle (if exists) to Bruba
```

---

## Part 5: PKM Skills

### Available Skills

| Skill | Purpose |
|-------|---------|
| `/bruba:sync` | Bidirectional sync (pull + push) |
| `/bruba:pull` | Pull closed sessions + mirror Bruba's files |
| `/bruba:push` | Generate and push PKM bundle |
| `/bruba:status` | Show sync status |

### Typical Workflows

**Daily sync:**
```
/bruba:sync
```

**Import new conversations:**
```
/bruba:pull                              # Pull sessions + mirror
/convert intake/bruba/2026-01-26-xxx.md  # Add CONFIG (interactive)
/intake                                  # Canonicalize
/sync                                    # Full workflow (includes bruba:push)
```

**Push knowledge to Bruba:**
```
/sync                   # Full workflow (includes bruba:push)
# Or standalone:
/bruba:push
```

### Skill Definitions

Skills are defined in `.claude/commands/`:
- `bruba-sync.md` — Runs pull + push
- `bruba-pull.md` — Pulls sessions, runs parse-jsonl, mirrors Bruba's files
- `bruba-push.md` — Generates bundle, runs sync-to-bruba.sh
- `bruba-status.md` — Shows last sync times, pending files

---

## Part 6: Troubleshooting

### Memory Tools Not Appearing

**Symptom:** `/context detail` shows no memory tools

**Check:**
1. Plugin loaded? `clawdbot status | grep Memory`
2. Sandbox tools configured? `cat ~/.clawdbot/clawdbot.json | jq '.tools.sandbox.tools'`
3. Restart after config change? `clawdbot restart`

**Fix:** Add `group:memory` to `tools.sandbox.tools.allow`

### Memory Search Fails: "database is not open"

**Symptom:**
```
clawdbot memory search "query"
No matches.
[memory] sync failed (search): Error: database is not open
```

**Cause:** Index is dirty, auto-sync didn't trigger.

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

### Session Pull Fails

**Symptom:** `pull-bruba-sessions.sh` errors

**Check:**
1. SSH works? `ssh bruba "ls ~/.clawdbot/agents/bruba-main/sessions/"`
2. State file exists? `cat ~/.pkm-state/pulled-bruba-sessions.txt`
3. Active session excluded? Script should skip active session

### Mirror Gets PKM Content

**Symptom:** `reference/bruba-mirror/` contains files from bundles/

**Check:** Mirror script should only pull:
- Core files from `~/clawd/`
- Dated journals (`YYYY-MM-DD.md`) from `~/clawd/memory/`

**Fix:** Update `mirror-bruba.sh` to exclude non-dated files from memory/

### Sync Doesn't Update Bruba's Search

**Symptom:** New content not appearing in Bruba's memory_search

**Check:** After rsync, need to reindex:
```bash
ssh bruba "clawdbot memory reindex"
```

**Fix:** Ensure `sync-to-bruba.sh` includes reindex step

### Non-Interactive SSH Commands Fail

**Symptom:** `ssh bruba "clawdbot status"` shows "command not found"

**Cause:** ~/.zshrc not loaded for non-interactive shells

**Fix:**
```bash
ssh bruba
cat > ~/.zshenv << 'EOF'
source ~/.zshrc
EOF
exit

# Test
ssh-bruba "which clawdbot"
```

### Files Not Being Indexed

**Symptom:** Files in memory/ but not searchable

**Check:**
1. Files directly in `~/clawd/memory/`? (no subdirectories)
2. Real files, not symlinks? (`ls -la` to check)
3. Valid source name? Only `memory` works, not custom names

**Fix:** Copy files directly into memory/, run `clawdbot memory index --verbose`

### WebChat Won't Connect

**Symptom:** `disconnected (1008): control ui requires HTTPS or localhost (secure context)`

**Cause:** WebChat requires a secure context (HTTPS or localhost). LAN bind mode doesn't work.

**Fix:** Use Tailscale serve:
```bash
# On main user (not bruba)
tailscale serve --bg 18789

# Access via Tailscale URL
https://your-machine.tail042aa8.ts.net/chat?session=main
```

### Voice Messages Not Transcribed

**Current approach:** Prompt-driven (Bruba manually transcribes audio).

Auto-transcription via `tools.media.audio` doesn't work with wrapper scripts — the config is accepted but the wrapper is never invoked. Tested extensively with logging; no calls to the wrapper.

**Setup for prompt-driven voice:**

1. **Disable auto-transcription:**
   ```bash
   ssh bruba 'clawdbot config set tools.media.audio.enabled false'
   ```

2. **Add voice scripts to exec allowlist:**
   ```bash
   # whisper-clean.sh and tts.sh should already be in exec-approvals.json
   ssh bruba 'cat ~/.clawdbot/exec-approvals.json | grep -E "whisper|tts"'
   ```

3. **Verify scripts work:**
   ```bash
   ssh bruba '/Users/bruba/clawd/tools/whisper-clean.sh /path/to/audio.mp3'
   ssh bruba '/Users/bruba/clawd/tools/tts.sh "Hello world" /tmp/test.wav'
   ```

4. **Update Bruba's TOOLS.md** with voice handling instructions (see Bruba Voice Integration.md)

**Why not auto-transcription?**
- `tools.media.audio` with CLI provider: configures correctly but never invokes wrapper scripts
- Direct whisper command works but produces messy output (timestamps, warnings)
- Wrapper scripts produce clean output but aren't invoked by Clawdbot
- Prompt-driven approach is reliable and debuggable

### Signal Port Conflict

**Symptom:** `signal daemon not ready (HTTP 401)` or Signal messages not flowing

**Cause:** Default port 8080 conflicts with code-server or other services.

**Fix:**
```bash
lsof -i :8080  # Check what's using port
clawdbot config set channels.signal.httpPort 8088
clawdbot daemon restart
```

---

## Part 7: Session Management

### Understanding Sessions

- Each Telegram conversation is a **session**
- Sessions stored in `~/.clawdbot/agents/bruba-main/sessions/*.jsonl`
- Active session tracked in `sessions.json`
- `/reset` in Telegram closes current session, starts new one
- Closed sessions are **immutable** — safe to pull once

**Session behavior:**

| State | Behavior |
|-------|----------|
| While active | Append-only (~5 lines per message exchange) |
| After `/reset` | Immutable — old session preserved exactly, new session created |
| Deletion | Never — sessions accumulate indefinitely |

**Implication:** Closed sessions are the authoritative conversation record. Pull them once; they won't change.

### Finding Sessions

```bash
# List all sessions
ssh bruba "ls -la ~/.clawdbot/agents/bruba-main/sessions/"

# Get active session ID
ssh bruba "cat ~/.clawdbot/agents/bruba-main/sessions/sessions.json" | jq -r '.sessionId'

# Check session sizes
ssh bruba "wc -l ~/.clawdbot/agents/bruba-main/sessions/*.jsonl"
```

### Session Import Pipeline

```
JSONL → parse-jsonl → intake/bruba/ → /convert → /intake → transcripts/
```

**Step by step:**

1. **Pull sessions:**
   ```
   /bruba:pull
   ```

2. **Convert to markdown:**
   ```bash
   python tools/parse-jsonl.py intake/bruba/session-id.jsonl -o intake/bruba/
   ```

3. **Add CONFIG block:**
   ```
   /convert intake/bruba/2026-01-26-topic.md
   ```

4. **Process to transcripts:**
   ```
   /intake
   ```

### Journal Reliability

**Location:** `~/clawd/memory/YYYY-MM-DD.md`

Journals are **event-driven**, not automatic:
- Created when Bruba decides something is "noteworthy"
- Heartbeat prompts (if HEARTBEAT.md has tasks) can trigger journaling
- **Writes may fail silently** — Bruba may say "creating journal" but file doesn't appear

**Implication:** Sessions are reliable; journals are "best effort" bonus content. Don't depend on journals for intake completeness.

### JSONL Parser Details

The `parse-jsonl` command in convo-processor applies filtering:

**Skipped content:**
- `type: "session"` (metadata)
- `type: "custom"` (internal events)
- `model: "delivery-mirror"` (duplicates)
- System messages ("New session started...")
- Thinking blocks (`type: "thinking"`)
- `[message_id: N]` markers (stripped)

**Output format:**
```
=== MESSAGE 1 | USER ===
user message content

=== MESSAGE 2 | ASSISTANT ===
assistant response
```

---

## Testing Checklist

After setup, verify:

| Test | Command/Action | Expected |
|------|----------------|----------|
| Telegram responds | Send "Hello" | Response within 10s |
| Memory loads | Ask "What are your capabilities?" | Mentions MEMORY.md content |
| Memory search | Ask "Search memory for test" | Finds indexed content |
| File reading | Ask to read a file | Can read ~/clawd/ files |
| Exec blocked | Ask to run `ls` | Refuses, tools denied |
| SSH commands | `ssh-bruba "clawdbot status"` | Shows status |
| Mirror | `./tools/mirror-bruba.sh` | Copies files |
| Push | `/bruba:push` | Syncs bundle |

---

## Security Validation

Verify these security measures:

- [ ] Sandbox mode: `agents.defaults.sandbox.mode: "all"`
- [ ] Workspace read-only: `workspaceAccess: "ro"`
- [ ] Docker network disabled: `docker.network: "none"`
- [ ] Exec tools denied: `tools.deny` includes "exec"
- [ ] Gateway loopback: `gateway.bind: "loopback"`
- [ ] DM policy pairing: `channels.telegram.dmPolicy: "pairing"`
- [ ] State directory 700: `ls -ld ~/.clawdbot` shows `drwx------`
- [ ] Local embeddings: No external API keys for memory

---

## File Locations

| Path | Purpose |
|------|---------|
| `~/.clawdbot/clawdbot.json` | Main config |
| `~/.clawdbot/agents/bruba-main/sessions/` | Session JSONL files |
| `~/clawd/` | Workspace root |
| `~/clawd/memory/` | Memory files (indexed) |
| `~/clawd/MEMORY.md` | Curated long-term memory |
| `~/.cache/node-llama-cpp/` | Embedding model cache |
| `~/.pkm-state/` | PKM sync state tracking |

**PKM paths:**
| Path | Purpose |
|------|---------|
| `bundles/bruba/` | Generated bundle for Bruba |
| `reference/bruba-mirror/` | Mirror of Bruba's files |
| `intake/bruba/` | Sessions pending processing |
| `tools/` | Sync scripts |

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 5.17.0 | 2026-01-28 | Added "Single to Multi-Agent Migration" subsection to § 1.10 |
| 5.16.0 | 2026-01-28 | Rewrote 1.9 Config File Protection with two ownership models, doctor warning guidance |
| 5.15.0 | 2026-01-28 | Collapsed changelog for readability |
| 5.14.0 | 2026-01-28 | Split out Usage SOP for day-to-day operations |
| 5.13.0 | 2026-01-28 | Config Architecture Reference (1.10) |
| 5.12.0 | 2026-01-28 | Consolidated exec-approvals.json to bruba-main |
| 5.11.0 | 2026-01-28 | Exec Allowlist Structure (per-agent namespacing) |
| 5.10.0 | 2026-01-28 | Web Search Configuration (isolated reader subagent) |
| 5.9.0 | 2026-01-28 | Config file protection (partial) |
| 5.8.0 | 2026-01-28 | Prompt-driven voice handling |
| 5.7.0 | 2026-01-27 | Removed path scoping (approval UX broken) |
| 5.6.0 | 2026-01-27 | Expanded filesystem access (ls, head, tail, grep) |
| 5.5.0 | 2026-01-27 | Token-conscious filesystem access (wc) |
| 5.4.0 | 2026-01-27 | Exec Lockdown requirement |
| 5.3.0 | 2026-01-27 | Sandbox mode, TCC permissions, troubleshooting |
| 5.2.0 | 2026-01-27 | Part 9 verified working |
| 5.1.0 | 2026-01-26 | Reminders & Calendar Integration |
| 5.0.0 | 2026-01-26 | Major consolidation: Part 8 Key Insights, Signal setup, voice, shell config |

**Pre-5.0:** Foundation releases (v3.0-4.1) — source install, local embeddings, SSH workflow, memory plugin, PKM integration basics.

---

## Part 8: Key Insights & Gotchas

Hard-won lessons from setup and troubleshooting sessions:

### Installation & Config

1. **npm link doesn't work reliably** — Manual symlink was needed: `ln -sf ~/src/clawdbot/dist/entry.js ~/.npm-global/bin/clawdbot`

2. **Phone numbers need `--json` flag** — `+1...` gets parsed as a number otherwise:
   ```bash
   clawdbot config set --json channels.signal.account '"+12026437862"'  # Correct
   clawdbot config set channels.signal.account +12026437862             # Wrong
   ```

3. **Signal cliPath defaults wrong** — Must explicitly set:
   ```bash
   clawdbot config set --json channels.signal.cliPath '"/opt/homebrew/bin/signal-cli"'
   ```

4. **Daemon doesn't load .zshrc** — Must use FULL PATH to binaries in clawdbot config

5. **Homebrew Node shared between users works** — No per-user install needed; bruba uses `/opt/homebrew/bin/node` from main user

### Signal Setup

6. **qrencode DOESN'T work for Signal linking** — Use https://qr.io with "Text mode" instead; qrencode mishandles URL-encoded base64 (`%3D`, `%2F`, `%2B`)

7. **Signal requires three-step setup:**
   1. Configure clawdbot (enable channel, set account, cliPath, httpPort)
   2. Link signal-cli to phone (via qr.io QR code)
   3. Approve pairing in clawdbot

8. **Signal daemon port conflict** — Default port 8080 may conflict with code-server; use `httpPort: 8088`:
   ```bash
   clawdbot config set channels.signal.httpPort 8088
   ```

### Voice Transcription

9. **Use Python openai-whisper, not whisper-cpp** — whisper-cpp doesn't handle m4a (Signal's voice format); Python whisper does

10. **Audio transcription is Gateway pre-processing, NOT an agent tool** — Transcript replaces message body before agent sees it. That's why:
    - `group:media` sandbox config does nothing (group doesn't exist)
    - Agent correctly reports "no audio tools" (there aren't any to call)
    - Skill showing "Ready" doesn't mean daemon can find the binary

### WebChat

11. **WebChat requires secure context** — Must access via HTTPS or localhost. Error: `control ui requires HTTPS or localhost (secure context)`

12. **Tailscale serve on main user is cleanest** — Bruba binds to loopback, main user runs `tailscale serve --bg 18789`

### Shell & Environment

13. **Even with .zshenv sourcing .zshrc, some SSH modes bypass PATH** — When in doubt, use full paths like `/opt/homebrew/bin/signal-cli`

14. **Source install > npm global** — Better for dev/debugging, easier to update

15. **nvm can stay installed but unloaded** — Just don't source it in .zshrc; clawdbot complains about version managers

### Reminders & Calendar

16. **TCC permissions are per-binary: Node.js ≠ Terminal.app** — Running `remindctl authorize` in Terminal grants permission to Terminal, but Clawdbot uses Node.js. Have Bruba execute the command via Signal to grant permission to Node.js.

17. **`tccutil reset <service>` clears cached TCC denials** — If you clicked Deny, the denial is cached. Reset with `tccutil reset Reminders` or `tccutil reset Calendar`, then retry.

18. **Sandbox mode "all" breaks CLI tool access** — Default sandbox puts everything in Docker. Use `sandbox.mode: "off"` for host CLI access. The exec-approvals.json allowlist is still the security boundary.

19. **`clawdbot sandbox explain` is the diagnostic** — Shows runtime (direct vs docker), mode, and what's allowed/denied.

20. **icalBuddy shows calendars from bruba's iCloud account** — Share calendars from main account to bruba via iCloud sharing. The "Bruba" calendar (if created) is what Bruba can write to.

21. **dmPolicy "allowlist" silently drops unknown senders** — Unlike "pairing" which gives a code, "allowlist" mode ignores messages from numbers not in allowFrom. No response, no pairing code, nothing.

22. **exec-approvals.json requires explicit gateway mode** — With `sandbox.mode: "off"`, the allowlist is ignored unless you also set:
    ```bash
    clawdbot config set tools.exec.host gateway
    clawdbot config set tools.exec.security allowlist
    ```
    This was the missing piece for proper lockdown.

23. **Token economics require filesystem access** — Bruba needs read-only commands to check file sizes (`wc`, `du`), list files (`ls`), preview content (`head`/`tail`), and search (`grep`) before loading full documents. All added to exec-approvals.json allowlist. Security relies on account isolation (scoped patterns blocked by approval UX issues).

24. **Clawdbot's tools.media.audio CLI provider doesn't invoke wrapper scripts** — Config is accepted and appears correct, but the wrapper is never called. Tested with debug logging — no invocations. Workaround: prompt-driven voice handling where Bruba manually calls whisper-clean.sh via exec.

### Working Shell Config

**~/.zshrc:**
```bash
# PATH setup - order matters (first = highest priority)
export PATH="$HOME/.npm-global/bin:$PATH"    # npm globals (clawdbot)
export PATH="/opt/homebrew/bin:$PATH"         # Homebrew (shared from main user)
export PATH="$HOME/.local/bin:$PATH"          # Local binaries

# NVM - installed but not loaded (using Homebrew Node instead)
export NVM_DIR="$HOME/.nvm"
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

# Watch logs for audio processing
ssh bruba "tail -f /tmp/clawdbot/clawdbot-2026-01-26.log" | grep -i audio

# Test whisper manually
ssh bruba "whisper ~/.local/share/signal-cli/attachments/example.m4a --model base"

# Check media config
ssh bruba "clawdbot config get tools.media"

# Check if binary accessible in daemon context
ssh bruba "sudo -u bruba /bin/zsh -c 'which whisper'"
```

---

## Part 9: Reminders & Calendar Integration

### 9.1 Overview

Enable Bruba to access Apple Reminders and Calendar via iCloud sharing.

| Component | Purpose |
|-----------|---------|
| remindctl | CLI for Apple Reminders (list, add, complete, edit) |
| icalBuddy | CLI for Apple Calendar (list calendars, events) |
| apple-reminders skill | Clawdbot skill wrapping remindctl |

### 9.2 Install CLI Tools

Both tools install via Homebrew on the main account (shared with bruba):

```bash
# remindctl (from steipete tap)
brew tap steipete/tap
brew install steipete/tap/remindctl

# icalBuddy
brew install ical-buddy

# Verify
which remindctl icalBuddy
# /opt/homebrew/bin/remindctl
# /opt/homebrew/bin/icalBuddy
```

**Note:** If Homebrew install fails due to CLT issues, download remindctl directly:
```bash
curl -sL "https://github.com/steipete/remindctl/releases/latest/download/remindctl-macos.zip" -o /tmp/remindctl.zip
unzip -o /tmp/remindctl.zip -d /tmp
mv /tmp/remindctl /opt/homebrew/bin/
chmod +x /opt/homebrew/bin/remindctl
```

### 9.3 Configure Sandbox Mode

**Critical:** With default `sandbox.mode: "all"`, Bruba runs in Docker and cannot access host CLI tools. Must change to "off" or "non-main".

```bash
# Use "off" for single-user setup (simplest)
ssh bruba 'clawdbot config set agents.defaults.sandbox.mode off'
ssh bruba "clawdbot daemon restart"
```

**Sandbox mode options:**
| Mode | Behavior |
|------|----------|
| `"off"` | No sandboxing, everything runs on host |
| `"non-main"` | Main DM session on host, group chats sandboxed |
| `"all"` | Everything sandboxed in Docker (default, breaks CLI tools) |

**Why "off" is safe:** The exec-approvals.json allowlist still constrains which binaries can run. Only remindctl and icalBuddy are permitted.

**Diagnostic command:**
```bash
ssh bruba "clawdbot sandbox explain"
# Should show: runtime: direct, mode: off
```

### 9.4 Configure Exec Permissions

**Security model (6 layers):**
```
Layer 1: sandbox.mode              → must be "off" or "non-main" for host access
Layer 2: tools.deny                → exec must NOT be in deny list
Layer 3: tools.allow               → exec must be explicitly allowed
Layer 4: tools.elevated.enabled    → allow host-level exec
Layer 5: exec-approvals.json       → tight allowlist (remindctl, icalBuddy only)
Layer 6: macOS TCC                 → what those binaries can access (granted to Node.js!)
```

**Step 1: Configure tools permissions:**

```bash
# Enable elevated tools (allows host-level exec with allowlist)
ssh bruba "clawdbot config set --json tools.elevated.enabled true"

# Remove exec from deny list (keep other dangerous tools blocked)
ssh bruba 'clawdbot config set --json tools.deny '\''["process", "browser", "canvas", "nodes", "cron", "gateway"]'\'''

# Add exec to allow lists (NO group:reminders or group:calendar - use CLI directly)
ssh bruba 'clawdbot config set --json tools.allow '\''["read", "write", "edit", "exec", "memory_search", "memory_get", "group:memory", "group:sessions", "image", "web_search", "web_fetch"]'\'''
ssh bruba 'clawdbot config set --json tools.sandbox.tools.allow '\''["group:memory", "group:media", "group:sessions", "exec", "group:web"]'\'''
```

**Step 2: Create exec approvals allowlist:**

See section 1.8.1 for the full allowlist structure. The key entries for reminders/calendar are:

```bash
# Add remindctl and icalBuddy to bruba-main allowlist
ssh bruba 'cat ~/.clawdbot/exec-approvals.json | jq ".agents[\"bruba-main\"].allowlist += [
  {\"pattern\": \"/opt/homebrew/bin/remindctl\", \"id\": \"remindctl\"},
  {\"pattern\": \"/opt/homebrew/bin/icalBuddy\", \"id\": \"icalbuddy\"}
]" > /tmp/exec.json && mv /tmp/exec.json ~/.clawdbot/exec-approvals.json'

ssh bruba "clawdbot daemon restart"
```

**What this allows:**
| Binary | Allowed? | Purpose |
|--------|----------|---------|
| /opt/homebrew/bin/remindctl | ✅ Yes | Reminders manipulation |
| /opt/homebrew/bin/icalBuddy | ✅ Yes | Read-only calendar access |
| /usr/bin/wc | ✅ Yes | File size checking (token-conscious loading) |
| /bin/ls | ✅ Yes | List files and sizes |
| /usr/bin/head | ✅ Yes | Preview first N lines |
| /usr/bin/tail | ✅ Yes | Preview last N lines |
| /usr/bin/grep | ✅ Yes | Search file contents |
| /usr/bin/du | ✅ Yes | Directory size checking (`du -sh`) |
| /bin/cat | ✅ Yes | Read file contents |
| /usr/bin/find | ✅ Yes | Find files by pattern |
| /Users/bruba/clawd/tools/whisper-clean.sh | ✅ Yes | Voice transcription |
| /Users/bruba/clawd/tools/tts.sh | ✅ Yes | Text-to-speech |
| /Users/bruba/bin/web-search.sh | ✅ Yes | Web search wrapper |
| Everything else | ❌ No | Blocked by exec-approvals.json |

**Note:** Bruba uses CLI tools directly via exec (NOT skills or group:reminders/group:calendar). Commands have full disk access within Bruba's account. Security relies on account isolation.

### 9.4.1 Pattern Matching Behavior

**Critical:** Patterns match the **binary path only**, not the full command string.

| Pattern | Matches | Does NOT Match |
|---------|---------|----------------|
| `/usr/bin/grep` | `/usr/bin/grep "test" file.md` | `grep "test" file.md` |

**Requirements for commands to work:**

1. **Full paths required** — Bruba must call `/usr/bin/grep`, not `grep`
2. **Pipes** — Each command in a pipe must use full path:
   - ✅ `/usr/bin/grep "x" file | /usr/bin/head -5`
   - ❌ `/usr/bin/grep "x" file | head -5`
3. **Redirections not supported** — `2>/dev/null` breaks allowlist mode; omit redirects
4. **Safe bins (stdin-only)** — `grep`, `head`, `tail`, `wc` work without full path ONLY for stdin-only operations (no file arguments)

**Implication:** Bruba's TOOLS.md must instruct it to always use full paths. The exec-approvals.json patterns cannot scope by argument (e.g., restricting to `~/clawd/*` via patterns is not supported).

### 9.5 Grant TCC Permissions (Critical: Node.js, Not Terminal)

**Key insight:** TCC permissions are per-binary. Running `remindctl authorize` in Terminal grants permission to Terminal.app, but Clawdbot runs commands via **Node.js**—a different binary. You must grant permission to Node.js.

**The correct approach:** Have Bruba execute the authorize command so macOS prompts for Node.js permission.

**Step 1: Ensure GUI access to bruba account**

Use Screen Sharing or Fast User Switching to see bruba's desktop (for the TCC popup).

**Step 2: Trigger TCC prompts via Bruba (not Terminal)**

In Signal, tell Bruba:
```
execute remindctl authorize
```

Watch for GUI popup on bruba account, click **Allow**.

Then for Calendar:
```
execute icalBuddy calendars
```

Approve Calendar access popup.

**Step 3: Verify permissions granted to Node.js**

Check: System Settings → Privacy & Security → Reminders/Calendars → Look for "node" or "Node.js" (not just Terminal)

**If permission was previously denied:**

The denial is cached. Reset it, then retry:
```bash
# On bruba account (via SSH or Terminal)
tccutil reset Reminders
tccutil reset Calendar
```
Then have Bruba run the authorize commands again via Signal.

### 9.6 Share iCloud Lists

From <REDACTED-NAME>'s account, share Reminders lists to Bruba's iCloud account.

**Lists to share:**
| List | Share? |
|------|--------|
| Reminders (Default) | ✅ Yes |
| Scheduled | ✅ Yes |
| Backlog | ✅ Yes |
| Groceries | ✅ Yes |
| Work | ✅ Yes |
| Work Scheduled | ✅ Yes |
| Work Backlog | ✅ Yes |
| Planning | ✅ Yes |
| Personal | ✅ Yes |
| Got To Buy It | ❌ NO (family shared) |
| Family | ❌ NO (off limits) |

**To share a list:**
1. Open Reminders app
2. Right-click list → Manage Sharing
3. Add Bruba's iCloud email
4. Accept invite from Bruba's account

**For Calendar:** Share calendars the same way via Calendar app → File → Share Calendar.

### 9.7 Verify Integration

```bash
# Test remindctl from SSH
ssh bruba "/opt/homebrew/bin/remindctl list"
ssh bruba "/opt/homebrew/bin/remindctl today"

# Test icalBuddy
ssh bruba "/opt/homebrew/bin/icalBuddy calendars"
ssh bruba "/opt/homebrew/bin/icalBuddy eventsToday"

# Test apple-reminders skill status
ssh bruba "clawdbot skills list | grep reminders"
```

**Test via Signal:**
Send to Bruba:
- "What's on my reminders today?"
- "What events do I have this week?"

### 9.8 Troubleshooting

**"capabilities=none" or "sandboxed in Docker"**
- Sandbox mode is "all" — change to "off" or "non-main"
- Run: `ssh bruba 'clawdbot config set agents.defaults.sandbox.mode off'`
- Restart daemon after changing
- Verify with: `ssh bruba "clawdbot sandbox explain"` (should show `runtime: direct`)

**remindctl works in Terminal but not via Bruba**
- TCC permission was granted to Terminal.app, not Node.js
- Have Bruba execute `remindctl authorize` via Signal to trigger Node.js permission prompt
- Check System Settings → Privacy & Security → Reminders for "node" entry

**"Reminders access: Denied" even after granting**
- Permission cached as denied from earlier attempt
- Reset the cache: `tccutil reset Reminders` (on bruba account)
- Then have Bruba retry via Signal

**"No calendars" or wrong calendars showing**
- icalBuddy sees calendars from bruba's iCloud account
- Share calendars from main account via iCloud sharing
- The "Bruba" calendar (created on bruba account) is what Bruba can write to

**Skill not responding**
- Verify sandbox mode: `clawdbot config get agents.defaults.sandbox.mode` (should be "off")
- Verify elevated tools: `clawdbot config get tools.elevated` (should show enabled: true)
- Verify exec in allow list: `clawdbot config get tools.allow` (should include "exec")
- Check exec-approvals.json exists: `cat ~/.clawdbot/exec-approvals.json`
- Restart daemon: `clawdbot daemon restart`
- Reset session in Signal: `/reset`
- Restart daemon: `clawdbot daemon restart`

**Shared lists not appearing**
- iCloud sync delay (wait a few minutes)
- Accept sharing invite from Bruba's iCloud account
- Verify bruba has iCloud signed in: System Settings → Apple ID

### 9.9 Single-User Lockdown

For single-user setups, lock down Bruba so only you can message it:

```bash
# Set dmPolicy to allowlist (unknown senders silently ignored)
ssh bruba 'clawdbot config set channels.signal.dmPolicy allowlist'

# Allow only your phone number
ssh bruba 'clawdbot config set --json channels.signal.allowFrom '\''["+1XXXXXXXXXX"]'\'''

# Restart
ssh bruba "clawdbot daemon restart"
```

**dmPolicy modes:**
| Mode | Unknown sender behavior |
|------|------------------------|
| `"pairing"` | Gets pairing code, can be approved later |
| `"allowlist"` | Silently ignored, no code, cannot be added |
| `"open"` | Anyone can message (dangerous) |

**Verify lockdown:**
```bash
ssh bruba 'clawdbot config get channels.signal'
# Should show:
# dmPolicy: "allowlist"
# allowFrom: ["+1XXXXXXXXXX"]
```

With `allowlist` + your number only, anyone else messaging Bruba's Signal number gets silently dropped. No way to add new users without editing config.

**Gateway Dashboard** is already protected by token auth (configured during setup).

---

## Part 10: Web Search Configuration

Web search uses an isolated reader subagent pattern for security.

### 10.1 Architecture

```
User → Bruba (Signal)
         │
         │ exec: /Users/bruba/bin/web-search.sh "query"
         ▼
    web-search.sh wrapper (allowlisted)
         │
         │ clawdbot agent --agent web-reader --local --json
         ▼
    Web-Reader Agent (sandboxed in Docker)
         │
         │ web_search / web_fetch (actual execution)
         ▼
    Brave API → Web
         │
         │ JSON result
         ▼
    Bruba receives output, analyzes, reports to user
```

**Security properties:**
- Main agent cannot access web tools directly (denied in config)
- Reader agent has web_search + web_fetch only (no exec/write/edit)
- Reader runs sandboxed in Docker (`sandbox.mode: "all"`)
- Wrapper script constrains invocation to web-reader only
- Wrapper must be in `agents.bruba-main.allowlist` (see 1.8.1)

### 10.2 Configuration Files

| File | Purpose |
|------|---------|
| `~/bin/web-search.sh` | Wrapper script (invokes reader via CLI) |
| `~/bruba-reader/SOUL.md` | Reader security instructions |
| `~/.clawdbot/exec-approvals.json` | Wrapper must be in `agents.bruba-main.allowlist` |
| `~/.clawdbot/logs/reader-raw-output.log` | Raw reader responses (logged via Write tool) |
| `~/.clawdbot/.env` | BRAVE_API_KEY |
| `~/clawd/TOOLS.md` | Web search protocol for main agent |

### 10.3 Relevant Config Sections

**agents.list:**
```json
[
  {
    "id": "bruba-main",
    "tools": {
      "allow": ["sessions_send", ...],
      "deny": ["web_fetch", "web_search", "browser", ...]
    }
  },
  {
    "id": "web-reader",
    "workspace": "~/bruba-reader",
    "sandbox": { "mode": "all", "scope": "agent" },
    "tools": {
      "allow": ["web_fetch", "web_search", "read"],
      "deny": ["exec", "write", "edit", ...]
    }
  }
]
```

**tools.web:**
```json
{
  "search": { "enabled": true, "provider": "brave", "maxResults": 10 },
  "fetch": { "enabled": true, "maxChars": 50000, "timeoutSeconds": 30 }
}
```

**tools.agentToAgent:**
```json
{ "enabled": true, "allow": ["web-reader"] }
```

### 10.4 Usage Protocol

1. User asks something that needs web search
2. Bruba asks permission: "Want me to search for that?"
3. User confirms
4. Bruba runs exec: `/Users/bruba/bin/web-search.sh 'Search for "[query]"...'`
5. Wrapper invokes reader agent via `clawdbot agent --local --json`
6. Reader executes `web_search` and `web_fetch` tools (actual API calls)
7. Bruba receives JSON output, logs via Write tool, analyzes for anomalies
8. Bruba reports: summary + sources + tokens + security status

### 10.5 Troubleshooting

**Reader not responding:**
- Check daemon status: `clawdbot daemon status`
- Verify agentToAgent enabled: `clawdbot config get tools.agentToAgent`
- Check reader in agents list: `clawdbot config get agents.list`

**No search results:**
- Verify BRAVE_API_KEY in .env: `cat ~/.clawdbot/.env`
- Check web.search.enabled: `clawdbot config get tools.web`
- Test Brave API directly:
  ```bash
  curl -H "X-Subscription-Token: $BRAVE_API_KEY" \
    "https://api.search.brave.com/res/v1/web/search?q=test"
  ```

**Security flags appearing frequently:**
- Review flagged content in reader-raw-output.log
- Consider adding domain restrictions if pattern emerges
- May indicate injection attempts — investigate sources

**Reader has wrong tools:**
- Verify reader config: `clawdbot config get agents.list | jq ".[1]"`
- Should show: `tools.allow: ["web_fetch", "web_search", "read"]`
- Should show: `sandbox.mode: "all"`

### 10.6 Docker Requirement (CRITICAL)

**Web search requires Docker Desktop running.** The reader agent uses `sandbox.mode: "all"` which runs in a Docker container.

**Enable auto-start:**
1. Open Docker Desktop → Settings → General
2. Enable "Start Docker Desktop when you sign in"
3. Or: System Settings → Login Items → Add Docker Desktop

**Verify Docker is running:**
```bash
ssh bruba 'docker ps'  # Should return without error
```

**If Docker not running:**
- Web search will fail with sandbox/container errors
- Start Docker Desktop manually or reboot with auto-start enabled

**Mac Mini / CLI Docker (future):**
For headless servers without Docker Desktop, use colima:
```bash
brew install colima docker
colima start

# Auto-start via launchd (create ~/Library/LaunchAgents/com.colima.plist)
```

### 10.7 Known Limitations

**Exec wrapper approach (not sessions_send):**
- Original design used `sessions_send` tool for inter-agent communication
- Tool intersection rules made this unavailable at runtime
- Current approach uses exec wrapper calling `clawdbot agent --local`
- Wrapper must be in `agents.bruba-main.allowlist` (not `agents.main`)

**Audit logging uses Write tool:**
- Bruba logs reader output using Write tool (already allowed)
- Do NOT use exec for logging — hits approval gate
- Reader responses also appear in session history as backup

**Harmless warning on search:**
```
[tools] tools.allow allowlist contains unknown entries (group:memory, group:reminders, group:calendar)
```
This appears because global `tools.allow` includes plugins the reader doesn't use. Not breaking, just noisy.
