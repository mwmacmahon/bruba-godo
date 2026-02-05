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

Scan all intake files (across per-agent subdirs) and categorize as trivial if:
- **≤4 messages** (incomplete exchanges, abandoned sessions)
- **OR total filesize < 800 characters** (very short messages like "test", "hello", "oops")

```bash
# Get message count and size for each file (scan per-agent subdirs)
for f in intake/*/*.md intake/*.md; do
    [ -f "$f" ] || continue
    msgs=$(grep -c "^=== MESSAGE" "$f" 2>/dev/null || echo 0)
    chars=$(wc -c < "$f")
    printf "%s|%d|%d\n" "$f" "$msgs" "$chars"
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
# Delete both intake and archived JSONL (use per-agent paths)
rm intake/<agent>/<session-id>.md
rm sessions/<agent>/<session-id>.jsonl
# Also remove from .pulled tracking
sed -i '' '/^<session-id>$/d' sessions/<agent>/.pulled
```

**After triage**, continue with remaining files.

---

### 1. Discover Files

Find files across per-agent intake subdirs and categorize them:

```bash
# All intake files (per-agent subdirs + legacy flat)
find intake -name "*.md" -not -path "*/processed/*" -not -path "*/split/*" -not -path "*/skipped/*" 2>/dev/null

# Files WITH CONFIG blocks (ready for canonicalization)
grep -rl "=== EXPORT CONFIG ===" intake/*/  intake/*.md 2>/dev/null

# Files WITHOUT CONFIG blocks (need /convert first)
grep -rL "=== EXPORT CONFIG ===" intake/*/ intake/*.md 2>/dev/null
```

Report per agent:
- X files in intake/{agent}/
- Y ready for canonicalization (have CONFIG)
- Z need CONFIG (no CONFIG block)

### 1.5 Handle Files Without CONFIG

For files WITHOUT CONFIG blocks, show auto-detection results:

```bash
python -m components.distill.lib.cli auto-config intake/<files-without-config>
```

This detects source type and extracts metadata. Present findings:

```
=== Files Without CONFIG ===

#  Filename               Source           Title (auto)
1  abc12345.md            bruba            "Discussion about..."
2  bookmarklet.md         claude-projects  "API Design Session"
3  voice-memo-01.md       voice-memo       "Project update notes"

Options:
  [A] Apply auto-CONFIG to all and continue to canonicalize
  [S] Select which to auto-CONFIG (others need /convert)
  [C] Route all to /convert for full AI-assisted CONFIG
  [Q] Skip files without CONFIG for now
```

**Source detection patterns:**
- `bruba` — Has `[Signal ... id:...]` or `[Telegram ... id:...]` markers
- `voice-memo` — Contains `[Transcript]` or `[attached audio file`
- `claude-projects` — Default (no Bruba or voice markers)

If user selects **[A]** or **[S]**:

```bash
python -m components.distill.lib.cli auto-config intake/<file>.md --apply
```

Auto-generated CONFIG uses:
- **title**: First ~60 chars of first user message, or "Untitled"
- **slug**: `{YYYY-MM-DD}-{sanitized-title}`
- **date**: From Signal timestamp, filename pattern, or today
- **source**: Auto-detected
- **tags**: `[]` (empty)
- **sections_remove**: `[]` (empty)

**Note:** Auto-CONFIG is minimal. For conversations needing summaries, section removal, or transcription fixes, route to `/convert` instead.

After applying auto-CONFIG, continue to step 2 (canonicalize).

### 2. Create Directories

Ensure output directories exist:

```bash
mkdir -p reference/transcripts
# Per-agent processed dirs
for agent_dir in intake/*/; do
    [ -d "$agent_dir" ] && mkdir -p "${agent_dir}processed" "${agent_dir}split"
done
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

For each file WITH a CONFIG block (or each part file), pass `--agent` to set the `agents:` frontmatter field:

```bash
# For files in intake/{agent}/ subdirs, detect agent from path
python -m components.distill.lib.cli canonicalize intake/<agent>/<file>.md \
    --agent <agent> \
    -o reference/transcripts/ \
    -c components/distill/config/corrections.yaml \
    --move intake/<agent>/processed
```

For files in the legacy flat `intake/` dir (no agent subdir), default to `--agent bruba-main`.

The CLI will:
- Parse the CONFIG block → YAML frontmatter
- Set `agents: [<agent>]` if not already in CONFIG
- Apply transcription corrections from corrections.yaml
- Strip Signal/Telegram wrappers
- Content stays intact (sections_remove applied later at /export)
- Use the slug from CONFIG as the output filename
- Move source file to `intake/{agent}/processed/` after successful canonicalization

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
intake/{agent}/*.md (delimited markdown, per agent)
  ↓
/convert (adds CONFIG + backmatter, including agents: field)
  ↓
intake/{agent}/*.md (with CONFIG)
  ↓
/intake (this skill - canonicalizes with --agent)  ← YOU ARE HERE
  ↓
reference/transcripts/*.md (canonical, agents: in frontmatter)
  ↓
/export (routes to per-agent exports via agents: frontmatter)
  ↓
exports/bot/{agent}/*.md
  ↓
/push (syncs content_pipeline agents)
```

## Related Skills

- `/sync` - Full pipeline sync (prompts + content)
- `/convert` - Add CONFIG block to intake files (prerequisite)
- `/pull` - Pull sessions to create intake files
- `/export` - Generate filtered exports from canonical files
- `/push` - Push exports to bot memory
