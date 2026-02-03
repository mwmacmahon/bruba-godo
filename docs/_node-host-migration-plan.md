---
version: 1.3.0
updated: 2026-02-03
type: cc-packet
project: bruba-godo
tags: [node-host, docker, security, migration, guru, defense-in-depth]
---

# CC Packet: Node Host Migration

> ⚠️ **STATUS: SANDBOX DISABLED (2026-02-03)**
>
> Sandbox mode turned off due to agent-to-agent session visibility bug. With `sandbox.scope: "agent"`, `sessions_send` cannot see other agents' sessions, breaking guru routing.
>
> **Current config:** `sandbox.mode: "off"` — agents run on host.
> **TODO:** Re-enable when OpenClaw fixes cross-agent visibility.

**Objective:** Dockerize Bruba agents while keeping exec on the host via OpenClaw's node host. This closes the exec-approvals.json self-escalation security gap.

**Decision already made:** We ARE doing this. Don't second-guess the decision. Flag blockers that would break functionality, not cost-benefit concerns.

---

## Context

**Current state:**
- OpenClaw node host LaunchAgent installed: `~/Library/LaunchAgents/ai.openclaw.node.plist`
- Signal-cli running as HTTP daemon on `127.0.0.1:8088`
- Auth stored in `~/.openclaw/openclaw.json` (not per-agent files)
- Docker Desktop installed (managed from bruba account, installed via admin)
- **Four agents:** bruba-main, bruba-guru, bruba-manager, bruba-web
- **Shared storage:** bruba-shared for Main↔Guru handoff

**Security gap being closed:**
- Currently, agents can theoretically edit `~/.openclaw/exec-approvals.json` to self-escalate
- After migration: agents run in Docker, can't reach host filesystem, exec goes through node host

**Target architecture:**
```
Host: Node host process (reads exec-approvals.json, executes commands)
      Signal-cli daemon (127.0.0.1:8088)
      Tailscale (admin-managed)
      
Container: OpenClaw gateway + all four agents
           Bind mounts for workspace/memory/tools(ro)/media/shared
           Reaches node host via host.docker.internal
           Reaches signal-cli via host.docker.internal:8088
```

---

## Phase 0: Filesystem Verification

**CRITICAL:** Before any Docker work, verify all agent directories exist and are properly structured. Docker bind mounts will fail silently or cause confusing errors if paths don't exist.

### 0.1: Agent Directory Checklist

Run this verification script:

```bash
#!/bin/bash
# verify-agent-dirs.sh

echo "=== Verifying Agent Directories ==="

# Define expected structure
# NOTE: All agents get tools/ for defense-in-depth (mounted :ro)
declare -A AGENT_DIRS=(
  ["bruba-main"]="workspace memory tools results artifacts canvas output logs media intake"
  ["bruba-guru"]="workspace memory tools results"
  ["bruba-manager"]="inbox state tools results memory"
  ["bruba-web"]="tools results"
)

# Shared directories
SHARED_DIRS="bruba-shared/packets bruba-shared/context"

# OpenClaw directories
OPENCLAW_DIRS=".openclaw/agents/bruba-main/sessions .openclaw/agents/bruba-guru/sessions .openclaw/agents/bruba-manager/sessions .openclaw/agents/bruba-web/sessions .openclaw/media/inbound .openclaw/media/outbound"

# Clawdbot auth directories
CLAWDBOT_DIRS=".clawdbot/agents/bruba-main .clawdbot/agents/bruba-guru .clawdbot/agents/bruba-manager .clawdbot/agents/bruba-web"

BASE="/Users/bruba"
MISSING=()

echo ""
echo "Checking agent workspaces..."
for agent in "${!AGENT_DIRS[@]}"; do
  echo "  $agent:"
  for dir in ${AGENT_DIRS[$agent]}; do
    path="$BASE/agents/$agent/$dir"
    if [[ -d "$path" ]]; then
      echo "    ✓ $dir"
    else
      echo "    ✗ $dir (MISSING)"
      MISSING+=("$path")
    fi
  done
done

echo ""
echo "Checking shared directories..."
for dir in $SHARED_DIRS; do
  path="$BASE/agents/$dir"
  if [[ -d "$path" ]]; then
    echo "  ✓ $dir"
  else
    echo "  ✗ $dir (MISSING)"
    MISSING+=("$path")
  fi
done

echo ""
echo "Checking OpenClaw directories..."
for dir in $OPENCLAW_DIRS; do
  path="$BASE/$dir"
  if [[ -d "$path" ]]; then
    echo "  ✓ $dir"
  else
    echo "  ✗ $dir (MISSING)"
    MISSING+=("$path")
  fi
done

echo ""
echo "Checking Clawdbot auth directories..."
for dir in $CLAWDBOT_DIRS; do
  path="$BASE/$dir"
  if [[ -d "$path" ]]; then
    echo "  ✓ $dir"
    # Also check for auth-profiles.json
    if [[ -f "$path/auth-profiles.json" ]]; then
      echo "    ✓ auth-profiles.json"
    else
      echo "    ✗ auth-profiles.json (MISSING)"
      MISSING+=("$path/auth-profiles.json")
    fi
  else
    echo "  ✗ $dir (MISSING)"
    MISSING+=("$path")
  fi
done

echo ""
echo "=== Summary ==="
if [[ ${#MISSING[@]} -eq 0 ]]; then
  echo "All directories present. Ready for Docker migration."
else
  echo "MISSING items (${#MISSING[@]}):"
  for item in "${MISSING[@]}"; do
    echo "  - $item"
  done
  echo ""
  echo "Run the creation commands below before proceeding."
fi
```

