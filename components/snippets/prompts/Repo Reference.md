---
type: prompt
scope: meta
title: "Repo Reference Guide"
output_name: "Repo Reference"
---

# Repo Reference Guide

Full reference for navigating the bruba-godo repository snapshot in memory.

## What's Inside

| Path | Contents |
|------|----------|
| `scripts/` | convert-doc.py and other utilities |
| `tools/` | Shell tool wrappers |
| `docs/` | Pipeline and system documentation |
| `templates/` | Prompt and config templates |
| `components/` | Component definitions for AGENTS.md |
| `CLAUDE.md` | CC's workspace instructions |

## Rules

- **Read freely** — understand the code, reference it in conversations
- **Don't modify** — changes get overwritten on sync
- **To change something:** Write a packet → CC implements in the actual repo

## Finding Files

Use `memory_search` to discover files in the repo:
```
memory_search "guru-routing component"
  → Returns: .../memory/repos/bruba-godo/components/guru-routing/...
```

Then read:
```
read ${WORKSPACE}/memory/repos/bruba-godo/components/guru-routing/...
```

## Example Usage

```
# Read a file:
read ${WORKSPACE}/memory/repos/bruba-godo/CLAUDE.md

# Search for content:
memory_search "exec-approvals"
  → Returns relevant files

# Read config:
read ${WORKSPACE}/memory/repos/bruba-godo/config.yaml
```

**Note:** The repo snapshot is synced from the operator machine. You can read it, but don't modify — write a packet instead.
