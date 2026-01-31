#!/usr/bin/env python3
"""
Tests for convo-processor variants module.

These tests verify Step 2 of the pipeline:
- Section removal (sections_remove, sections_lite_remove)
- Code block processing (keep, summarize, remove)
- Variant generation (transcript, transcript-lite, summary)

Run with:
    python tests/run_tests.py test_variants
    python -m pytest tests/test_variants.py -v
"""

import sys
from pathlib import Path

TOOL_ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(TOOL_ROOT))

from components.distill.lib.variants import (
    parse_canonical_file,
    apply_section_removals,
    process_code_blocks,
    generate_variants,
    generate_variants_from_content,
    VariantOptions,
    _fuzzy_find,
    _normalize_for_matching,
)
from components.distill.lib.models import SectionSpec, CodeBlockSpec
from components.distill.lib.canonicalize import canonicalize, load_corrections

try:
    import pytest
    HAS_PYTEST = True
except ImportError:
    HAS_PYTEST = False

FIXTURES_DIR = TOOL_ROOT / 'tests' / 'fixtures'


# =============================================================================
# Fixture-based integration tests
# =============================================================================

def test_section_removal_applied():
    """Test that sections_remove actually removes content from transcript."""
    fixture = FIXTURES_DIR / "002-section-removal"
    input_path = fixture / "input.md"

    if not input_path.exists():
        print("  (skipping - fixture not found)")
        return

    # First canonicalize
    canonical, config, _ = canonicalize(input_path)

    # Then generate variants
    result = generate_variants_from_content(canonical)

    # The sports tangent should be removed
    assert "Lakers" not in result.transcript, "Sports tangent should be removed"
    assert "three-pointer" not in result.transcript, "Sports tangent should be removed"

    # But API content should remain
    assert "REST" in result.transcript
    assert "rate limiting" in result.transcript

    # Removal marker should be present
    assert "[Removed:" in result.transcript


def test_section_lite_removal_applied():
    """Test that sections_lite_remove applies to lite version only."""
    fixture = FIXTURES_DIR / "002-section-removal"
    input_path = fixture / "input.md"

    if not input_path.exists():
        print("  (skipping - fixture not found)")
        return

    canonical, config, _ = canonicalize(input_path)
    # Enable lite generation explicitly (disabled by default)
    options = VariantOptions(generate_lite=True)
    result = generate_variants_from_content(canonical, options)

    # Full transcript should have the endpoint details
    assert "POST /auth/login" in result.transcript

    # Lite version should have replacement text (from fixture config)
    assert "Defined auth endpoints" in result.transcript_lite or "[Removed:" in result.transcript_lite
    assert "POST /auth/login" not in result.transcript_lite


def test_code_block_processing():
    """Test code block actions are applied to lite variant."""
    fixture = FIXTURES_DIR / "004-code-blocks"
    input_path = fixture / "input.md"

    if not input_path.exists():
        print("  (skipping - fixture not found)")
        return

    canonical, config, _ = canonicalize(input_path)
    # Enable lite generation explicitly (disabled by default)
    options = VariantOptions(generate_lite=True)
    result = generate_variants_from_content(canonical, options)

    # Block 1 (action: remove) - removed entirely from lite
    # Block 2 (action: keep) - preserved
    # Block 3 (action: summarize) - replaced with description

    # Full transcript has all code
    assert "class User:" in result.transcript
    assert "EMAIL_PATTERN" in result.transcript or "__init__" in result.transcript

    # Lite version: block 3 summarized (description: "test code demonstrating usage")
    assert "[Code:" in result.transcript_lite
    assert "test code" in result.transcript_lite.lower()


def test_full_export_variant_generation():
    """Test variant generation for complex full export."""
    fixture = FIXTURES_DIR / "005-full-export"
    input_path = fixture / "input.md"

    if not input_path.exists():
        print("  (skipping - fixture not found)")
        return

    corrections = load_corrections(TOOL_ROOT / "components" / "distill" / "config" / "corrections.yaml")
    canonical, config, backmatter = canonicalize(input_path, corrections=corrections)
    result = generate_variants_from_content(canonical)

    # Transcript should exist
    assert result.transcript
    assert "JWT" in result.transcript

    # Section removal should be applied
    assert "TV show" not in result.transcript or "[Removed:" in result.transcript

    # Summary should come from backmatter
    assert result.summary
    assert "JWT authentication" in result.summary


def test_ui_artifacts_cleaned_in_variants():
    """Test that variants don't contain UI artifacts."""
    fixture = FIXTURES_DIR / "001-ui-artifacts"
    input_path = fixture / "input.md"

    if not input_path.exists():
        print("  (skipping - fixture not found)")
        return

    corrections = load_corrections(TOOL_ROOT / "components" / "distill" / "config" / "corrections.yaml")
    canonical, config, _ = canonicalize(input_path, corrections=corrections)
    result = generate_variants_from_content(canonical)

    # No UI artifacts in transcript
    assert "4:02 PM" not in result.transcript
    assert "Show more" not in result.transcript
    assert "5 steps" not in result.transcript


