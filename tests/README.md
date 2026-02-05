# Testing Guide

Test suite for bruba-godo tooling, focusing on the distill pipeline (conversation → knowledge).

## Quick Start

```bash
# Run all Python tests
python3 tests/run_tests.py

# Run with verbose output
python3 tests/run_tests.py -v

# Run specific test module
python3 tests/run_tests.py test_variants

# Run shell-based tests
./tests/test-export-prompts.sh
./tests/test-prompt-assembly.sh --quick
./tests/test-e2e-pipeline.sh
./tests/test-component-tools.sh --quick
./tests/test-lib.sh --quick
./tests/test-mirror.sh --quick
./tests/test-pull-sessions.sh --quick
./tests/test-push.sh --quick
./tests/test-sync-cronjobs.sh --quick
./tests/test-identity-system.sh --quick
./tests/test-efficiency.sh --quick

# Full test suite
python3 tests/run_tests.py -v && \
  ./tests/test-export-prompts.sh && \
  ./tests/test-prompt-assembly.sh --quick && \
  ./tests/test-e2e-pipeline.sh && \
  ./tests/test-component-tools.sh --quick && \
  ./tests/test-lib.sh --quick && \
  ./tests/test-mirror.sh --quick && \
  ./tests/test-pull-sessions.sh --quick && \
  ./tests/test-push.sh --quick && \
  ./tests/test-sync-cronjobs.sh --quick && \
  ./tests/test-identity-system.sh --quick && \
  ./tests/test-efficiency.sh --quick
```

## Test Structure

```
tests/
├── run_tests.py                    # Test runner (works without pytest)
├── test_variants.py                # Variant generation tests (24 tests)
├── test_export.py                  # Export pipeline tests (18 tests)
├── test_convert_doc.py             # convert-doc.py script tests (15 tests)
├── test_detect_conflicts.sh        # Conflict detection tests (18 tests)
├── test-export-prompts.sh          # Profile targeting tests (38 tests)
├── test-prompt-assembly.sh         # Prompt assembly tests (13 tests)
├── test-e2e-pipeline.sh            # E2E content pipeline tests (10 tests)
├── test-component-tools.sh         # Component tool sync tests (36 tests)
├── test-lib.sh                     # Shared library tests (9 tests)
├── test-mirror.sh                  # Mirror script tests (7 tests)
├── test-pull-sessions.sh           # Pull sessions tests (9 tests)
├── test-push.sh                    # Push script tests (16 tests)
├── test-sync-cronjobs.sh           # Cron sync tests (6 tests)
├── test-identity-system.sh         # Config-driven identity tests (23 tests)
├── test-efficiency.sh              # Efficiency audit tests (17 tests)
└── fixtures/                       # Test fixtures
    ├── FIXTURES.md                 # Fixture documentation
    ├── 001-ui-artifacts/
    ├── 002-section-removal/
    ├── 003-transcription-corrections/
    ├── 004-code-blocks/
    ├── 005-full-export/
    ├── 006-v1-migration/
    ├── 007-paste-and-export/
    ├── 008-filter-test/
    └── 009-e2e-pipeline/           # E2E pipeline test fixture
```

## Test Modules

### Python Tests

| Module | Tests | Description |
|--------|-------|-------------|
| `test_variants.py` | 24 | Variant generation from canonical files |
| `test_export.py` | 18 | Export pipeline routing and frontmatter preservation |
| `test_convert_doc.py` | 15 | Isolated document conversion script |

**Total Python tests: 57**

#### What's Tested in `test_variants.py`

- **Section removal** - Anchor-based removal with `[Removed: ...]` markers
- **Lite-specific removal** - `sections_lite_remove` for transcript-lite variant
- **Code block processing** - keep/summarize/remove actions
- **Canonical file parsing** - Frontmatter + content + backmatter
- **Fuzzy anchor matching** - Case-insensitive, normalized text matching
- **Variant generation** - transcript, transcript-lite, summary

#### What's Tested in `test_export.py`

- **Type/scope parsing** - Frontmatter type and scope extraction
- **Export routing** - Type-based routing (doc→docs/, refdoc→refdocs/, etc.)
- **Routing priority** - Frontmatter type takes precedence over path
- **Frontmatter preservation** - Type/scope preserved in variant output
- **Footer handling** - "End of Transcript" only for transcript types

