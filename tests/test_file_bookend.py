#!/usr/bin/env python3
"""Tests for file-bookend.py"""

import subprocess
import tempfile
from pathlib import Path

SCRIPT = Path(__file__).parent.parent / "tools" / "helpers" / "file-bookend.py"


def run_bookend(file_path: str, content: str, prepend: bool = False, use_stdin: bool = True) -> str:
    """Run file-bookend.py and return stdout."""
    cmd = ["python3", str(SCRIPT), file_path]
    if prepend:
        cmd.append("--prepend")

    if use_stdin:
        result = subprocess.run(cmd, input=content, capture_output=True, text=True)
    else:
        cmd.extend(["--content", content])
        result = subprocess.run(cmd, capture_output=True, text=True)

    if result.returncode != 0:
        raise RuntimeError(f"Script failed: {result.stderr}")

    return result.stdout


def test_append_basic():
    """Test basic append functionality."""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as f:
        f.write("original content\n")
        f.flush()

        run_bookend(f.name, "appended content")

        result = Path(f.name).read_text()
        assert "original content" in result
        assert "appended content" in result
        assert result.index("original") < result.index("appended")

        Path(f.name).unlink()


def test_prepend_basic():
    """Test basic prepend functionality."""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as f:
        f.write("original content\n")
        f.flush()

        run_bookend(f.name, "prepended content", prepend=True)

        result = Path(f.name).read_text()
        assert "original content" in result
        assert "prepended content" in result
        assert result.index("prepended") < result.index("original")

        Path(f.name).unlink()


def test_append_via_content_flag():
    """Test append using --content flag instead of stdin."""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as f:
        f.write("original\n")
        f.flush()

        run_bookend(f.name, "via flag", use_stdin=False)

        result = Path(f.name).read_text()
        assert "original" in result
        assert "via flag" in result

        Path(f.name).unlink()


def test_append_multiline():
    """Test appending multiline content."""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as f:
        f.write("line 1\n")
        f.flush()

        multiline = """=== CONFIG ===
key: value
list:
  - item1
  - item2
=== END CONFIG ==="""

        run_bookend(f.name, multiline)

        result = Path(f.name).read_text()
        assert "line 1" in result
        assert "=== CONFIG ===" in result
        assert "- item1" in result
        assert "=== END CONFIG ===" in result

        Path(f.name).unlink()


def test_prepend_multiline():
    """Test prepending multiline content."""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as f:
        f.write("=== MESSAGE 1 ===\nContent here\n")
        f.flush()

        frontmatter = """---
title: Test
date: 2026-01-01
---"""

        run_bookend(f.name, frontmatter, prepend=True)

        result = Path(f.name).read_text()
        assert result.startswith("---\ntitle: Test")
        assert "=== MESSAGE 1 ===" in result

        Path(f.name).unlink()


def test_file_not_found():
    """Test error on non-existent file."""
    result = subprocess.run(
        ["python3", str(SCRIPT), "/nonexistent/file.txt"],
        input="content",
        capture_output=True,
        text=True
    )
    assert result.returncode != 0
    assert "does not exist" in result.stderr


def test_empty_content():
    """Test error on empty content."""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as f:
        f.write("original\n")
        f.flush()

        result = subprocess.run(
            ["python3", str(SCRIPT), f.name],
            input="",
            capture_output=True,
            text=True
        )
        assert result.returncode != 0
        assert "No content" in result.stderr

        Path(f.name).unlink()


if __name__ == "__main__":
    test_append_basic()
    print("✓ test_append_basic")

    test_prepend_basic()
    print("✓ test_prepend_basic")

    test_append_via_content_flag()
    print("✓ test_append_via_content_flag")

    test_append_multiline()
    print("✓ test_append_multiline")

    test_prepend_multiline()
    print("✓ test_prepend_multiline")

    test_file_not_found()
    print("✓ test_file_not_found")

    test_empty_content()
    print("✓ test_empty_content")

    print("\nAll tests passed!")
