# /intake - Batch Canonicalize Intake Files

Process intake files with CONFIG blocks into canonical format.

## Arguments

$ARGUMENTS

Options:
- `--all` - Process all ready files (default: prompt for each)
- `--file <path>` - Process specific file only
- `--skip-triage` - Skip the trivial conversation triage step

## Instructions

### 0. Triage Trivial Conversations (Interactive)

**Before processing**, identify conversations that are likely not worth keeping.

Scan all intake files and categorize as trivial if:
- **≤4 messages** (incomplete exchanges, abandoned sessions)
- **OR total filesize < 800 characters** (very short messages like "test", "hello", "oops")

```bash
# Get message count and size for each file
for f in intake/*.md; do
    msgs=$(grep -c "^=== MESSAGE" "$f" 2>/dev/null || echo 0)
    chars=$(wc -c < "$f")
    session_id=$(basename "$f" .md)
    printf "%s|%d|%d\n" "$session_id" "$msgs" "$chars"
done
```

**If trivial files are found**, present them interactively:

```
=== Trivial Conversation Triage ===

Found X conversations that appear trivial (≤4 messages or <800 chars):

 #  Messages  Size     Session ID                               Preview
 1      1      63      57ce03ef-748c-4355-afc1-bf4228525739     [Bot greeting only, no response]
 2      2      77      db7cd26d-b1da-4f61-bbf5-99471cd9418c     "test ping" / "Pong"
 3      2     111      f33f045c-df79-43c1-bd17-9c0f3bf4a286     [brief exchange]
 ...

Recommendation: Delete these trivial files to reduce clutter.
```

**For each trivial file**, show a preview (first ~200 chars of content) so the user can decide.

**Ask the user:**
- "Delete all X trivial files? [Y/n/review]"
- If "review": Go through each one, asking keep/delete
- If user has questions about any specific file, show full content

**When deleting**, offer choices:
1. **Delete intake only** - Remove from intake/, keep archived JSONL in sessions/
2. **Delete both** (recommended) - Remove intake file AND sessions/*.jsonl to avoid bloat
3. **Move to intake/skipped/** - Keep but exclude from processing

Default recommendation is "delete both" for truly trivial files.

```bash
# Delete both intake and archived JSONL
rm intake/<session-id>.md
rm sessions/<session-id>.jsonl
# Also remove from .pulled tracking
sed -i '' '/^<session-id>$/d' sessions/.pulled
```

**After triage**, continue with remaining files.

---

### 1. Discover Files

Find files in intake/ and categorize them:

```bash
# All intake files
ls intake/*.md 2>/dev/null | wc -l

# Files WITH CONFIG blocks (ready for canonicalization)
grep -l "=== EXPORT CONFIG ===" intake/*.md 2>/dev/null

# Files WITHOUT CONFIG blocks (need /convert first)
grep -L "=== EXPORT CONFIG ===" intake/*.md 2>/dev/null
```

Report:
- X files in intake/
- Y ready for canonicalization (have CONFIG)
- Z need /convert first (no CONFIG)

### 2. Create Directories

Ensure output directories exist:

```bash
mkdir -p reference/transcripts intake/processed intake/split
```

### 3. Check for Large Files & Split if Needed

For each file WITH a CONFIG block, check size:

```bash
wc -c intake/<file>.md
```

**If file > 60,000 characters:** Split along message boundaries:

```bash
python -m components.distill.lib.cli split intake/<file>.md -o intake/ --max-chars 60000
```

This creates:
- `intake/<file>-part-1.md`
- `intake/<file>-part-2.md`
- etc.

Each part:
- Has the CONFIG block with part metadata (`part: 1`, `total_parts: N`)
- Updated slug (`original-slug-part-1`)
- Continuation notes ("Conversation continues in Part N+1")
- Minimum 5 messages per chunk

**After splitting:** Process the part files instead of the original.

### 4. Canonicalize Ready Files

For each file WITH a CONFIG block (or each part file):

```bash
python -m components.distill.lib.cli canonicalize intake/<file>.md \
    -o reference/transcripts/ \
    -c components/distill/config/corrections.yaml \
    --move intake/processed
```

The CLI will:
- Parse the CONFIG block → YAML frontmatter
- Apply transcription corrections from corrections.yaml
- Strip Signal/Telegram wrappers
- Content stays intact (sections_remove applied later at /export)
- Use the slug from CONFIG as the output filename
- Move source file to `intake/processed/` after successful canonicalization

### 6. Report Results

Show summary:
- Files processed: X
- Files split: Y (into Z parts)
- Files skipped (no CONFIG): W
- Output location: reference/transcripts/

For each processed file, show:
- Input: intake/<original>.md
- Output: reference/transcripts/<slug>.md
- Title from CONFIG

### 7. Prompt About Remaining Files

If there are files without CONFIG:

```
Files needing CONFIG blocks:
  - intake/abc12345.md
  - intake/def67890.md

Run `/convert <file>` to add CONFIG blocks.
```

## Error Handling

If canonicalization fails:
1. Show the error message
2. Don't move the file to processed/
3. Suggest checking the CONFIG block format
4. Offer to run parse command to debug:

```bash
python -m components.distill.lib.cli parse intake/<file>.md
```

## Example Session

```
=== /intake ===

Scanning intake/...

Found: 5 files
  Ready: 3 (have CONFIG)
  Need /convert: 2 (no CONFIG)

Checking file sizes...
  abc12345.md: 45,000 chars (OK)
  def67890.md: 125,000 chars (SPLIT NEEDED)
  ghi11111.md: 28,000 chars (OK)

Splitting large files...
  def67890.md -> 2 parts
    -> intake/def67890-part-1.md (msgs 1-47, 62,000 chars)
    -> intake/def67890-part-2.md (msgs 48-89, 63,000 chars)

Processing ready files...

[1/4] abc12345.md
  Title: "Implementing User Authentication"
  -> reference/transcripts/2026-01-28-user-auth.md
  -> moved to intake/processed/

[2/4] def67890-part-1.md
  Title: "Database Schema Discussion (Part 1)"
  -> reference/transcripts/2026-01-27-db-schema-part-1.md
  -> moved to intake/processed/

[3/4] def67890-part-2.md
  Title: "Database Schema Discussion (Part 2)"
  -> reference/transcripts/2026-01-27-db-schema-part-2.md
  -> moved to intake/processed/

[4/4] ghi11111.md
  Title: "Voice Memo Processing"
  -> reference/transcripts/2026-01-26-voice-memo.md
  -> moved to intake/processed/

=== Summary ===
Processed: 4 files (1 was split into 2 parts)
Output: reference/transcripts/

Files still needing CONFIG:
  - intake/jkl22222.md
  - intake/mno33333.md

Run /convert to add CONFIG blocks to these files.
```

## Pipeline Position

```
/pull
  ↓
intake/*.md (delimited markdown)
  ↓
/convert (adds CONFIG + backmatter)
  ↓
intake/*.md (with CONFIG)
  ↓
/intake (this skill - canonicalizes)  ← YOU ARE HERE
  ↓
reference/transcripts/*.md (canonical)
  ↓
/export (filters + redacts)
  ↓
exports/bot/*.md
  ↓
/push
```

## Related Skills

- `/sync` - Full pipeline sync (prompts + content)
- `/convert` - Add CONFIG block to intake files (prerequisite)
- `/pull` - Pull sessions to create intake files
- `/export` - Generate filtered exports from canonical files
- `/push` - Push exports to bot memory
