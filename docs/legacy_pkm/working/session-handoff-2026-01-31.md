# Session Handoff: Intake Pipeline Work

**Date:** 2026-01-31
**Context:** Full pipeline test run with significant clarifications made

---

## Critical Clarifications Made This Session

### The `/convert` Model (AI-powered)

**TWO things happen:**

1. **REMOVES noise from file** — heartbeats, exec denials, `HEARTBEAT_OK`, system errors
   - These are **actually deleted** from the file before canonicalize
   - Use Edit tool to remove them

2. **MARKS content in CONFIG** — everything else is just marked, NOT removed:
   - `sections_remove` — debugging tangents, off-topic (applied at export)
   - `sensitivity` — names, health, personal, financial (redacted per export profile)
   - `code_blocks` — walls of text, artifacts with keep/summarize/remove actions (applied at export)

**CRITICAL:** Only noise is removed from file. Canonical keeps all content. CONFIG just marks for later processing.

### The `/intake` Model (NOT AI-powered)

Canonicalize does deterministic processing:
- Reads CONFIG → YAML frontmatter
- Applies `corrections.yaml` (transcription fixes)
- Strips Signal/Telegram wrappers `[Signal Michael id:...]` (automatic, pattern-based)
- **Content stays intact** — sections_remove, sensitivity just go in frontmatter

### The `/export` Model (NOT AI-powered)

Export actually applies the CONFIG markings:
- Applies `sections_remove` — actually removes sections
- Applies redaction per `exports.yaml` profile
- Applies `code_blocks` actions (summarize replaces with placeholder)

---

## Pipeline Flow Summary

```
sessions/*.jsonl
    ↓ /pull (parse-jsonl)
intake/*.md (raw delimited markdown)
    ↓ /convert (AI)
    │   - REMOVES: noise (heartbeats, system cruft)
    │   - MARKS: sections_remove, sensitivity, code_blocks in CONFIG
    │   - ADDS: backmatter summary
intake/*.md (noise gone, has CONFIG)
    ↓ /intake (NOT AI)
    │   - CONFIG → YAML frontmatter
    │   - Strips Signal wrappers (automatic)
    │   - corrections.yaml applied
    │   - Content stays intact
reference/transcripts/*.md (canonical, full content, frontmatter)
    ↓ /export (NOT AI)
    │   - sections_remove applied (actually removes)
    │   - Redaction per exports.yaml
    │   - code_blocks actions applied
exports/bot/*.md (filtered, redacted)
    ↓ /push
bot memory
```

---

## Current State

### Files Processed
- `intake/c473f501-ef45-4810-b24f-d27cd804bf00.md` — converted, ready for /intake
  - Noise removed (heartbeat msgs 6-7)
  - CONFIG added with code_blocks (pasted docs marked summarize)
  - Backmatter added

### Files Remaining
- 39 files in intake/ still need CONFIG blocks
- 13 trivial files were deleted (test pings, heartbeats)

### Tasks Status
- Step 1 (/pull): Complete — 40 files in intake
- Step 2 (/convert): In progress — 1 file done
- Step 3-5: Pending

---

## Key Documentation (READ THESE)

1. **`.claude/commands/convert.md`** — Updated with clear model
2. **`.claude/commands/intake.md`** — Has triage step for trivial files
3. **`components/distill/README.md`** — Updated with pipeline flow
4. **`docs/intake-pipeline.md`** — Updated with clarifications
5. **PKM reference:** `pkm/tools/convo-processor/prompts/export.md` — Original CONFIG format

---

## Code Blocks / Artifacts

These are the same concept (legacy naming). Includes:
- Actual code blocks
- Walls of copy-pasted text
- Continuation packets
- Log dumps

Actions: `keep`, `summarize`, `remove`, `extract`

---

## Interactive Flow for /convert

1. Show analysis table with:
   - 🗑️ NOISE TO DELETE (removed from file)
   - ✂️ SECTIONS TO MARK (in CONFIG, applied at export)
   - 💻 CODE BLOCKS (in CONFIG)
   - 🔒 SENSITIVITY (in CONFIG)
   - 📦 ARTIFACTS (informational)

2. Interactive review per category
3. Delete noise from file
4. Generate CONFIG + backmatter
5. Append to end of file
6. Verify with `parse` command

---

## What NOT to do

- Don't edit file content except to remove noise
- Don't apply sections_remove at convert time
- Don't apply redaction at convert/canonicalize time
- Transcription fixes come from corrections.yaml, not per-file CONFIG

---

## Next Steps

1. Continue `/convert` on more files (or batch)
2. Run `/intake` on files with CONFIG
3. Run `/export --profile bot`
4. Run `/push` to sync to bot
5. Document any gaps found

---

## Open Questions / Future Work

- Task #7: Add short conversation filtering to /convert (triage is in /intake, could move to /convert)
- Verify canonicalize actually preserves content correctly
- Verify export applies sections_remove and code_blocks actions
- Test full round-trip
