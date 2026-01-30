# /mirror - Mirror Bot Files

Pull the bot's files locally for backup and reference.

## Instructions

### 1. Run Mirror Script
```bash
./tools/mirror.sh --verbose
```

### 2. Show Results
Report what was mirrored:
- Prompts (AGENTS.md, MEMORY.md, etc.)
- Memory entries (date-prefixed files)
- Config files (tokens redacted)
- Tool scripts

## Arguments

$ARGUMENTS

If `--dry-run` is passed, add `--dry-run` to the script call.

## Example Output

```
=== Mirror ===

Prompts: 6 files
  AGENTS.md, MEMORY.md, USER.md, IDENTITY.md, SOUL.md, TOOLS.md

Memory: 12 entries
  2026-01-15 through 2026-01-29

Config: 2 files (tokens redacted)

Tools: 3 scripts

Total: 23 files mirrored to mirror/
```

## Related Skills

- `/pull` - Pull closed sessions
- `/status` - Check current state
