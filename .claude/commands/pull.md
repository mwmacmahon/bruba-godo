# /pull - Pull Closed Sessions

Pull closed bot sessions and convert to delimited markdown.

## Instructions

### 1. Run Pull Script
```bash
./tools/pull-sessions.sh --verbose
```

### 2. Show Results
Report:
- How many new sessions pulled
- How many skipped (already pulled)
- How many converted to intake/
- Active session (always skipped)

## Arguments

$ARGUMENTS

Options:
- `--dry-run` - Show what would be pulled
- `--force UUID` - Force re-pull a specific session
- `--no-convert` - Skip conversion to markdown (raw JSONL only)

## Example Output

```
=== Pull Sessions ===

Active session: abc12345 (skipping)

Pulled: 3 new sessions
  def67890.jsonl -> intake/def67890.md
  ghi12345.jsonl -> intake/ghi12345.md
  jkl67890.jsonl -> intake/jkl67890.md

Skipped: 24 already pulled

Sessions: 3 new, 24 skipped, 3 converted to intake/
```

## Pipeline

```
/pull
  ↓
sessions/*.jsonl (raw JSONL, archived)
  ↓ (automatic conversion)
intake/*.md (delimited markdown, ready for /convert)
```

## Notes

- Closed sessions are immutable - once pulled, they never change
- Active session is always skipped (still being written)
- Raw JSONL kept in sessions/ for archival
- Delimited markdown written to intake/ for processing
- State tracked in `sessions/.pulled`

## Next Steps

After pulling, files in intake/ need CONFIG blocks added before canonicalization:
1. `/convert <file>` - AI-assisted CONFIG generation
2. `/intake` - Batch canonicalize files with CONFIG

## Related Skills

- `/sync` - Full pipeline sync (prompts + content)
- `/convert` - Add CONFIG block to intake files
- `/intake` - Batch canonicalize processed files
- `/mirror` - Pull bot's prompt/config files
- `/convo` - Load active conversation
- `/status` - Check current state
