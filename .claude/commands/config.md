# /config - Configure Bot Settings

Interactively configure bot daemon settings.

## Instructions

### 1. Load Current Config

```bash
./tools/bot cat /Users/bruba/.clawdbot/clawdbot.json
```

Parse and display relevant current settings to the user.

### 2. Present Setting Menu

Use `AskUserQuestion` to let user choose what to configure:

**Options:**
- Heartbeat - Configure heartbeat ping interval and target
- Exec Allowlist - Manage which binaries the bot can execute

### 3. Setting: Heartbeat

Current config location: `.agents.list[] | select(.id == "bruba-main") | .heartbeat`

**Show current state:**
- Enabled: yes/no (presence of heartbeat object)
- Interval: e.g., "2m", "5m", "30s"
- Target: e.g., "signal"
- Model: e.g., "haiku", "sonnet", "opus" (which model sends the heartbeat)

**Ask what to change:**
1. Toggle enabled/disabled
2. Change interval
3. Change target
4. Change model

**To enable heartbeat:**
```bash
ssh bruba 'jq '\''(.agents.list[] | select(.id == "bruba-main")) += {"heartbeat": {"every": "2m", "target": "signal", "model": "haiku"}}'\'' ~/.clawdbot/clawdbot.json > /tmp/cb.json && mv /tmp/cb.json ~/.clawdbot/clawdbot.json'
```

**To disable heartbeat:**
```bash
ssh bruba 'jq '\''(.agents.list[] | select(.id == "bruba-main")) |= del(.heartbeat)'\'' ~/.clawdbot/clawdbot.json > /tmp/cb.json && mv /tmp/cb.json ~/.clawdbot/clawdbot.json'
```

**To change interval (example: 5m):**
```bash
ssh bruba 'jq '\''(.agents.list[] | select(.id == "bruba-main")).heartbeat.every = "5m"'\'' ~/.clawdbot/clawdbot.json > /tmp/cb.json && mv /tmp/cb.json ~/.clawdbot/clawdbot.json'
```

**To change target:**
```bash
ssh bruba 'jq '\''(.agents.list[] | select(.id == "bruba-main")).heartbeat.target = "signal"'\'' ~/.clawdbot/clawdbot.json > /tmp/cb.json && mv /tmp/cb.json ~/.clawdbot/clawdbot.json'
```

**To change model (example: haiku):**
```bash
ssh bruba 'jq '\''(.agents.list[] | select(.id == "bruba-main")).heartbeat.model = "haiku"'\'' ~/.clawdbot/clawdbot.json > /tmp/cb.json && mv /tmp/cb.json ~/.clawdbot/clawdbot.json'
```

### 3b. Setting: Exec Allowlist

Config file: `~/.clawdbot/exec-approvals.json`
Location: `.agents["bruba-main"].allowlist`

**Note:** This file is separate from clawdbot.json. It controls which binaries the agent can execute.

**List current allowlist:**
```bash
./tools/bot cat /Users/bruba/.clawdbot/exec-approvals.json | jq '.agents["bruba-main"].allowlist[] | .pattern'
```

**Show full allowlist with metadata:**
```bash
./tools/bot cat /Users/bruba/.clawdbot/exec-approvals.json | jq '.agents["bruba-main"].allowlist'
```

**Find binary path before adding:**
```bash
./tools/bot which '<command>'
# If "shell built-in", check for binary:
./tools/bot ls -la /bin/<command> /usr/bin/<command>
```

**Add a binary to allowlist:**
```bash
ssh bruba 'jq '\''(.agents["bruba-main"].allowlist) += [{"pattern": "/path/to/binary", "id": "binary-name-bruba-main"}]'\'' ~/.clawdbot/exec-approvals.json > /tmp/ea.json && mv /tmp/ea.json ~/.clawdbot/exec-approvals.json'
```

**Remove a binary from allowlist:**
```bash
ssh bruba 'jq '\''(.agents["bruba-main"].allowlist) |= map(select(.pattern != "/path/to/binary"))'\'' ~/.clawdbot/exec-approvals.json > /tmp/ea.json && mv /tmp/ea.json ~/.clawdbot/exec-approvals.json'
```

**Common paths:**
- `/bin/echo`, `/bin/cat`, `/bin/ls` - Basic utilities
- `/usr/bin/grep`, `/usr/bin/head`, `/usr/bin/tail` - Text processing
- `/opt/homebrew/bin/*` - Homebrew-installed tools (macOS)

### 4. Restart Prompt

After any config change, ask if user wants to restart the daemon:

```bash
ssh bruba 'clawdbot gateway restart'
```

## Arguments

$ARGUMENTS

## Example

```
User: /config

Claude:
=== Bot Config ===

Current settings:
  Heartbeat: enabled (every 2m → signal, model: haiku)

What would you like to configure?
> Heartbeat

Current heartbeat:
  Enabled: yes
  Interval: 2m
  Target: signal
  Model: haiku

What would you like to change?
> Change interval

Enter new interval (e.g., 30s, 2m, 5m):
> 5m

Updated heartbeat interval to 5m.
Restart daemon to apply? [y/n]
```

## Self-Learning

This skill should grow as the user teaches it new config options.

**When the user:**
- Asks to configure something not documented here
- Corrects an assumption about config structure
- Shows you how a setting actually works

**You should:**
1. Help the user with their immediate config need
2. Ask: "Would you like me to add this capability to /config so it knows about [setting] in the future?"
3. If yes, edit this file to add the new setting section following the existing pattern

**Example additions to track:**
- Model selection (agents.list[].model)
- Tool permissions in clawdbot.json (agents.list[].tools.allow/deny)
- Sandbox settings (agents.list[].sandbox)
- Channel configs (channels.signal.*, channels.telegram.*)

## Discovering Config Options

When you need to understand what config options are available:

**Query defaults with clawdbot CLI:**
```bash
./tools/bot clawdbot config get agents.defaults.heartbeat
./tools/bot clawdbot config get agents.defaults
./tools/bot clawdbot config get tools
```

This shows default values and available fields for different config sections.

**Use clawdbot's built-in help:**
```bash
./tools/bot clawdbot help
./tools/bot clawdbot config --help
```

## Related Skills

- `/status` - Show current daemon status
- `/restart` - Restart the daemon
