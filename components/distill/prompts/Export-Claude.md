---
type: prompt
scope: meta
profile: claude
title: "Export Prompt (Claude Code)"
output_name: "Export"
---

# Export Prompt (Claude Code)

Generate a CONFIG block and backmatter for this conversation, then write the exported file.

## When to Use

Trigger words: "export", "done", "wrap up", "finished", end of session.

## What You'll Generate

1. **CONFIG block** — metadata for processing (filtering, redaction, section removal)
2. **Backmatter** — summary, decisions, outputs, continuation context
3. **Write the file** — save to `intake/` directory

Unlike the standard export prompt, you have file access. Write the complete exported conversation directly to `intake/YYYY-MM-DD-slug.md`.

---

## CONFIG Block Format (V2)

```yaml
=== EXPORT CONFIG ===
title: "Descriptive Title"
slug: YYYY-MM-DD-topic-slug
date: YYYY-MM-DD
source: claude-code
tags: [tag1, tag2, tag3]

sections_remove:
  - start: "First 5-50 words of section start..."
    end: "First 5-50 words of section end..."
    description: "Why removed OR replacement text"

sensitivity:
  terms:
    names: [Name1, Name2]
    health: [condition, medication]
    personal: [private detail]
    financial: [amount, account]
  sections:
    - start: "Anchor text..."
      end: "Anchor text..."
      tags: [health, personal]
      description: "What this section contains"
=== END CONFIG ===
```

### Field Reference

| Field | Required | Description |
|-------|----------|-------------|
| `title` | Yes | Descriptive title for the conversation |
| `slug` | Yes | `YYYY-MM-DD-topic-slug` format |
| `date` | Yes | Conversation date (YYYY-MM-DD) |
| `source` | Yes | Always `claude-code` for this context |
| `tags` | Yes | Topical tags for categorization |
| `sections_remove` | No | Sections to replace with description at export |
| `sensitivity.terms` | No | Individual sensitive terms by category |
| `sensitivity.sections` | No | Longer passages with sensitive content |

---

## Sections Remove

Use `sections_remove` for content that should be replaced with a summary at export time. The `description` field becomes the replacement text.

### When to Mark for Removal

- Debugging tangents (brief dead ends)
- Large code blocks (summarize instead)
- Tool output walls (file listings, grep results)
- Failed attempts that don't add value
- Off-topic discussions

### Replacement Patterns

| Content Type | Description Pattern |
|--------------|---------------------|
| Large code block | `[Code: N lines lang - what it does]` |
| Tool output | `[Tool output: tool name - summary]` |
| Debug tangent | Brief description, e.g. "Debugging path issue" |
| File listing | `[File listing: N files in path/]` |

---

## Anchor Guidelines

Anchors (`start` and `end` fields) must be exact text from the conversation:

- **5-50 words** — enough to be unique, not so long it's fragile
- **Exact copy-paste** — don't modify the text
- **Must be unique** — if text appears multiple times, use longer surrounding context

---

## Sensitivity Categories

| Category | Examples | When to Use |
|----------|----------|-------------|
| `names` | Real names, companies | Always mark real names |
| `health` | Medical conditions, medications, symptoms | Any health discussion |
| `personal` | Private life, relationships, emotions | Private matters |
| `financial` | Dollar amounts, accounts, transactions | Money discussions |

**Terms vs Sections:**
- Use `terms` for individual words/phrases that appear throughout
- Use `sections` for longer passages where context matters

---

## Backmatter Format

After the CONFIG block, add backmatter:

```markdown
---
<!-- === BACKMATTER === -->

## Summary

[2-4 sentences: What is this conversation about? Current state?]

## What Was Discussed

[Narrative arc of the conversation. Scale to substance — brief for simple chats, detailed for complex sessions.]

## Decisions Made

- **[Decision]** — [Why/context]

## Outputs

- [What was created, updated, or produced]

## Open Threads

[Unresolved questions or topics to revisit. Omit section if none.]

## Continuation Context

[Context needed to continue this work. What would someone need to know to pick up where we left off?]
```

---

## Output Instructions (Claude Code)

When the user asks for export:

1. Read the conversation transcript (if available as a file)
2. Analyze for sections to remove and sensitive content
3. Generate the CONFIG block with appropriate fields
4. Generate the backmatter summary
5. **Write the complete file** to `intake/YYYY-MM-DD-slug.md`:
   - CONFIG block at the top
   - Full conversation content
   - Backmatter at the end
6. Report the file path to the user

### File Structure

```markdown
=== EXPORT CONFIG ===
...config...
=== END CONFIG ===

[Full conversation content]

---
<!-- === BACKMATTER === -->

## Summary
...
```

The user can then run `/intake` to canonicalize the file.
