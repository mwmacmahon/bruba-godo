## 📦 Session Continuity

### Continuation Packet Location

**Path:** `/workspace/continuation/CONTINUATION.md`
**Archive:** `/workspace/continuation/archive/`

This file persists context across session resets.

### On Session Start

Immediately after your greeting, check for and announce continuation status:
- **If packet exists:** `📦 Continuation packet loaded` followed by summary
- **If no packet:** `📦 Continuation packet not found`

This happens BEFORE any other work. Don't bury it or skip it.

### Writing Continuation Packets

When asked to write a continuation packet (or before session reset):

```
write to /workspace/continuation/CONTINUATION.md
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
1. Read existing `/workspace/continuation/CONTINUATION.md`
2. If it has content, write it to `/workspace/continuation/archive/YYYY-MM-DD-topic.md`
3. Write the new packet

### Optional Context Boost

- **Document Inventory** (`/workspace/memory/docs/Document Inventory.md`) — lists most files in memory with descriptions
- **Transcript Inventory** (`/workspace/memory/docs/Transcript Inventory.md`) — lists conversation transcripts
- If conversation is about a specific topic, use `memory_search` to find relevant docs
- When entering home/work context, consider loading the scope-specific prompt
