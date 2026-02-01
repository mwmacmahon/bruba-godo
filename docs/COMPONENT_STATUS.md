---
type: doc
scope: reference
title: "Component Status"
description: "Accurate inventory of all bruba-godo components"
---

# Component Status

Last updated: 2026-01-31

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
| repo-reference | Prompt-Only | ✓ | - | - | - | Repository reference guidance |
| voice | Partial | ✓ | ✓ 3 | - | - | Has snippet + tools but no setup/validate |
| web-search | Partial | - | ✓ 2 | - | - | Has tools but missing snippet |
| reminders | Partial | - | ✓ 2 | - | - | Has tools but missing snippet |

## Tools Inventory

### voice/tools/
- `tts.sh` - Text-to-speech via sherpa-onnx
- `whisper-clean.sh` - Speech-to-text via Whisper
- `voice-status.sh` - Voice system status check

### web-search/tools/
- `web-search.sh` - Wrapper invoking web-reader agent
- `ensure-web-reader.sh` - Ensures Docker sandbox is running

### reminders/tools/
- `cleanup-reminders.sh` - Cleanup old completed reminders
- `helpers/cleanup-reminders.py` - Python implementation

## Prompt Assembly Wiring

All components with snippets are wired into `exports.yaml` → `agents_sections`:

```
header → http-api → first-run → session → continuity → memory → distill →
safety → bot:exec-approvals → cc-packets → external-internal → workspace →
repo-reference → group-chats → tools → voice → heartbeats → signal → make-it-yours
```

**Not in agents_sections** (no snippets):
- web-search
- reminders

## Gaps to Address

1. **voice**: README says "Planned" but is actually Partial (has snippet + tools)
2. **web-search**: Has tools, needs snippet and agents_sections entry
3. **reminders**: Has tools, needs snippet and agents_sections entry
4. **No tool sync**: push.sh doesn't sync component tools to bot
5. **No allowlist automation**: exec-approvals updated manually

## See Also

- [Implementation packets](../workspace/output/packets/) for each phase
- [Operations Guide](operations-guide.md) for current workarounds
