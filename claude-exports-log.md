# Export Pipeline Implementation Log

Date: 2026-01-31

## Original Goal

1. Get the export prompt synced to Bruba's memory as `Prompt - Export.md`
2. Create a Claude Projects variant in a new `claude` export profile
3. Identify missing supporting prompts (transcription, triage, etc.)

---

## Initial Understanding (Incorrect)

I initially understood the sync paths as:
```
prompt-sync: components/AGENTS.snippet.md → assembled/AGENTS.md → bot ~/clawd/
push:        reference/ → exports/bot/ → bot ~/clawd/memory/
```

And assumed task prompts like `Prompt - Export.md` needed to be manually copied in push.sh.

---

## Changes Made (Session 1)

### 1. Modified `tools/push.sh`

Added prompt-copying logic before the rsync (lines 62-84):

```bash
# Ensure exports/bot directory exists
mkdir -p "$EXPORTS_DIR/bot"

# Copy prompts from components to export
log "Copying prompts from components..."
PROMPT_COUNT=0
for prompt_file in components/*/prompts/*.md; do
    [[ -e "$prompt_file" ]] || continue  # Skip if no matches
    filename=$(basename "$prompt_file")
    # Skip AGENTS.snippet.md files (those go via prompt-sync)
    if [[ "$filename" == "AGENTS.snippet.md" ]]; then
        continue
    fi
    # Convert to "Prompt - Name.md" format
    # e.g., Export.md → Prompt - Export.md
    dest_name="Prompt - ${filename}"
    cp "$prompt_file" "$EXPORTS_DIR/bot/$dest_name"
    log "  → $dest_name"
    ((PROMPT_COUNT++)) || true
done
if [[ $PROMPT_COUNT -gt 0 ]]; then
    log "Copied $PROMPT_COUNT prompt(s)"
fi
```

### 2. Renamed `components/distill/prompts/export.md`

```bash
mv components/distill/prompts/export.md components/distill/prompts/Export.md
```

Purpose: Follow naming convention so it becomes `Prompt - Export.md` in memory.

### 3. Added `claude` profile to `exports.yaml`

Added after the `rag` profile:

```yaml
  claude:
    description: "Prompts for Claude Projects / Claude Code"
    output_dir: exports/claude
    include:
      type: [prompt]
```

### 4. Created `components/distill/prompts/Export-Claude.md`

New file (222 lines) - a variant of Export.md adjusted for Claude Code context where the assistant has file access and can write CONFIG directly to intake files.

---

## Corrected Understanding

After user feedback, I realized the architecture already exists but isn't fully wired up:

```
exports.yaml          ← Defines profiles (bot, rag, claude) with include/exclude/redaction
        ↓
/export command       ← CLI: reads exports.yaml, processes reference/ → exports/<profile>/
        ↓
/push command         ← Syncs exports/bot/ to bot memory (BUT doesn't call /export!)
```

**The real problem:**
- `exports.yaml` IS the equivalent of PKM's bundles.yaml
- The export CLI (`python -m components.distill.lib.cli export`) already reads it
- But prompts in `components/*/prompts/` aren't in `reference/`, so they don't flow through the export pipeline
- My push.sh changes bypass the export pipeline entirely

---

## Revised Plan

### Approach: Extend CLI to Scan Component Prompts

Rather than copying prompts in push.sh, modify the export CLI to also scan `components/*/prompts/*.md`:
- Single source of truth: prompts stay in components/
- Prompts get frontmatter for filtering (type: prompt, scope: meta)
- Output renamed to `Prompt - {filename}`

### Remaining Tasks

1. **Add Prompt Scanning to Export CLI** (`components/distill/lib/cli.py`)
   - Scan `components/*/prompts/*.md` (excluding AGENTS.snippet.md)
   - Apply same filtering/redaction as other files
   - Rename output to `Prompt - {filename}`

2. **Add Frontmatter to Prompt Files**
   ```yaml
   ---
   type: prompt
   scope: meta
   title: "Export Prompt"
   ---
   ```

3. **Update exports.yaml bot profile**
   ```yaml
   bot:
     include:
       scope: [meta, reference, transcripts]
       type: [prompt]  # Add this line
   ```

4. **Decision: Keep or Revert push.sh changes?**
   - Current push.sh changes work as a stopgap
   - Proper fix is CLI extension, then push.sh changes become redundant

---

## Files Changed This Session

| File | Change |
|------|--------|
| `tools/push.sh` | Added prompt-copying logic (lines 62-84) |
| `components/distill/prompts/export.md` | Renamed to `Export.md` |
| `components/distill/prompts/Export-Claude.md` | Created (Claude Code variant) |
| `exports.yaml` | Added `claude` profile |

---

## Note: RAG Profile