### 0.2: Create Missing Directories

If any directories are missing, create them:

```bash
# Agent workspaces (all agents get tools/ for defense-in-depth)
mkdir -p /Users/bruba/agents/bruba-main/{workspace,memory,tools,results,artifacts,canvas,output,logs,media,intake}
mkdir -p /Users/bruba/agents/bruba-guru/{workspace,memory,tools,results}
mkdir -p /Users/bruba/agents/bruba-manager/{inbox,state,tools,results,memory}
mkdir -p /Users/bruba/agents/bruba-web/{tools,results}

# Shared storage
mkdir -p /Users/bruba/agents/bruba-shared/{packets,context}

# OpenClaw session directories
mkdir -p /Users/bruba/.openclaw/agents/bruba-main/sessions
mkdir -p /Users/bruba/.openclaw/agents/bruba-guru/sessions
mkdir -p /Users/bruba/.openclaw/agents/bruba-manager/sessions
mkdir -p /Users/bruba/.openclaw/agents/bruba-web/sessions
mkdir -p /Users/bruba/.openclaw/media/{inbound,outbound}

# Clawdbot auth directories
mkdir -p /Users/bruba/.clawdbot/agents/{bruba-main,bruba-guru,bruba-manager,bruba-web}
```

### 0.3: Copy Auth Profiles

Each agent needs `auth-profiles.json`. Copy from bruba-main to others if missing:

```bash
# Source auth
SRC="/Users/bruba/.clawdbot/agents/bruba-main/auth-profiles.json"

# Copy to other agents (only if they don't already have it)
for agent in bruba-guru bruba-manager bruba-web; do
  DEST="/Users/bruba/.clawdbot/agents/$agent/auth-profiles.json"
  if [[ ! -f "$DEST" ]]; then
    cp "$SRC" "$DEST"
    echo "Copied auth to $agent"
  else
    echo "$agent already has auth-profiles.json"
  fi
done
```

### 0.4: Initialize State Files

Manager needs initialized state files:

```bash
# Initialize if not present
STATE_DIR="/Users/bruba/agents/bruba-manager/state"

[[ ! -f "$STATE_DIR/nag-history.json" ]] && \
  echo '{"reminders": {}, "lastUpdated": null}' > "$STATE_DIR/nag-history.json"

[[ ! -f "$STATE_DIR/staleness-history.json" ]] && \
  echo '{"projects": {}, "lastUpdated": null}' > "$STATE_DIR/staleness-history.json"

[[ ! -f "$STATE_DIR/pending-tasks.json" ]] && \
  echo '{"tasks": [], "lastUpdated": null}' > "$STATE_DIR/pending-tasks.json"
```

