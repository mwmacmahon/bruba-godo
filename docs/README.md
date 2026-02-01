---
type: doc
scope: reference
title: "Documentation Index"
description: "Navigation hub for bruba-godo documentation"
---

# Documentation Index

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

### [setup.md](setup.md)
End-to-end setup: creating the bot account, installing clawdbot, SSH configuration, onboarding wizard, security hardening, exec lockdown, config protection. Start here if you're setting up a new machine or provisioning a fresh bot.

### [operations-guide.md](operations-guide.md)
The daily driver. Daemon start/stop/restart, viewing sessions, continuation files, code review workflow, memory search, file sync operations (mirror/pull/push), config editing, checking logs. Reference this when you're actually running the bot.

### [pipeline.md](pipeline.md)
How content flows from raw session transcripts to bot memory. The 5-stage content pipeline (pull → convert → canonicalize → export → push), CONFIG block format, prompt assembly system, export filtering and redaction. Reference this when processing conversations.

### [security-model.md](security-model.md)
Threat model, trust boundaries, the exec allowlist system, config file protection (chown root), permission scoping, and known security issues. Read this before giving the bot new capabilities.

### [troubleshooting.md](troubleshooting.md)
Organized by symptom. Daemon issues, SSH problems, exec denials, Signal/voice failures, memory search not working, config gotchas. Includes the "25 Key Insights" distilled from months of setup pain.

### [bruba-vision.md](bruba-vision.md)
The why behind the what. Bot-agnostic design philosophy, separation of operator/bot concerns, the decision log (23 architectural choices with rationale), and the original vision for what this project enables.

---

## Reference

### [component-status.md](component-status.md)
Inventory of all 14 components with their current status (Active/Prompt-Only/Partial), what tools they include, and the prompt assembly wiring order.

---

## Components

Full component documentation: **[../components/README.md](../components/README.md)**

Highlights:
- [Signal](../components/signal/README.md) — Full Signal setup including voice messages, QR linking, agent configuration
- [Distill](../components/distill/README.md) — Converting conversations to structured knowledge docs
- [Voice](../components/voice/README.md) — Whisper transcription and TTS output
