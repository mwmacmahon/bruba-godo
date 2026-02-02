---
version: 1.0.0
updated: 2026-02-02 14:15
type: cc-packet
project: bruba-godo
tags: [node-host, docker, security, migration]
---

# CC Packet: Node Host Migration

**Objective:** Dockerize Bruba agents while keeping exec on the host via OpenClaw's node host. This closes the exec-approvals.json self-escalation security gap.

**Decision already made:** We ARE doing this. Don't second-guess the decision. Flag blockers that would break functionality, not cost-benefit concerns.

---

## Context

**Current state:**
- OpenClaw node host LaunchAgent installed: `~/Library/LaunchAgents/ai.openclaw.node.plist`
- Signal-cli running as HTTP daemon on `127.0.0.1:8088`
- Auth stored in `~/.openclaw/openclaw.json` (not per-agent files)
- Docker Desktop installed (managed from bruba account, installed via admin)
- Three agents: bruba-main, bruba-manager, bruba-web

**Security gap being closed:**
- Currently, agents can theoretically edit `~/.openclaw/exec-approvals.json` to self-escalate
- After migration: agents run in Docker, can't reach host filesystem, exec goes through node host

**Target architecture:**
```
Host: Node host process (reads exec-approvals.json, executes commands)
      Signal-cli daemon (127.0.0.1:8088)
      Tailscale (admin-managed)
      
Container: OpenClaw gateway + all three agents
           Bind mounts for workspace/memory/tools(ro)/media
           Reaches node host via host.docker.internal
           Reaches signal-cli via host.docker.internal:8088
```

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
      
      # Agent workspaces
      - ~/agents/bruba-main/workspace:/workspaces/main/workspace:rw
      - ~/agents/bruba-main/memory:/workspaces/main/memory:rw
      - ~/agents/bruba-main/tools:/workspaces/main/tools:ro
      
      - ~/agents/bruba-manager/inbox:/workspaces/manager/inbox:rw
      - ~/agents/bruba-manager/state:/workspaces/manager/state:rw
      
      - ~/agents/bruba-web/results:/workspaces/web/results:rw
      
      # Media (voice I/O)
      - ~/.openclaw/media:/media:rw
      
      # Sessions (need to persist)
      - ~/.openclaw/agents:/root/.openclaw/agents:rw
      
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

### Required mounts (container paths TBD based on OpenClaw expectations):

| Host Path | Container Path | Access | Purpose |
|-----------|---------------|--------|---------|
| `~/.openclaw/openclaw.json` | `/root/.openclaw/openclaw.json` | ro | Config |
| `~/.openclaw/agents/` | `/root/.openclaw/agents/` | rw | Sessions |
| `~/.openclaw/media/` | `/media/` or native path | rw | Voice I/O |
| `~/agents/bruba-main/workspace/` | TBD | rw | Working files |
| `~/agents/bruba-main/memory/` | TBD | rw | PKM content |
| `~/agents/bruba-main/tools/` | TBD | **ro** | Scripts |
| `~/agents/bruba-manager/inbox/` | TBD | rw | Cron outputs |
| `~/agents/bruba-manager/state/` | TBD | rw | State files |
| `~/agents/bruba-web/results/` | TBD | rw | Research outputs |

### NOT mounted (security boundary):

| Host Path | Reason |
|-----------|--------|
| `~/.openclaw/exec-approvals.json` | Prevents self-escalation |
| `~/src/` | Source code not needed |

**BLOCKER CHECK:** If OpenClaw gateway needs exec-approvals.json to function, we have a problem. Check:
```bash
grep -r "exec-approvals" ~/src/clawdbot/
```

If gateway reads it: The node host reads it (good), gateway should just send exec requests to node host.

---

## Phase 5: Path Updates in Prompts

After container paths are determined, update bruba-godo.

### 5.1: Find all hardcoded paths

```bash
cd ~/bruba-godo
grep -r "/Users/bruba" templates/ components/ --include="*.md"
```

### 5.2: Create path mapping

Document the before/after mapping based on actual mount points.

### 5.3: Update files

Use sed or manual edits. Then:

```bash
./tools/assemble-prompts.sh
./tools/push.sh
```

---

## Phase 6: Testing

### Security tests (from inside container):

```bash
# These should all FAIL:
docker exec -it bruba-gateway sh -c "cat /Users/bruba/.openclaw/exec-approvals.json"
docker exec -it bruba-gateway sh -c "ls /Users/bruba/"
docker exec -it bruba-gateway sh -c "echo test > /workspaces/main/tools/evil.sh"
```

### Functional tests:

| Test | How | Expected |
|------|-----|----------|
| Gateway starts | `docker-compose logs` | No errors |
| Signal connection | Send message | Received |
| Exec works | Voice message | Transcription completes |
| Memory read | Agent reads file | Success |
| Memory write | Agent writes file | Success |
| Tools read | Agent reads script | Success |
| Tools write | Agent writes script | FAILS (ro) |

---

## Phase 7: Cutover

### 7.1: Stop current gateway

```bash
openclaw gateway stop
```

### 7.2: Start containerized gateway

```bash
cd ~/docker/bruba
docker-compose up -d
```

### 7.3: Verify

```bash
docker-compose logs -f &
# Send test message via Signal
# Verify response
```

### 7.4: Update startup

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

If any blocker is hit, STOP and document before proceeding.

---

## Success Criteria

Migration complete when:

- [ ] Gateway runs in Docker container
- [ ] All three agents functional
- [ ] Exec commands work via node host
- [ ] Voice transcription works
- [ ] Signal messages work
- [ ] Agent cannot access exec-approvals.json
- [ ] Agent cannot write to tools/ directory
- [ ] Sessions persist across container restarts
- [ ] Container auto-starts on machine boot

---

## References

- `Doc - bruba-filesystem-guide.md` — Full path reference
- `Refdoc - bruba-multi-agent-architecture.md` — Agent topology
- OpenClaw docs: https://docs.openclaw.ai/cli/node