# bruba-web Docker Sandbox Migration

Re-enable OpenClaw's native Docker sandbox for bruba-web with network access.

## Status

**✅ COMPLETED (Partial):** 2026-02-04

Implemented **bruba-web only** sandboxing instead of full agent sandboxing:
- bruba-web: Docker sandbox with `network: bridge`
- Other agents: Running directly on host (`sandbox.mode: "off"` globally)

This provides prompt injection isolation for web content while avoiding complexity of full sandboxing.

## Background

**Disabled:** 2026-02-03
**Reason:** `sessions_send` cannot see other agents' sessions when `sandbox.scope: "agent"`. Error: "Session not visible from this sandboxed agent session: agent:bruba-guru:main"

**Fix confirmed:** OpenClaw 2026.2.1 — cross-agent `sessions_send` works with per-agent sandbox

## What Was Done (2026-02-04)

### 1. Per-Agent Sandbox for bruba-web Only

Instead of global sandbox defaults, we enabled sandbox only for bruba-web:

```json
{
  "id": "bruba-web",
  "sandbox": {
    "mode": "all",
    "scope": "agent",
    "workspaceRoot": "/Users/bruba/agents/bruba-web",
    "docker": {
      "network": "bridge"
    }
  }
}
```

Global `agents.defaults.sandbox.mode` remains `"off"`.

### 2. Container Auto-Warm

Created `~/bin/bruba-start` script and LaunchAgent to warm the container on login:
- Script: `/Users/bruba/bin/bruba-start`
- LaunchAgent: `~/Library/LaunchAgents/ai.openclaw.sandbox-warm.plist`

### 3. Verification Performed

```bash
# bruba-web responds in container
openclaw agent --agent bruba-web -m "ping"
# Result: PONG

# Web search works from container
openclaw agent --agent bruba-web -m "Search for OpenClaw AI"
# Result: Returns search results with sources

# Cross-agent routing works (Main → Web)
openclaw agent --agent bruba-main -m "Use sessions_send to ask bruba-web to search for weather"
# Result: Main successfully routed to bruba-web and got results
```

## Future: Full Agent Sandboxing (Optional)

If desired, the original plan below can still be implemented to sandbox all agents.

---

## Original Plan: Full Sandbox (Not Implemented)

**Goal:** All agents containerized; bruba-web gets `network: bridge` for web access, others get `network: none`

### Global Sandbox Defaults

In `~/.openclaw/openclaw.json`, add sandbox defaults:

```json
{
  "agents": {
    "defaults": {
      "sandbox": {
        "mode": "all",
        "scope": "agent"
      }
    }
  }
}
```

### Full Example (All Agents Sandboxed)

```json
{
  "agents": {
    "defaults": {
      "sandbox": {
        "mode": "all",
        "scope": "agent"
      }
    },
    "list": [
      {
        "id": "bruba-main",
        "sandbox": {
          "docker": {
            "network": "none",
            "binds": [
              "/Users/bruba/agents/bruba-main/tools:/workspace/tools:ro"
            ]
          }
        }
      },
      {
        "id": "bruba-guru",
        "sandbox": {
          "docker": {
            "network": "none",
            "binds": [
              "/Users/bruba/agents/bruba-guru/tools:/workspace/tools:ro"
            ]
          }
        }
      },
      {
        "id": "bruba-manager",
        "sandbox": {
          "docker": {
            "network": "none",
            "binds": [
              "/Users/bruba/agents/bruba-manager/tools:/workspace/tools:ro"
            ]
          }
        }
      },
      {
        "id": "bruba-web",
        "sandbox": {
          "docker": {
            "network": "bridge",
            "binds": [
              "/Users/bruba/agents/bruba-web/tools:/workspace/tools:ro"
            ]
          }
        }
      }
    ]
  }
}
```

### Full Migration Steps (If Implementing)

1. **Stop the daemon**
   ```bash
   openclaw stop
   ```

2. **Backup current config**
   ```bash
   cp ~/.openclaw/openclaw.json ~/.openclaw/openclaw.json.bak
   ```

3. **Edit configuration**
   ```bash
   # Add sandbox defaults and per-agent docker config
   # See "Full Example" above
   ```

4. **Start the daemon**
   ```bash
   openclaw start
   ```

5. **Verify containers are running**
   ```bash
   docker ps --filter "name=openclaw-sandbox"
   ```

   Expected output:
   ```
   NAMES                        STATUS
   openclaw-sandbox-bruba-main  Up ...
   openclaw-sandbox-bruba-guru  Up ...
   openclaw-sandbox-bruba-manager Up ...
   openclaw-sandbox-bruba-web   Up ...
   ```

### Verification (Full Sandbox)

1. **Ping test** — verify agent responds in container
   ```bash
   openclaw agent --agent bruba-web -m "ping"
   ```

2. **Cross-agent routing** — verify sessions_send works
   ```bash
   openclaw agent --agent bruba-main -m "route to web: search for weather in San Francisco"
   ```

3. **Network isolation** — verify bruba-main has no network
   ```bash
   docker exec openclaw-sandbox-bruba-main ping -c 1 google.com
   # Expected: Network unreachable or timeout
   ```

4. **bruba-web network** — verify bridge network works
   ```bash
   docker exec openclaw-sandbox-bruba-web ping -c 1 google.com
   # Expected: Success
   ```

