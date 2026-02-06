---
version: 1.2.0
updated: 2026-02-06
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

Two frontmatter fields control routing. For agent exports, **both** are checked:

```yaml
---
title: "Some Conversation"
slug: 2026-02-05-some-conversation
agents: [bruba-main, bruba-rex]   # Which bot agents receive this file
users: [gus, rex]                 # Which human's profiles receive this file
---
```

### `users` Field (Primary Routing)

- **Default**: Files without `users:` go to everyone (standalone profiles) or default to bruba-main (agent profiles, with warning)
- **Multi-user**: `[gus, rex]` sends to both users' profiles AND auto-derives agent routing
- **Used by**: Both standalone and agent export paths
- **Exclusive prefix**: `only-gus` means only profiles that serve exactly gus

### `agents` Field (Optional Override)

- **Usually not needed**: Auto-derived from `users` via user→agent mapping in config
- **Set automatically**: `--agent` flag on canonicalize sets it from the intake subdir
- **Override use**: When you need routing that differs from the user→agent mapping

### User→Agent Mapping

The export system maps `users` to agents using `identity.human_name` from config.yaml:

| `users` value | Auto-derived `agents` |
|---------------|----------------------|
| `[gus]` | `[bruba-main]` (because bruba-main has `identity.human_name: "Gus"`) |
| `[rex]` | `[bruba-rex]` (because bruba-rex has `identity.human_name: "Rex"`) |
| `[gus, rex]` | `[bruba-main, bruba-rex]` |
| *(empty)* | `['bruba-main']` with warning |

See `docs/distill-pipeline.md` for the full filter system.

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

## Export Filter Improvements

### Stale File Reconciliation

After each export profile run, `_reconcile_stale_files()` removes `.md` files in the output directory that weren't written or confirmed unchanged. Skips inventory files and `core-prompts/` (managed by assemble-prompts.sh). Also cleans empty subdirectories.

### Tag Exclusions

`exclude.tags` filters files by tag. If a file's tags intersect with the exclude list, the file is skipped. Example: `tags: [legacy, do-not-sync]` excludes pkm-legacy files and internal planning packets.

### Per-User Routing

The `users:` frontmatter field controls which human's agents receive a document. See "Per-User Routing" section below.

## Backward Compatibility

| Scenario | Behavior |
|----------|----------|
| Files in flat `agents/bruba-main/intake/` | Treated as bruba-main |
| Canonical files without `agents:` | Auto-derived from `users`; if no `users` either, defaults to `[bruba-main]` with warning |
| Canonical files without `users:` | Go to everyone on standalone profiles; default to bruba-main on agent profiles (with warning) |
| Files with `users` but no `agents` | Agent routing auto-derived from `users` (e.g. `users: [rex]` → `agents: [bruba-rex]`) |
| Existing `.pulled` | Auto-migrates to `agents/bruba-main/sessions/.pulled` |
| Existing `*.jsonl` | Left in place, new pulls go to per-agent dirs |
| Standalone export profiles (claude-gus, claude-rex, tests) | Filter by users if configured |

## Per-User Routing

Two humans use the system -- Gus (served by bruba-main, bruba-manager, bruba-guru) and Rex (served by bruba-rex). The `users:` frontmatter field controls which human's agents receive a document.

### Frontmatter Field

```yaml
---
title: "Some Document"
users: [gus]        # Only Gus's agents receive this
---
```

### Matching Semantics

| Document `users:` | Profile `include.users: [gus]` | Profile `include.users: [rex]` |
|---|---|---|
| *(empty)* | yes | yes |
| `[gus]` | yes | no |
| `[rex]` | no | yes |
| `[gus, rex]` | yes | yes |
| `[only-gus]` | yes | no |

The `only-X` prefix is exclusive: `only-gus` means the profile's users must be a subset of `{gus}`. A profile with `include.users: [gus, rex]` would fail.

### Auto-Derivation

Agent profiles auto-derive `include.users` from `identity.human_name` if not set explicitly. Since bruba-main has `identity.human_name: "Gus"`, its profile automatically gets `include.users: [gus]`.

### Config

```yaml
agents:
  bruba-main:
    include:
      users: [gus]         # Explicit (or auto-derived from identity.human_name)
  bruba-rex:
    include:
      users: [rex]

exports:
  claude-gus:
    include:
      users: [gus]         # Standalone profiles need explicit config
  claude-rex:
    include:
      users: [rex]
```

## Key Files Changed

- `config.yaml` -- `content_pipeline: true` on bruba-main and bruba-rex; `include.users` per agent; split claude into claude-gus/claude-rex
- `components/distill/lib/models.py` -- `agents` and `users` fields on CanonicalConfig
- `components/distill/lib/parsing.py` -- Parses `agents:` and `users:` from frontmatter
- `components/distill/lib/canonicalize.py` -- Writes `agents:` and `users:` to frontmatter, accepts `--agent` param
- `components/distill/lib/cli.py` -- `_matches_user_filter()`, auto-derive users from identity, per-agent export routing, stale cleanup, tag exclusions
- `tools/lib.sh` -- `get_content_pipeline_agents()`, extended `load_agent_config()`
- `tools/pull-sessions.sh` -- Per-agent pull loop with backward compat migration
- `tools/push.sh` -- Uses `content_pipeline` flag instead of hardcoded bruba-main check