### 0.5: Verify Prompt Files Exist

Each agent needs its prompt files:

```bash
echo "=== Checking Prompt Files ==="

declare -A AGENT_PROMPTS=(
  ["bruba-main"]="AGENTS.md TOOLS.md IDENTITY.md"
  ["bruba-guru"]="AGENTS.md TOOLS.md IDENTITY.md"
  ["bruba-manager"]="AGENTS.md TOOLS.md HEARTBEAT.md IDENTITY.md"
  ["bruba-web"]="AGENTS.md"
)

for agent in "${!AGENT_PROMPTS[@]}"; do
  echo "$agent:"
  for file in ${AGENT_PROMPTS[$agent]}; do
    path="/Users/bruba/agents/$agent/$file"
    if [[ -f "$path" ]]; then
      echo "  ✓ $file"
    else
      echo "  ✗ $file (MISSING - run prompt sync)"
    fi
  done
done
```

If prompts are missing, run from bruba-godo:
```bash
./tools/assemble-prompts.sh
./tools/push.sh
```

### 0.6: Gate Check

**DO NOT PROCEED** to Phase 1 until:
- [ ] All agent directories exist
- [ ] All shared directories exist
- [ ] All OpenClaw session directories exist
- [ ] All agents have auth-profiles.json
- [ ] Manager state files initialized
- [ ] All prompt files present

---

## Phase 1: Discovery

Run these commands and document findings. We need to understand:
1. How node host works
2. Current exec-approvals structure  
3. OpenClaw sandbox config options (if any)
4. What the LaunchAgent plist contains

### Commands to run:

```bash
# Node host status
openclaw node status

# Full config (look for sandbox/docker keys)
openclaw config show

# Check for sandbox in config
grep -i sandbox ~/.openclaw/openclaw.json

# LaunchAgent details
cat ~/Library/LaunchAgents/ai.openclaw.node.plist

# Current exec-approvals structure
cat ~/.openclaw/exec-approvals.json

# Check if there's built-in Docker/sandbox support
openclaw --help 2>&1 | grep -iE "sandbox|docker|container"
```

### Document findings in a summary block before proceeding.

---

## Phase 2: Determine Container Strategy

Based on Phase 1 findings, determine:

**Question 1: Does OpenClaw have native Docker/sandbox support?**
- If yes: Use native config in openclaw.json
- If no: We create docker-compose.yml manually

**Question 2: How does gateway connect to node host?**
- Look for `OPENCLAW_NODE_HOST` env var or config key
- May need `host.docker.internal:PORT` configuration

**Question 3: How does gateway connect to Signal?**
- Signal runs on `127.0.0.1:8088`
- Container needs to reach `host.docker.internal:8088`
- Check if signal config in openclaw.json needs updating for container

**Question 4: Where does gateway read auth/API keys from?**
- Currently in `~/.openclaw/openclaw.json` under `"auth": {`
- Need to either: mount that file, or pass as env vars

### If native support exists:
Document the config schema and proceed to Phase 3A.

### If manual Docker needed:
Proceed to Phase 3B.

---

## Phase 3A: Native OpenClaw Sandbox Config

If OpenClaw has built-in sandbox support, update `~/.openclaw/openclaw.json`:

```json
{
  "sandbox": {
    "mode": "docker",
    "execHost": "node"
  },
  "agents": {
    "defaults": {
      "sandbox": {
        "enabled": true
      }
    }
  }
}
```

(Adjust based on actual schema discovered in Phase 1)

Test:
```bash
openclaw gateway restart
openclaw node status
# Send test message, verify exec still works
```

---

## Phase 3B: Manual Docker Compose

If no native support, create docker-compose setup.

### 3B.1: Create directory structure

```bash
mkdir -p ~/docker/bruba
cd ~/docker/bruba
```

### 3B.2: Create docker-compose.yml

