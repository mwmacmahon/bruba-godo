# /convert - Add CONFIG Block to Intake File

AI-assisted generation of CONFIG blocks for intake files. **Interactive, one file at a time.**

## Arguments

$ARGUMENTS

The path to a file in `intake/` (without CONFIG). If omitted, show available files and ask which one.

## How It Works

`/convert` does TWO things:

1. **REMOVES noise** from the file — heartbeats, exec denials, system errors are **deleted automatically** before analysis
2. **MARKS content** in CONFIG block — sections_remove, sensitivity are **just marked** (applied later at export)

**CRITICAL:** Noise removal happens automatically with default patterns before the file is sent for analysis. Everything else stays in the file — CONFIG just marks it for processing at export time.

**NOTE:** Use `sections_remove` for walls of text, large code blocks, pasted docs, and log dumps. The `description` field becomes the replacement text.

## Instructions

**IMPORTANT: Context Isolation**

This skill uses `tools/helpers/convert-doc.py` for document analysis to prevent context bloat. The script makes isolated API calls — document content dies when the script exits. CC only sees the analysis results.

CONFIG + backmatter are appended using `tools/helpers/file-bookend.py` — no need to read the file into context just to append.

### 1. Select Target File

If no file specified:

**"convert something" / "convert any" / "just pick one"** → Auto-select the first available file. Don't ask, just proceed.

**"/convert" with no context** → List files and ask which one:

```bash
grep -L "=== EXPORT CONFIG ===" intake/*.md 2>/dev/null
```

Show a numbered list with message count and size.

### 2. Remove Noise (Automatic)

Run noise removal with default patterns **before** analysis. This cleans up heartbeats, system errors, and pings so the analyzer sees clean content.

```bash
python3 tools/helpers/remove-noise.py intake/<file>.md
```

Report the result briefly:
```
🗑️  Noise removed: N messages (heartbeats, errors, pings)
```

If nothing was removed, skip the message and proceed silently.

### 3. Analyze via Script

Show file info header, then run analysis:

```
📄 intake/<session-id>.md (N KB)
   View: code intake/<session-id>.md
```

**DO NOT read the file directly.** Call the conversion script:

```bash
python3 tools/helpers/convert-doc.py intake/<file>.md "Analyze this conversation for CONFIG block generation.

Identify and report:

1. SECTIONS TO REMOVE (mark in CONFIG):
   - Debugging tangents, off-topic discussions
   - Walls of text, large code blocks, pasted docs
   - Failed attempts
   Format: msg range, type, description (will be replacement text)

2. SENSITIVITY:
   - Terms by category: names, health, personal, financial
   - Sections with sensitive content
   Format: category → [terms] or msg range + tags

3. METADATA:
   - Suggested title
   - Date (from timestamps)
   - Source (bruba/claude-projects/claude-code/voice-memo)
   - Tags

4. ARTIFACTS:
   - Large pasted content, code blocks, logs
   Format: type, size, recommendation (remove/keep)

Output as structured analysis table.

Note: Noise (heartbeats, system errors, pings) has already been removed automatically."
```

Parse the script output to extract findings.

**If script fails:**
- Report the error to user and STOP
- Do NOT fall back to reading the file directly — that defeats context isolation
- User must fix script/config before proceeding
- Common issues: missing ANTHROPIC_API_KEY, wrong .env path, network errors

**Automatic (handled by canonicalize):**
- Signal/Telegram wrappers (`[Signal Michael id:... 2026-01-28 ...]`) → stripped automatically
- Transcription fixes → applied from `corrections.yaml`

### 4. Show Analysis Table

Present findings in a clear table format:

```
=== Conversion Analysis: <session-id> ===

📋 SUMMARY
   Title: "Proposed Title Here"
   Description: "One-line summary for inventory"
   Date: 2026-01-28
   Source: bruba
   Tags: [tag1, tag2, tag3]

✂️  SECTIONS TO REMOVE (N found) — marked in CONFIG, replaced with description at export
   #  Location     Type           Description
   1  msgs 15-18   tangent        "Debugging path issue"
   2  msgs 30-35   off-topic      "Unrelated discussion"
   3  msg 6        pasted-docs    "[Pasted documentation: Section 2.5 ...]"
   4  msg 22       code-block     "[Code: 45 lines bash - debug output]"

🔒 SENSITIVITY: TERMS (by category) — marked in CONFIG, redacted per export profile
   Category   Terms
   names      [Michael]
   health     (none)
   personal   (none)
   financial  (none)

🔒 SENSITIVITY: SECTIONS (N found)
   #  Location     Tags       Description
   1  msgs 20-25   [health]   "Medical appointment discussion"

📦 ARTIFACTS (N found) — for reference, already included in sections_remove above
   #  Type           Size     Notes
   1  documentation  1.5K     "Section 2.5 docs" → sections_remove #3
   2  continuation   800ch    "Session state packet" → keep (small)
```

### 5. Batched Approval

**Use ONE AskUserQuestion to approve all categories at once.** Do NOT ask serial questions.

After showing the analysis table, use AskUserQuestion with up to 2 questions (one per category that has findings):

