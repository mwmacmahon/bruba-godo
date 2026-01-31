# CC-Packets Component

Enables packet-based task exchange between Bruba (main session) and Claude Code (bruba-godo).

## Overview

This component adds instructions to Bruba's AGENTS.md for:
- Writing task packets for Claude Code
- Finding Claude Code's work logs
- When and how to use the packet system

## Packet Flow

```
Bruba (main session)
    │
    │ writes packet to
    ▼
workspace/output/packets/YYYY-MM-DD-<name>.md
    │
    │ CC checks for incoming work
    ▼
Claude Code (bruba-godo)
    │
    │ writes work log to
    ▼
docs/cc_logs/YYYY-MM-DD-<slug>.md
    │
    │ exported to Bruba's memory as
    ▼
Claude Code Log - <title>.md
```

## Packet Format

```markdown
# Packet: <Title>

**Created:** YYYY-MM-DD
**From:** Bruba (main session via Michael)
**For:** Claude Code (bruba-godo)
**Priority:** HIGH | MEDIUM | LOW

---

## Goal
[What needs to happen]

## Context
[Background CC needs to understand]

## Deliverables
[Specific things to produce]

## Verification
[How to know it's done]

---

## End of Packet
```

## Related

- CLAUDE.md "Output Conventions" section documents CC's side
- `docs/cc_logs/` contains CC's work logs
- `workspace/output/packets/archive/` for completed packets
