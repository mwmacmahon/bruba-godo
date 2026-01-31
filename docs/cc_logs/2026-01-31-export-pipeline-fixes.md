---
type: claude_code_log
scope: reference
title: "Export Pipeline Fixes - 2026-01-31"
---

# Export Pipeline Fixes - 2026-01-31

Implementation log documenting fixes to make docs and refdocs exportable.

## Issues Discovered

1. **Export only scanned `reference/`** - `docs/` directory was never processed by the export CLI
2. **Docs lacked frontmatter** - The parser requires `---` YAML frontmatter with `type` and `scope` fields
3. **Claude profile too limited** - Only had `scope: [meta]` and `type: [prompt]`, excluding docs
4. **Summaries generated but not written** - `generate_summary=True` was set but summaries were never saved to disk

## Changes Made

### 1. Added frontmatter to 19 docs files

All files in `docs/` now have proper YAML frontmatter:

```yaml
---
type: doc
scope: reference
title: "<title from first heading>"
---
```

**Root docs/ (11 files):**
- `docs/README.md`
- `docs/Vision.md`
- `docs/full-setup-guide.md`
- `docs/intake-pipeline.md`
- `docs/operations-guide.md`
- `docs/pipeline.md`
- `docs/quickstart-new-machine.md`
- `docs/security-model.md`
- `docs/setup-operator-ssh.md`
- `docs/setup-remote-machine.md`
- `docs/signal-setup-guide.md` (already had frontmatter, updated type)

**docs/legacy_pkm/ (8 files):**
- `docs/legacy_pkm/Bruba Vision and Roadmap.md`
- `docs/legacy_pkm/Bruba Usage SOP.md`
- `docs/legacy_pkm/Bruba Siri Hearbeat Drama.md`
- `docs/legacy_pkm/Bruba Security Overview.md`
- `docs/legacy_pkm/Bruba Setup SOP.md`
- `docs/legacy_pkm/Bruba Voice Integration.md`
- `docs/legacy_pkm/Document Processing Pipeline.md`
- `docs/legacy_pkm/working/session-handoff-2026-01-31.md`

### 2. Added frontmatter to test refdoc

File: `reference/refdocs/test_refdoc.md`

```yaml
---
type: refdoc
scope: reference
title: "Test Refdoc"
---
```

### 3. Updated export CLI to scan docs/

Modified `components/distill/lib/cli.py` around line 296-303:

```python
# Find canonical files in reference/ AND docs/
input_dir = Path(args.input) if args.input else Path('reference')
canonical_files = []
if input_dir.exists():
    canonical_files = list(input_dir.rglob("*.md"))

# Also scan docs/ directory for documentation files
docs_dir = Path('docs')
if docs_dir.exists() and not args.input:  # Only auto-scan docs if using default input
    canonical_files.extend(docs_dir.rglob("*.md"))
```

### 4. Updated exports.yaml profiles

**bot profile:**
```yaml
include:
  scope: [meta, reference, transcripts]
  type: [prompt, doc, refdoc]  # Added doc, refdoc
```

**claude profile:**
```yaml
include:
  type: [prompt, doc, refdoc]  # Added doc, refdoc
  scope: [meta, reference, transcripts]  # Expanded from just [meta]
```

### 5. Fixed summary output

Added summary writing to `cmd_export()` after writing transcript:

```python
# Write summary if generated
if result.summary:
    summary_dir = output_dir / "summaries"
    summary_dir.mkdir(parents=True, exist_ok=True)
    summary_name = f"Summary - {canonical_path.stem}.md"
    summary_path = summary_dir / summary_name
    summary_path.write_text(result.summary, encoding='utf-8')
```

## Files Modified

| File | Change |
|------|--------|
| `docs/**/*.md` (19 files) | Added YAML frontmatter |
| `reference/refdocs/test_refdoc.md` | Added YAML frontmatter |
| `components/distill/lib/cli.py` | Scan docs/, write summaries |
| `exports.yaml` | Updated bot and claude profiles |

## Verification

Run these commands to verify:

```bash
# Test export with verbose output
python3 -m components.distill.lib.cli export --profile bot -v

# Expected output directories:
# - exports/bot/docs/ (Doc - *.md files)
# - exports/bot/refdocs/ (Refdoc - *.md files)
# - exports/bot/summaries/ (Summary - *.md files)

# Test claude profile
python3 -m components.distill.lib.cli export --profile claude -v
```

---

## Part 2: Fix Export Routing (Same Day)

After the initial fixes, docs were still being exported as "Transcript - " to `transcripts/` instead of "Doc - " to `docs/`.

### Root Cause

`CanonicalConfig` model lacked `type` and `scope` fields, so `parse_v2_config_block` didn't parse them from frontmatter. The routing function `_get_content_subdirectory_and_prefix` never saw `type: doc`.

### Additional Changes

#### 6. Added `type` and `scope` to CanonicalConfig

Modified `components/distill/lib/models.py`:

```python
@dataclass
class CanonicalConfig:
    # === IDENTITY ===
    title: str
    slug: str
    date: str
    source: str = "claude"
    tags: List[str] = field(default_factory=list)
    type: str = ""  # doc | refdoc | transcript | prompt  # NEW
    scope: str = ""  # reference | meta | transcripts  # NEW
    description: str = ""
```

#### 7. Updated parse_v2_config_block to parse type and scope

Modified `components/distill/lib/parsing.py`:

