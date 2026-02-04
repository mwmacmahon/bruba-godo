# bruba-web Docker Sandbox Migration

Re-enable OpenClaw's native Docker sandbox for bruba-web with network access.

## Background

**Disabled:** 2026-02-03
**Reason:** `sessions_send` cannot see other agents' sessions when `sandbox.scope: "agent"`. Error: "Session not visible from this sandboxed agent session: agent:bruba-guru:main"

**Current state:** `sandbox.mode: "off"` — all agents run directly on host

**Goal:** All agents containerized; bruba-web gets `network: bridge` for web access, others get `network: none`

## Pre-requisites

1. OpenClaw version with sandbox bugfix (cross-agent session visibility)
2. Docker running on bot host

### Verify the Fix

Before migrating, test that `sessions_send` works across agents in sandbox mode:

```bash
# Send from bruba-main to bruba-guru (should not error)
openclaw agent --agent bruba-main -m "route to guru: ping"

# Expected: Message routes successfully
# Broken: "Session not visible from this sandboxed agent session: agent:bruba-guru:main"
```

## Configuration Changes

### 1. Global Sandbox Defaults

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

### 2. bruba-web Network Access

In the bruba-web agent config, add network override:

```json
{
  "id": "bruba-web",
  "sandbox": {
    "docker": {
      "network": "bridge"
    }
  }
}
```

### 3. Full Example

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

## Migration Steps

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

## Verification

### Quick Check

```bash
# From operator machine
./tools/test-sandbox.sh --all
```

### Manual Tests

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

## Container Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          Mac Host (dadmini)                              │
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

## Container Path Mapping

| Host Path | Container Path | Notes |
|-----------|----------------|-------|
| `/Users/bruba/agents/{agent}/` | `/workspace/` | Agent's workspace |
| `/Users/bruba/agents/{agent}/tools/` | `/workspace/tools/` | Read-only |
| `/Users/bruba/agents/bruba-shared/packets/` | `/workspaces/shared/packets/` | All containers |
| `/Users/bruba/agents/bruba-shared/context/` | `/workspaces/shared/context/` | All containers |
| `/Users/bruba/agents/bruba-shared/repo/` | `/workspaces/shared/repo/` | All containers (ro) |

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
```

### Cross-agent routing fails

This is the bug that caused sandbox to be disabled. If you see:
```
Session not visible from this sandboxed agent session: agent:bruba-guru:main
```

**Rollback immediately** and wait for OpenClaw fix.

### Network issues on bruba-web

```bash
# Verify network mode
docker inspect openclaw-sandbox-bruba-web | jq '.[0].NetworkSettings.Networks'

# Should show "bridge" network, not "none"
```

### tools/ is writable (security failure)

```bash
# Check bind mount
docker inspect openclaw-sandbox-bruba-main | jq '.[0].Mounts[] | select(.Destination=="/workspace/tools")'

# Should show "ro" (read-only) in Mode
```

## References

- `docs/architecture-masterdoc.md` — Full Docker architecture documentation
- `tools/test-sandbox.sh` — Automated verification script
