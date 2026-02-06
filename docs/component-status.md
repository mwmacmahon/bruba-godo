---
type: doc
scope: reference
title: "Component Status"
description: "Accurate inventory of all bruba-godo components"
---

# Component Status

Last updated: 2026-02-06

## Status Labels

| Label | Meaning |
|-------|---------|
| **Active** | Fully implemented: README, snippet, tools (if applicable), setup/validate |
| **Prompt-Only** | Has AGENTS.snippet.md only, no tools or setup scripts |
| **Partial** | Has some pieces (e.g., tools) but missing others (e.g., snippet) |
| **Planned** | Placeholder or not yet implemented |

## Component Inventory

| Component | Status | Snippet | Tools | Setup | Validate | Notes |
|-----------|--------|---------|-------|-------|----------|-------|
| signal | Active | ✓ | - | ✓ | ✓ | Signal messaging channel. Complete. |
| distill | Active | ✓ | - | ✓ | ✓ | Conversation → knowledge pipeline. Has extensive lib/. |
| session | Prompt-Only | ✓ | - | - | - | Session management instructions |
| memory | Prompt-Only | ✓ | - | - | - | Memory system instructions |
| heartbeats | Prompt-Only | ✓ | - | - | - | Heartbeat behavior instructions |
| group-chats | Prompt-Only | ✓ | - | - | - | Group chat handling instructions |
| workspace | Prompt-Only | ✓ | - | - | - | Workspace usage instructions |
| http-api | Prompt-Only | ✓ | - | - | - | HTTP API access instructions |
| continuity | Prompt-Only | ✓ | - | - | - | Session continuity instructions |
| cc-packets | Prompt-Only | ✓ | - | - | - | Claude Code packet handling |
| repo-reference | Prompt-Only | ✓ | - | - | - | Trigger stub + on-demand prompt (`Repo Reference.md`) |
| voice | Partial | ✓ | ✓ 3 | - | - | Has snippet + tools but no setup/validate |
| web-search | Prompt Ready | ✓ | - | - | - | Trigger stub + on-demand prompt (`Web Search.md`); bruba-web prompt in templates/prompts/web/ |
| guru-routing | Prompt-Only | ✓ | - | - | - | Trigger stub + on-demand prompt (`Guru Routing.md`) |
| reminders | Partial | ✓ | ✓ 2 | - | - | Has AGENTS + TOOLS snippets + tools |

## Tools Inventory

### voice/tools/
- `tts.sh` - Text-to-speech via sherpa-onnx
- `whisper-clean.sh` - Speech-to-text via Whisper
- `voice-status.sh` - Voice system status check

### reminders/tools/
- `cleanup-reminders.sh` - Cleanup old completed reminders
- `helpers/cleanup-reminders.py` - Python implementation

## Prompt Assembly Wiring

All components with snippets are wired into `config.yaml` → `agents_sections`:

```
header → http-api → first-run → session → continuity → memory → distill →
safety → bot:exec-approvals → cc-packets → external-internal → workspace →
repo-reference → group-chats → tools → web-search → reminders → voice →
heartbeats → signal → make-it-yours
```

## Automation Tools

| Tool | Purpose |
|------|---------|
| `./tools/push.sh --tools-only` | Sync component tools to bot |
| `./tools/push.sh --update-allowlist` | Update exec-approvals entries |
| `./tools/update-allowlist.sh` | Bidirectional allowlist sync (add missing, remove orphans) |
| `./tools/update-allowlist.sh --check` | Check allowlist status without changes |
| `./tools/validate-components.sh` | Check component consistency |

**Allowlist sync in /sync:** Step 5 validates allowlist after push, prompts to add/remove entries.

## See Also

- [Operations Guide](operations-guide.md) for day-to-day usage
- [cc_logs/2026-01-31-component-audit-complete.md](cc_logs/2026-01-31-component-audit-complete.md) for implementation details
