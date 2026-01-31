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
# Last prompt sync (check exports/bot/core-prompts/ timestamps)
ls -la exports/bot/core-prompts/*.md 2>/dev/null | head -5

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

# Export files ready (all subdirectories)
find exports/bot -name "*.md" 2>/dev/null | wc -l
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

#### Step 2: Triage & Convert

**2a. Identify trivial files for deletion**

Scan for tiny conversations (≤4 messages OR <800 chars) that are likely heartbeat/test sessions:

```bash
for f in intake/*.md; do
    msgs=$(grep -c "^=== MESSAGE" "$f" 2>/dev/null || echo 0)
    chars=$(wc -c < "$f" | tr -d ' ')
    if [ "$msgs" -le 4 ] || [ "$chars" -lt 800 ]; then
        echo "$f|$msgs|$chars"
    fi
done
```

If trivial files found, present them:
```
=== Trivial Conversations (likely deletable) ===

 #  Msgs  Size   File                    Preview
 1     1    63   57ce03ef...             [Bot greeting only]
 2     2   120   db7cd26d...             "test" / "Pong"
 3     2   180   f33f045c...             [heartbeat check]

Options:
  [D] Delete all trivial files (intake + sessions/)
  [R] Review each one individually
  [S] Skip triage, keep all
```

**2b. Handle files needing CONFIG**

Check for files without CONFIG:
```bash
grep -L "=== EXPORT CONFIG ===" intake/*.md 2>/dev/null
```

If files need CONFIG, show in batches (10 at a time) with auto-config preview:

```bash
python -m components.distill.lib.cli auto-config intake/<files> 2>/dev/null
```

Present as:
```
=== Files Needing CONFIG (batch 1/3) ===

 #  Date        Source   Title (auto-detected)
 1  2026-01-27  bruba    "can you check my reminders for today"
 2  2026-01-27  bruba    "quick question about the API"
...
10  2026-01-28  bruba    "did you read the packet?"

Options:
  [A] Auto-CONFIG this batch (minimal CONFIG, continue)
  [C] Convert interactively (/convert for each)
  [N] Next batch (skip this batch for now)
  [Q] Continue to intake (unconverted files stay in intake/)
```

Unconverted files are fine — they'll just sit in intake/ until the next sync or manual `/convert`.

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

[2/5] Triage & Convert...

  === Trivial Conversations ===
  Found 2 trivial files (≤4 msgs or <800 chars):
    1. abc11111.md (1 msg, 63 chars) - [bot greeting only]
    2. def22222.md (2 msgs, 120 chars) - "test" / "Pong"

  Delete trivial files? [D/r/s]: d
  Deleted 2 trivial files (intake + sessions/)

  === Files Needing CONFIG (batch 1/1) ===
  3 files need CONFIG:
    1. 2026-01-30  bruba  "can you help with the API?"
    2. 2026-01-30  bruba  "quick question about auth"
    3. 2026-01-30  bruba  "project planning discussion"

  Options: [A]uto-CONFIG / [C]onvert / [Q]uit to intake
  User: a

  Applied auto-CONFIG to 3 files

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