#### What's Tested in `test_convert_doc.py`

Tests for `tools/helpers/convert-doc.py`, an isolated LLM document conversion script.

**CLI tests (5):**
- **Usage message** - Shows usage when no file argument provided
- **API key required** - Errors when `ANTHROPIC_API_KEY` not set
- **File validation** - Errors for nonexistent files
- **Help flag** - `--help` shows usage and model options
- **Invalid model** - Rejects invalid model choices

**Unit tests (7):**
- **Script structure** - Shebang, imports, main function, messages.create
- **Environment config** - Uses `ANTHROPIC_API_KEY` from environment
- **Prompt formatting** - Prompt + content combined with separator
- **Default prompt** - Fallback when no prompt argument given
- **Token limits** - Reasonable max_tokens setting (8192)
- **Model flag structure** - Has MODELS dict with opus/sonnet/haiku, default opus
- **Model IDs** - Valid Claude model identifiers

**Integration tests (3, require `ANTHROPIC_API_KEY`):**
- **Basic API call** - Simple conversion works end-to-end
- **Multi-invocation workflow** - Exploratory → initial config → refined config
- **Stateless behavior** - Different prompts on same file produce different outputs

#### What's Tested in `test_detect_conflicts.sh`

- **No conflicts** - Clean state when mirror matches config
- **New BOT-MANAGED sections** - Detects bot-added BOT-MANAGED blocks
- **New COMPONENT sections** - Detects bot-added COMPONENT blocks (regression test)
- **Edited components** - Detects when bot modifies component content
- **Multiple conflicts** - Handles multiple simultaneous conflicts

### Shell Tests

| Script | Tests | Description |
|--------|-------|-------------|
| `test_detect_conflicts.sh` | 18 | Conflict detection for sync workflow |
| `test-export-prompts.sh` | 38 | Profile targeting, prompt export, silent mode content |
| `test-prompt-assembly.sh` | 13 | Prompt assembly from templates + components |
| `test-e2e-pipeline.sh` | 10 | Full content pipeline: intake → reference → exports |
| `test-component-tools.sh` | 36 | Component tool sync, allowlist automation, validation |
| `test-lib.sh` | 9 | Shared library: config loading, arg parsing, log rotation |
| `test-mirror.sh` | 7 | Mirror script: date filtering, token redaction |
| `test-pull-sessions.sh` | 9 | Pull sessions: state file, deduplication, JSON parsing |
| `test-push.sh` | 16 | Push script: config parsing, file counting, routing |
| `test-sync-cronjobs.sh` | 6 | Cron sync: YAML parsing, validation, status filtering |
| `test-identity-system.sh` | 23 | Config-driven identity: validation, substitution, assembly, cronjobs |
| `test-efficiency.sh` | 17 | Efficiency audit: SSH patterns, change detection, documentation |

**Total tests: 259** (57 Python + 202 Shell)

#### What's Tested in `test-export-prompts.sh`

- **Prompt file existence** - Export.md, Transcription.md (Export-Claude.md merged)
- **config.yaml exports profiles** - bot, claude, tests profiles defined
- **Unified prompts** - Single Export.md with conditional file access behavior
- **Subdirectory structure** - Prompts go to exports/{profile}/prompts/
- **Frontmatter preservation** - YAML frontmatter retained in exports
- **AGENTS.snippet.md exclusion** - Snippet files not exported as prompts
- **Silent transcript mode** - Voice snippet has 6-step flow, Transcription.md has decision tree
- **Export pipeline notes** - Distill snippet references source/output locations

#### What's Tested in `test-e2e-pipeline.sh`

- **Fixture setup** - Copy test file to intake/
- **Canonicalization** - CLI processes to reference/transcripts/
- **File movement** - Original moved to intake/processed/
- **Export generation** - CLI exports to exports/bot/transcripts/ with prefix
- **Content preservation** - Frontmatter, messages, backmatter intact

#### What's Tested in `test-component-tools.sh`

Tests component audit Phase B-E implementation:

- **Component tools discovery** - voice, web-search, reminders have tools/
- **Allowlist.json validation** - Valid JSON, entries array, pattern+id fields, ${WORKSPACE} placeholder
- **validate-components.sh** - Script runs, reports counts, no errors on current state
- **update-allowlist.sh --check** - Status output (requires SSH, skipped in --quick)
- **update-allowlist.sh --dry-run** - Dry run works (requires SSH, skipped in --quick)
- **Allowlist expansion** - ${WORKSPACE} placeholder correctly expanded
- **AGENTS.snippet.md wiring** - Snippets exist and are in config.yaml agents_sections
- **Push script options** - --tools-only, sync_component_tools(), --update-allowlist
- **Orphan detection** - find_orphan_entries(), --add-only, --remove-only flags
- **Sync skill integration** - Validate Allowlist step in sync.md

#### What's Tested in `test-lib.sh`

Tests for `tools/lib.sh` shared library functions:

- **Config loading** - YAML parsing, path resolution, missing file handling
- **Default values** - Fallbacks for missing config keys
- **Argument parsing** - --dry-run, --verbose, --quiet, --help flags
- **Command existence** - require_commands success/failure
- **Log rotation** - Rotates large files, skips small files

#### What's Tested in `test-mirror.sh`

Tests for `tools/mirror.sh` local logic:

- **Date filtering regex** - Matches YYYY-MM-DD prefixed files
- **Invalid date rejection** - Rejects non-date-prefixed filenames
- **Token redaction** - botToken and generic token fields
- **Field preservation** - Non-token fields stay intact
- **Directory structure** - Creates prompts/memory/config/tools subdirs
- **CORE_FILES list** - All expected prompt files included

#### What's Tested in `test-pull-sessions.sh`

Tests for `tools/pull-sessions.sh` local logic:

- **State file operations** - Read, write, append to .pulled
- **Session deduplication** - Already-pulled detection via grep
- **Force re-pull** - Removes then re-adds session ID
- **JSON parsing** - Session ID extraction from sessions.json
- **Empty handling** - Empty JSON and empty state file
- **Exact matching** - Session IDs matched exactly (no partial matches)
- **Summary format** - Output text formatting

#### What's Tested in `test-push.sh`

Tests for `tools/push.sh` core logic:

- **Config parsing** - exports.bot.remote_path extraction
- **Default values** - Fallback to 'memory' for missing remote_path
- **File counting** - Recursive .md file count in exports/bot/
- **Zero file case** - Handles empty exports directory
- **Subdirectory list** - All expected subdirs in iteration
- **Core-prompts routing** - Separate destination for core-prompts/
- **Root-level files** - Detection excludes subdirectories
- **Rsync options** - --dry-run, --verbose/--quiet toggle
- **Argument flags** - --no-index, --tools-only, --update-allowlist present
- **Tools-only mode** - Early exit pattern
- **Clone repo code** - Conditional check exists
- **Subdirectory routing** - transcripts → memory/transcripts/, docs → memory/docs/
- **mkdir before rsync** - Target directory creation

#### What's Tested in `test-sync-cronjobs.sh`

Tests for `tools/sync-cronjobs.sh` cron synchronization:

- **YAML parsing** - Single-parse field extraction (name, cron, session, agent, etc.)
- **Status filtering** - Only syncs jobs with status: active
- **Field validation** - Required fields (name, cron, message) checked
- **Session handling** - Main sessions use --system-event flag
- **YAML validity** - All cronjobs/*.yaml files are valid YAML
- **Required fields** - All YAML files have name, status, schedule, message

#### What's Tested in `test-identity-system.sh`

Tests the config-driven identity system (Phases 1-4) end-to-end:

**Category 1: Config Validation (4 tests)**
- **peer_agent refs** - peer_agent values point to real agents in config
- **signal_uuid format** - UUIDs match standard format regex
- **reset/wake consistency** - reset_cycle agents also have wake_cycle
- **cross-comms requirements** - cross-comms agents have peer_agent + CROSS_COMMS_GOAL

**Category 2: Identity Config Completeness (2 tests)**
- **Component variable refs** - All `${VAR}` in component snippets have backing config
- **Template base files** - Same check for guru-base, manager-base, web-base, base templates

**Category 3: apply_substitutions() Sync (2 tests)**
- **Function exists in both** - assemble-prompts.sh and detect-conflicts.sh
- **Function bodies match** - Normalized diff (known workspace param difference excluded)

**Category 4: Variable Substitution Completeness (4 tests)**
- **Assembly succeeds** - `assemble-prompts.sh --force` exits 0
- **No unresolved `${...}`** - No leftover variable placeholders in output
- **No unresolved `{{...}}`** - No leftover template placeholders in output
- **Output dirs exist** - All configured agents have core-prompts/ directory

**Category 5: Variable Round-Trip (5 tests)**
- **Main's human_name** - bruba-main output contains its configured name
- **Rex's human_name** - bruba-rex output contains its name, not main's
- **Guru's signal_uuid** - bruba-guru output contains correct UUID
- **Cross-comms peer refs** - Peer agent names appear in cross-comms output
- **Per-agent WORKSPACE** - Different agents have different workspace paths in output

**Category 6: Cronjob Generation (6 tests)**
- **Generation succeeds** - `generate-cronjobs.sh` exits 0
- **Valid YAML** - All 4 cronjob files parse as valid YAML
- **No placeholders** - No `{{...}}` remain after generation
- **Manager's name** - morning-briefing.yaml contains manager's human_name
- **Prep agent count** - sessions_send count matches reset agent count
- **Wake agent count** - sessions_send count matches wake agent count

All tests gracefully skip (not fail) if specific agents don't exist in config.

#### What's Tested in `test-efficiency.sh`

Tests for sync pipeline efficiency (from 2026-02-03 audit):

**YAML Parsing Efficiency:**
- **Single parse** - Extracts all 9 cron fields in one YAML load
- **Helper exists** - parse-yaml.py helper available

**SSH Call Patterns:**
- **N+1 avoidance** - mirror.sh uses find instead of individual test -f
- **Batch operations** - CORE_FILES enables batch file operations

**Change Detection:**
- **Hash detection** - push.sh uses MD5 for change detection
- **Incremental tracking** - pull-sessions.sh uses .pulled file
- **Diff before write** - update-allowlist.sh compares before writing

**Rsync Efficiency:**
- **Compression** - push.sh uses -z flag
- **Archive mode** - push.sh uses -a flag

**SSH ControlMaster:**
- **Configuration** - lib.sh has ControlMaster settings

**Pure Local Scripts:**
- **No SSH in assemble** - assemble-prompts.sh is pure local
- **No SSH in conflicts** - detect-conflicts.sh is pure local

**Documentation:**
- **Usage docs** - All core scripts have usage documentation
- **Efficiency doc** - docs/efficiency-recommendations.md exists
- **Script audit** - Doc has script audit table
- **Command audit** - Doc has command audit table
- **Cron sync spec** - Doc has bidirectional cron sync design
- **Discovery searches** - Audit log has grep search results

## Fixtures

Test fixtures in `fixtures/` are based on realistic conversation exports.

See `fixtures/FIXTURES.md` for:
- How to create new fixtures
- Fixture patterns (voice transcripts, paste-and-export, etc.)
- Sanitization guidelines

### Fixture Summary

| Fixture | Tests |
|---------|-------|
| 001-ui-artifacts | Timestamp removal, "Show more", thinking summaries |
| 002-section-removal | Anchor-based sections_remove and sections_lite_remove |
| 003-transcription-corrections | Voice mishearing fixes |
| 004-code-blocks | Code block processing actions |
| 005-full-export | Full pipeline with combined features |
| 006-v1-migration | Legacy v1 config format migration |
| 007-paste-and-export | Pasted conversation with transcription_replacements |
| 008-filter-test | Sensitivity and scope filtering |
| 009-e2e-pipeline | E2E test: intake → reference → exports |

## Debug Mode

Run the full pipeline on a fixture with detailed logging:

```bash
# Debug specific fixture
python3 tests/run_tests.py --debug 002-section-removal

# Debug any input file
python3 tests/run_tests.py --debug-file path/to/input.md

# Custom output directory
python3 tests/run_tests.py --debug 001-ui-artifacts --debug-output /tmp/test-output
```

Debug output includes:
- `00-input.md` - Original input
- `01-canonical.md` - After canonicalization
- `02-transcript.md` - Full transcript variant
- `03-transcript-lite.md` - Lite variant
- `04-summary.md` - Summary variant
- `pipeline.log` - Processing details

## Running with pytest

If pytest is installed, you can use it for richer output:

```bash
# Run all tests
python3 -m pytest tests/ -v

# Run specific test
python3 -m pytest tests/test_variants.py::test_section_removal_applied -v
```

## Adding Tests

### Simple Python test

```python
def test_something():
    """Description of what's being tested."""
    result = function_under_test(input_data)
    assert result == expected_value
```

### Fixture-based test

```python
def test_with_fixture():
    """Test using a fixture directory."""
    fixture = FIXTURES_DIR / "001-ui-artifacts"
    input_path = fixture / "input.md"

    if not input_path.exists():
        print("  (skipping - fixture not found)")
        return

    corrections = load_corrections(
        TOOL_ROOT / "components" / "distill" / "config" / "corrections.yaml"
    )
    canonical, config, backmatter = canonicalize(input_path, corrections=corrections)

    # Verify key behaviors
    assert "4:02 PM" not in canonical, "Timestamps should be removed"
```

### Shell test

```bash
# In test-*.sh
if [[ -f "expected/file.md" ]]; then
    pass "File exists"
else
    fail "File not found"
fi
```

## Test Imports

Tests use the `components.distill.lib` module path:

```python
from components.distill.lib.variants import (
    parse_canonical_file,
    apply_section_removals,
    generate_variants_from_content,
    VariantOptions,
)
from components.distill.lib.models import SectionSpec, CodeBlockSpec
from components.distill.lib.canonicalize import canonicalize, load_corrections
```

Corrections file path:
```python
TOOL_ROOT / "components" / "distill" / "config" / "corrections.yaml"
```

## Known Issues / Notes to Fix

Issues discovered during test-identity-system.sh development (2026-02-05):

### 1. lib.sh `log()` function name collision
`tools/lib.sh` exports a `log()` function that writes to `$LOG_FILE`. Any test script that sources lib.sh and also defines its own `log()` helper will have the lib version overwrite it. **Workaround:** test-identity-system.sh uses `tlog()` for its test logging and sets `LOG_FILE=/dev/null` before calling `load_config`.

**Fix:** Rename lib.sh's `log()` to `lib_log()` or similar, or guard the `LOG_FILE` write with a check.

### 2. generate-cronjobs.sh `set -e` + `[[ ]] && echo` pattern
Line 190 in `generate-cronjobs.sh` had `[[ "$VERBOSE" == "true" ]] && echo "Generated: $output_file"` — when VERBOSE is false under `set -e`, the `&&` short-circuit returns exit code 1 and kills the script. This caused silent exit-1 when running without `--verbose`.

**Fixed (2026-02-05):** Added `|| true` to the line. But the same pattern may exist in other scripts — audit for `[[ ... ]] && echo` under `set -e`.

### 3. grep count mismatch in cronjob tests
`grep -c 'sessions_send'` in cronjob files counts ALL occurrences including header text like "Use sessions_send to tell agents...". The tests needed `grep -c 'sessions_send to agent:'` to match only the per-agent directive lines.

**Lesson:** When counting structured YAML message content, use specific-enough patterns to avoid matching prose.

### 4. SHARED_TOOLS config parsing in lib.sh
`load_config` uses `grep '^  shared_tools:'` to find the shared_tools value. The indentation-sensitive grep may fail if config.yaml has shared_tools nested differently (e.g., under `remote:` at 4-space indent). Currently works because the default fallback kicks in. Worth switching to Python-based YAML parsing for robustness.

## CI/Local Verification

Before committing changes to the distill pipeline:

```bash
# Run full test suite
python3 tests/run_tests.py -v && \
  ./tests/test-export-prompts.sh && \
  ./tests/test-prompt-assembly.sh --quick && \
  ./tests/test-e2e-pipeline.sh && \
  ./tests/test-component-tools.sh --quick && \
  ./tests/test-lib.sh --quick && \
  ./tests/test-mirror.sh --quick && \
  ./tests/test-pull-sessions.sh --quick && \
  ./tests/test-push.sh --quick && \
  ./tests/test-sync-cronjobs.sh --quick && \
  ./tests/test-identity-system.sh --quick && \
  ./tests/test-efficiency.sh --quick

# Verify profile targeting
python3 -m components.distill.lib.cli export --profile bot --verbose
python3 -m components.distill.lib.cli export --profile claude --verbose

# Check specific exports
ls exports/bot/
ls exports/claude/
```