```yaml
version: '3.8'

services:
  gateway:
    image: node:20-slim
    working_dir: /app
    command: ["npx", "openclaw", "gateway", "run"]
    
    volumes:
      # OpenClaw config (read-only for security)
      - ~/.openclaw/openclaw.json:/root/.openclaw/openclaw.json:ro
      
      # === bruba-main ===
      - ~/agents/bruba-main/workspace:/workspaces/main/workspace:rw
      - ~/agents/bruba-main/memory:/workspaces/main/memory:rw
      - ~/agents/bruba-main/tools:/workspaces/main/tools:ro
      - ~/agents/bruba-main/results:/workspaces/main/results:rw
      - ~/agents/bruba-main/artifacts:/workspaces/main/artifacts:rw
      - ~/agents/bruba-main/output:/workspaces/main/output:rw
      
      # === bruba-guru ===
      - ~/agents/bruba-guru/workspace:/workspaces/guru/workspace:rw
      - ~/agents/bruba-guru/memory:/workspaces/guru/memory:rw
      - ~/agents/bruba-guru/tools:/workspaces/guru/tools:ro
      - ~/agents/bruba-guru/results:/workspaces/guru/results:rw

      # === bruba-manager ===
      - ~/agents/bruba-manager/inbox:/workspaces/manager/inbox:rw
      - ~/agents/bruba-manager/state:/workspaces/manager/state:rw
      - ~/agents/bruba-manager/tools:/workspaces/manager/tools:ro
      - ~/agents/bruba-manager/results:/workspaces/manager/results:rw
      - ~/agents/bruba-manager/memory:/workspaces/manager/memory:rw

      # === bruba-web ===
      - ~/agents/bruba-web/tools:/workspaces/web/tools:ro
      - ~/agents/bruba-web/results:/workspaces/web/results:rw
      
      # === bruba-shared ===
      - ~/agents/bruba-shared/packets:/workspaces/shared/packets:rw
      - ~/agents/bruba-shared/context:/workspaces/shared/context:rw
      
      # Media (voice I/O)
      - ~/.openclaw/media:/media:rw
      
      # Sessions (need to persist)
      - ~/.openclaw/agents:/root/.openclaw/agents:rw
      
      # Auth profiles
      - ~/.clawdbot/agents:/root/.clawdbot/agents:ro
      
    environment:
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
      - OPENCLAW_NODE_HOST=host.docker.internal:18789
      - SIGNAL_CLI_URL=http://host.docker.internal:8088
      
    extra_hosts:
      - "host.docker.internal:host-gateway"
      
    ports:
      - "18789:18789"
      
    restart: unless-stopped
```

**NOTE:** This is a starting template. Actual image and command depend on how OpenClaw gateway is packaged. May need to:
- Build from source
- Use official OpenClaw image if one exists
- Mount the entire `~/.openclaw` directory

### 3B.3: Create .env file

```bash
cat > ~/docker/bruba/.env << 'EOF'
ANTHROPIC_API_KEY=sk-ant-...
EOF
chmod 600 ~/docker/bruba/.env
```

### 3B.4: Test container startup

```bash
cd ~/docker/bruba
docker-compose up -d
docker-compose logs -f
```

---

## Phase 4: Bind Mount Specification

### Sandbox Configuration (Native OpenClaw)

OpenClaw's native sandbox mode handles most mount configuration automatically via `workspaceAccess: "rw"`. The key per-agent settings are:

**Per-agent sandbox config:**
```json
{
  "id": "bruba-main",
  "workspace": "/Users/bruba/agents/bruba-main",
  "sandbox": {
    "workspaceRoot": "/Users/bruba/agents/bruba-main"
  }
}
```

**Key points:**
1. `sandbox.workspaceRoot` = agent's `workspace` path (tells OpenClaw file tools where `/workspace/` is)
2. Tools are at `/Users/bruba/tools/` (outside workspaces) — no Docker bind needed for protection
3. Shared mounts configured in `agents.defaults.sandbox.docker.binds`

### Effective Mount Table (Via OpenClaw Sandbox)

