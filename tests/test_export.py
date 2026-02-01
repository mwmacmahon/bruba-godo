#!/usr/bin/env python3
"""
Tests for export pipeline routing and frontmatter preservation.

These tests verify:
- Export routing based on frontmatter type
- Frontmatter preservation in variant output
- Type/scope parsing from frontmatter

Run with:
    python tests/run_tests.py test_export
    python -m pytest tests/test_export.py -v
"""

import sys
from pathlib import Path

TOOL_ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(TOOL_ROOT))

from components.distill.lib.models import CanonicalConfig
from components.distill.lib.parsing import parse_v2_config_block
from components.distill.lib.variants import (
    parse_canonical_file,
    generate_variants_from_content,
    VariantOptions,
)

# Import the routing function - need to access it from cli module
from components.distill.lib.cli import _get_content_subdirectory_and_prefix, _write_if_changed
import tempfile
import os

try:
    import pytest
    HAS_PYTEST = True
except ImportError:
    HAS_PYTEST = False


# =============================================================================
# Unit tests for type/scope parsing
# =============================================================================

def test_parse_type_from_frontmatter():
    """Test that type field is parsed from frontmatter."""
    block = """
title: "Test Doc"
slug: test-doc
date: 2026-01-31
type: doc
scope: reference
"""
    config = parse_v2_config_block(block)

    assert config.type == "doc"
    assert config.scope == "reference"
    assert config.title == "Test Doc"


def test_parse_type_refdoc():
    """Test parsing refdoc type."""
    block = """
title: "Reference Document"
slug: ref-doc
date: 2026-01-31
type: refdoc
scope: reference
"""
    config = parse_v2_config_block(block)

    assert config.type == "refdoc"
    assert config.scope == "reference"


def test_parse_type_transcript():
    """Test parsing transcript type."""
    block = """
title: "Conversation"
slug: convo
date: 2026-01-31
type: transcript
scope: transcripts
"""
    config = parse_v2_config_block(block)

    assert config.type == "transcript"
    assert config.scope == "transcripts"


def test_parse_type_missing():
    """Test that missing type defaults to empty string."""
    block = """
title: "No Type"
slug: no-type
date: 2026-01-31
"""
    config = parse_v2_config_block(block)

    assert config.type == ""
    assert config.scope == ""


def test_parse_canonical_file_with_type_scope():
    """Test parse_canonical_file preserves type and scope."""
    content = """---
title: "My Document"
slug: my-doc
date: 2026-01-31
type: doc
scope: reference
---
Document content here.
"""
    config, main_content, backmatter = parse_canonical_file(content)

    assert config.type == "doc"
    assert config.scope == "reference"
    assert config.title == "My Document"
    assert "Document content" in main_content


# =============================================================================
# Unit tests for export routing
# =============================================================================

def test_routing_type_doc():
    """Test that type: doc routes to docs/ with Doc - prefix."""
    config = CanonicalConfig(
        title="Test",
        slug="test",
        date="2026-01-31",
        type="doc",
        scope="reference"
    )
    path = Path("docs/README.md")

    subdir, prefix = _get_content_subdirectory_and_prefix(path, config)

    assert subdir == "docs"
    assert prefix == "Doc - "


def test_routing_type_refdoc():
    """Test that type: refdoc routes to refdocs/ with Refdoc - prefix."""
    config = CanonicalConfig(
        title="Test",
        slug="test",
        date="2026-01-31",
        type="refdoc",
        scope="reference"
    )
    path = Path("reference/refdocs/test.md")

    subdir, prefix = _get_content_subdirectory_and_prefix(path, config)

    assert subdir == "refdocs"
    assert prefix == "Refdoc - "


def test_routing_type_transcript():
    """Test that type: transcript routes to transcripts/ with Transcript - prefix."""
    config = CanonicalConfig(
        title="Test",
        slug="test",
        date="2026-01-31",
        type="transcript",
        scope="transcripts"
    )
    path = Path("reference/transcripts/test.md")

    subdir, prefix = _get_content_subdirectory_and_prefix(path, config)

    assert subdir == "transcripts"
    assert prefix == "Transcript - "