# =============================================================================
# Unit tests for parse_canonical_file
# =============================================================================

def test_parse_canonical_file_basic():
    """Test parsing a basic canonical file."""
    content = """---
title: "Test Title"
slug: 2026-01-24-test
date: 2026-01-24
tags: [test]
---
Main content here.
---

<!-- === BACKMATTER === -->

## Summary

This is the summary.

## Continuation Context

Continue here.
"""
    config, main_content, backmatter = parse_canonical_file(content)

    assert config.title == "Test Title"
    assert config.slug == "2026-01-24-test"
    assert "test" in config.tags
    assert "Main content" in main_content
    assert "summary" in backmatter.summary.lower()
    assert "Continue" in backmatter.continuation


def test_parse_canonical_file_no_backmatter():
    """Test parsing without backmatter."""
    content = """---
title: "Test"
slug: test
date: 2026-01-24
---
Just content.
"""
    config, main_content, backmatter = parse_canonical_file(content)

    assert config.title == "Test"
    assert "Just content" in main_content
    assert backmatter.summary == ""


def test_parse_canonical_file_missing_frontmatter():
    """Test that missing frontmatter raises error."""
    if not HAS_PYTEST:
        print("  (skipping - pytest not available)")
        return

    content = "No frontmatter here."

    with pytest.raises(ValueError, match="must start with YAML frontmatter"):
        parse_canonical_file(content)


# =============================================================================
# Unit tests for apply_section_removals
# =============================================================================

def test_apply_section_removals_basic():
    """Test basic anchor-based section removal."""
    content = """Before the tangent.

Oh by the way, did you see the game?
It was amazing!
Back to work.

After the tangent."""

    specs = [SectionSpec(
        start="Oh by the way",
        end="Back to work.",
        description="off-topic"
    )]

    result, count = apply_section_removals(content, specs)

    assert count == 1
    assert "game" not in result
    assert "[Removed: off-topic]" in result
    assert "Before the tangent" in result
    assert "After the tangent" in result


def test_apply_section_removals_not_found():
    """Test graceful handling when anchors not found."""
    content = "Some content without the anchors."
    specs = [SectionSpec(start="not here", end="also not here")]

    result, count = apply_section_removals(content, specs)

    assert count == 0
    assert result == content


def test_apply_section_removals_with_replacement():
    """Test custom replacement text."""
    content = "Before START secret content END after."
    specs = [SectionSpec(
        start="START",
        end="END",
        replacement="[REDACTED]"
    )]

    result, count = apply_section_removals(content, specs)

    assert count == 1
    assert "[REDACTED]" in result
    assert "secret content" not in result


def test_apply_section_removals_multiple():
    """Test removing multiple sections."""
    content = """Part A.
REMOVE1 stuff1 ENDREMOVE1
Part B.
REMOVE2 stuff2 ENDREMOVE2
Part C."""

    specs = [
        SectionSpec(start="REMOVE1", end="ENDREMOVE1", description="first"),
        SectionSpec(start="REMOVE2", end="ENDREMOVE2", description="second"),
    ]

    result, count = apply_section_removals(content, specs)

    assert count == 2
    assert "stuff1" not in result
    assert "stuff2" not in result
    assert "Part A" in result
    assert "Part B" in result
    assert "Part C" in result


# =============================================================================
# Unit tests for fuzzy matching
# =============================================================================

def test_fuzzy_find_exact():
    """Test exact match."""
    content = "Hello world, this is a test."
    assert _fuzzy_find(content, "world") == 6


def test_fuzzy_find_case_insensitive():
    """Test case-insensitive match."""
    content = "Hello WORLD, this is a test."
    assert _fuzzy_find(content, "world") == 6


def test_fuzzy_find_normalized():
    """Test normalized match with punctuation."""
    content = "Hello, world! This is a test."
    pos = _fuzzy_find(content, "world this")
    assert pos is not None


def test_fuzzy_find_not_found():
    """Test when anchor not found."""
    content = "Hello world."
    assert _fuzzy_find(content, "xyz123") is None


def test_normalize_for_matching():
    """Test text normalization."""
    assert _normalize_for_matching("Hello, World!") == "hello world"
    assert _normalize_for_matching("  Multiple   Spaces  ") == "multiple spaces"
    assert _normalize_for_matching("Punctuation! Is? Removed.") == "punctuation is removed"


# =============================================================================
# Unit tests for process_code_blocks
# =============================================================================

def test_process_code_blocks_keep():
    """Test 'keep' action preserves code."""
    content = """Text.

```python
def hello():
    pass
```

More text."""

    specs = [CodeBlockSpec(id=1, language="python", lines=2, action="keep")]
    result, count = process_code_blocks(content, specs)

    assert count == 0
    assert "def hello" in result