| Host Path | Container Path | Access | How Configured |
|-----------|----------------|--------|----------------|
| **Per-Agent (automatic via workspaceAccess: rw)** |
| `~/agents/{agent}/` | `/workspace/` | rw | OpenClaw auto-mounts workspace |
| `~/agents/{agent}/memory/` | `/workspace/memory/` | rw | Part of workspace |
| **Shared (via defaults.sandbox.docker.binds)** |
| `~/agents/bruba-shared/packets/` | `/workspaces/shared/packets` | rw | Default bind |
| `~/agents/bruba-shared/context/` | `/workspaces/shared/context` | rw | Default bind |
| `~/agents/bruba-shared/repo/` | `/workspaces/shared/repo` | **ro** | Default bind |
| **Tools (outside workspaces)** |
| `/Users/bruba/tools/` | N/A | exec only | Tools protected by being outside workspaceRoot |

### NOT Mounted (Security Boundary)

| Host Path | Reason |
|-----------|--------|
| `~/.openclaw/exec-approvals.json` | **CRITICAL** — Prevents self-escalation |
| `~/src/` | Source code not needed |
| `~/bruba-godo/` | Operator tools not needed at runtime |

**BLOCKER CHECK:** If OpenClaw gateway needs exec-approvals.json to function, we have a problem. The node host should read it (on host), gateway should just send exec requests to node host.

---

## Phase 5: Path Updates in Prompts

After container paths are determined, update bruba-godo prompts.

### 5.1: Find all hardcoded paths

```bash
cd ~/bruba-godo
grep -rn "/Users/bruba" templates/ components/ --include="*.md"
```

### 5.2: Path Mapping Reference

| Current (Host) | Container | Notes |
|----------------|-----------|-------|
| `/Users/bruba/agents/bruba-main/workspace/` | `/workspaces/main/workspace/` | |
| `/Users/bruba/agents/bruba-main/memory/` | `/workspaces/main/memory/` | |
| `/Users/bruba/agents/bruba-main/tools/` | `/workspaces/main/tools/` | Read-only |
| `/Users/bruba/agents/bruba-guru/workspace/` | `/workspaces/guru/workspace/` | |
| `/Users/bruba/agents/bruba-guru/memory/` | `/workspaces/guru/memory/` | |
| `/Users/bruba/agents/bruba-guru/results/` | `/workspaces/guru/results/` | |
| `/Users/bruba/agents/bruba-shared/` | `/workspaces/shared/` | |
| `/Users/bruba/.openclaw/media/` | `/media/` | Voice I/O |

### 5.3: Update files

Use sed or manual edits. Example:

```bash
# Preview changes
grep -rn "/Users/bruba/agents/bruba-main/tools" templates/ components/

# Apply changes (carefully!)
# sed -i '' 's|/Users/bruba/agents/bruba-main/tools|/workspaces/main/tools|g' file.md
```

After updates:
```bash
./tools/assemble-prompts.sh
./tools/push.sh
```

---

## Phase 6: Testing

### Security Tests (from inside container)

These should all **FAIL**:

```bash
# Cannot access exec-approvals
docker exec -it bruba-gateway sh -c "cat ~/.openclaw/exec-approvals.json"
# Expected: No such file or directory

# Cannot access host filesystem outside mounts
docker exec -it bruba-gateway sh -c "ls /Users/bruba/"
# Expected: No such file or directory

# Cannot write to tools (read-only mount)
docker exec -it bruba-gateway sh -c "echo test > /workspaces/main/tools/evil.sh"
# Expected: Read-only file system
```

### Functional Tests

| Test | Command/Action | Expected |
|------|----------------|----------|
| Gateway starts | `docker-compose logs` | No errors |
| Signal connection | Send message via Signal | Received by agent |
| Main exec works | Voice message | Transcription completes |
| Main memory read | Agent reads file | Success |
| Main memory write | Agent writes file | Success |
| Main tools read | Agent reads script | Success |
| Main tools write | Agent writes script | **FAILS** (ro) |
| Guru routing | Technical question | Routes to Guru, response in Signal |
| Guru direct message | Guru completes analysis | Response appears in Signal directly |
| Guru web delegation | Guru asks bruba-web | Research completes |
| Guru TTS | Voice response from Guru | Audio file delivered |
| Manager heartbeat | Wait for heartbeat | Executes without error |
| Manager inbox | Cron writes to inbox | File appears |
| Web search | Manager requests search | Results written |
| Shared storage | Main writes packet | Guru can read it |
| Siri async | "Tell Bruba..." | Response in Signal |
| Voice reply | Voice message | Audio response delivered |

