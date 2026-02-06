# Guru Routing Component

**Status:** Active

Provides technical deep-dive routing from bruba-main to bruba-guru. Guru is Bruba's deep-focus technical mode (she/her) — Main detects technical questions and routes them to Guru for thorough analysis.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  User (via iMessage/BlueBubbles)                             │
└─────────────────┬───────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────────┐
│  bruba-main (Opus)                                          │
│  - Detects technical questions                              │
│  - Routes via sessions_send to bruba-guru                   │
│  - Relays response to user                                  │
└─────────────────┬───────────────────────────────────────────┘
                  │ sessions_send
                  ▼
┌─────────────────────────────────────────────────────────────┐
│  bruba-guru (Opus)                                          │
│  - Deep technical analysis                                  │
│  - Full file access, exec, memory                           │
│  - Can reach bruba-web for research                         │
└─────────────────────────────────────────────────────────────┘
```

## Routing Modes

### 1. Auto-Routing (Default)

Main detects technical content and routes automatically:

**Triggers:**
- Code blocks or config files pasted
- "Why isn't this working", "debug this", "what's wrong with"
- Architecture questions, system design
- Explicit: "ask guru", "guru question"

### 2. Guru Mode (Extended Session)

User explicitly enters extended technical session:

**Enter:** "guru mode", "route me to guru", "let me talk to guru"
**Exit:** "back to main", "normal mode", "that's all for guru"

In guru mode, Main becomes pass-through relay.

### 3. Status Check

User asks about Guru without switching:

**Triggers:** "what's guru working on?", "guru status"

## Handoff Zone

Both Main and Guru can access `/Users/bruba/agents/bruba-shared/`:
- `packets/` — Work handoff packets
- `context/` — Shared context files

Use for multi-session technical work or context handoff.

## Prerequisites

1. **bruba-guru agent** configured in `openclaw.json`:

```json
{
  "agents": {
    "list": [
      {
        "id": "bruba-guru",
        "name": "Guru",
        "workspace": "/Users/bruba/agents/bruba-guru",
        "model": { "primary": "anthropic/claude-opus-4-5" },
        "heartbeat": { "every": "0m" },
        "tools": {
          "deny": ["web_search", "web_fetch", "browser", "canvas",
                   "cron", "gateway", "sessions_spawn"]
        }
      }
    ]
  }
}
```

2. **Agent-to-agent communication** enabled:

```json
{
  "tools": {
    "agentToAgent": {
      "enabled": true,
      "allow": ["bruba-main", "bruba-manager", "bruba-web", "bruba-guru"]
    }
  }
}
```

3. **Guru workspace** created:

```bash
mkdir -p /Users/bruba/agents/bruba-guru/{workspace,memory,results}
mkdir -p /Users/bruba/agents/bruba-shared/{packets,context}
```

4. **Auth profile** copied:

```bash
# Note: Auth profiles are in ~/.openclaw, NOT ~/.openclaw
mkdir -p /Users/bruba/.clawdbot/agents/bruba-guru
cp /Users/bruba/.clawdbot/agents/bruba-main/auth-profiles.json \
   /Users/bruba/.clawdbot/agents/bruba-guru/
```

## Setup

1. Enable component in `config.yaml`:
   ```yaml
   agents:
     bruba-main:
       agents_sections:
         - guru-routing  # Add to Main's sections
   ```

2. Assemble and push prompts:
   ```bash
   ./tools/assemble-prompts.sh
   ./tools/push.sh
   ```

3. Complete bot-side setup (see Prerequisites)

4. Prime Guru session:
   ```bash
   openclaw agent --agent bruba-guru \
     --message "Test initialization. Confirm operational."
   ```

## Usage

From Main's perspective, technical routing uses:

```json
{
  "tool": "sessions_send",
  "sessionKey": "agent:bruba-guru:main",
  "message": "[Technical question with context]",
  "wait": true
}
```

See `prompts/AGENTS.snippet.md` for full routing instructions.

## Files

- `README.md` — This documentation
- `prompts/AGENTS.snippet.md` — Routing instructions for bruba-main