def test_process_code_blocks_summarize():
    """Test 'summarize' replaces code with description."""
    content = """Text.

```python
def hello():
    pass
```

More text."""

    specs = [CodeBlockSpec(
        id=1, language="python", lines=2,
        action="summarize",
        description="Hello function"
    )]
    result, count = process_code_blocks(content, specs)

    assert count == 1
    assert "def hello" not in result
    assert "[Code: Hello function]" in result


def test_process_code_blocks_remove():
    """Test 'remove' deletes code entirely."""
    content = """Text.

```python
def hello():
    pass
```

More text."""

    specs = [CodeBlockSpec(id=1, language="python", lines=2, action="remove")]
    result, count = process_code_blocks(content, specs)

    assert count == 1
    assert "def hello" not in result
    assert "```" not in result


def test_process_code_blocks_multiple():
    """Test processing multiple code blocks."""
    content = """First:
```python
block1
```

Second:
```javascript
block2
```

Third:
```bash
block3
```"""

    specs = [
        CodeBlockSpec(id=1, language="python", lines=1, action="keep"),
        CodeBlockSpec(id=2, language="javascript", lines=1, action="summarize", description="JS code"),
        CodeBlockSpec(id=3, language="bash", lines=1, action="remove"),
    ]
    result, count = process_code_blocks(content, specs)

    assert "block1" in result  # kept
    assert "[Code: JS code]" in result  # summarized
    assert "block3" not in result  # removed


# =============================================================================
# Unit tests for generate_variants
# =============================================================================

def test_generate_variants_from_content_basic():
    """Test basic variant generation."""
    content = """---
title: "Test"
slug: test
date: 2026-01-24
---
Hello!
---

<!-- === BACKMATTER === -->

## Summary

Brief summary.
"""
    # Enable lite generation explicitly (disabled by default)
    options = VariantOptions(generate_lite=True)
    result = generate_variants_from_content(content, options)

    assert result.transcript
    assert "Hello" in result.transcript
    assert result.summary
    assert "Brief summary" in result.summary
    assert result.transcript_lite


def test_generate_variants_options():
    """Test variant options control output."""
    content = """---
title: "Test"
slug: test
date: 2026-01-24
---
Content.
---

<!-- === BACKMATTER === -->

## Summary

Summary.
"""
    options = VariantOptions(
        generate_transcript=True,
        generate_lite=False,
        generate_summary=False
    )

    result = generate_variants_from_content(content, options)

    assert result.transcript
    assert not result.transcript_lite
    assert not result.summary


def test_generate_variants_with_sections_remove():
    """Test sections_remove applied to transcript."""
    content = """---
title: "Test"
slug: test
date: 2026-01-24
sections_remove:
  - start: "START"
    end: "END"
    description: "removed"
---
Keep this.

START
Remove this.
END

Also keep this.
"""
    result = generate_variants_from_content(content)

    assert "Keep this" in result.transcript
    assert "Also keep this" in result.transcript
    assert "Remove this" not in result.transcript
    assert "[Removed: removed]" in result.transcript


def run_all_tests():
    """Run all tests and report results."""
    tests = [
        # Integration tests
        test_section_removal_applied,
        test_section_lite_removal_applied,
        test_code_block_processing,
        test_full_export_variant_generation,
        test_ui_artifacts_cleaned_in_variants,
        # Unit tests - parse_canonical_file
        test_parse_canonical_file_basic,
        test_parse_canonical_file_no_backmatter,
        test_parse_canonical_file_missing_frontmatter,
        # Unit tests - apply_section_removals
        test_apply_section_removals_basic,
        test_apply_section_removals_not_found,
        test_apply_section_removals_with_replacement,
        test_apply_section_removals_multiple,
        # Unit tests - fuzzy matching
        test_fuzzy_find_exact,
        test_fuzzy_find_case_insensitive,
        test_fuzzy_find_normalized,
        test_fuzzy_find_not_found,
        test_normalize_for_matching,
        # Unit tests - process_code_blocks
        test_process_code_blocks_keep,
        test_process_code_blocks_summarize,
        test_process_code_blocks_remove,
        test_process_code_blocks_multiple,
        # Unit tests - generate_variants
        test_generate_variants_from_content_basic,
        test_generate_variants_options,
        test_generate_variants_with_sections_remove,
    ]

    print("\nRunning variants tests...\n")

    passed = 0
    failed = 0

    for test in tests:
        try:
            test()
            print(f"  ✓ {test.__name__}")
            passed += 1
        except AssertionError as e:
            print(f"  ✗ {test.__name__}: {e}")
            failed += 1
        except Exception as e:
            print(f"  ✗ {test.__name__}: {type(e).__name__}: {e}")
            failed += 1

    print(f"\n{passed} passed, {failed} failed")
    return failed == 0


if __name__ == '__main__':
    success = run_all_tests()
    sys.exit(0 if success else 1)
