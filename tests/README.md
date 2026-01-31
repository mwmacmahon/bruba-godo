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

# Full test suite
python3 tests/run_tests.py -v && \
  ./tests/test-export-prompts.sh && \
  ./tests/test-prompt-assembly.sh --quick && \
  ./tests/test-e2e-pipeline.sh
```

## Test Structure

```
tests/
├── run_tests.py                    # Test runner (works without pytest)
├── test_variants.py                # Variant generation tests (24 tests)
├── test_export.py                  # Export pipeline tests (18 tests)
├── test_detect_conflicts.sh        # Conflict detection tests (18 tests)
├── test-export-prompts.sh          # Profile targeting tests (38 tests)
├── test-prompt-assembly.sh         # Prompt assembly tests (13 tests)
├── test-e2e-pipeline.sh            # E2E content pipeline tests (10 tests)
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

**Total Python tests: 42**

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

**Total tests: 121** (42 Python + 79 Shell)

#### What's Tested in `test-export-prompts.sh`

- **Prompt file existence** - Export.md, Transcription.md (Export-Claude.md merged)
- **exports.yaml profiles** - bot, claude, tests profiles defined
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

## CI/Local Verification

Before committing changes to the distill pipeline:

```bash
# Run full test suite
python3 tests/run_tests.py -v && \
  ./tests/test-export-prompts.sh && \
  ./tests/test-prompt-assembly.sh --quick && \
  ./tests/test-e2e-pipeline.sh

# Verify profile targeting
python3 -m components.distill.lib.cli export --profile bot --verbose
python3 -m components.distill.lib.cli export --profile claude --verbose

# Check specific exports
ls exports/bot/
ls exports/claude/
```
