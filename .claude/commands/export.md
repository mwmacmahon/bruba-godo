# /export - Generate Filtered Exports

Generate filtered and redacted exports from canonical transcripts.

## Arguments

$ARGUMENTS

Options:
- `--profile <name>` - Run specific profile only (default: all)
- `--dry-run` - Show what would be exported without writing

## Instructions

### 1. Run Export Command

For all profiles:
```bash
python -m components.distill.lib.cli export --verbose
```

For specific profile:
```bash
python -m components.distill.lib.cli export --profile bot --verbose
```

### 2. Report Results

Show for each profile:
- How many files processed
- How many files skipped (filtered out)
- Output location
- Redaction categories applied

## Export Profiles

Profiles are defined in `exports.yaml`:

```yaml
exports:
  bot:
    description: "Content synced to bot memory"
    output_dir: exports/bot
    remote_path: memory
    include:
      scope: [meta, reference, transcripts]
    exclude:
      sensitivity: [sensitive, restricted]
    redaction: [names, health]

  rag:
    description: "Content for external RAG systems"
    output_dir: exports/rag
    include:
      scope: [reference, transcripts]
    format: chunked
```

### Filter Rules

**include.scope** - File must match at least one scope:
- `transcripts` - All canonical transcript files (always matches)
- `reference` - Files tagged as reference material
- `meta` - Meta/documentation files

**include.tags** - File must have at least one of these tags

**exclude.sensitivity** - Skip files with these sensitivity levels:
- `sensitive` - Marked as sensitive
- `restricted` - Highly restricted content

### Sections Remove

The `sections_remove` entries from each file's frontmatter are applied:
- Content between `start` and `end` anchors is removed
- Replaced with `[Removed: description]`
- Use for walls of pasted text, large code blocks, debug tangents

### Redaction

Categories specified in `redaction` list are redacted:
- `names` - Personal names
- `health` - Medical/health information
- `personal` - Personal details (addresses, etc.)
- `financial` - Financial information

Redaction uses the `sensitivity.terms` defined in each file's frontmatter.

## Example Output

```
=== /export ===

Found 12 canonical files in reference/transcripts/

=== Profile: bot ===
  Content synced to bot memory

  Processing...
    2026-01-28-user-auth.md -> exports/bot/
    2026-01-27-db-schema.md -> exports/bot/
    Skip (filtered): 2026-01-26-health-notes.md  # excluded: sensitive

  Processed: 11, Skipped: 1
  Redaction: names, health
  Output: exports/bot/

=== Profile: rag ===
  Content for external RAG systems

  Processing...
    2026-01-28-user-auth.md -> exports/rag/
    ...

  Processed: 10, Skipped: 2
  Output: exports/rag/

Export complete.
```

## Pipeline Position

```
/pull
  ↓
intake/*.md
  ↓
/convert
  ↓
intake/*.md (with CONFIG)
  ↓
/intake
  ↓
reference/transcripts/*.md
  ↓
/export (this skill)  ← YOU ARE HERE
  ↓
exports/bot/*.md (filtered + redacted)
  ↓
/push
  ↓
bot memory
```

## Verification

After export, verify output:

```bash
# Check export counts
ls exports/bot/*.md | wc -l
ls exports/rag/*.md | wc -l

# Spot-check redaction worked
grep -l "\[REDACTED\]" exports/bot/*.md
```

## Related Skills

- `/sync` - Full pipeline sync (prompts + content)
- `/intake` - Canonicalize intake files (prerequisite)
- `/push` - Push exports to bot memory
- `/prompt-sync` - Prompt assembly only
