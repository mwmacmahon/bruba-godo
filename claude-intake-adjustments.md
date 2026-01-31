# Intake Pipeline Adjustments: Auto-CONFIG for Files Without CONFIG

**Date:** 2026-01-31
**Goal:** Make `/intake` handle files without CONFIG blocks by auto-detecting source and offering auto-generation

## Overall Plan

The plan from Stage 3 was:

1. **Add source detection to `parsing.py`** — Four new functions:
   - `detect_source()` — Auto-detect bruba/claude-projects/voice-memo from content patterns
   - `extract_date_from_content()` — Extract date from Signal timestamps, filename, or today
   - `generate_slug()` — Generate URL-safe slug from title and date
   - `extract_title_hint()` — Extract title from first substantial user message

2. **Add `auto-config` CLI command to `cli.py`** — New subcommand that:
   - Takes file paths as positional args
   - Has `--apply` flag (default: dry-run preview)
   - Skips files that already have CONFIG
   - Generates minimal CONFIG block and appends to file

3. **Update `/intake` skill** — Add Step 1.5 between discovery and canonicalization:
   - Run auto-config on files without CONFIG
   - Present findings in table format
   - Offer options: apply all, select, route to /convert, or skip

## What Was Implemented

### 1. Source Detection Functions (`components/distill/lib/parsing.py`)

Added four new functions at the end of the parsing module:

#### `detect_source(content: str) -> str`
Auto-detects conversation source from content patterns:
- `'bruba'` — Has `[Signal ... id:...]` or `[Telegram ... id:...]` markers (uses existing `BRUBA_METADATA_PREFIX_PATTERN`)
- `'voice-memo'` — Contains `[Transcript]` or `[attached audio file`
- `'claude-projects'` — Default (no Bruba or voice markers)

#### `extract_date_from_content(content: str, filename: str) -> str`
Extracts date in YYYY-MM-DD format by checking:
1. Signal timestamp pattern (`2026-01-31 10:00 EST`)
2. YYYY-MM-DD prefix in filename
3. Falls back to today's date

#### `generate_slug(title: str, date: str) -> str`
Generates URL-safe slug from title and date:
- Lowercases, replaces spaces/separators with hyphens
- Removes non-alphanumeric chars except hyphens
- Truncates to ~50 chars at word boundary
- Format: `YYYY-MM-DD-slugified-title`

#### `extract_title_hint(content: str) -> Optional[str]`
Extracts title from first substantial user message:
- Parses messages using existing `parse_messages()`
- Cleans Bruba artifacts with `clean_bruba_artifacts()`
- Strips `[Transcript]` prefix for voice memos
- Removes common conversational prefixes (Hey, Hi, OK, etc.)
- Truncates to 60 chars at word boundary
- Returns `None` if no suitable content found

### 2. Auto-Config CLI Command (`components/distill/lib/cli.py`)

Added `cmd_auto_config()` function and registered `auto-config` subparser:

```
python -m components.distill.lib.cli auto-config <files>... [--apply]
```

**Arguments:**
- `files` — Positional, markdown files to process
- `--apply` — Write CONFIG to files (default: dry-run preview)

**Behavior:**
- Skips files that already have CONFIG blocks
- Detects source, extracts date and title
- Generates minimal CONFIG block:
  ```yaml
  title: "extracted or Untitled"
  slug: YYYY-MM-DD-slugified-title
  date: YYYY-MM-DD
  source: bruba|claude-projects|voice-memo
  tags: []

  sections_remove: []
  ```
- Dry-run shows preview; `--apply` appends CONFIG to file

### 3. Updated `/intake` Skill (`.claude/commands/intake.md`)

Added **Step 1.5: Handle Files Without CONFIG** after file discovery:

- Runs `auto-config` on files without CONFIG
- Presents findings in table format with source and auto-detected title
- Offers four options:
  - **[A]** Apply auto-CONFIG to all and continue to canonicalize
  - **[S]** Select which to auto-CONFIG (others need `/convert`)
  - **[C]** Route all to `/convert` for full AI-assisted CONFIG
  - **[Q]** Skip files without CONFIG for now

- Documents source detection patterns
- Notes that auto-CONFIG is minimal (for simple cases), while `/convert` is for conversations needing summaries, section removal, or transcription fixes

## Design Decisions

1. **Minimal CONFIG**: Auto-CONFIG generates bare minimum fields. Complex conversations should still use `/convert` for full AI-assisted processing with summaries and section removal.

2. **Source detection priority**:
   - Bruba markers checked first (specific pattern)
   - Voice memo indicators second
   - Claude-projects as default

3. **Title extraction**: Cleans Bruba artifacts before extracting to get the actual message content, not metadata.

4. **Date extraction order**: Signal timestamp > filename pattern > today's date. This ensures conversations from the bot preserve their original date.

5. **Slug truncation**: Keeps slug readable (~50 chars max for title portion) while maintaining uniqueness via date prefix.

## Files Modified

| File | Changes |
|------|---------|
| `components/distill/lib/parsing.py` | Added `detect_source()`, `extract_date_from_content()`, `generate_slug()`, `extract_title_hint()`, and related patterns |
| `components/distill/lib/cli.py` | Added `cmd_auto_config()` function and `auto-config` subparser, updated docstring |
| `.claude/commands/intake.md` | Added Step 1.5 for handling files without CONFIG |

## Testing Performed

1. **Source detection**:
   - `claude-projects`: Content with standard message delimiters → detected correctly
   - `bruba`: Content with `[Signal Michael id:uuid:...]` → detected correctly
   - `voice-memo`: Content with `[Transcript]` → detected correctly

2. **Date extraction**:
   - Signal timestamp `2026-01-15 14:30 EST` → extracted `2026-01-15`
   - No timestamp → falls back to today's date

