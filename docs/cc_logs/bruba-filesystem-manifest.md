# Bruba Filesystem Manifest

**Generated:** 2026-01-31
**Purpose:** Identify stray/orphan files from previous syncs and internal writes

## Summary

| Category | Count | Action |
|----------|-------|--------|
| Expected (current export format) | ~40 | Keep |
| Legacy naming (old format) | ~45 | Migrate or delete |
| Potential duplicates | ~25 | Dedupe |
| Bruba internal writes | ~10 | Keep/archive |
| Planning/packet files | ~12 | Delete or move |
| Miscellaneous strays | ~15 | Review |

---

## /Users/bruba/clawd/ (workspace root)

### Core Prompts (Expected)
```
AGENTS.md        ← synced from exports/bot/core-prompts/
BOOTSTRAP.md     ← synced
HEARTBEAT.md     ← synced
IDENTITY.md      ← synced
MEMORY.md        ← synced
SOUL.md          ← synced
TOOLS.md         ← synced
USER.md          ← synced (may have bot edits)
```

### Directories
```
memory/          ← main concern (see below)
tools/           ← component scripts (OK)
workspace/       ← clone_repo_code destination (OK)
output/          ← bruba outputs (OK)
logs/            ← whisper benchmarks (OK)
backup-2026-01-30/ ← manual backup (can archive)
artifacts/       ← (check contents)
canvas/          ← (check contents)
media/           ← (check contents)
.git/            ← orphaned git folder (not a valid repo) - DELETE
```

---

## /Users/bruba/clawd/memory/ (175 files)

### EXPECTED FORMAT (Current Export Pipeline)

Files matching `<Type> - <Name>.md`:

```
Doc - *.md              (documentation)
Transcript - *.md       (conversation transcripts)
Summary - *.md          (conversation summaries)
Claude Code Log - *.md  (CC session logs)
Prompt - *.md           (prompt templates)
Refdoc - *.md           (reference documents)
Artifact - *.md         (exported artifacts)
```

**Expected files found:**
- Doc - component-status.md
- Doc - setup.md
- Doc - operations-guide.md
- Doc - pipeline.md
- Doc - security-model.md
- (etc - ~15 Doc files)
- Transcript - 2026-01-31-*.md (3 files)
- Summary - 2026-01-31-*.md (2 files)
- Claude Code Log - 2026-01-31-*.md (3 files)
- Prompt - *.md (~12 files)
- Refdoc - *.md (4 files)
- Artifact - *.md (6 files)

### LEGACY FORMAT (Old Export Pipeline)

**"Docs -" prefix (should be "Doc -"):**
```
Docs - Bruba Security Overview.md
Docs - Bruba Setup SOP.md
Docs - Bruba Siri Hearbeat Drama.md
Docs - Bruba Usage SOP.md
Docs - Bruba Vision and Roadmap.md
Docs - Bruba Voice Integration.md
Docs - Claude Code Setup Guide.md
Docs - Convo Processor - Todo.md
Docs - Document Processing Pipeline.md
Docs - PKM Core Todo.md
Docs - PKM Quickstart.md
Docs - PKM System Primer.md
Docs - PKM System Reference.md
Docs - PKM Tag Assignment Log.md
Docs - PKM Testing.md
Docs - Workflow - *.md (4 files)
Docs - _research_bruba_signal_issues.md
```
**Action:** Delete (superseded by "Doc -" versions)

**Lowercase transcript/summary (old format):**
```
transcript-2026-01-12-*.md
transcript-2026-01-13-*.md
transcript-2026-01-14-*.md
transcript-2026-01-15-*.md
transcript-2026-01-17-*.md
transcript-2026-01-18-*.md
transcript-2026-01-21-*.md
transcript-2026-01-22-*.md
transcript-2026-01-23-*.md
transcript-2026-01-26-*.md
summary-2026-01-12-*.md
summary-2026-01-13-*.md
summary-2026-01-14-*.md
summary-2026-01-15-*.md
summary-2026-01-17-*.md
summary-2026-01-21-*.md
summary-2026-01-22-*.md
summary-2026-01-23-*.md
summary-2026-01-26-*.md
```
**Action:** Keep (historical data, not duplicated in new format)

### BARE NAMES (No Prefix - Strays)

