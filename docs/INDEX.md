# Documentation Index

Quick reference for all docs in bruba-godo.

---

## Core Documentation

| File | Description |
|------|-------------|
| [architecture-masterdoc.md](architecture-masterdoc.md) | **Master reference** — multi-agent architecture, tool policies, cron, security, operations |
| [setup.md](setup.md) | Complete setup guide for OpenClaw from scratch |
| [operations-guide.md](operations-guide.md) | Day-to-day bot operations and maintenance |
| [troubleshooting.md](troubleshooting.md) | Common issues and solutions |

## Pipeline & Prompts

| File | Description |
|------|-------------|
| [pipeline.md](pipeline.md) | Content processing: intake → export |
| [prompt-management.md](prompt-management.md) | Prompt assembly system, section types, conflict resolution |

## Technical Deep-Dives

| File | Description |
|------|-------------|
| [security-model.md](security-model.md) | Threat model, permissions, exec allowlists |
| [filesystem-guide.md](filesystem-guide.md) | Directory structure, file locations, path conventions |
| [session-lifecycles.md](session-lifecycles.md) | Agent session management, reset patterns |
| [voice-integration.md](voice-integration.md) | Voice handling (STT/TTS) and Siri integration |
| [vault-strategy.md](vault-strategy.md) | Vault mode: symlink-based private content management |

## Vision & Planning

| File | Description |
|------|-------------|
| [bruba-vision.md](bruba-vision.md) | Bot-agnostic operator design vision |
| [component-status.md](component-status.md) | Component inventory and status |
| [efficiency-recommendations.md](efficiency-recommendations.md) | Sync pipeline optimization notes |

## Work-in-Progress (Underscore Prefix)

| File | Description |
|------|-------------|
| [_agentic-system-overhaul-notes.md](_agentic-system-overhaul-notes.md) | WIP: Agentic system redesign notes |
| [_agentic-system-overhaul-prompts.md](_agentic-system-overhaul-prompts.md) | WIP: Prompt snippets for overhaul |
| [_node-host-migration-plan.md](_node-host-migration-plan.md) | WIP: Node host migration planning |

## Subdirectories

| Directory | Contents |
|-----------|----------|
| [cc_logs/](cc_logs/) | Claude Code work logs (see [cc_logs/INDEX.md](cc_logs/INDEX.md)) |

---

## File Naming Conventions

- `_prefix.md` — Work-in-progress, not ready for reference
- `YYYY-MM-DD-*.md` — Dated logs (in cc_logs/)
- `*-guide.md` — How-to documentation
- `*-masterdoc.md` — Comprehensive reference documents

---

*Last updated: 2026-02-03*
