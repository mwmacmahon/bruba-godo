#!/usr/bin/env python3
"""
Tests for tools/helpers/convert-doc.py

Run with:
    python tests/run_tests.py test_convert_doc
    python -m pytest tests/test_convert_doc.py -v
"""

import subprocess
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

TOOL_ROOT = Path(__file__).parent.parent
SCRIPT_PATH = TOOL_ROOT / "tools" / "helpers" / "convert-doc.py"

try:
    import pytest
    HAS_PYTEST = True
except ImportError:
    HAS_PYTEST = False


# =============================================================================
# CLI tests (subprocess)
# =============================================================================

def test_missing_file_arg_shows_usage():
    """Running without args should show usage and exit 2 (argparse)."""
    result = subprocess.run(
        [sys.executable, str(SCRIPT_PATH)],
        capture_output=True,
        text=True
    )
    assert result.returncode == 2  # argparse exits with 2 for missing args
    assert "usage:" in result.stderr.lower()
    assert "file" in result.stderr.lower()


def test_missing_api_key_error():
    """Running without ANTHROPIC_API_KEY should error."""
    # Create a temp file
    import tempfile
    with tempfile.NamedTemporaryFile(mode='w', suffix='.md', delete=False) as f:
        f.write("# Test\nContent here.")
        temp_path = f.name

    try:
        # Run with empty env to ensure no API key
        result = subprocess.run(
            [sys.executable, str(SCRIPT_PATH), temp_path],
            capture_output=True,
            text=True,
            env={"PATH": "/usr/bin:/bin"}  # Minimal env, no API key
        )
        assert result.returncode == 1
        # Should mention authentication or API key
        assert "api_key" in result.stderr.lower() or "auth" in result.stderr.lower()
    finally:
        Path(temp_path).unlink()


def test_nonexistent_file_error():
    """Running with nonexistent file should error."""
    result = subprocess.run(
        [sys.executable, str(SCRIPT_PATH), "/nonexistent/path/file.md"],
        capture_output=True,
        text=True
    )
    assert result.returncode != 0
    assert "not found" in result.stderr.lower() or "error" in result.stderr.lower()


def test_help_flag():
    """--help should show usage and model options."""
    result = subprocess.run(
        [sys.executable, str(SCRIPT_PATH), "--help"],
        capture_output=True,
        text=True
    )
    assert result.returncode == 0
    assert "--model" in result.stdout or "-m" in result.stdout
    assert "opus" in result.stdout
    assert "sonnet" in result.stdout
    assert "haiku" in result.stdout


def test_invalid_model_rejected():
    """Invalid model choice should be rejected."""
    import tempfile
    with tempfile.NamedTemporaryFile(mode='w', suffix='.md', delete=False) as f:
        f.write("# Test")
        temp_path = f.name

    try:
        result = subprocess.run(
            [sys.executable, str(SCRIPT_PATH), temp_path, "--model", "invalid"],
            capture_output=True,
            text=True
        )
        assert result.returncode == 2  # argparse error
        assert "invalid" in result.stderr.lower()
    finally:
        Path(temp_path).unlink()


# =============================================================================
# Unit tests (mocked)
# =============================================================================

def test_script_structure():
    """Verify the script has the expected structure."""
    content = SCRIPT_PATH.read_text()

    # Has shebang
    assert content.startswith("#!/usr/bin/env python3")

    # Imports anthropic
    assert "import anthropic" in content

    # Has main function
    assert "def main():" in content

    # Uses messages.create
    assert "messages.create" in content

    # Outputs to stdout
    assert "print(response" in content


def test_script_uses_env_api_key():
    """Script should use ANTHROPIC_API_KEY from environment."""
    content = SCRIPT_PATH.read_text()

    # Uses Anthropic() without explicit key (reads from env)
    assert "anthropic.Anthropic()" in content


def test_prompt_formatting():
    """Verify prompt is formatted correctly in the script."""
    content = SCRIPT_PATH.read_text()

    # Combines prompt and content with separator
    assert '---' in content
    assert 'prompt' in content.lower()
    assert 'content' in content


