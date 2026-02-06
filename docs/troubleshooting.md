---
type: doc
scope: reference
title: "Troubleshooting Guide"
description: "Common issues and solutions for bot operation"
---

# Troubleshooting Guide

Consolidated troubleshooting reference for common issues. For setup procedures, see [Setup Guide](setup.md).

---

## Quick Reference (Common Issues)

| Symptom | Likely Cause | Quick Fix |
|---------|--------------|-----------|
| Commands hang/timeout | Daemon not running | `/launch` or `ssh bruba "openclaw daemon start"` |
| Config changes ignored | Daemon needs restart | `/restart` |
| Exec command denied | Not in allowlist | Add to `exec-approvals.json`, restart |
| Memory search empty | Index stale | `ssh bruba "openclaw memory index"` |
| "Cannot connect" | SSH config issue | Check `~/.ssh/config` |
| Memory tools not appearing | Plugin not enabled | Add `group:memory` to `tools.sandbox.tools.allow` |
| Non-interactive SSH fails | .zshrc not loaded | Create `~/.zshenv` sourcing `~/.zshrc` |
| Tailscale serve won't connect | Wrong account | Run `tailscale serve` on bot account, not admin |

---

## Installation & Config Issues

### npm link Doesn't Work Reliably

**Symptom:** `openclaw: command not found` after `pnpm link --global`

**Fix:** Create a manual symlink:
```bash
ln -sf ~/src/openclaw/dist/entry.js ~/.npm-global/bin/openclaw
```

### Phone Numbers Need --json Flag

**Symptom:** Phone number gets parsed incorrectly

**Example:**
```bash
# Wrong - gets parsed as a number
openclaw config set channels.signal.account +12025551234

# Correct - wrapped as JSON string
openclaw config set --json channels.signal.account '"+12025551234"'
```

### Signal cliPath Defaults Wrong

**Symptom:** Signal commands fail even though signal-cli is installed

**Fix:** Explicitly set the path:
```bash
openclaw config set --json channels.signal.cliPath '"/opt/homebrew/bin/signal-cli"'
```

### Daemon Doesn't Load .zshrc

**Impact:** Commands fail because PATH isn't set correctly

**Rule:** Use FULL PATH to binaries in openclaw config and exec-approvals.json

**Example:**
```json
{ "pattern": "/opt/homebrew/bin/remindctl", "id": "remindctl" }
```

### Non-Interactive SSH Commands Fail

**Symptom:** `ssh bruba "openclaw status"` shows "command not found"

**Cause:** `~/.zshrc` not loaded for non-interactive shells

**Fix:**
```bash
ssh bruba
cat > ~/.zshenv << 'EOF'
source ~/.zshrc
EOF
exit

# Test
ssh bruba "which openclaw"
```

---

## Signal Issues

### qrencode Doesn't Work for Signal Linking

**Symptom:** QR code scanned but linking fails

**Cause:** qrencode mishandles URL-encoded base64 (`%3D`, `%2F`, `%2B`)

**Fix:** Use https://qr.io with "Text mode" instead

### Signal Requires Three-Step Setup

Missing any step causes connection issues:

1. Configure openclaw (enable channel, set account, cliPath, httpPort)
2. Link signal-cli to phone (via QR code)
3. Approve pairing in openclaw

### Signal Port Conflict

**Symptom:** `signal daemon not ready (HTTP 401)` or messages not flowing

**Cause:** Default port 8080 conflicts with code-server or other services

**Fix:**
```bash
lsof -i :8080  # Check what's using port
openclaw config set channels.signal.httpPort 8088
openclaw daemon restart
```

### dmPolicy "allowlist" Silently Drops Messages

**Symptom:** Unknown senders get no response, no pairing code

**Cause:** Unlike "pairing" which gives a code, "allowlist" mode ignores messages from numbers not in allowFrom

**Behavior by mode:**

| Mode | Unknown sender behavior |
|------|------------------------|
| `"pairing"` | Gets pairing code, can be approved later |
| `"allowlist"` | Silently ignored, no code, cannot be added |
| `"open"` | Anyone can message (dangerous) |

---

## Voice Issues

### Voice Memos Come Through as `<media:unknown>`

**Symptom:** Shared audio files from Voice Memos app don't auto-transcribe

