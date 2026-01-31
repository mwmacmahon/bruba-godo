# /sync - Full Pipeline Sync

Unified sync command for prompts and content pipeline. Interactive menu to choose what to sync.

## Arguments

$ARGUMENTS

Options:
- `--prompts` - Run prompt sync only (same as `/prompt-sync`)
- `--content` - Run content pipeline only
- `--all` - Run both without prompting
- `--status` - Show status only, no sync

## Instructions

### 1. Gather Status

Run these checks in parallel:

**Prompts status:**
```bash
# Last prompt sync (check assembled/ timestamps)
ls -la assembled/prompts/*.md 2>/dev/null | head -5

# Check for pending prompt changes
./tools/detect-conflicts.sh --quiet 2>/dev/null || echo "conflicts unknown"
```

**Content pipeline status:**
```bash
# Files in intake/ (pending)
ls intake/*.md 2>/dev/null | wc -l

# Files needing CONFIG
grep -L "=== EXPORT CONFIG ===" intake/*.md 2>/dev/null | wc -l

# Files ready for canonicalization
grep -l "=== EXPORT CONFIG ===" intake/*.md 2>/dev/null | wc -l

# Canonical files
ls reference/transcripts/*.md 2>/dev/null | wc -l

# Export files ready
ls exports/bot/*.md 2>/dev/null | wc -l
```

### 2. Show Status Dashboard

Present current state:

```
=== Sync Status ===

PROMPTS
  Last sync: [timestamp or "never"]
  Pending: [conflicts detected / clean / unknown]

CONTENT PIPELINE
  intake/           [N] files
    - Ready:        [X] (have CONFIG)
    - Need convert: [Y] (no CONFIG)
  reference/        [Z] canonical files
  exports/bot/      [W] export files

OPTIONS
  [1] Prompts only     — assemble + push prompts
  [2] Content only     — pull → convert → intake → export → push
  [3] Full sync        — both prompts and content
  [4] Status only      — (shown above, done)
```

### 3. Handle User Choice

Based on argument or user selection:

**[1] Prompts only** → Run `/prompt-sync`
- This runs the full prompt assembly pipeline
- Mirror → conflict detection → assemble → push

**[2] Content only** → Run content pipeline steps
- Follow the content pipeline below

**[3] Full sync** → Run both
- First: `/prompt-sync`
- Then: Content pipeline

**[4] Status only** → Done
- Already shown above, exit

### 4. Content Pipeline

When running content sync, follow these steps in order:

#### Step 1: Pull new sessions

```bash
./tools/pull-sessions.sh --verbose
```

Report: new sessions pulled, converted to intake/

#### Step 2: Convert files needing CONFIG

Check for files without CONFIG:
```bash
grep -L "=== EXPORT CONFIG ===" intake/*.md 2>/dev/null
```

If files need CONFIG:
```
Files needing CONFIG:
  1. intake/abc12345.md (45 messages, 12KB)
  2. intake/def67890.md (23 messages, 8KB)

Options:
  1. Convert all interactively (recommended)
  2. Skip conversion, continue with ready files
  3. Stop here
```

If user chooses to convert:
- Run `/convert` for each file interactively
- User reviews and approves each CONFIG

#### Step 3: Canonicalize ready files

```bash
# Check what's ready
grep -l "=== EXPORT CONFIG ===" intake/*.md 2>/dev/null
```

If files are ready:
```bash
python -m components.distill.lib.cli canonicalize intake/<file>.md \
    -o reference/transcripts/ \
    -c components/distill/config/corrections.yaml \
    --move intake/processed
```

#### Step 4: Generate exports

```bash
python -m components.distill.lib.cli export --profile bot --verbose
```

#### Step 5: Push to bot memory

```bash
./tools/push.sh --verbose
```

### 5. Summary

Show final summary:

```
=== Sync Complete ===

PROMPTS: [synced / skipped]
  - Assembled: X files
  - Pushed to: bruba:/Users/bruba/clawd/

CONTENT: [synced / skipped]
  - Pulled: N new sessions
  - Converted: X files
  - Canonicalized: Y files
  - Exported: Z files (profile: bot)
  - Pushed to: bruba:/Users/bruba/clawd/memory/
```

## Example Session

```
User: /sync

Claude:
=== Sync Status ===

PROMPTS
  Last sync: 2026-01-30 14:23
  Pending: clean (no conflicts)

CONTENT PIPELINE
  intake/           3 files
    - Ready:        1 (have CONFIG)
    - Need convert: 2 (no CONFIG)
  reference/        12 canonical files
  exports/bot/      10 export files

OPTIONS
  [1] Prompts only     — assemble + push prompts
  [2] Content only     — pull → convert → intake → export → push
  [3] Full sync        — both prompts and content
  [4] Status only      — (shown above, done)

User: 3

Claude: Running full sync...

=== Prompts ===
[runs /prompt-sync]
Mirror: 15 files
Conflicts: none
Assembled: AGENTS.md (18 sections)
Pushed to bot.

=== Content Pipeline ===

[1/5] Pulling sessions...
  Pulled: 1 new session → intake/ghi11111.md
  Skipped: 24 already pulled

[2/5] Converting files...
  Files needing CONFIG: 3
    1. intake/abc12345.md
    2. intake/def67890.md
    3. intake/ghi11111.md

  Options:
    1. Convert all interactively
    2. Skip conversion, continue with ready files
    3. Stop here

  User: 1

  [runs /convert for each, user approves]

[3/5] Canonicalizing...
  3 files ready
  → reference/transcripts/2026-01-30-topic-a.md
  → reference/transcripts/2026-01-30-topic-b.md
  → reference/transcripts/2026-01-30-topic-c.md

[4/5] Exporting...
  Profile: bot
  Processed: 15 files
  Skipped: 2 (filtered)
  → exports/bot/

[5/5] Pushing to bot...
  Synced 13 files
  Memory reindexed.

=== Sync Complete ===

PROMPTS: synced
  - Assembled: 8 files
  - Pushed to: bruba:/Users/bruba/clawd/

CONTENT: synced
  - Pulled: 1 new session
  - Converted: 3 files
  - Canonicalized: 3 files
  - Exported: 13 files
  - Pushed to: bruba:/Users/bruba/clawd/memory/
```

## Quick Sync (No Prompts)

For content-only sync with defaults:
```
/sync --content
```

For prompts-only sync:
```
/sync --prompts
```

## Related Skills

- `/prompt-sync` - Prompt assembly only (detailed conflict resolution)
- `/pull` - Pull sessions only
- `/convert` - Convert single file (AI-assisted CONFIG)
- `/intake` - Batch canonicalize
- `/export` - Generate exports
- `/push` - Push to bot memory
- `/status` - Quick bot status check
