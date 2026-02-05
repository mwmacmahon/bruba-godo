# bruba-help

Print quick reference of all available commands.

## Instructions

Output this reference card:

```
### Daemon Commands
| Command | Purpose |
|---------|---------|
| /status | Show daemon + local state |
| /launch | Start the daemon |
| /stop | Stop the daemon |
| /restart | Restart the daemon |
| /wake | Wake all agents |

### Sync Commands
| Command | Purpose |
|---------|---------|
| /sync | Full pipeline (prompts + config + content) |
| /prompt-sync | Prompts only with conflict detection |
| /config-sync | Sync config.yaml → openclaw.json |
| /mirror | Pull bot files locally |
| /pull | Pull closed sessions |
| /push | Push content to bot |

### Content Pipeline
| Command | Purpose |
|---------|---------|
| /convert | Add CONFIG block to intake file |
| /intake | Batch canonicalize intake files |
| /export | Generate filtered exports |

### Config Commands
| Command | Purpose |
|---------|---------|
| /config | Configure heartbeat, allowlist (interactive) |
| /component | Manage optional components |
| /prompts | Manage prompt assembly |
| /update | Update openclaw version |

**Note:** `/config` is interactive config editing. `/config-sync` syncs config.yaml to bot.

### Development
| Command | Purpose |
|---------|---------|
| /code | Review and migrate staged code |
| /convo | Load active conversation |
| /test | Run test suite |
| /morning-check | Verify post-reset wake |

### Common Workflows

**Update a prompt template:**
1. Edit `templates/prompts/*.md` or `components/*/prompts/*.snippet.md`
2. Run `/prompt-sync`

**Change agent settings (model, heartbeat, tools):**
1. Edit `config.yaml` under `agents:` or `openclaw:`
2. Run `/config-sync`

**Add content to bot memory:**
1. `/pull` → `/convert <file>` → `/intake` → `/export` → `/push`

**Debug sync issues:**
1. `/mirror` to get current bot state
2. Check `mirror/prompts/` vs `assembled/`
```