**Current approach:** Bot manually transcribes any audio file path it receives

### No Auto-Transcription

**Background:** Clawdbot's `tools.media.audio` pipeline doesn't work with wrapper scripts. The config is accepted but the wrapper is never invoked.

**Workaround:** Prompt-driven approach where bot manually calls `whisper-clean.sh` via exec

**Setup:**

1. Disable auto-transcription:
   ```bash
   ssh bruba 'openclaw config set tools.media.audio.enabled false'
   ```

2. Add voice scripts to exec allowlist (whisper-clean.sh, tts.sh)

3. Update TOOLS.md with voice handling instructions

### Whisper Model Selection

Use `base` model only. Benchmarked on M4 Mac Mini:

| Model | RTF | Notes |
|-------|-----|-------|
| tiny | 0.20 | 5x faster, lower quality |
| **base** | 0.28 | **3.5x faster, good quality** |
| small | 1.9 | Slower than real-time |
| medium | 5.3 | Much slower |

RTF = Real-Time Factor. <1.0 is faster than real-time.

### Use Python whisper, Not whisper-cpp

**Reason:** whisper-cpp doesn't handle m4a (Signal's voice format); Python whisper does

### Message Tool Not Working (Media Attachments)

**Symptom:** Bot outputs `MEDIA:/tmp/response.wav` as text instead of sending the file

**Cause:** The `message` tool isn't available. Most likely the global allowlist ceiling effect.

**Check:**
```bash
# Check global tools.allow includes message
ssh bruba 'cat ~/.openclaw/openclaw.json | jq ".tools.allow"'

# Check agent-level config
ssh bruba 'cat ~/.openclaw/openclaw.json | jq ".agents.list[] | select(.id==\"bruba-main\") | .tools"'
```

**Fix:** Add `message` to global `tools.allow`:
```bash
ssh bruba 'jq ".tools.allow += [\"message\"]" ~/.openclaw/openclaw.json > /tmp/oc.json && mv /tmp/oc.json ~/.openclaw/openclaw.json'
ssh bruba 'openclaw gateway restart'
```

**Correct usage pattern:**
```
1. exec: tts.sh "response" /tmp/response.wav
2. message action=send target=uuid:<from-header> filePath=/tmp/response.wav message="response"
3. Reply: NO_REPLY
```

**Critical:** Always respond with `NO_REPLY` after using the message tool to prevent duplicate text output.

### Voice Response Sends Twice

**Symptom:** User receives voice file AND a separate text message with the same content

**Cause:** Bot didn't use `NO_REPLY` after the message tool call

**Fix:** After `message action=send ... message="text"`, the bot must respond with just `NO_REPLY`. The message tool already sends both the audio and text.

### Siri Async Replies Not Working

**Symptom:** Bot processes Siri async message but no Signal reply arrives

**Cause:** USER.md missing Signal UUID. Siri async messages don't include UUID metadata.

**Fix:** Add your Signal UUID to USER.md on the bot:

```markdown
## Signal Identity
- **Signal UUID:** `uuid:XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX`
```

Get the UUID from any Signal message header (look for `id:uuid:...`).

---

## Web Search Issues

### Docker Not Running

**Symptom:** Web search fails with sandbox/container errors

**Cause:** Web reader uses `sandbox.mode: "all"` which requires Docker

**Fix:** Start Docker Desktop or configure colima for headless servers

**Verify:**
```bash
ssh bruba 'docker ps'  # Should return without error
```

### Reader Not Responding

**Check:**
1. Daemon status: `openclaw daemon status`
2. agentToAgent enabled: `openclaw config get tools.agentToAgent`
3. Reader in agents list: `openclaw config get agents.list`

### No Search Results

**Check:**
1. BRAVE_API_KEY in .env: `cat ~/.openclaw/.env`
2. web.search.enabled: `openclaw config get tools.web`
3. Test API directly:
   ```bash
   curl -H "X-Subscription-Token: $BRAVE_API_KEY" \
     "https://api.search.brave.com/res/v1/web/search?q=test"
   ```

---

## Memory/Search Issues

### Memory Tools Not Appearing

**Symptom:** `/context detail` shows no memory tools