The `rag` profile exists in exports.yaml with `format: chunked`, but chunking isn't implemented in the CLI. Basic filtering works; chunking for embeddings is a future enhancement.

---

## Issues & Concerns Raised

### 1. Push.sh Bypasses Export Pipeline

The push.sh changes I made copy prompts directly to `exports/bot/` without going through the export CLI. This means:
- **No filtering** based on include/exclude rules
- **No redaction** applied (names, health, etc.)
- **No profile differentiation** - bot and claude get identical copies

This defeats the purpose of having `exports.yaml` define different profiles.

### 2. Need PKM-Style Profile System

User asked: "is there not an equivalent of pkm/config/bundles.yaml or something to define different output profiles for export/bot?"

Answer: **Yes, `exports.yaml` already serves this purpose.** It defines:
- `bot` profile: includes meta/reference/transcripts, excludes sensitive/restricted, redacts names/health
- `rag` profile: includes reference/transcripts, chunked format (not implemented)
- `claude` profile: includes type: prompt (just added)

The issue is the pipeline isn't wired up - push.sh doesn't call the export CLI.

### 3. Potential PKM Integration

User raised: "if not we may need to combine our current push.sh capabilities with the pkm repo's export capabilities"

PKM has:
- `config/profiles/*.yaml` - per-bundle redaction settings (work, home, personal, meta)
- `scripts/helpers/profiles.py` - profile loading logic
- `bundles/` - generated output directory

bruba-godo's `components/distill/lib/cli.py` already has similar functionality (`cmd_export`), it just needs to:
1. Also scan component prompts
2. Actually be called before push

---

## Future Steps (From Original Plan)

### 1. Unified Claude Projects Import

Create bookmarklet → `intake/` → same pipeline flow for Claude Projects exports.

### 2. PKM Prompt Migration

Migrate supporting prompts from PKM to `components/distill/prompts/`:

| Source (PKM) | Destination | Bot Memory Name |
|--------------|-------------|-----------------|
| `Prompt - Daily Triage.md` | `Daily-Triage.md` | `Prompt - Daily Triage.md` |
| `Prompt - Transcription.md` | `Transcription.md` | `Prompt - Transcription.md` |
| `Prompt - Reminders Integration.md` | `Reminders-Integration.md` | `Prompt - Reminders Integration.md` |
| `Prompt - Home.md` | `Home.md` | `Prompt - Home.md` |
| `Prompt - Work.md` | `Work.md` | `Prompt - Work.md` |

These are referenced in the Export prompt but don't exist yet in bruba-godo.

### 3. Wire Up Full Pipeline

Either:
- Have `/push` call `/export` automatically, OR
- Have `/sync` orchestrate both, OR
- Document the manual sequence: `/export` then `/push`

### 4. Implement RAG Chunking

The `format: chunked` option in the rag profile isn't implemented. Future enhancement for embedding-based retrieval.

---

## Verification Steps

1. Run `python -m components.distill.lib.cli export --profile bot --verbose`
2. Run `/push --dry-run` - should show `Prompt - Export.md`
3. Check bot: `./tools/bot clawdbot memory search "export prompt"`

---

## Session 2: Proper Implementation (2026-01-31)

After user feedback, implemented the proper solution:

### Changes Made

1. **Extended CLI** (`components/distill/lib/cli.py`):
   - `cmd_export()` now scans both `reference/` AND `components/*/prompts/*.md`
   - Excludes `AGENTS.snippet.md` (goes via prompt-sync)
   - Prompts output with `Prompt - {name}.md` prefix
   - Added `_parse_prompt_frontmatter()` and `_matches_prompt_filters()` helpers

2. **Added Frontmatter** to prompt files:
   - `components/distill/prompts/Export.md` - added `type: prompt, scope: meta`
   - `components/distill/prompts/Export-Claude.md` - added `type: prompt, scope: meta`

3. **Updated exports.yaml**:
   - Added `tests` profile for local testing
   - Added `type: [prompt]` to bot profile includes

4. **Reverted push.sh workaround**:
   - Removed direct prompt copying (lines 62-84)
   - Push now requires `/export` to run first

5. **Updated tests** (`tests/test-export-prompts.sh`):
   - Now tests actual CLI execution
   - Verifies prompts exported to `exports/tests/`
   - All 17 tests pass

### Test Results

```
=== Summary ===
Passed: 17
Failed: 0

All tests passed!
```

### How to Use

```bash
# Generate exports (now includes prompts automatically)
python3 -m components.distill.lib.cli --verbose export --profile bot

# Push to bot (requires config.yaml)
./tools/push.sh

# Or full pipeline
/export && /push
```

---

## Session 3: PKM Prompt Migration (2026-01-31)

Completed Stage 1 gap: migrated Transcription prompt from PKM.

### Changes Made

