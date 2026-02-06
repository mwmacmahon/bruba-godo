---
type: doc
scope: reference
title: "Configuration Reference"
description: "config.yaml and openclaw.json settings reference"
---

# Configuration Reference

Source-of-truth configuration (config.yaml) and target state (openclaw.json) for the Bruba multi-agent system.

> **Related docs:**
> - [Operations Guide](operations-guide.md) — Syncing config, editing, diagnostics
> - [Security Model](security-model.md) — Config file protection, exec allowlist

---

## config.yaml (Operator Source of Truth)

As of v3.8.3, `config.yaml` is the source of truth for OpenClaw settings. The operator controls configuration locally, then syncs to the bot via `sync-openclaw-config.sh`.

**Key sections:**

```yaml
# Global defaults (synced to agents.defaults in openclaw.json)
openclaw:
  model:
    primary: opus
    fallbacks: [anthropic/claude-sonnet-4-5, anthropic/claude-haiku-4-5]
  compaction:
    mode: safeguard
    reserve_tokens_floor: 20000
    memory_flush:
      enabled: true
      soft_threshold_tokens: 40000
      prompt: |-
        Write to memory/CONTINUATION.md immediately...
  context_pruning:
    mode: cache-ttl
    ttl: 1h
  sandbox:
    mode: "off"
  max_concurrent: 4

# Per-agent settings (synced to agents.list[] in openclaw.json)
agents:
  bruba-main:
    model: sonnet                    # String alias or object
    heartbeat: false                 # false = disabled (every: "0m")
    tools_allow: [...]
    tools_deny: [...]

  bruba-manager:
    model:
      primary: anthropic/claude-sonnet-4-5
      fallbacks: [anthropic/claude-haiku-4-5]
    heartbeat:
      every: 15m
      model: anthropic/claude-haiku-4-5
      target: signal
      active_hours:
        start: "07:00"
        end: "22:00"

  bruba-web:
    model: anthropic/claude-sonnet-4-5
    heartbeat: false
    memory_search: false             # Stateless (memorySearch.enabled)
```

### Syncing

```bash
./tools/sync-openclaw-config.sh --check      # Show discrepancies
./tools/sync-openclaw-config.sh              # Apply changes
./tools/sync-openclaw-config.sh --dry-run    # Preview without applying
```

### What's NOT Managed by config.yaml

- `auth.profiles` - API keys/tokens
- `channels` - Signal/Telegram secrets
- `gateway` - Port/auth config
- `env.vars` - API keys
- `plugins`, `skills`, `messages` - Runtime config

---

## openclaw.json (Target State)

```json
{
  "agents": {
    "defaults": {
      "compaction": { "mode": "safeguard" },
      "maxConcurrent": 4
    },
    "list": [
      {
        "id": "bruba-main",
        "name": "Bruba",
        "default": true,
        "workspace": "/Users/bruba/agents/bruba-main",
        "model": {
          "primary": "anthropic/claude-opus-4-5",
          "fallbacks": ["anthropic/claude-sonnet-4-5"]
        },
        "heartbeat": { "every": "0m" },
        "tools": {
          "deny": ["web_search", "web_fetch", "browser", "canvas",
                   "cron", "gateway", "sessions_spawn"]
        }
      },
      {
        "id": "bruba-manager",
        "name": "Manager",
        "workspace": "/Users/bruba/agents/bruba-manager",
        "model": {
          "primary": "anthropic/claude-sonnet-4-5",
          "fallbacks": ["anthropic/claude-haiku-4-5"]
        },
        "heartbeat": {
          "every": "15m",
          "model": "anthropic/claude-haiku-4-5",
          "target": "signal",
          "activeHours": { "start": "07:00", "end": "22:00" }
        },
        "tools": {
          "deny": ["web_search", "web_fetch", "browser", "canvas",
                   "cron", "gateway", "edit", "apply_patch"]
        }
      },
      {
        "id": "bruba-web",
        "name": "Web",
        "workspace": "/Users/bruba/agents/bruba-web",
        "model": "anthropic/claude-sonnet-4-5",
        "memorySearch": { "enabled": false },
        "heartbeat": { "every": "0m" },
        "sandbox": {
          "mode": "all",
          "scope": "agent",
          "workspaceAccess": "none",
          "docker": {
            "network": "bridge",
            "readOnlyRoot": true,
            "memory": "512m"
          }
        },
        "tools": {
          "allow": ["web_search", "web_fetch", "read", "write"],
          "deny": ["exec", "edit", "apply_patch",
                   "memory_search", "memory_get",
                   "sessions_spawn", "sessions_send",
                   "browser", "canvas", "cron", "gateway"]
        }
      }
    ]
  },
  "bindings": [
    { "agentId": "bruba-main", "match": { "channel": "signal" } }
  ],
  "tools": {
    "agentToAgent": {
      "enabled": true,
      "allow": ["bruba-main", "bruba-manager", "bruba-web", "bruba-guru"]
    }
  },
  "channels": {
    "signal": {
      "enabled": true,
      "dmPolicy": "pairing"
    }
  },
  "gateway": {
    "port": 18789,
    "bind": "loopback"
  }
}
```