3. **Title extraction**:
   - Plain message → first 60 chars
   - Bruba message → extracts content after cleaning metadata
   - Voice memo → extracts content after stripping `[Transcript]`
   - Conversational prefix → removed ("Hey, " stripped)

4. **Auto-config workflow**:
   - Dry-run shows preview with source, title, slug, date
   - `--apply` appends CONFIG block to file
   - Files with existing CONFIG are skipped

5. **Full pipeline**:
   - Created file without CONFIG
   - Ran `auto-config --apply`
   - Successfully canonicalized with `canonicalize` command

## Example Output

```
$ python3 -m components.distill.lib.cli auto-config test-bruba.md test-voice.md test-cp.md

=== test-bruba.md ===
source: bruba
title: can you help me with the project setup?
slug: 2026-01-15-can-you-help-me-with-the-project-setup
date: 2026-01-15

=== test-voice.md ===
source: voice-memo
title: The project is going well. We need to finish the API work...
slug: 2026-01-31-the-project-is-going-well-we-need-to-finish-the
date: 2026-01-31

=== test-cp.md ===
source: claude-projects
title: I need help implementing a REST API for user authentication.
slug: 2026-01-31-i-need-help-implementing-a-rest-api-for-user
date: 2026-01-31
```

## Tests Added

No formal unit tests were added to the test suite. Testing was done manually during implementation:

### Manual Test Commands Run

```bash
# 1. Create test files for each source type
cat > /tmp/test-claude-projects.md << 'EOF'
=== MESSAGE 0 | USER ===
I need help implementing a REST API for user authentication.
10:15 AM
=== MESSAGE 1 | ASSISTANT ===
I'd be happy to help with that!
EOF

cat > /tmp/test-bruba.md << 'EOF'
=== MESSAGE 0 | USER ===
[Signal Michael id:uuid:abc123 +5s 2026-01-31 10:00 EST] Hey, can you help me with the project setup?
=== MESSAGE 1 | ASSISTANT ===
Of course!
EOF

cat > /tmp/test-voice.md << 'EOF'
=== MESSAGE 0 | USER ===
[Transcript] The project is going well. We need to finish the API work by Friday.
=== MESSAGE 1 | ASSISTANT ===
Got it!
EOF

# 2. Test source detection (dry-run)
python3 -m components.distill.lib.cli auto-config /tmp/test-*.md

# 3. Test date extraction from Signal timestamp
cat > /tmp/test-bruba-dated.md << 'EOF'
=== MESSAGE 0 | USER ===
[Signal Michael id:uuid:abc123 +5s 2026-01-15 14:30 EST] Hey, can you help me with the project setup?
=== MESSAGE 1 | ASSISTANT ===
Of course!
EOF
python3 -m components.distill.lib.cli auto-config /tmp/test-bruba-dated.md
# Verified: extracted date 2026-01-15 from Signal timestamp

# 4. Test --apply flag
cp /tmp/test-claude-projects.md /tmp/test-apply.md
python3 -m components.distill.lib.cli auto-config /tmp/test-apply.md --apply
cat /tmp/test-apply.md
# Verified: CONFIG block appended to file

# 5. Test skip for files with existing CONFIG
python3 -m components.distill.lib.cli auto-config /tmp/test-apply.md
# Verified: output "already has CONFIG, skipping"

# 6. Test parsing of auto-generated CONFIG
python3 -m components.distill.lib.cli parse /tmp/test-apply.md
# Verified: parsed as v2 config with correct fields

# 7. Test full pipeline (auto-config → canonicalize)
awk '/^=== EXPORT CONFIG ===/{exit} {print}' tests/fixtures/005-full-export/input.md > /tmp/no-config.md
python3 -m components.distill.lib.cli auto-config /tmp/no-config.md --apply
mkdir -p /tmp/canonical-test
python3 -m components.distill.lib.cli canonicalize /tmp/no-config.md -o /tmp/canonical-test/
# Verified: produced canonical file at /tmp/canonical-test/2026-01-31-*.md
```

### Suggested Future Tests

If formalizing these as unit tests in `tests/`:

```python
# tests/test_auto_config.py

def test_detect_source_bruba():
    content = "[Signal Michael id:uuid:123 +5s 2026-01-31 10:00 EST] Hello"
    assert detect_source(content) == 'bruba'

def test_detect_source_voice_memo():
    content = "[Transcript] This is a voice memo"
    assert detect_source(content) == 'voice-memo'

def test_detect_source_claude_projects():
    content = "=== MESSAGE 0 | USER ===\nHello\n"
    assert detect_source(content) == 'claude-projects'

def test_extract_date_from_signal_timestamp():
    content = "[Signal Michael id:uuid:123 +5s 2026-01-15 14:30 EST] Hello"
    assert extract_date_from_content(content, "test.md") == '2026-01-15'

def test_extract_date_fallback_to_today():
    content = "Hello world"
    # Would need to mock datetime.now() or accept today's date

def test_generate_slug():
    assert generate_slug("Hello World", "2026-01-31") == "2026-01-31-hello-world"
    assert generate_slug("API Authentication Setup", "2026-01-15") == "2026-01-15-api-authentication-setup"

def test_extract_title_hint_simple():
    content = "=== MESSAGE 0 | USER ===\nI need help with authentication.\n"
    assert extract_title_hint(content) == "I need help with authentication."

def test_extract_title_hint_bruba():
    content = "=== MESSAGE 0 | USER ===\n[Signal Michael id:uuid:123 +5s] Can you help?\n"
    assert extract_title_hint(content) == "Can you help?"

def test_extract_title_hint_voice():
    content = "=== MESSAGE 0 | USER ===\n[Transcript] Project update notes here.\n"
    assert extract_title_hint(content) == "Project update notes here."
```
