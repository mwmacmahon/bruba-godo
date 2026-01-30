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

### 2. Generate Bundle (if needed)

Check if bundles/bot/ exists and is up-to-date:

```bash
ls -la bundles/bot/ 2>/dev/null || echo "No bundle found"
```

If no bundle or user requests regeneration, the bundle needs to be built from `reference/` with filters from `bundles.yaml`. This is a simplified pipeline — for now, manual copy:

```bash
mkdir -p bundles/bot
cp reference/*.md bundles/bot/
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
1. Rsyncs `bundles/bot/` → Bot's `~/clawd/memory/`
2. Triggers `clawdbot memory index` to reindex

## Arguments

$ARGUMENTS

## What Gets Synced

Bundles are defined in `bundles.yaml`:

| Bundle | Include | Exclude | Redaction |
|--------|---------|---------|-----------|
| bot | scope: meta, reference | sensitivity: sensitive, restricted | names, health |

Content in `reference/` with appropriate tags gets filtered into `bundles/bot/`.

## Example

```
User: /push

Claude: [generates bundle, syncs]

Reference files: 12
Bundle 'bot': 10 files (2 excluded by filters)

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

- `/pull` - Pull sessions from bot
- `/mirror` - Mirror bot files locally
- `/status` - Show bot sync status
