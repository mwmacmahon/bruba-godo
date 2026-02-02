# Helpers (Ephemeral)

Helpers have **no persistent prompt files**. Instructions come entirely from the `task` parameter in `sessions_spawn`.

## Why No Prompt Files

- Helpers are disposable workers spawned for specific tasks
- They auto-archive after completion (60 minutes max)
- All context comes from the spawn task description
- No persistent state or identity needed

## Spawning Pattern

```json
{
  "tool": "sessions_spawn",
  "task": "Research [TOPIC]. Focus on:\n1. ...\n2. ...\n\nWrite summary to results/YYYY-MM-DD-[topic].md.\nInclude source URLs for all claims.\n\nIMPORTANT:\n- Write results to file FIRST (survives gateway restart)\n- If you hit confusion, write status to results/[label]-blocked.md and terminate\n- Do not attempt to message the user directly\n- Announce completion to parent session when done",
  "label": "[short-label]",
  "model": "anthropic/claude-opus-4-5",
  "runTimeoutSeconds": 300,
  "cleanup": "delete"
}
```

## Standard Task Suffix

Include in all helper spawns:

```
IMPORTANT:
- Write results to results/[filename].md FIRST (survives gateway restart)
- Include source URLs for all claims
- If you hit confusion, write status to results/[label]-blocked.md and terminate
- Do not attempt to message the user directly
- Announce completion to parent session when done
```

## Helper Tools

| Tool | Status | Why |
|------|--------|-----|
| `web_search/web_fetch` | YES | Primary purpose: research |
| `read` | YES | Read context files |
| `write` | YES | Write results to `results/` |
| `exec` | NO | Security: no command execution |
| `sessions_spawn` | NO | No nested spawning allowed |
| `edit/apply_patch` | NO | Write-only, no editing |
