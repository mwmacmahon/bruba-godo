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
./tools/push.sh --dry-run         # See what would sync
./tools/push.sh --verbose         # Detailed output
./tools/push.sh --no-index        # Skip memory reindex
./tools/push.sh --tools-only      # Sync only component tools
./tools/push.sh --update-allowlist # Also update exec-approvals
```

This:
1. Rsyncs `exports/bot/` → Bot's `~/clawd/memory/`
2. Syncs component tools (`components/*/tools/`) → Bot's `~/clawd/tools/`
3. Optionally updates exec-approvals allowlist (with `--update-allowlist`)
4. Triggers `clawdbot memory index` to reindex

## Component Tools

Component tools are automatically synced to the bot's `~/clawd/tools/` directory with executable permissions.

Tools from these components are synced:
- `components/voice/tools/` (tts.sh, whisper-clean.sh, voice-status.sh)
- `components/web-search/tools/` (web-search.sh, ensure-web-reader.sh)
- `components/reminders/tools/` (cleanup-reminders.sh, helpers/)

To sync only tools (skip content):
```bash
./tools/push.sh --tools-only
```

## Exec-Approvals Allowlist

Component tools need exec-approvals entries to be callable by the bot. Use `--update-allowlist` to automatically add missing entries:

```bash
# Sync tools and update allowlist
./tools/push.sh --tools-only --update-allowlist

# Check what entries are needed
./tools/update-allowlist.sh --check

# Update allowlist standalone
./tools/update-allowlist.sh
```

Each component defines required entries in `allowlist.json`:
- `components/voice/allowlist.json`
- `components/web-search/allowlist.json`
- `components/reminders/allowlist.json`

After allowlist changes, restart the daemon: `./tools/bot 'clawdbot daemon restart'`

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
