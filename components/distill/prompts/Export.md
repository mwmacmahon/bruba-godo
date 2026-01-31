---
type: prompt
scope: meta
profile: bot
title: "Export Prompt"
output_name: "Export"
---

# Export Prompt

Generate a CONFIG block and backmatter for this conversation.

## When to Use

Trigger words: "export", "done", "wrap up", "finished", end of session.

## What You'll Generate

1. **CONFIG block** — metadata for processing (filtering, redaction, section removal)
2. **Backmatter** — summary, decisions, outputs, continuation context

Output these at the end of your response. The user will copy the conversation (including your output) into the intake pipeline.

---

## CONFIG Block Format (V2)

```yaml
=== EXPORT CONFIG ===
title: "Descriptive Title"
slug: YYYY-MM-DD-topic-slug
date: YYYY-MM-DD
source: bruba | claude-projects | claude-code | voice-memo
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
| `source` | Yes | Where this came from (see Source Detection) |
| `tags` | Yes | Topical tags for categorization |
| `sections_remove` | No | Sections to replace with description at export |
| `sensitivity.terms` | No | Individual sensitive terms by category |
| `sensitivity.sections` | No | Longer passages with sensitive content |

---

## Source Detection

Determine the `source` field from conversation format:

| Indicator | Source |
|-----------|--------|
| `[Signal ... id:...]` markers | `bruba` |
| `[Telegram ... id:...]` markers | `bruba` |
| Standard bookmarklet format (Claude.ai export) | `claude-projects` |
| CLI output, tool calls, file edits | `claude-code` |
| Wall-of-text dictation, transcription | `voice-memo` |

---

## Sections Remove

Use `sections_remove` for content that should be replaced with a summary at export time. The `description` field becomes the replacement text.

### When to Mark for Removal

- Debugging tangents (brief dead ends)
- Off-topic discussions
- Failed attempts that don't add value
- Walls of text (pasted documentation)
- Large code blocks
- Log dumps

### Replacement Patterns

| Content Type | Description Pattern |
|--------------|---------------------|
| Pasted docs | `[Pasted documentation: topic summary]` |
| Large code block | `[Code: N lines lang - what it does]` |
| Log dump | `[Log output: N lines - what it shows]` |
| Debug tangent | Brief description, e.g. "Debugging path issue" |
| Off-topic | Brief description, e.g. "Unrelated discussion about X" |

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

## Complete Example

```yaml
=== EXPORT CONFIG ===
title: "Setting Up Export Pipeline"
slug: 2026-01-31-export-pipeline-setup
date: 2026-01-31
source: claude-projects
tags: [pkm, pipeline, export, config]

sections_remove:
  - start: "Let me try a different approach to parsing"
    end: "Okay that didn't work either"
    description: "Debugging YAML parser issue"
  - start: "Here's the full error log from the failed run"
    end: "End of error output"
    description: "[Log output: 45 lines - parser stack trace]"

sensitivity:
  terms:
    names: [Michael, Acme Corp]
=== END CONFIG ===

---
<!-- === BACKMATTER === -->

## Summary

Set up the export pipeline for converting conversations to canonical format. Created CONFIG block spec and integrated with intake workflow.

## What Was Discussed

Started with requirements for the export format. Worked through V2 CONFIG structure, settled on anchor-based section marking. Debugged parser issues with nested YAML. Finalized the backmatter template.

## Decisions Made

- **Anchor-based sections** — More robust than line numbers, survives edits
- **Separate terms vs sections** — Terms for find/replace, sections for context-aware handling

## Outputs

- CONFIG block V2 specification
- Backmatter template
- Updated parser to handle nested sensitivity blocks

## Continuation Context

Parser now handles V2 format. Next step is updating the export profiles in exports.yaml to use the new sensitivity categories.
```

---

## Output Instructions

When the user asks for export:

1. Analyze the conversation for sections to remove and sensitive content
2. Generate the CONFIG block with appropriate fields
3. Generate the backmatter summary
4. Output both at the end of your response

The user will copy the full conversation (including your output) into a file for processing.
