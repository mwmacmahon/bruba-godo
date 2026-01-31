# /push - Sync Content to Bot

Push filtered content to bot's memory for search.

## Instructions

### 1. Check Reference Content

```bash
# Check what's in reference/
ls -la reference/

# Count markdown files
find reference -name "*.md" -type f | wc -l
```

If no content in `reference/`, inform user they need to add content first.

### 2. Generate Export (if needed)

Check if exports/bot/ exists and is up-to-date:

```bash
ls -la exports/bot/ 2>/dev/null || echo "No export found"
```

If no export or user requests regeneration, the export needs to be built from `reference/` with filters from `exports.yaml`. This is a simplified pipeline — for now, manual copy:

```bash
mkdir -p exports/bot
cp reference/*.md exports/bot/
```

For full filtering/redaction support, a more advanced document processing pipeline would be used.

### 3. Push to Bot

```bash
./tools/push.sh
```

Or with options:
```bash
./tools/push.sh --dry-run    # See what would sync
./tools/push.sh --verbose    # Detailed output
./tools/push.sh --no-index   # Skip memory reindex
```

This:
1. Rsyncs `exports/bot/` → Bot's `~/clawd/memory/`
2. Triggers `clawdbot memory index` to reindex

## Arguments

$ARGUMENTS

## What Gets Synced

Exports are defined in `exports.yaml`:

| Export | Include | Exclude | Redaction |
|--------|---------|---------|-----------|
| bot | scope: meta, reference, transcripts | sensitivity: sensitive, restricted | names, health |

Content in `reference/` with appropriate tags gets filtered into `exports/bot/`.

## Example

```
User: /push

Claude: [generates export, syncs]

Reference files: 12
Export 'bot': 10 files (2 excluded by filters)

=== Starting push ===
Syncing to bruba:~/clawd/memory/...
sent 10 files
Triggering memory reindex...
Memory index updated.
=== Push complete! ===
```

## Verify

Test search from bot via messaging:
> "Search your memory for [topic]"

Or via command line:
```bash
./tools/bot clawdbot memory search "[topic]"
```

## Related Skills

- `/sync` - Full pipeline sync (prompts + content)
- `/pull` - Pull sessions from bot
- `/export` - Generate filtered exports (prerequisite)
- `/mirror` - Mirror bot files locally
- `/status` - Show bot sync status