```python
tags = parse_inline_list(parsed.get('tags', []))
file_type = parsed.get('type', '')  # NEW
scope = parsed.get('scope', '')  # NEW
description = parsed.get('description', '')

# ... and in the return statement:
return CanonicalConfig(
    ...
    tags=tags,
    type=file_type,  # NEW
    scope=scope,  # NEW
    description=description,
    ...
)
```

#### 8. Fixed routing logic to check type first

Modified `_get_content_subdirectory_and_prefix` in `components/distill/lib/cli.py`:

```python
def _get_content_subdirectory_and_prefix(canonical_path: Path, config) -> tuple:
    # Check type from frontmatter FIRST (highest priority)
    if hasattr(config, 'type') and config.type:
        file_type = config.type
        if file_type == 'doc':
            return ('docs', 'Doc - ')
        if file_type == 'refdoc':
            return ('refdocs', 'Refdoc - ')
        if file_type == 'transcript':
            return ('transcripts', 'Transcript - ')

    # Then check source path as fallback
    path_str = str(canonical_path)
    if 'transcripts' in path_str:
        return ('transcripts', 'Transcript - ')
    if 'refdocs' in path_str:
        return ('refdocs', 'Refdoc - ')
    if '/docs/' in path_str or path_str.startswith('docs/'):
        return ('docs', 'Doc - ')

    # Default to transcripts
    return ('transcripts', 'Transcript - ')
```

### Updated Files Summary

| File | Change |
|------|--------|
| `components/distill/lib/models.py` | Added `type`, `scope` fields to CanonicalConfig |
| `components/distill/lib/parsing.py` | Parse `type`, `scope` from frontmatter |
| `components/distill/lib/cli.py` | Check `type` first in routing logic |

### Final Verification

```bash
python3 -m components.distill.lib.cli --verbose export --profile bot

# Confirmed output:
# exports/bot/docs/Doc - README.md
# exports/bot/docs/Doc - Vision.md
# exports/bot/docs/Doc - pipeline.md
# ... (21 total docs)
# exports/bot/refdocs/Refdoc - test_refdoc.md
# exports/bot/transcripts/Transcript - <actual transcripts>
```

---

## Part 3: Preserve Frontmatter in Variant Output

Export was rewriting frontmatter and changing `type: refdoc` to `type: transcript`, plus adding unwanted "End of Transcript" footer.

### Root Cause

`_build_transcript_output()` in `variants.py` was hardcoding `type: transcript` and always adding "End of Transcript" footer.

### Fix

Modified `_build_transcript_output()` to:
1. Preserve original `type` from config (falls back to `transcript` if not set)
2. Preserve `scope` from config
3. Only add "End of Transcript" footer for actual transcripts

**File:** `components/distill/lib/variants.py`

```python
# Preserve original type from frontmatter, or default based on is_lite
if config.type:
    file_type = config.type
    if is_lite and file_type == 'transcript':
        file_type = 'transcript-lite'
    lines.append(f'type: {file_type}')
else:
    lines.append(f'type: {"transcript-lite" if is_lite else "transcript"}')

# Preserve scope if present
if config.scope:
    lines.append(f'scope: {config.scope}')

# Only add "End of Transcript" footer for actual transcripts
if not config.type or config.type in ('transcript', 'transcript-lite'):
    lines.append('')
    lines.append('---')
    lines.append('')
    lines.append('## End of Transcript')
```

---

## Part 4: Added Export Pipeline Tests

Created `tests/test_export.py` with 18 tests covering:

### Type/Scope Parsing (5 tests)
- `test_parse_type_from_frontmatter` - doc type parsed correctly
- `test_parse_type_refdoc` - refdoc type parsed
- `test_parse_type_transcript` - transcript type parsed
- `test_parse_type_missing` - missing type defaults to empty
- `test_parse_canonical_file_with_type_scope` - full file parsing

### Export Routing (6 tests)
- `test_routing_type_doc` - doc → docs/ with "Doc - "
- `test_routing_type_refdoc` - refdoc → refdocs/ with "Refdoc - "
- `test_routing_type_transcript` - transcript → transcripts/
- `test_routing_type_takes_priority_over_path` - frontmatter beats path
- `test_routing_fallback_to_path_when_no_type` - path used when no type
- `test_routing_default_to_transcripts` - unknown paths → transcripts

### Frontmatter Preservation (5 tests)
- `test_variant_preserves_type_doc` - type: doc preserved, no footer
- `test_variant_preserves_type_refdoc` - type: refdoc preserved
- `test_variant_adds_footer_for_transcript` - transcript gets footer
- `test_variant_adds_footer_when_no_type` - defaults to transcript behavior
- `test_variant_no_scope_when_missing` - scope not added if not present

### Integration (2 tests)
- `test_full_doc_export_flow` - end-to-end doc export
- `test_full_refdoc_export_flow` - end-to-end refdoc export

**Run tests:**
```bash
python3 tests/run_tests.py -v           # All tests (42 total)
python3 tests/test_export.py            # Export tests only (18)
```

---

## Part 5: Changed Default Fallback to Artifacts

Changed the default routing fallback from `transcripts` to `artifacts` for files without a recognized type or path.

**File:** `components/distill/lib/cli.py`

```python
# Before
# Default to transcripts for conversation-like content
return ('transcripts', 'Transcript - ')

# After
# Default to artifacts for unclassified content
return ('artifacts', 'Artifact - ')
```

Updated test `test_routing_default_to_artifacts` to match.

---

## Future Work

- Auto-add frontmatter to refdocs during sync/parse step