```
questions:
  - question: "Approve sections_remove? (N items marked for export filtering)"
    header: "Sections"
    options:
      - label: "Approve all"
        description: "Mark sections for removal at export time"
      - label: "Skip"
        description: "Don't mark any sections"
      - label: "Edit"
        description: "Modify the list"

  - question: "Approve sensitivity terms? (terms: [list])"
    header: "Sensitivity"
    options:
      - label: "Approve all"
        description: "Mark terms for redaction per export profile"
      - label: "Skip"
        description: "No sensitivity marking"
      - label: "Edit"
        description: "Modify term list"
```

If user selects "Edit" for any category, ask ONE follow-up for just that category.

**Skip categories with no findings** — don't ask about empty categories.

### 6. Generate CONFIG Block via Script

After user approval of findings, call the script to generate the CONFIG block. Pass the approved decisions in the prompt:

```bash
python3 tools/helpers/convert-doc.py intake/<file>.md "Generate CONFIG block with:
- title: <approved>
- date: <approved>
- source: <approved>
- tags: <approved>
- sections_remove: <approved list with anchors>
- sensitivity: <approved terms/sections>

Use exact anchors from the document (5-50 words, unique).
Output ONLY the CONFIG block in this format:

=== EXPORT CONFIG ===
title: ...
description: ...
slug: YYYY-MM-DD-topic-slug
...
=== END CONFIG ==="
```

Expected CONFIG format:

```yaml
=== EXPORT CONFIG ===
title: "Final Title"
description: "One-line summary for inventory display"
slug: YYYY-MM-DD-topic-slug
date: YYYY-MM-DD
source: bruba
tags: [tag1, tag2]

sections_remove:
  - start: "First 5-50 words of section start..."
    end: "First 5-50 words of section end..."
    description: "Why removed OR replacement text"

sensitivity:
  terms:
    names: [Michael]
  sections:
    - start: "Start anchor text..."
      end: "End anchor text..."
      tags: [health]
      description: "Medical appointment discussion"
=== END CONFIG ===
```

### 7. Generate Backmatter via Script

Call the script to generate the summary backmatter:

```bash
python3 tools/helpers/convert-doc.py intake/<file>.md "Generate BACKMATTER summary for this conversation.

Output in this exact format:

---
<!-- === BACKMATTER === -->

## Summary
[2-4 sentences: What is this about? Current state?]

## What Was Discussed
[Narrative arc. Scale to substance.]

## Decisions Made
- **[Decision]** — [Why]

## Outputs
- [What was created/updated]

## Open Threads
[Unresolved questions. Omit section if none.]

## Continuation Context
[Context for future work on this topic]"
```

### 8. Show and Apply CONFIG

Display the complete CONFIG block and backmatter, then append to file using the bookend tool:

```
=== APPLYING CONFIG + BACKMATTER ===

[show full CONFIG block]

---
[show full backmatter]
```

**Do NOT ask for another approval here** — the batch approval in step 5 already covered this. Just show what's being added and append it.

**Append using file-bookend.py** (avoids reading file into context):

```bash
cat <<'EOF' | python3 tools/helpers/file-bookend.py intake/<file>.md

=== EXPORT CONFIG ===
...config content...
=== END CONFIG ===

---
<!-- === BACKMATTER === -->
...backmatter content...
EOF
```

**Do NOT use Edit tool here** — that requires reading the file first, which defeats context isolation.

### 9. Verify

```bash
python -m components.distill.lib.cli parse intake/<file>
```

Report success and suggest next steps.

---

## Source Detection

| Indicator | Source |
|-----------|--------|
| `[Signal ... id:...]` markers | bruba |
| `[Telegram ... id:...]` markers | bruba |
| Standard bookmarklet format | claude-projects |
| CLI output, tool calls | claude-code |
| Wall-of-text dictation | voice-memo |

---

## Anchor Guidelines

Anchors must be exact text from the content:

- **5-50 words** (enough to be unique, not fragile)
- **Exact copy-paste** from content
- **Unique** in the document

If anchor appears multiple times, use longer surrounding text.

---

## Sections Remove: Replacement Patterns

Use `description` field as the replacement text:

| Content Type | Replacement Pattern |
|--------------|---------------------|
| Pasted docs | `[Pasted documentation: topic summary]` |
| Large code block | `[Code: N lines lang - what it does]` |
| Log dump | `[Log output: N lines - what it shows]` |
| Debug tangent | Brief description, e.g. "Debugging path issue" |
| Off-topic | Brief description, e.g. "Unrelated discussion about X" |

---

## Sensitivity Categories

| Category | Examples | Typical Redaction |
|----------|----------|-------------------|
| `health` | Medical conditions, medications | work, bot |
| `personal` | Private life, relationships | work |
| `names` | Real names, companies | work, bot |
| `financial` | Dollar amounts, accounts | work, bot |

Terms are marked in CONFIG; redaction happens per export profile in `exports.yaml`.

---

## Related Skills

- `/sync` - Full pipeline sync (prompts + content)
- `/pull` - Pull sessions (creates intake files)
- `/intake` - Batch canonicalize files with CONFIG
- `/export` - Generate filtered exports
