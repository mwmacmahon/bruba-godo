# Web Search Component

**Status:** Ready

Web research capability via bruba-web agent using native OpenClaw agent-to-agent communication.

## Overview

This component provides:
- **Web search access** for agents that don't have direct web tools
- **Security isolation** via dedicated bruba-web agent
- **Sync/async patterns** depending on whether results are needed immediately

## Architecture

```
bruba-main (or other agent)
    │
    │ sessions_send(agent:bruba-web:main, wait: true/false)
    │
    ▼
bruba-web
    │
    │ web_search, web_fetch
    │
    ▼
 Internet
```

**Why this design:**
- Web content is untrusted and could contain prompt injection
- bruba-web is isolated: no file access, no exec, no sessions_send
- Results are filtered through bruba-web's summarization before reaching Main
- Clear security boundary between internal operations and external web content

## Prerequisites

bruba-web agent must be configured in config.yaml with:
- `tools_allow: [web_search, web_fetch]`
- `tools_deny: [read, write, exec, edit, ...]` (proper isolation)
- Workspace at `/Users/bruba/agents/bruba-web`

## Files

```
components/web-search/
├── README.md                    # This file
└── prompts/
    └── AGENTS.snippet.md        # Instructions for using bruba-web
```

No tools or allowlist — this component only provides prompt instructions for using the existing bruba-web agent.

## Setup

1. **Verify bruba-web agent exists:**
```bash
./tools/bot 'ls -la /Users/bruba/agents/bruba-web/'
```

2. **Enable component in config.yaml:**
```yaml
agents:
  bruba-main:
    agents_sections:
      - web-search  # Uncomment this line
```

3. **Regenerate prompts:**
```bash
./tools/assemble-prompts.sh
```

## Usage

### From bruba-main

Synchronous (wait for results):
```json
{
  "tool": "sessions_send",
  "sessionKey": "agent:bruba-web:main",
  "message": "Search for recent OpenClaw release notes. Summarize key changes with source URLs.",
  "wait": true
}
```

Asynchronous (results delivered later):
```json
{
  "tool": "sessions_send",
  "sessionKey": "agent:bruba-web:main",
  "message": "Research best practices for TypeScript monorepos. Send summary when done.",
  "wait": false
}
```

### Request Patterns

| Use Case | Pattern |
|----------|---------|
| Quick lookup | `"wait": true` — block until results |
| Background research | `"wait": false` — continue working |
| Multi-topic research | Multiple async sends, process results as they arrive |

## Security Model

bruba-web has strict tool isolation:

| Tool | Status | Reason |
|------|--------|--------|
| web_search | ✅ Allowed | Core function |
| web_fetch | ✅ Allowed | Core function |
| read | ❌ Denied | No file access |
| write | ❌ Denied | No file creation |
| exec | ❌ Denied | No command execution |
| edit | ❌ Denied | No file modification |
| sessions_send | ❌ Denied | Cannot reach other agents |
| sessions_spawn | ❌ Denied | Cannot create helpers |
| memory_* | ❌ Denied | No memory access |

This isolation ensures that even if web content contains prompt injection, bruba-web cannot:
- Access or modify files
- Execute commands
- Communicate with other agents
- Persist malicious content

## Sandbox Configuration (Optional)

For additional isolation, bruba-web can run in a Docker sandbox. Add to config.yaml under the bruba-web agent:

```yaml
bruba-web:
  # ... existing config ...
  sandbox:
    mode: "all"
    scope: "agent"
    prune:
      idleHours: 0
      maxAgeDays: 0
    docker:
      network: "bridge"  # Needs internet access
      memory: "256m"
      cpus: 0.5
```

**Note:** Global sandbox is currently `off` due to "agent-to-agent session visibility bug". Per-agent sandbox may need testing.
