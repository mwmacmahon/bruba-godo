# Repo Reference

Read-only access to the bruba-godo repository snapshot.

## What It Does

Documents the synced repository at `workspace/repo/`:
- What directories contain (scripts, tools, docs, templates, components)
- Read-only rules (don't modify, changes get overwritten)
- How to request changes (write a packet for Claude Code)

Lets the bot reference the operator's codebase without asking where it is.

## Status

**Prompt-Only** — No setup script, just prompt additions.

## Usage

Add `repo-reference` to your `agents_sections` in `config.yaml`:

```yaml
exports:
  bot:
    agents_sections:
      - header
      - repo-reference  # Add this
      # ...
```

Then run `/prompt-sync` to rebuild prompts.

## Prerequisites

The repository must be synced to the bot's workspace. This happens during `/push` when `clone_repo_code: true` is set in `config.yaml`.

## Files

- `prompts/AGENTS.snippet.md` — Repository layout and access rules
