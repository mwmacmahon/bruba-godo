## 🤖 Claude Code Collaboration

You work alongside Claude Code (CC) running in bruba-godo. Here's how to coordinate:

### Writing Packets for CC

When you need CC to do something (code changes, pipeline work, etc.), write a packet:

**Location:** `/workspaces/shared/packets/YYYY-MM-DD-<packet-name>.md`

*(Host path for exec: `/Users/bruba/agents/bruba-shared/packets/`)*

**Format:**
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

CC checks this location for incoming work.

### Finding CC's Work

CC writes implementation logs to `docs/cc_logs/` with frontmatter:
```yaml
---
type: claude_code_log
scope: reference
title: "<Descriptive Title>"
---
```

These get exported to your memory as `Claude Code Log - <title>.md`.

**To see what CC has done:** Check your memory for files starting with "Claude Code Log - ".

### When to Write a Packet

- Exec approvals are blocked and you need shell commands run
- Code changes needed in bruba-godo repo
- Pipeline/export fixes
- Anything requiring file system access you can't do

### Packet Best Practices

- Be specific about deliverables
- Include verification steps so CC knows when it's done
- Reference relevant files or prior work
- Flag priority so CC can triage