1. **Created `components/distill/prompts/Transcription.md`**
   - Source: `~/source/pkm/prompts/Prompt - Transcription.md`
   - Updated frontmatter to our format:
     ```yaml
     ---
     type: prompt
     scope: meta
     title: "Transcription Mode"
     ---
     ```
   - Content: Voice transcript cleanup rules, known common mistakes table, temporal messaging handling

2. **Updated `tests/test-export-prompts.sh`**
   - Added checks for `Transcription.md` existence
   - Added checks for `Prompt - Transcription.md` in exports
   - Tests increased from 17 to 20

### Test Results

```
=== Summary ===
Passed: 20
Failed: 0

All tests passed!
```

### Export Output

```bash
python3 -m components.distill.lib.cli --verbose export --profile bot
# Found 3 files (0 in reference/, 3 prompts)
# -> exports/bot/Prompt - Export.md
# -> exports/bot/Prompt - Export-Claude.md
# -> exports/bot/Prompt - Transcription.md
```

### PKM Prompts Status

| PKM Prompt | Status | Notes |
|------------|--------|-------|
| `Prompt - Export.md` | ✅ Own version | Our version in distill/prompts/ |
| `Prompt - Transcription.md` | ✅ Migrated | Now `Transcription.md` |
| `Prompt - Reference Doc Create Update.md` | ⏭️ Skipped | PKM-specific, not needed for bot |

### Stage 1 Complete

All requirements from `memory/packet-stage1-export-pipeline.md` now met:
- CLI scans components/*/prompts/ ✅
- Export to exports/bot/, exports/claude/ ✅
- Test target exports/tests/ ✅
- Tests validate pipeline ✅ (20 tests)
- No workarounds ✅
- PKM-derived prompts ✅

### Push Status

Push requires `config.yaml` (SSH settings) which isn't present on this machine. Exports are ready in `exports/bot/`.

---

## Session 4: Config Cleanup & First Push (2026-01-31)

Consolidated config files and completed first successful push.

### Problem

Config files were scattered:
- `config/corrections.yaml` - transcription fixes (but docs referenced `components/distill/config/`)
- `config.yaml.example` - SSH settings template (no actual config.yaml existed)
- `exports.yaml` - export profiles (in repo root, correct location)

### Changes Made

1. **Moved `config/corrections.yaml` → `components/distill/config/corrections.yaml`**
   - Docs already referenced this location
   - Removed empty `config/` directory

2. **Updated `tools/helpers/parse-jsonl.py`**
   - Changed default corrections path from `config/corrections.yaml` to `components/distill/config/corrections.yaml`
   - Updated docstring to match

3. **Created `config.yaml` from SSH config**
   - Read `~/.ssh/config` to find `bruba` host definition
   - Generated config.yaml with correct SSH host and remote paths:
   ```yaml
   version: 2
   ssh:
     host: bruba
   remote:
     home: /Users/bruba
     workspace: /Users/bruba/clawd
     clawdbot: /Users/bruba/.clawdbot
     agent_id: bruba-main
   local:
     mirror: mirror
     sessions: sessions
     logs: logs
     intake: intake
     reference: reference
     exports: exports
     assembled: assembled
   ```

### First Successful Push

```bash
./tools/push.sh --verbose
```

Output:
```
=== Pushing Content to Bot ===
Files to sync: 3
Syncing to bruba:/Users/bruba/clawd/memory/
Prompt - Export-Claude.md
Prompt - Export.md
Prompt - Transcription.md
sent 6291 bytes  received 368 bytes
Synced 3 files
Triggering memory reindex...
Memory index updated (bruba-main).
Memory index updated (web-reader).
=== Push Complete ===
```

### Files Changed

| File | Change |
|------|--------|
| `config/corrections.yaml` | Deleted (moved) |
| `components/distill/config/corrections.yaml` | Created (from move) |
| `tools/helpers/parse-jsonl.py` | Updated default path |
| `config.yaml` | Created from SSH config |

### Current Config File Layout

```
bruba-godo/
├── config.yaml              # SSH/bot connection (gitignored)
├── config.yaml.example      # Template for config.yaml
├── exports.yaml             # Export profile definitions
└── components/distill/
    └── config/
        └── corrections.yaml # Transcription error corrections
```

### Verification

```bash
# Bot connection works
./tools/bot echo "test"
# → test

# Push works
./tools/push.sh --dry-run
# → Push: 3 files
```

### Stage 1 Complete + Operational

Export pipeline is now fully operational:
1. Prompts in `components/distill/prompts/` ✅
2. Export CLI scans and processes them ✅
3. `exports.yaml` defines profiles ✅
4. `config.yaml` enables bot connection ✅
5. Push syncs to bot memory ✅
6. Memory indexed on bot ✅
