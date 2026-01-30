# /pull - Pull Closed Sessions

Pull closed bot sessions locally as JSONL files.

## Instructions

### 1. Run Pull Script
```bash
./tools/pull-sessions.sh --verbose
```

### 2. Show Results
Report:
- How many new sessions pulled
- How many skipped (already pulled)
- Active session (always skipped)

## Arguments

$ARGUMENTS

Options:
- `--dry-run` - Show what would be pulled
- `--force UUID` - Force re-pull a specific session

## Example Output

```
=== Pull Sessions ===

Active session: abc12345 (skipping)

Pulled: 3 new sessions
  2026-01-28-def67890.jsonl
  2026-01-27-ghi12345.jsonl
  2026-01-26-jkl67890.jsonl

Skipped: 24 already pulled

Sessions saved to: sessions/
```

## Notes

- Closed sessions are immutable - once pulled, they never change
- Active session is always skipped (still being written)
- Sessions are saved as raw JSONL (no conversion)
- State tracked in `sessions/.pulled`

## Related Skills

- `/mirror` - Pull bot's prompt/config files
- `/convo` - Load active conversation
- `/status` - Check current state
