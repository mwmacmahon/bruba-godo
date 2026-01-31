## PKM Knowledge Resources

You have PKM content indexed in your memory from <REDACTED-NAME>'s knowledge management system.

**What's available:**
- **Prompts** — Task-specific instructions (export, transcription, sanitization, etc.)
- **Reference docs** — System architecture, conventions, decision history
- **Summaries** — Past conversation summaries with context
- **Document Inventory** — Categorized list of all docs with descriptions
- **Transcript Inventory** — Past conversations grouped by date/topic

### Key Inventories

Your `memory/` folder contains inventories that serve as indexes to all available content:

| Inventory | What It Lists |
|-----------|---------------|
| `Document Inventory.md` | Master list — all docs synced to your memory |
| `Transcript Inventory.md` | Past conversations by date/topic |
| `Meta - Document Inventory.md` | PKM system documentation |
| `Home - Document Inventory.md` | Home and family docs |
| `Work - Document Inventory.md` | Professional/work docs |

**Use inventories to find relevant docs** before searching broadly. They contain descriptions of each file to help you pick the right one.

### Key Prompts

These prompts provide consistent workflows. Load them when you hit their trigger conditions:

| Prompt | When to Load | Trigger Words |
|--------|--------------|---------------|
| `Prompt - Export.md` | Session wrap-up | "export", "done", "wrap up" |
| `Prompt - Transcription.md` | Voice processing | "transcribe", "dictate" |
| `Prompt - Daily Triage.md` | Morning routine | "triage" |
| `Prompt - Reminders Integration.md` | Task management | (helpful for any reminder work) |

> **Note:** These prompts are synced via the export pipeline. Source of truth:
> - Reusable prompts: `components/distill/prompts/`
> - User content: `reference/`
>
> Bot memory receives the exported versions (`exports/bot/Prompt - *.md`).

**Scope-specific prompts:**
- `Prompt - Home.md` — For home/family conversations
- `Prompt - Work.md` — For professional conversations

When entering a scope-specific conversation, loading the relevant prompt provides consistent conventions.

### What's Synced (and What's Not)

Your `memory/` folder contains **filtered** PKM content:
- **Included:** meta, home, and work scope docs
- **Excluded:** personal scope (intentionally private)
- **Redacted:** Some terms (names, health, financial info)

If you search for something and don't find it, it may be intentionally excluded. Ask <REDACTED-NAME> if you need something that seems to be missing.

### When to Search Memory

- User mentions "export", "done", "wrap up" → search for export prompt
- User mentions "transcript", "cleanup", "dictation" → search for transcription guidance
- User asks "how does X work" about PKM → search reference docs
- User asks about past decisions or context → search summaries
- User asks "what docs do we have about X" → search inventories

**Default behavior:** When uncertain whether PKM content is relevant, search first rather than guessing.

### Token-Conscious Loading

Before loading large files into context, check their size first:

```bash
# Check file size in tokens (rough: chars/4)
wc -c ~/clawd/memory/some-file.md | awk '{print int($1/4) " tokens"}'

# Check directory size
du -sh ~/clawd/memory/

# List files with sizes
ls -la ~/clawd/memory/

# Preview first/last lines without loading full file
head -20 ~/clawd/memory/some-file.md
tail -20 ~/clawd/memory/some-file.md

# Find files containing a keyword (without loading them)
grep -l "keyword" ~/clawd/memory/*.md

# Read a file (use sparingly - loads full content)
cat ~/clawd/memory/some-file.md
```

**Reporting requirement:** When loading any file >2000 tokens, report to the user:
- What file you're loading and why
- Approximate tokens being added

This helps <REDACTED-NAME> track context burn and adjust if needed. For smaller files, load freely without reporting.

### 📚 Inventories — Your Table of Contents

At session start, skim:
- `memory/Document Inventory.md` — docs with descriptions
- `memory/Transcript Inventory.md` — archived conversations with descriptions

This builds your mental map of what's available. When a topic comes up where prior context might help, check the inventory first — the descriptions often tell you if a file is relevant without opening it.

**Loading strategy:**
1. Scan inventory description
2. If promising, read the Summary (if one exists)
3. Only load full transcript/doc if the summary confirms relevance

This keeps context lean while still leveraging your memory.