**Check:**
1. Plugin loaded? `openclaw status | grep Memory`
2. Sandbox tools configured? `cat ~/.openclaw/openclaw.json | jq '.tools.sandbox.tools'`
3. Restart after config change? `openclaw daemon restart`

**Fix:** Add `group:memory` to `tools.sandbox.tools.allow`

### Memory Search Fails: "database is not open"

**Symptom:**
```
openclaw memory search "query"
No matches.
[memory] sync failed (search): Error: database is not open
```

**Cause:** Index is dirty, auto-sync didn't trigger

**Fix:**
```bash
openclaw memory index --verbose
openclaw memory status --deep  # Should show Dirty: no
```

**Nuclear option:**
```bash
openclaw daemon stop
rm -f ~/.openclaw/memory/*.sqlite
openclaw daemon start
openclaw memory index --verbose
```

### Files Not Being Indexed

**Check:**
1. Files directly in `~/clawd/memory/`? (no subdirectories — indexer doesn't recurse)
2. Real files, not symlinks? (`ls -la` to check — symlinks not followed)
3. Valid source name? Only `memory` works, not custom names

**Key constraints:**
- **Predefined sources only** — `memory` maps to `~/clawd/memory/*.md` + `MEMORY.md`
- **No subdirectory recursion** — Only direct children are indexed
- **Symlinks not followed** — Files must be actual files

---

## HTTP API Issues

### Tailscale Serve Setup

**Critical insight:** Each macOS user account has its own isolated localhost. `tailscale serve` must run under the **same account** as the gateway.

**Wrong:**
```bash
# On admin user (dadbook) — DOESN'T WORK
tailscale serve --bg 18789
# This proxies to dadbook's localhost, but gateway is on bruba's localhost
```

**Correct:**
```bash
# On bot account (bruba) — same account as gateway
ssh bruba 'tailscale serve --bg 18789'
```

**Architecture:**
```
Phone → Tailscale HTTPS → tailscale serve (bruba account)
                                    ↓
                          http://127.0.0.1:18789
                                    ↓
                          openclaw gateway (bruba account)
```

**Gateway config stays on loopback** — don't change `bind: "loopback"` to `tailnet` or `all`. Let tailscale serve handle external access while gateway stays locked to localhost.

**Endpoint:** `https://dadmini.tail042aa8.ts.net/v1/chat/completions`

**To verify:**
```bash
ssh bruba 'tailscale serve status'
```

**To tear down:**
```bash
ssh bruba 'tailscale serve --https=443 off'
```

### WebChat Won't Connect

**Symptom:** `disconnected (1008): control ui requires HTTPS or localhost (secure context)`

**Cause:** WebChat requires a secure context (HTTPS or localhost). LAN bind mode doesn't work.

**Fix:** Use Tailscale serve (see above), then access via:
```
https://your-machine.tail042aa8.ts.net/chat?session=main
```

### Gateway Bind Options

**Problem:** Gateway bound to loopback (127.0.0.1) is unreachable from phone

**Don't do:** Change `bind: "loopback"` to `bind: "all"` — exposes endpoint to entire LAN

**Do:** Keep gateway on loopback, use Tailscale serve for external access

**Security properties:**
- Gateway only listens on 127.0.0.1 (not exposed to LAN)
- Tailscale handles TLS (automatic certs)
- Only devices on your Tailnet can reach the endpoint
- Bearer token provides second layer of auth

### Token Rotation

If Bearer token is exposed:
```bash
NEW_TOKEN="bruba_gw_$(openssl rand -base64 32 | tr -d '/+=' | head -c 40)"
ssh bruba "openclaw config set gateway.http.auth.token '$NEW_TOKEN'"
ssh bruba 'openclaw gateway restart'
```

### HTTP API Logging for Siri/Shortcuts

Messages via HTTP API (Siri, Shortcuts) should be logged for continuity:

1. Prefix messages with source tag: `[From Siri]`, `[From Automation]`
2. Bot logs to `memory/HTTP_API_LOG.md`
3. Periodic relay sends to Signal (via cron or heartbeat)

**Known issue:** Signal delivery from cron context is flaky — `Signal RPC -1: Failed to send message` errors occur intermittently.

---

## Exec & Sandbox Issues

### Sandbox Mode "all" Breaks CLI Tool Access

**Symptom:** Skills show "capabilities=none" or commands fail

**Cause:** Default `sandbox.mode: "all"` puts everything in Docker, blocking host CLI tools

**Fix:**
```bash
ssh bruba 'openclaw config set agents.defaults.sandbox.mode off'
ssh bruba "openclaw daemon restart"
```

**Sandbox mode options:**

| Mode | Behavior |
|------|----------|
| `"off"` | No sandboxing, everything runs on host |
| `"non-main"` | Main DM session on host, group chats sandboxed |
| `"all"` | Everything sandboxed in Docker (breaks CLI tools) |

**Why "off" is safe:** exec-approvals.json allowlist still constrains binaries

### exec-approvals.json Requires Explicit Gateway Mode

**Symptom:** Allowlist exists but commands still blocked/unrestricted

**Cause:** With `sandbox.mode: "off"`, the allowlist is ignored unless you also set gateway mode

**Fix:**
```bash
openclaw config set tools.exec.host gateway
openclaw config set tools.exec.security allowlist
openclaw daemon restart
```

### Wrong Agent ID in exec-approvals.json

**Common mistake:** Using `agents.main` instead of `agents.bruba-main`

The agent ID includes the instance prefix. Check:
```bash
ssh bruba 'cat ~/.openclaw/exec-approvals.json | jq ".agents | keys"'
# Should return: ["bruba-main"]
```

### TCC Permissions Per-Binary

**Problem:** `remindctl authorize` in Terminal grants permission to Terminal, not Node.js

**Solution:** Have bot execute the command so macOS prompts for Node.js permission

```
# In Signal, tell bot:
execute remindctl authorize
```

Watch for GUI popup on bot account, click Allow.

**If permission was previously denied:**
```bash
# On bot account
tccutil reset Reminders
tccutil reset Calendar
```
Then have bot run authorize commands again.

---

## Sync Issues

### Push Succeeds but Memory Search Empty

**Cause:** Index stale after push

**Fix:**
```bash
ssh bruba "openclaw memory index"
```

### Pull Finds No New Sessions

**Cause:** All sessions already pulled

**Check:** `agents/{agent}/sessions/.pulled` contains the session IDs

**Note:** Closed sessions are immutable — only need to pull once

### Mirror Missing Files

**Check:** Bot hasn't created the files yet

**Verify:**
```bash
ssh bruba "ls ~/clawd/"
```

### Mirror Gets PKM Content (Circular Sync)

**Symptom:** `agents/*/mirror/` contains files from exports

**Cause:** Mirror script pulling non-dated files from memory/

**Fix:** Update mirror script patterns to exclude non-dated files

---

## Key Insights & Gotchas

### Shell Config That Works

**~/.zshrc:**
```bash
# PATH setup - order matters (first = highest priority)
export PATH="$HOME/.npm-global/bin:$PATH"    # npm globals (openclaw)
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

# Watch logs for audio processing
ssh bruba "tail -f /tmp/openclaw/openclaw-$(date +%Y-%m-%d).log" | grep -i audio

# Test whisper manually
ssh bruba "whisper ~/.local/share/signal-cli/attachments/example.m4a --model base"

# Check media config
ssh bruba "openclaw config get tools.media"

# Check if binary accessible in daemon context
ssh bruba "sudo -u bruba /bin/zsh -c 'which whisper'"
```

### Doctor Warning: "Config file is group/world readable"

Response depends on ownership model:

| Ownership | Doctor Suggestion | Action |
|-----------|-------------------|--------|
| bruba:wheel | chmod 600 | Safe to apply |
| root:staff | chmod 600 | Do NOT apply (would break daemon) |

**Check before applying:** `ls -la ~/.openclaw/openclaw.json`

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.1.1 | 2026-02-02 | Added Siri async troubleshooting (USER.md Signal UUID requirement) |
| 1.1.0 | 2026-02-02 | Added message tool troubleshooting (media attachments, voice responses, NO_REPLY pattern) |
| 1.0.1 | 2026-02-01 | Fixed Tailscale serve docs — must run on bot account due to localhost isolation |
| 1.0.0 | 2026-02-01 | Initial version (consolidated from legacy PKM docs) |