### Agent-to-Agent Communication

| Test | Expected |
|------|----------|
| Main → Guru | sessions_send works |
| Main → Web | sessions_send works |
| Guru → Web | sessions_send works |
| Manager → Main | sessions_send works |
| Manager → Web | sessions_send works |

---

## Phase 7: Cutover

### 7.1: Pre-cutover checklist

- [ ] Phase 0 complete (all directories verified)
- [ ] Phase 6 tests passing
- [ ] Backup current config: `cp ~/.openclaw/openclaw.json ~/.openclaw/openclaw.json.bak`
- [ ] Note current gateway status: `openclaw gateway status`

### 7.2: Stop current gateway

```bash
openclaw gateway stop
```

### 7.3: Start containerized gateway

```bash
cd ~/docker/bruba
docker-compose up -d
```

### 7.4: Verify

```bash
docker-compose logs -f &

# Send test message via Signal
# Verify response

# Test voice
# Test Siri

# Test Guru routing
# Technical question → should route → response in Signal
```

### 7.5: Update startup

Ensure container starts on boot:
```bash
# docker-compose already has restart: unless-stopped
# But may want launchd for cleaner boot integration
```

---

## Rollback

If things break:

```bash
# Stop container
cd ~/docker/bruba
docker-compose down

# Restore config if needed
cp ~/.openclaw/openclaw.json.bak ~/.openclaw/openclaw.json

# Start gateway directly
openclaw gateway start

# Verify
openclaw gateway status
```

---

## Potential Blockers to Flag

During implementation, flag if you discover:

1. **Gateway requires exec-approvals.json directly** — Would need architectural change
2. **Signal integration doesn't support remote host** — Would need socket mount or other approach  
3. **Sessions don't persist properly** — Would lose conversation history
4. **Node host doesn't work with containerized gateway** — Core assumption broken
5. **OpenClaw image doesn't exist / can't be containerized** — Would need to build custom image
6. **Agent-to-agent communication fails across container boundary** — Would need network config
7. **Message tool can't reach Signal from container** — Would need host.docker.internal config

If any blocker is hit, STOP and document before proceeding.

---

## Success Criteria

Migration complete when:

- [ ] All directories verified (Phase 0)
- [ ] Gateway runs in Docker container
- [ ] All **four** agents functional
- [ ] Exec commands work via node host
- [ ] Voice transcription works (whisper-clean.sh)
- [ ] Voice response works (tts.sh + message tool)
- [ ] Signal messages work
- [ ] Guru direct-message pattern works
- [ ] Guru ↔ Web delegation works
- [ ] Main ↔ Guru routing works
- [ ] Siri async routing works
- [ ] Agent cannot access exec-approvals.json
- [ ] Agent cannot write to tools/ directory
- [ ] Sessions persist across container restarts
- [ ] Container auto-starts on machine boot

---

## References

- `Doc - bruba-filesystem-guide.md` — Full path reference (v1.3.0+)
- `Doc - bruba-multi-agent-architecture.md` — Agent topology (v3.3.3+)
- `complete-prompt-snippets.md` — Voice/message tool patterns
- OpenClaw docs: https://docs.openclaw.ai/cli/node

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.2.0 | 2026-02-03 | **Defense-in-depth:** ALL agents get tools/ directory and :ro mount (not just bruba-main). Updated Phase 0, docker-compose, bind mount tables |
| 1.1.0 | 2026-02-03 | Added Phase 0 (filesystem verification), four-agent support (added bruba-guru), bruba-shared mounts, Guru-specific tests, message tool tests, updated success criteria |
| 1.0.0 | 2026-02-02 | Initial version |