5. **Security tests** — verify containers cannot access sensitive files
   ```bash
   # Should fail (file not mounted)
   docker exec openclaw-sandbox-bruba-main cat /root/.openclaw/exec-approvals.json

   # Should fail (tools is read-only)
   docker exec openclaw-sandbox-bruba-main touch /workspace/tools/test.txt
   ```

---

## Reference: Architecture Diagrams

### Current State (bruba-web Only)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          Mac Host (bruba)                                │
│                                                                          │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐                     │
│  │ bruba-main   │ │ bruba-guru   │ │bruba-manager │  ← Direct on host   │
│  │  (direct)    │ │  (direct)    │ │  (direct)    │                     │
│  └──────────────┘ └──────────────┘ └──────────────┘                     │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │                   Docker Container                                 │  │
│  │  ┌──────────────┐                                                  │  │
│  │  │  bruba-web   │  ← Only agent in container                       │  │
│  │  │network:bridge│                                                  │  │
│  │  └──────────────┘                                                  │  │
│  └────────────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────────────┘
```

### Full Sandbox (Future Option)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          Mac Host (bruba)                                │
│                                                                          │
│  PROTECTED (not mounted into containers):                                │
│  ├── ~/.openclaw/exec-approvals.json   ← Exec allowlist                  │
│  ├── ~/.openclaw/openclaw.json         ← Agent configs                   │
│  └── ~/agents/bruba-main/tools/        ← Scripts (ro overlay only)       │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │                    Node Host Process (port 18789)                  │  │
│  │  • Reads exec-approvals.json from HOST filesystem                  │  │
│  │  • Validates commands against allowlist                            │  │
│  │  • Executes approved commands ON THE HOST                          │  │
│  │  • Returns results to gateway                                      │  │
│  └────────────────────────────▲───────────────────────────────────────┘  │
│                               │ exec requests                            │
│  ┌────────────────────────────┼───────────────────────────────────────┐  │
│  │                   Docker Containers                                │  │
│  │  ┌─────────────────────────┴─────────────────────────────────────┐ │  │
│  │  │                   OpenClaw Gateway                             │ │  │
│  │  │                                                                │ │  │
│  │  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐           │ │  │
│  │  │  │ bruba-main   │ │ bruba-guru   │ │bruba-manager │           │ │  │
│  │  │  │ network:none │ │ network:none │ │ network:none │           │ │  │
│  │  │  └──────────────┘ └──────────────┘ └──────────────┘           │ │  │
│  │  │                                                                │ │  │
│  │  │  ┌──────────────┐                                              │ │  │
│  │  │  │  bruba-web   │  ← Only agent with network access            │ │  │
│  │  │  │network:bridge│                                              │ │  │
│  │  │  └──────────────┘                                              │ │  │
│  │  └────────────────────────────────────────────────────────────────┘ │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────────────┘
```

## Container Path Mapping (Full Sandbox)

| Host Path | Container Path | Notes |
|-----------|----------------|-------|
| `/Users/bruba/agents/{agent}/` | `/workspace/` | Agent's workspace |
| `/Users/bruba/agents/{agent}/tools/` | `/workspace/tools/` | Read-only |
| `/Users/bruba/agents/bruba-shared/packets/` | `/workspaces/shared/packets/` | All containers |
| `/Users/bruba/agents/bruba-shared/context/` | `/workspaces/shared/context/` | All containers |
| `/Users/bruba/agents/bruba-shared/repo/` | `/workspaces/shared/repo/` | All containers (ro) |

---

## Rollback

If issues occur, disable sandbox immediately:

1. **Edit config**
   ```json
   {
     "agents": {
       "defaults": {
         "sandbox": {
           "mode": "off"
         }
       }
     }
   }
   ```

2. **Restart daemon**
   ```bash
   openclaw stop && openclaw start
   ```

3. **Or restore backup**
   ```bash
   cp ~/.openclaw/openclaw.json.bak ~/.openclaw/openclaw.json
   openclaw stop && openclaw start
   ```

## Troubleshooting

### Container won't start

```bash
# Check Docker status
docker info

# Check for port conflicts
docker ps -a --filter "name=openclaw"

# View container logs
docker logs openclaw-sandbox-bruba-web

# Check sandbox config
openclaw sandbox explain --agent bruba-web
```

### Container not running after reboot

The container starts on-demand. Either:
1. Run `~/bin/bruba-start` manually
2. Send any message to bruba-web: `openclaw agent --agent bruba-web -m "ping"`

### Cross-agent routing fails

**Fixed in OpenClaw 2026.2.1.** If you still see:
```
Session not visible from this sandboxed agent session: agent:bruba-guru:main
```

Check OpenClaw version: `openclaw --version`

### Network issues on bruba-web

```bash
# Verify network mode
docker inspect openclaw-sbx-agent-bruba-web-* | jq '.[0].NetworkSettings.Networks'

# Should show "bridge" network, not "none"

# Test from inside container
docker exec openclaw-sbx-agent-bruba-web-* ping -c 1 google.com
```

### Rollback bruba-web to direct mode

If sandbox causes issues, disable it:

```bash
# Edit openclaw.json - remove sandbox.mode from bruba-web
# Or set sandbox.mode: "off" for bruba-web

# Restart gateway
openclaw gateway restart
```

## References

- `docs/architecture-masterdoc.md` — Full Docker architecture documentation
- `components/web-search/README.md` — Web search component using bruba-web