def test_routing_type_takes_priority_over_path():
    """Test that frontmatter type takes priority over source path."""
    # File is in transcripts/ but type says doc
    config = CanonicalConfig(
        title="Test",
        slug="test",
        date="2026-01-31",
        type="doc",
        scope="reference"
    )
    path = Path("reference/transcripts/actually-a-doc.md")

    subdir, prefix = _get_content_subdirectory_and_prefix(path, config)

    # Type should win
    assert subdir == "docs"
    assert prefix == "Doc - "


def test_routing_fallback_to_path_when_no_type():
    """Test that path is used when no type is specified."""
    config = CanonicalConfig(
        title="Test",
        slug="test",
        date="2026-01-31"
        # No type or scope
    )

    # Test transcripts path
    path = Path("reference/transcripts/test.md")
    subdir, prefix = _get_content_subdirectory_and_prefix(path, config)
    assert subdir == "transcripts"

    # Test refdocs path
    path = Path("reference/refdocs/test.md")
    subdir, prefix = _get_content_subdirectory_and_prefix(path, config)
    assert subdir == "refdocs"

    # Test docs path
    path = Path("docs/test.md")
    subdir, prefix = _get_content_subdirectory_and_prefix(path, config)
    assert subdir == "docs"


def test_routing_default_to_artifacts():
    """Test that unknown paths default to artifacts."""
    config = CanonicalConfig(
        title="Test",
        slug="test",
        date="2026-01-31"
    )
    path = Path("some/random/path.md")

    subdir, prefix = _get_content_subdirectory_and_prefix(path, config)

    assert subdir == "artifacts"
    assert prefix == "Artifact - "


# =============================================================================
# Unit tests for frontmatter preservation in variant output
# =============================================================================

def test_variant_preserves_type_doc():
    """Test that type: doc is preserved in variant output."""
    content = """---
title: "My Document"
slug: my-doc
date: 2026-01-31
type: doc
scope: reference
---
Document content here.
"""
    result = generate_variants_from_content(content)

    # Check the output has correct type
    assert "type: doc" in result.transcript
    assert "scope: reference" in result.transcript
    # Should NOT have "End of Transcript" footer
    assert "End of Transcript" not in result.transcript


def test_variant_preserves_type_refdoc():
    """Test that type: refdoc is preserved in variant output."""
    content = """---
title: "Reference Doc"
slug: ref-doc
date: 2026-01-31
type: refdoc
scope: reference
---
Reference content.
"""
    result = generate_variants_from_content(content)

    assert "type: refdoc" in result.transcript
    assert "scope: reference" in result.transcript
    assert "End of Transcript" not in result.transcript


def test_variant_adds_footer_for_transcript():
    """Test that type: transcript gets End of Transcript footer."""
    content = """---
title: "Conversation"
slug: convo
date: 2026-01-31
type: transcript
scope: transcripts
---
Conversation content.
"""
    result = generate_variants_from_content(content)

    assert "type: transcript" in result.transcript
    assert "End of Transcript" in result.transcript


def test_variant_adds_footer_when_no_type():
    """Test that missing type defaults to transcript behavior with footer."""
    content = """---
title: "No Type"
slug: no-type
date: 2026-01-31
---
Some content.
"""
    result = generate_variants_from_content(content)

    # Should default to transcript type and have footer
    assert "type: transcript" in result.transcript
    assert "End of Transcript" in result.transcript


def test_variant_no_scope_when_missing():
    """Test that scope is not added when not present in original."""
    content = """---
title: "No Scope"
slug: no-scope
date: 2026-01-31
type: transcript
---
Content.
"""
    result = generate_variants_from_content(content)

    # Should have type but no scope line
    assert "type: transcript" in result.transcript
    # Scope line should not exist
    lines = result.transcript.split('\n')
    scope_lines = [l for l in lines if l.startswith('scope:')]
    assert len(scope_lines) == 0


# =============================================================================
# Integration test
# =============================================================================

def test_full_doc_export_flow():
    """Integration test: doc type parses, routes, and outputs correctly."""
    content = """---
title: "Full Test Document"
slug: full-test
date: 2026-01-31
type: doc
scope: reference
description: "A test document"
tags: [test, docs]
---

# Full Test Document

This is a complete test of the doc export flow.

## Section 1

Some content here.

## Section 2

More content.
"""
    # Parse
    config, main_content, backmatter = parse_canonical_file(content)
    assert config.type == "doc"
    assert config.scope == "reference"

    # Route
    path = Path("docs/full-test.md")
    subdir, prefix = _get_content_subdirectory_and_prefix(path, config)
    assert subdir == "docs"
    assert prefix == "Doc - "

    # Generate variant
    result = generate_variants_from_content(content)
    assert "type: doc" in result.transcript
    assert "scope: reference" in result.transcript
    assert "End of Transcript" not in result.transcript
    assert "Full Test Document" in result.transcript


