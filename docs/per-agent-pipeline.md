---
version: 1.0.0
updated: 2026-02-05
type: refdoc
scope: reference
tags: [bruba, content-pipeline, multi-agent, architecture]
---

# Per-Agent Content Pipeline

The content pipeline (`/pull` -> `/convert` -> `/intake` -> `/export` -> `/push`) now handles intake and export per-agent, routing content to the correct bot agent's memory.

## What Changed

Previously, the pipeline was hardcoded to bruba-main:
- Sessions pulled from one agent's session dir
- All content exported to `agents/bruba-main/exports/`
- Push synced only bruba-main's memory

Now, the pipeline is agent-aware:
- Sessions pulled per-agent from each content_pipeline agent
- Canonical files carry an `agents:` frontmatter field for routing
- Export routes files to the correct agent's export dir
- Push syncs all content_pipeline agents

## Config Flag

Agents opt in with `content_pipeline: true` in config.yaml:

```yaml
agents:
  bruba-main:
    content_pipeline: true
    # ... existing config ...

  bruba-rex:
    content_pipeline: true
    # ... existing config ...

  bruba-web:
    # No content_pipeline (stateless service agent)
```

## Routing Model

The `agents:` field in canonical file frontmatter controls which agents receive the file:

```yaml
---
title: "Some Conversation"
slug: 2026-02-05-some-conversation
agents: [bruba-main, bruba-rex]
---
```

- **Default**: Files without `agents:` default to `[bruba-main]`
- **Multi-agent**: Add multiple agents to share content across memories
- **Set automatically**: `--agent` flag on canonicalize sets it from the intake subdir

## Pipeline Flow

```
Bot sessions (per agent)
  ↓ /pull
agents/{agent}/sessions/*.jsonl → agents/{agent}/intake/*.md
  ↓ /convert (adds agents: field to CONFIG)
  ↓ /intake (canonicalizes with --agent)
reference/transcripts/*.md (agents: in frontmatter)
  ↓ /export (routes via agents: field)
agents/{agent}/exports/ (per-agent exports)
  ↓ /push (syncs content_pipeline agents)
Bot memory (per agent)
```

## Backward Compatibility

| Scenario | Behavior |
|----------|----------|
| Files in flat `agents/bruba-main/intake/` | Treated as bruba-main |
| Canonical files without `agents:` | Default to `[bruba-main]` during export |
| Existing `.pulled` | Auto-migrates to `agents/bruba-main/sessions/.pulled` |
| Existing `*.jsonl` | Left in place, new pulls go to per-agent dirs |
| Standalone export profiles (claude, tests) | Unchanged -- process all files regardless of agents |

## Key Files Changed

- `config.yaml` -- `content_pipeline: true` on bruba-main and bruba-rex
- `components/distill/lib/models.py` -- `agents` field on CanonicalConfig
- `components/distill/lib/parsing.py` -- Parses `agents:` from frontmatter
- `components/distill/lib/canonicalize.py` -- Writes `agents:` to frontmatter, accepts `--agent` param
- `components/distill/lib/cli.py` -- `--agent` on canonicalize, per-agent export routing
- `tools/lib.sh` -- `get_content_pipeline_agents()`, extended `load_agent_config()`
- `tools/pull-sessions.sh` -- Per-agent pull loop with backward compat migration
- `tools/push.sh` -- Uses `content_pipeline` flag instead of hardcoded bruba-main check
