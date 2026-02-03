## 📦 Session Continuity

### Continuation Packet Location

**Path:** `/Users/bruba/agents/bruba-main/continuation/CONTINUATION.md`
**Archive:** `/Users/bruba/agents/bruba-main/continuation/archive/`

This file persists context across session resets.

### On Session Start

Immediately after your greeting, check for and announce continuation status:
- **If packet exists:** `📦 Continuation packet loaded` followed by summary
- **If no packet:** `📦 Continuation packet not found`

This happens BEFORE any other work. Don't bury it or skip it.

### Writing Continuation Packets

When asked to write a continuation packet (or before session reset):

```
write /Users/bruba/agents/bruba-main/continuation/CONTINUATION.md
```

**Format:**
```markdown
## Session Summary
[What we discussed/accomplished]

## In Progress
[Tasks with status and blockers]

## Open Questions
[Unresolved items]

## Next Steps
[Action items for next session]
```

### Archiving Old Packets

When writing a new continuation packet, archive the old one first:
1. Read existing continuation file
2. If it has content, write it to `continuation/archive/YYYY-MM-DD-topic.md`
3. Write the new packet

### Recall Context with memory_search

**Use `memory_search` liberally** to recall past context:
- User mentions a topic? → `memory_search` for past discussions
- Resuming ongoing work? → `memory_search` for recent activity
- Uncertain about context? → `memory_search` before asking

```
memory_search "project X"     → Past discussions, decisions
memory_search "dentist"       → Reminders, appointments
memory_search "2026-01"       → January activity
```

`memory_search` is fast and cheap — use it frequently in all conversations, not just technical ones.