def test_full_refdoc_export_flow():
    """Integration test: refdoc type parses, routes, and outputs correctly."""
    content = """---
title: "Reference Doc Test"
slug: ref-test
date: 2026-01-31
type: refdoc
scope: reference
---

External reference content.
"""
    # Parse
    config, main_content, backmatter = parse_canonical_file(content)
    assert config.type == "refdoc"

    # Route
    path = Path("reference/refdocs/ref-test.md")
    subdir, prefix = _get_content_subdirectory_and_prefix(path, config)
    assert subdir == "refdocs"
    assert prefix == "Refdoc - "

    # Generate variant
    result = generate_variants_from_content(content)
    assert "type: refdoc" in result.transcript
    assert "End of Transcript" not in result.transcript


# =============================================================================
# Unit tests for _write_if_changed
# =============================================================================

def test_write_if_changed_creates_new_file():
    """Test that _write_if_changed creates a new file."""
    with tempfile.TemporaryDirectory() as tmpdir:
        path = Path(tmpdir) / "new_file.md"
        content = "Hello, world!"

        result = _write_if_changed(path, content)

        assert result is True
        assert path.exists()
        assert path.read_text() == content


def test_write_if_changed_skips_identical():
    """Test that _write_if_changed skips writing identical content."""
    with tempfile.TemporaryDirectory() as tmpdir:
        path = Path(tmpdir) / "existing.md"
        content = "Same content"

        # Create initial file
        path.write_text(content)
        original_mtime = os.path.getmtime(path)

        # Small delay to ensure mtime would change if written
        import time
        time.sleep(0.01)

        # Try to write same content
        result = _write_if_changed(path, content)

        assert result is False
        # mtime should be unchanged
        assert os.path.getmtime(path) == original_mtime


def test_write_if_changed_overwrites_different():
    """Test that _write_if_changed overwrites when content differs."""
    with tempfile.TemporaryDirectory() as tmpdir:
        path = Path(tmpdir) / "changing.md"

        # Create initial file
        path.write_text("Original content")
        original_mtime = os.path.getmtime(path)

        # Small delay
        import time
        time.sleep(0.01)

        # Write different content
        new_content = "Updated content"
        result = _write_if_changed(path, new_content)

        assert result is True
        assert path.read_text() == new_content
        # mtime should have changed
        assert os.path.getmtime(path) != original_mtime


def test_write_if_changed_handles_empty_file():
    """Test that _write_if_changed handles empty files correctly."""
    with tempfile.TemporaryDirectory() as tmpdir:
        path = Path(tmpdir) / "empty.md"

        # Create empty file
        path.write_text("")

        # Write empty content - should skip
        result = _write_if_changed(path, "")
        assert result is False

        # Write non-empty content - should write
        result = _write_if_changed(path, "content")
        assert result is True
        assert path.read_text() == "content"


# =============================================================================
# Test runner
# =============================================================================

def run_all_tests():
    """Run all tests and report results."""
    tests = [
        # Type/scope parsing
        test_parse_type_from_frontmatter,
        test_parse_type_refdoc,
        test_parse_type_transcript,
        test_parse_type_missing,
        test_parse_canonical_file_with_type_scope,
        # Export routing
        test_routing_type_doc,
        test_routing_type_refdoc,
        test_routing_type_transcript,
        test_routing_type_takes_priority_over_path,
        test_routing_fallback_to_path_when_no_type,
        test_routing_default_to_artifacts,
        # Frontmatter preservation
        test_variant_preserves_type_doc,
        test_variant_preserves_type_refdoc,
        test_variant_adds_footer_for_transcript,
        test_variant_adds_footer_when_no_type,
        test_variant_no_scope_when_missing,
        # Integration
        test_full_doc_export_flow,
        test_full_refdoc_export_flow,
        # Write if changed
        test_write_if_changed_creates_new_file,
        test_write_if_changed_skips_identical,
        test_write_if_changed_overwrites_different,
        test_write_if_changed_handles_empty_file,
    ]

    print("\nRunning export pipeline tests...\n")

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