def test_default_prompt_provided():
    """Script should have a default prompt when none specified."""
    content = SCRIPT_PATH.read_text()

    # Default prompt text exists
    assert "Convert this document" in content


def test_max_tokens_reasonable():
    """max_tokens should be set to a reasonable value."""
    content = SCRIPT_PATH.read_text()

    # Has max_tokens setting
    assert "max_tokens" in content
    # Value should be reasonable (at least 4096)
    assert "8192" in content or "4096" in content


def test_model_flag_structure():
    """Script should have model selection with opus as default."""
    content = SCRIPT_PATH.read_text()

    # Has MODELS dict
    assert "MODELS" in content
    assert '"opus"' in content
    assert '"sonnet"' in content
    assert '"haiku"' in content

    # Default is opus
    assert 'default="opus"' in content

    # Uses argparse
    assert "argparse" in content
    assert "--model" in content or '"-m"' in content


def test_model_ids_correct():
    """Model IDs should be valid Claude model identifiers."""
    content = SCRIPT_PATH.read_text()

    # Check model ID format
    assert "claude-opus-4" in content
    assert "claude-sonnet-4" in content
    assert "claude-haiku-4" in content


# =============================================================================
# Integration tests (require API key)
# =============================================================================

def test_integration_with_api_key():
    """Integration test - only runs if ANTHROPIC_API_KEY is set."""
    import os
    if not os.environ.get("ANTHROPIC_API_KEY"):
        print("  (skipping - ANTHROPIC_API_KEY not set)")
        return

    import tempfile
    with tempfile.NamedTemporaryFile(mode='w', suffix='.md', delete=False) as f:
        f.write("# Simple Test\n\nThis is a test document.")
        temp_path = f.name

    try:
        result = subprocess.run(
            [sys.executable, str(SCRIPT_PATH), temp_path, "Echo back the title of this document"],
            capture_output=True,
            text=True,
            timeout=30
        )
        # Should succeed
        assert result.returncode == 0, f"stderr: {result.stderr}"
        # Should have some output
        assert len(result.stdout) > 0
    finally:
        Path(temp_path).unlink()


