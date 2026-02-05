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
=== Pulling Bot Sessions ===
Content pipeline agents: bruba-main bruba-rex

--- Agent: bruba-main ---
  Pulled: 3 new
  def67890.jsonl -> intake/bruba-main/def67890.md
  ghi12345.jsonl -> intake/bruba-main/ghi12345.md

--- Agent: bruba-rex ---
  Pulled: 1 new
  abc11111.jsonl -> intake/bruba-rex/abc11111.md

bruba-main: 3 new, 24 skipped, 3 converted
bruba-rex: 1 new, 5 skipped, 1 converted
Sessions: 4 new, 29 skipped, 4 converted
```

## Pipeline

Per-agent pull (for agents with `content_pipeline: true` in config.yaml):

```
/pull
  ↓
sessions/{agent}/*.jsonl (raw JSONL, archived per agent)
  ↓ (automatic conversion)
intake/{agent}/*.md (delimited markdown, ready for /convert)
```

## Notes

- Closed sessions are immutable - once pulled, they never change
- Active session is always skipped (still being written)
- Iterates over all agents with `content_pipeline: true`
- Raw JSONL kept in `sessions/{agent}/` for archival
- Delimited markdown written to `intake/{agent}/` for processing
- State tracked per-agent in `sessions/{agent}/.pulled`
- Backward compat: existing `sessions/.pulled` auto-migrates to `sessions/bruba-main/.pulled`

## Next Steps

After pulling, files in `intake/{agent}/` need CONFIG blocks added before canonicalization:
1. `/convert <file>` - AI-assisted CONFIG generation
2. `/intake` - Batch canonicalize files with CONFIG

## Related Skills

- `/sync` - Full pipeline sync (prompts + content)
- `/convert` - Add CONFIG block to intake files
- `/intake` - Batch canonicalize processed files
- `/mirror` - Pull bot's prompt/config files
- `/convo` - Load active conversation
- `/status` - Check current state
