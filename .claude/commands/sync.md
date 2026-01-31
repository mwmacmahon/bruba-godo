# /sync - Full Pipeline Sync

Runs full sync: prompts + content pipeline. No menu, just runs everything.

## Instructions

### 1. Prompt Sync

Run `/prompt-sync` (mirror → conflict detection → assemble → push).

### 2. Content Pipeline

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

If files need CONFIG, show full list with date column:

```bash
for f in intake/*.md; do
    msgs=$(grep -c "^=== MESSAGE" "$f" 2>/dev/null || echo 0)
    size=$(wc -c < "$f" | tr -d ' ')
    name=$(basename "$f" .md | cut -c1-12)
    # Extract date from file (look for timestamp in header)
    date=$(grep -m1 "^Date:" "$f" 2>/dev/null | cut -d' ' -f2 || echo "unknown")
    printf "%s  %s  %3d msgs  %6d\n" "$name" "$date" "$msgs" "$size"
done
```

Present as:
```
=== Files Needing CONFIG (25 files) ===

 #  Session       Date        Msgs   Size
 1  867bb508...   2026-01-28     5   1.3K
 2  9bd86045...   2026-01-29    63  29.7K
 3  a05bd263...   2026-01-29    34  10.1K
...

Options:
  [A] Auto-CONFIG subset (specify files or search criteria)
  [C] Convert document-by-document (clears context between each)
  [S] Skip (leave unconverted, continue pipeline)
```

**Note:** Unconverted files stay in intake/ until next sync or manual `/convert`.

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

### 3. Summary

Show brief summary of what was synced.

## Related Skills

- `/prompt-sync` - Prompt assembly only (detailed conflict resolution)
- `/pull` - Pull sessions only
- `/convert` - Convert single file (AI-assisted CONFIG)
- `/intake` - Batch canonicalize
- `/export` - Generate exports
- `/push` - Push to bot memory
- `/status` - Quick bot status check
