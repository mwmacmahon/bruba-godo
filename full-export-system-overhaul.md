# Export System Overhaul Log

Implementing plan from: `memory/packet-stage2.6-transcription-refinement.md`

---

## Phase 1: Directory Restructure

### Task 1: Update assemble-prompts.sh ✓
- Changed `PROMPTS_OUTPUT` from `$ASSEMBLED_DIR/prompts` to `$EXPORTS_DIR/bot/core-prompts`
- Added comment explaining that core-prompts syncs to ~/clawd/ (not memory/)

### Task 2: Update cli.py export paths ✓
- Added `_get_content_subdirectory_and_prefix()` function
- Returns (subdirectory, prefix) tuple based on content type:
  - `('transcripts', 'Transcript - ')` for conversations
  - `('refdocs', 'Refdoc - ')` for reference docs
  - `('docs', 'Doc - ')` for documentation
  - `('artifacts', 'Artifact - ')` for artifacts
- Prompts already had prefix: `('prompts', 'Prompt - ')`
- All content now goes to appropriate subdirectory with type prefix

### Task 3: Update push.sh ✓
- Completely rewrote sync logic to handle multiple subdirectories
- **core-prompts/** → `~/clawd/` (workspace root, for AGENTS.md)
- **prompts/, transcripts/, refdocs/, docs/, artifacts/** → `~/clawd/memory/{subdir}/`
- Added legacy compatibility for root-level files
- Counts synced files per subdirectory

### Task 4: Update lib.sh (in progress)
- Need to keep ASSEMBLED_DIR for now since tests reference it
- Will be cleaned up after tests are updated

---

## Target Structure

```
exports/
  bot/
    core-prompts/        → syncs to ~/clawd/
      AGENTS.md
    prompts/             → syncs to ~/clawd/memory/prompts/
      Prompt - Export.md
      Prompt - Transcription.md
    transcripts/         → syncs to ~/clawd/memory/transcripts/
      Transcript - *.md
    refdocs/             → syncs to ~/clawd/memory/refdocs/
      Refdoc - *.md
    docs/                → syncs to ~/clawd/memory/docs/
      Doc - *.md
    artifacts/           → syncs to ~/clawd/memory/artifacts/
      Artifact - *.md
  claude/
    prompts/
      Prompt - Export.md
```

---

## Phase 2: Prompt Consolidation

### Task 5: Update Transcription.md (pending)
- Expand Bruba Silent Mode section with decision tree

### Task 6: Merge Export prompts (pending)
- Merge Export-Claude.md into Export.md
- Add conditional for file write access

### Task 7: Simplify voice AGENTS.snippet (pending)
- Reduce from 7 to 6 steps

### Task 8: Update exports.yaml (pending)
- Remove profile targeting for Export

---

## Phase 3: Tests & Documentation

### Task 9: Update tests (pending)
### Task 10: Update prompt-sync.md (pending)
### Task 11: Update documentation (pending)
### Task 12: Cleanup assembled/ (pending)

---

## Progress

- [x] assemble-prompts.sh → exports/bot/core-prompts/
- [x] cli.py → subdirectories with prefixes
- [x] push.sh → multi-target sync
- [x] lib.sh → removed ASSEMBLED_DIR
- [x] Transcription.md → expanded silent mode with decision tree
- [x] Export.md ← merged Export-Claude.md (deleted Export-Claude.md)
- [x] voice/AGENTS.snippet.md → simplified 6-step flow
- [x] exports.yaml → no profile targeting (unified prompts)
- [x] Tests updated (40 export + 13 assembly + 10 e2e + 24 python = 87 tests)
- [x] Documentation updated (CLAUDE.md, docs/pipeline.md, tests/README.md, templates/prompts/README.md, components/distill/README.md, README.md, skills)
- [x] assembled/ references removed from config.yaml.example and lib.sh

---

## Final Test Results

```
Python tests:    24 passed
Export tests:    40 passed
Assembly tests:  13 passed, 1 skipped
E2E tests:       10 passed
─────────────────────────────
Total:           87 passed, 1 skipped
```

## Key Decisions Made

1. **Export.md merge** - Merged Export-Claude.md into Export.md with a conditional: "If you have file write access (Claude Code)..." Single file now works for both bot and Claude Code contexts.

2. **Transcription.md scope** - Removed `profile: bot` field so it exports to all profiles. Both bot and Claude profiles now get Transcription.md.

3. **Subdirectory structure** - Content exports to typed subdirectories:
   - `core-prompts/` → AGENTS.md (syncs to ~/clawd/)
   - `prompts/` → Prompt - *.md (syncs to ~/clawd/memory/prompts/)
   - `transcripts/` → Transcript - *.md (syncs to ~/clawd/memory/transcripts/)
   - `refdocs/` → Refdoc - *.md (syncs to ~/clawd/memory/refdocs/)
   - `docs/` → Doc - *.md (syncs to ~/clawd/memory/docs/)

4. **Filename prefixes** - All content types get prefixes: `Prompt - `, `Transcript - `, `Refdoc - `, `Doc - `, `Artifact - `

5. **Voice snippet simplification** - Reduced from 7 steps to 6, more concise with key principles section

6. **Expanded Bruba Silent Mode** - Added decision tree (confident/uncertain × matters/doesn't matter), what to track internally, what to print, example workflow

---

## Post-Overhaul Fix: Conflict Detection Bug

**Date:** 2026-01-31

### The Bug

`detect-conflicts.sh` had a TODO that was never implemented:
```bash
# 2. Check if components were edited by bot
# (This is harder - we'd need to compare component content to what's in mirror)
# For now, we detect if mirror has content that doesn't match any known pattern
```

It only detected **new BOT-MANAGED sections**, not when the bot **edited existing component content**.

**Result:** Bot's changes to the session component were silently overwritten during sync.

### The Fix

1. **Implemented component edit detection** in `detect-conflicts.sh`:
   - Extract each component's content from mirror
   - Compare to source component file
   - Flag as conflict if different

2. **Added hard enforcement** in `assemble-prompts.sh`:
   - Checks for conflicts before assembly
   - Blocks with clear error message if conflicts found
   - `--force` flag to override when intentionally discarding

3. **New tests** in `test-prompt-assembly.sh`:
   - Test 3b: Single component edit detection
   - Test 3c: Multiple component edit detection

### What It Looks Like Now

```
$ ./tools/assemble-prompts.sh

⚠️  CONFLICTS DETECTED - Assembly blocked

Bot has made changes that would be overwritten.
Run './tools/detect-conflicts.sh' to see details.

Options:
  1. Resolve conflicts (see /prompt-sync skill)
  2. Use --force to overwrite bot changes
```

```
$ ./tools/detect-conflicts.sh

⚠️  Conflicts detected: 1

EDITED COMPONENTS (bot modified source component content):

  Component: session
  Source: components/session/prompts/AGENTS.snippet.md

  Options:
    1. Keep bot's version: copy changes to source component
    2. Discard bot's changes: next push will overwrite
    3. Convert to bot-managed: rename to BOT-MANAGED section

  Run: ./tools/detect-conflicts.sh --diff session
```

### Updated Test Results

```
Assembly tests:  17 passed, 1 skipped (was 13)
```

New tests added:
- Component edit detection
- Multiple component edit detection