Files without export prefix:
```
Bruba Security Overview.md
Bruba Setup SOP.md
Bruba Siri Hearbeat Drama.md
Bruba Usage SOP.md
Bruba Vision and Roadmap.md
Bruba Voice Integration.md
Document Processing Pipeline.md
```
**Action:** Delete (duplicates of "Doc -" versions)

### PKM LEGACY (Doc - PKM Legacy -)

```
Doc - PKM Legacy - Bruba Security Overview.md
Doc - PKM Legacy - Bruba Setup SOP.md
Doc - PKM Legacy - Bruba Siri Hearbeat Drama.md
Doc - PKM Legacy - Bruba Usage SOP.md
Doc - PKM Legacy - Bruba Vision and Roadmap.md
Doc - PKM Legacy - Bruba Voice Integration.md
Doc - PKM Legacy - Document Processing Pipeline.md
```
**Action:** Review - may be intentional archives

### DUPLICATE CLUSTERS

**"Bruba Usage SOP" appears as:**
1. `Bruba Usage SOP.md` ← bare (delete)
2. `Doc - Bruba Usage SOP.md` ← current format (keep)
3. `Docs - Bruba Usage SOP.md` ← old format (delete)
4. `Doc - PKM Legacy - Bruba Usage SOP.md` ← legacy archive (keep?)
5. `Refdoc - Bruba Usage SOP.md` ← refdoc export (keep)

Similar pattern for: Security Overview, Setup SOP, Vision and Roadmap, Voice Integration, Siri Heartbeat Drama

### PLANNING/PACKET FILES (Internal)

```
packet-script-audit.md
packet-stage1-export-pipeline.md
packet-stage2-prompt-updates.md
packet-stage2.5-documentation.md
packet-stage2.6-transcription-refinement.md
packet-stage3-intake-pipeline.md
packet-transcript-flow-update.md
bruba-godo-design.md
claude-exports-log.md
claude-exports-overhaul.md
claude-intake-adjustments.md
full-export-system-overhaul.md
pkm-and-voice-prompts-overhaul.md
```
**Action:** Move to archive or delete (internal planning, not memory)

### SESSION-SPECIFIC (Dates without prefix)

```
2026-01-28-session-continuity-design.md
2026-01-28-web-search-setup.md
2026-01-31.md
```
**Action:** Review - may be bruba internal notes

### BRUBA INTERNAL WRITES

```
CONTINUATION.md           ← session continuity file
archive/                  ← continuation archives
  continuation-2025-02-01.md
  continuation-2026-01-31-early.md
  continuation-2026-01-31.md
Document Inventory.md     ← generated inventory
Transcript Inventory.md   ← generated inventory
```
**Action:** Keep (bruba runtime files)

### MISCELLANEOUS

```
Core - Job Overview.md
Core - Profile.md
Core - Timeline.md
Environment - Sandbox.md
Home - Document Inventory.md
Home - Quick Start.md
Introspection - Reflection.md
Meta - Document Inventory.md
Meta - Quick Start.md
Personal - Document Inventory.md
Personal - Quick Start.md
Project - *.md (7 files)
Reference - Repo Access.md
Technical - *.md (3 files)
Template - Sanitization Key.md
Work - Document Inventory.md
Work - Quick Start.md
```
**Action:** Review - PKM-style categorization, may be strays

---

## /Users/bruba/clawd/tools/

**Current state (OK):**
```
cleanup-reminders.sh
ensure-web-reader.sh
tts.sh
voice-status.sh
web-search.sh
whisper-clean.sh
helpers/
  cleanup-reminders.py
```
All match component tools - no strays.

---

## /Users/bruba/clawd/workspace/

```
output/packets/    ← CC packet exchange (OK)
repo/              ← clone_repo_code destination (OK)
```

---

## Cleanup Recommendations

### Phase 1: Safe Deletes (Clear Duplicates)
1. Delete bare-name files that have "Doc -" versions
2. Delete "Docs -" files that have "Doc -" versions

### Phase 2: Archive
1. Move packet-*.md to workspace/archive/
2. Move *-overhaul.md planning files to archive

### Phase 3: Review
1. Decide on PKM Legacy files (keep as archive or delete)
2. Categorize Core/Personal/Work/Meta files
3. Check .git in clawd root (why is it a repo?)

### Phase 4: Migrate
1. Convert lowercase transcript-* to Transcript - * if needed
2. Convert lowercase summary-* to Summary - * if needed
3. Standardize remaining files with proper prefixes
