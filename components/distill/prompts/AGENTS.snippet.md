## PKM Knowledge Resources

You have PKM content indexed in your memory from ${HUMAN_NAME}'s knowledge management system.

**What's available:** Prompts, reference docs, summaries, and inventories (Document Inventory, Transcript Inventory).

### Key Inventories

| Inventory | What It Lists |
|-----------|---------------|
| `Document Inventory.md` | All docs synced to memory |
| `Transcript Inventory.md` | Past conversations by date/topic |

**Use inventories first** — descriptions help you pick the right file without opening it.

### Key Prompts

| Prompt | Trigger |
|--------|---------|
| `Prompt - Export.md` | "export", "wrap up" |
| `Prompt - Transcription.md` | "transcribe", "dictate" |
| `Prompt - Daily Triage.md` | "triage" |

### What's Synced

- **Included:** meta, home, work scope docs
- **Excluded:** personal scope (private)
- **Redacted:** names, health, financial info

### When to Search Memory

- "export", "wrap up" → search for export prompt
- "transcript", "dictation" → transcription guidance
- Past decisions/context → search summaries
- **Default:** When uncertain, search first rather than guessing.

### Token-Conscious Loading

Before loading large files, check size (divide bytes by 4 for rough token count):

```bash
/usr/bin/wc -c ${WORKSPACE}/memory/some-file.md
/bin/ls -la ${WORKSPACE}/memory/
/usr/bin/head -20 ${WORKSPACE}/memory/some-file.md
```

**Report files >2000 tokens** to user before loading (what and why).