def test_multi_invocation_workflow():
    """
    Test the full CC workflow: exploratory → refinement → final config.

    Simulates how CC would use the script:
    1. First call: Explore the document structure
    2. Second call: Generate initial frontmatter
    3. Third call: Refine with specific requirements

    Only runs if ANTHROPIC_API_KEY is set.
    """
    import os
    if not os.environ.get("ANTHROPIC_API_KEY"):
        print("  (skipping - ANTHROPIC_API_KEY not set)")
        return

    import tempfile

    # Sample document without frontmatter
    sample_doc = """# Meeting Notes: API Design Discussion

## Attendees
- Alice (Tech Lead)
- Bob (Backend)
- Carol (Frontend)

## Discussion

We discussed the new REST API design for user authentication.

**Alice:** We should use JWT tokens with short expiration.

**Bob:** Agreed. I'll implement refresh token rotation.

**Carol:** The frontend needs clear error codes for auth failures.

## Action Items

1. Bob: Implement JWT with 15-min expiry
2. Carol: Add error handling for 401/403 responses
3. Alice: Review security requirements doc

## Next Steps

Follow-up meeting scheduled for Friday.
"""

    with tempfile.NamedTemporaryFile(mode='w', suffix='.md', delete=False) as f:
        f.write(sample_doc)
        temp_path = f.name

    try:
        # Invocation 1: Exploratory - understand the document
        result1 = subprocess.run(
            [sys.executable, str(SCRIPT_PATH), temp_path,
             "Analyze this document. What type of content is it? List the key topics covered."],
            capture_output=True,
            text=True,
            timeout=60
        )
        assert result1.returncode == 0, f"Invocation 1 failed: {result1.stderr}"
        assert len(result1.stdout) > 50, "Exploratory response too short"
        # Should identify it as meeting notes or similar
        output1_lower = result1.stdout.lower()
        assert any(word in output1_lower for word in ["meeting", "notes", "discussion", "api"]), \
            f"Expected document type identification, got: {result1.stdout[:200]}"

        # Invocation 2: Generate initial frontmatter
        result2 = subprocess.run(
            [sys.executable, str(SCRIPT_PATH), temp_path,
             "Add YAML frontmatter with: title, date (use 2026-01-31), type, and tags. Return the complete document."],
            capture_output=True,
            text=True,
            timeout=60
        )
        assert result2.returncode == 0, f"Invocation 2 failed: {result2.stderr}"
        assert "---" in result2.stdout, "Frontmatter delimiter missing"
        assert "title:" in result2.stdout.lower(), "Title field missing"

        # Invocation 3: Refine with specific requirements
        result3 = subprocess.run(
            [sys.executable, str(SCRIPT_PATH), temp_path,
             """Add YAML frontmatter with these exact fields:
- title: descriptive title
- date: 2026-01-31
- type: transcript
- scope: reference
- tags: list of relevant tags
- participants: list of attendee names

Return ONLY the frontmatter block (--- to ---), nothing else."""],
            capture_output=True,
            text=True,
            timeout=60
        )
        assert result3.returncode == 0, f"Invocation 3 failed: {result3.stderr}"
        output3 = result3.stdout

        # Verify frontmatter structure
        assert output3.strip().startswith("---"), "Should start with frontmatter delimiter"
        assert "scope:" in output3.lower(), "Scope field missing"
        assert "participants:" in output3.lower() or "attendees:" in output3.lower(), \
            "Participants field missing"

        print(f"    Invocation 1: {len(result1.stdout)} chars (exploratory)")
        print(f"    Invocation 2: {len(result2.stdout)} chars (initial config)")
        print(f"    Invocation 3: {len(result3.stdout)} chars (refined config)")

    finally:
        Path(temp_path).unlink()


def test_different_prompts_same_file():
    """
    Verify that different prompts on the same file produce different outputs.

    This confirms the script is stateless and each invocation is independent.
    Only runs if ANTHROPIC_API_KEY is set.
    """
    import os
    if not os.environ.get("ANTHROPIC_API_KEY"):
        print("  (skipping - ANTHROPIC_API_KEY not set)")
        return

    import tempfile

    with tempfile.NamedTemporaryFile(mode='w', suffix='.md', delete=False) as f:
        f.write("# Hello World\n\nThis is a simple test document about Python programming.")
        temp_path = f.name

    try:
        # First prompt: count words
        result1 = subprocess.run(
            [sys.executable, str(SCRIPT_PATH), temp_path,
             "Count the words in this document. Return just the number."],
            capture_output=True,
            text=True,
            timeout=30
        )

        # Second prompt: summarize
        result2 = subprocess.run(
            [sys.executable, str(SCRIPT_PATH), temp_path,
             "Summarize this in exactly 5 words."],
            capture_output=True,
            text=True,
            timeout=30
        )

        assert result1.returncode == 0
        assert result2.returncode == 0
        # Outputs should be different
        assert result1.stdout.strip() != result2.stdout.strip(), \
            "Same file with different prompts should produce different outputs"

    finally:
        Path(temp_path).unlink()


# =============================================================================
# Test runner
# =============================================================================

def run_all_tests():
    """Run all tests and report results."""
    tests = [
        # CLI tests
        test_missing_file_arg_shows_usage,
        test_missing_api_key_error,
        test_nonexistent_file_error,
        test_help_flag,
        test_invalid_model_rejected,
        # Unit tests
        test_script_structure,
        test_script_uses_env_api_key,
        test_prompt_formatting,
        test_default_prompt_provided,
        test_max_tokens_reasonable,
        test_model_flag_structure,
        test_model_ids_correct,
        # Integration (require API key)
        test_integration_with_api_key,
        test_multi_invocation_workflow,
        test_different_prompts_same_file,
    ]

    print("\nRunning convert-doc tests...\n")

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
