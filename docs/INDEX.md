---
type: doc
scope: reference
title: "Documentation Index"
description: "Navigation hub for bruba-godo documentation"
---

# Documentation Index

Quick reference for all docs in bruba-godo.

## Quick Navigation

| What you need | Start here |
|---------------|------------|
| Setting up a new bot from scratch | [setup.md](setup.md) |
| Starting/stopping the daemon, syncing files | [operations-guide.md](operations-guide.md) |
| Getting sessions into bot memory | [pipeline.md](pipeline.md) |
| Something's broken | [troubleshooting.md](troubleshooting.md) |
| Exec allowlist, config protection, permissions | [security-model.md](security-model.md) |
| Why does this exist? What's the architecture? | [bruba-vision.md](bruba-vision.md) |

---

## Core Documentation

| File | Description |
|------|-------------|
| [architecture-masterdoc.md](architecture-masterdoc.md) | **Master reference** — multi-agent architecture, tool policies, cron, security, operations |
| [setup.md](setup.md) | End-to-end setup: bot account, SSH, onboarding, security hardening, exec lockdown |
| [operations-guide.md](operations-guide.md) | Daily driver — daemon, sessions, sync, code review, memory search, logs |
| [troubleshooting.md](troubleshooting.md) | Organized by symptom — daemon, SSH, exec, Signal/voice, config gotchas |
| [channel-integrations.md](channel-integrations.md) | BlueBubbles (iMessage), Signal, inter-agent routing via sessions_send |

## Pipeline & Prompts

| File | Description |
|------|-------------|
| [pipeline.md](pipeline.md) | 5-stage content pipeline: pull → convert → canonicalize → export → push |
| [prompt-management.md](prompt-management.md) | Prompt assembly system, section types, conflict resolution |
| [per-agent-pipeline.md](per-agent-pipeline.md) | Per-agent content pipeline architecture |

## Technical Deep-Dives

| File | Description |
|------|-------------|
| [security-model.md](security-model.md) | Threat model, trust boundaries, exec allowlist, config protection |
| [filesystem-guide.md](filesystem-guide.md) | Directory structure, file locations, path conventions |
| [session-lifecycles.md](session-lifecycles.md) | Agent session management, reset patterns |
| [voice-integration.md](voice-integration.md) | Voice handling (STT/TTS) and Siri integration |
| [vault-strategy.md](vault-strategy.md) | Vault mode: symlink-based private content management |
| [bruba-web-docker-migration.md](bruba-web-docker-migration.md) | Docker sandbox for bruba-web — setup, verification, rollback |

## Vision & Planning

| File | Description |
|------|-------------|
| [bruba-vision.md](bruba-vision.md) | Bot-agnostic operator design philosophy and decision log |
| [component-status.md](component-status.md) | Component inventory (14 components) with status and prompt wiring |
| [efficiency-recommendations.md](efficiency-recommendations.md) | Sync pipeline optimization notes |

## Components

Full component documentation: **[../components/README.md](../components/README.md)**

Highlights:
- [Signal](../components/signal/README.md) — Full Signal setup including voice messages, QR linking, agent configuration
- [Distill](../components/distill/README.md) — Converting conversations to structured knowledge docs
- [Voice](../components/voice/README.md) — Whisper transcription and TTS output

## Subdirectories

| Directory | Contents |
|-----------|----------|
| [cc_logs/](cc_logs/) | Claude Code work logs *(gitignored — local only)* |

---

## File Naming Conventions

- `_prefix.md` — Work-in-progress, not ready for reference
- `YYYY-MM-DD-*.md` — Dated logs (in cc_logs/)
- `*-guide.md` — How-to documentation
- `*-masterdoc.md` — Comprehensive reference documents

---

*Last updated: 2026-02-06*
