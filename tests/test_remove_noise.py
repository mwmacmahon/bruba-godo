#!/usr/bin/env python3
"""Tests for remove-noise.py"""

import subprocess
import tempfile
from pathlib import Path

SCRIPT = Path(__file__).parent.parent / "tools" / "helpers" / "remove-noise.py"


def run_remove_noise(file_path: str, dry_run: bool = False, no_renumber: bool = False) -> tuple[str, str]:
    """Run remove-noise.py and return (stdout, file_content)."""
    cmd = ["python3", str(SCRIPT), file_path]
    if dry_run:
        cmd.append("--dry-run")
    if no_renumber:
        cmd.append("--no-renumber")

    result = subprocess.run(cmd, capture_output=True, text=True)

    file_content = Path(file_path).read_text() if Path(file_path).exists() else ""

    return result.stdout, file_content


def test_heartbeat_removal():
    """Test removal of heartbeat sequences."""
    content = """=== MESSAGE 1 | USER ===
[Signal <REDACTED-NAME> id:123 2026-01-28 10:00 EST] Hello there

=== MESSAGE 2 | ASSISTANT ===
Hi! How can I help?

=== MESSAGE 3 | USER ===
[Signal <REDACTED-NAME> id:124 2026-01-28 10:05 EST] Tool call denied: HEARTBEAT check

=== MESSAGE 4 | ASSISTANT ===
HEARTBEAT_OK

=== MESSAGE 5 | USER ===
[Signal <REDACTED-NAME> id:125 2026-01-28 10:10 EST] What's the weather?

=== MESSAGE 6 | ASSISTANT ===
I don't have weather data access.
"""

    with tempfile.NamedTemporaryFile(mode='w', suffix='.md', delete=False) as f:
        f.write(content)
        f.flush()

        stdout, result = run_remove_noise(f.name)

        # Should remove messages 3 and 4
        assert "HEARTBEAT_OK" not in result
        assert "Tool call denied: HEARTBEAT" not in result

        # Should keep messages 1, 2, 5, 6
        assert "Hello there" in result
        assert "How can I help?" in result
        assert "What's the weather?" in result
        assert "weather data access" in result

        # Should be renumbered to 1-4
        assert "MESSAGE 1" in result
        assert "MESSAGE 4" in result
        assert "MESSAGE 5" not in result

        Path(f.name).unlink()


def test_ping_pong_removal():
    """Test removal of empty ping/pong exchanges."""
    content = """=== MESSAGE 1 | USER ===
[Telegram <REDACTED-NAME> id:100 2026-01-28 10:00 EST] test

=== MESSAGE 2 | ASSISTANT ===
Yeah, I'm here.

=== MESSAGE 3 | USER ===
[Telegram <REDACTED-NAME> id:101 2026-01-28 10:01 EST] Great, let's discuss the project

=== MESSAGE 4 | ASSISTANT ===
Sure, what would you like to cover?
"""

    with tempfile.NamedTemporaryFile(mode='w', suffix='.md', delete=False) as f:
        f.write(content)
        f.flush()

        stdout, result = run_remove_noise(f.name)

        # Should remove messages 1 and 2
        assert "test\n" not in result or "test" not in result.split("MESSAGE")[1] if "MESSAGE" in result else True
        assert "Yeah, I'm here" not in result

        # Should keep messages 3 and 4
        assert "discuss the project" in result
        assert "what would you like to cover" in result

        Path(f.name).unlink()


def test_system_error_removal():
    """Test removal of system error messages."""
    content = """=== MESSAGE 1 | USER ===
[Signal <REDACTED-NAME> id:100 2026-01-28 10:00 EST] Help me with code

=== MESSAGE 2 | ASSISTANT ===
502 Bad Gateway - Service temporarily unavailable

=== MESSAGE 3 | USER ===
[Signal <REDACTED-NAME> id:101 2026-01-28 10:01 EST] Try again

=== MESSAGE 4 | ASSISTANT ===
Sure, here's the code you need...
"""

    with tempfile.NamedTemporaryFile(mode='w', suffix='.md', delete=False) as f:
        f.write(content)
        f.flush()

        stdout, result = run_remove_noise(f.name)

        # Should remove message 2
        assert "502 Bad Gateway" not in result

        # Should keep other messages
        assert "Help me with code" in result
        assert "here's the code" in result

        Path(f.name).unlink()


def test_dry_run():
    """Test dry run doesn't modify file."""
    content = """=== MESSAGE 1 | USER ===
[Signal <REDACTED-NAME> id:100 2026-01-28 10:00 EST] test

=== MESSAGE 2 | ASSISTANT ===
I'm here.
"""

    with tempfile.NamedTemporaryFile(mode='w', suffix='.md', delete=False) as f:
        f.write(content)
        f.flush()

        stdout, result = run_remove_noise(f.name, dry_run=True)

        # File should be unchanged
        assert result == content
        assert "dry run" in stdout.lower()

        Path(f.name).unlink()


def test_no_renumber():
    """Test --no-renumber flag preserves original numbers."""
    content = """=== MESSAGE 1 | USER ===
[Signal <REDACTED-NAME> id:100 2026-01-28 10:00 EST] What's the plan for today?

=== MESSAGE 2 | ASSISTANT ===
HEARTBEAT_OK

=== MESSAGE 3 | USER ===
[Signal <REDACTED-NAME> id:101 2026-01-28 10:01 EST] Real question
"""

    with tempfile.NamedTemporaryFile(mode='w', suffix='.md', delete=False) as f:
        f.write(content)
        f.flush()

        stdout, result = run_remove_noise(f.name, no_renumber=True)

        # Message 2 removed, but 1 and 3 keep original numbers
        assert "MESSAGE 1" in result
        assert "MESSAGE 3" in result
        assert "MESSAGE 2" not in result

        Path(f.name).unlink()


def test_no_noise():
    """Test file with no noise is unchanged."""
    content = """=== MESSAGE 1 | USER ===
[Signal <REDACTED-NAME> id:100 2026-01-28 10:00 EST] Help me with a real task

=== MESSAGE 2 | ASSISTANT ===
Sure, here's how to do it...
"""

    with tempfile.NamedTemporaryFile(mode='w', suffix='.md', delete=False) as f:
        f.write(content)
        f.flush()

        stdout, result = run_remove_noise(f.name)

        # File unchanged
        assert result == content
        assert "No noise found" in stdout

        Path(f.name).unlink()


def test_long_message_not_removed():
    """Test that long messages aren't removed even if they mention heartbeat."""
    content = """=== MESSAGE 1 | USER ===
[Signal <REDACTED-NAME> id:100 2026-01-28 10:00 EST] Can you explain what HEARTBEAT_OK means in the context of this system? I've been seeing it in logs and want to understand the architecture better. The system seems to use heartbeat checks to verify the connection is alive, and when it responds with HEARTBEAT_OK it means everything is working correctly. But I'm curious about the implementation details and whether we should adjust the heartbeat interval for better reliability.

=== MESSAGE 2 | ASSISTANT ===
Great question! The heartbeat system works by...
"""

    with tempfile.NamedTemporaryFile(mode='w', suffix='.md', delete=False) as f:
        f.write(content)
        f.flush()

        stdout, result = run_remove_noise(f.name)

        # Long message should be kept even though it mentions HEARTBEAT_OK
        assert "HEARTBEAT_OK means" in result
        assert "implementation details" in result

        Path(f.name).unlink()


def test_multiple_heartbeat_sequences():
    """Test removal of multiple heartbeat sequences."""
    content = """=== MESSAGE 1 | USER ===
[Signal <REDACTED-NAME> id:100 2026-01-28 10:00 EST] Hello

=== MESSAGE 2 | ASSISTANT ===
Hi there!

=== MESSAGE 3 | USER ===
[Signal <REDACTED-NAME> id:101 2026-01-28 10:05 EST] execution denied for heartbeat

=== MESSAGE 4 | ASSISTANT ===
HEARTBEAT_OK

=== MESSAGE 5 | USER ===
[Signal <REDACTED-NAME> id:102 2026-01-28 10:10 EST] Do something

=== MESSAGE 6 | ASSISTANT ===
Done!

=== MESSAGE 7 | USER ===
[Signal <REDACTED-NAME> id:103 2026-01-28 10:15 EST] tool call denied HEARTBEAT

=== MESSAGE 8 | ASSISTANT ===
HEARTBEAT_OK

=== MESSAGE 9 | USER ===
[Signal <REDACTED-NAME> id:104 2026-01-28 10:20 EST] Thanks!
"""

    with tempfile.NamedTemporaryFile(mode='w', suffix='.md', delete=False) as f:
        f.write(content)
        f.flush()

        stdout, result = run_remove_noise(f.name)

        # Should remove 4 noise messages (3, 4, 7, 8)
        assert "4 noise" in stdout or "Found 4" in stdout

        # Remaining should be renumbered 1-5
        assert "MESSAGE 5" in result
        assert "MESSAGE 6" not in result

        # Content check
        assert "Hello" in result
        assert "Hi there!" in result
        assert "Do something" in result
        assert "Thanks!" in result
        assert "HEARTBEAT_OK" not in result

        Path(f.name).unlink()


def run_remove_noise_with_patterns(file_path: str, patterns: list[str], dry_run: bool = False) -> tuple[str, str]:
    """Run remove-noise.py with custom patterns."""
    cmd = ["python3", str(SCRIPT), file_path]
    for p in patterns:
        cmd.extend(["--pattern", p])
    if dry_run:
        cmd.append("--dry-run")

    result = subprocess.run(cmd, capture_output=True, text=True)
    file_content = Path(file_path).read_text() if Path(file_path).exists() else ""
    return result.stdout, file_content


def test_custom_pattern():
    """Test custom pattern passed via --pattern."""
    content = """=== MESSAGE 1 | USER ===
[Signal <REDACTED-NAME> id:100 2026-01-28 10:00 EST] Let's discuss the project

=== MESSAGE 2 | ASSISTANT ===
Sure! What aspect would you like to focus on?

=== MESSAGE 3 | USER ===
[Signal <REDACTED-NAME> id:101 2026-01-28 10:01 EST] IGNORE_THIS_MESSAGE

=== MESSAGE 4 | ASSISTANT ===
Got it, moving on.
"""

    with tempfile.NamedTemporaryFile(mode='w', suffix='.md', delete=False) as f:
        f.write(content)
        f.flush()

        # Custom pattern to match IGNORE_THIS_MESSAGE
        stdout, result = run_remove_noise_with_patterns(f.name, ["IGNORE_THIS_MESSAGE::custom"])

        # Should remove message 3
        assert "IGNORE_THIS_MESSAGE" not in result
        assert "Let's discuss the project" in result
        assert "moving on" in result

        Path(f.name).unlink()


def test_custom_pattern_with_type():
    """Test custom pattern with type annotation."""
    content = """=== MESSAGE 1 | USER ===
[Signal <REDACTED-NAME> id:100 2026-01-28 10:00 EST] Question about code

=== MESSAGE 2 | ASSISTANT ===
[DEBUG] Starting analysis... [/DEBUG] Here's the answer.

=== MESSAGE 3 | USER ===
[Signal <REDACTED-NAME> id:101 2026-01-28 10:01 EST] Thanks!
"""

    with tempfile.NamedTemporaryFile(mode='w', suffix='.md', delete=False) as f:
        f.write(content)
        f.flush()

        # Custom pattern with type
        stdout, result = run_remove_noise_with_patterns(
            f.name,
            [r"^\[DEBUG\].*\[/DEBUG\].*$::debug-output"],
            dry_run=True
        )

        # Dry run, should report finding
        assert "debug-output" in stdout or "Found" in stdout

        Path(f.name).unlink()


def test_no_builtin_flag():
    """Test --no-builtin skips built-in patterns."""
    content = """=== MESSAGE 1 | USER ===
[Signal <REDACTED-NAME> id:100 2026-01-28 10:00 EST] Question

=== MESSAGE 2 | ASSISTANT ===
HEARTBEAT_OK

=== MESSAGE 3 | USER ===
[Signal <REDACTED-NAME> id:101 2026-01-28 10:01 EST] Answer please
"""

    with tempfile.NamedTemporaryFile(mode='w', suffix='.md', delete=False) as f:
        f.write(content)
        f.flush()

        # Run with --no-builtin - should not remove HEARTBEAT_OK
        cmd = ["python3", str(SCRIPT), f.name, "--no-builtin"]
        result = subprocess.run(cmd, capture_output=True, text=True)
        file_content = Path(f.name).read_text()

        # HEARTBEAT_OK should still be there since built-ins are skipped
        assert "HEARTBEAT_OK" in file_content
        assert "No noise found" in result.stdout

        Path(f.name).unlink()


if __name__ == "__main__":
    test_heartbeat_removal()
    print("✓ test_heartbeat_removal")

    test_ping_pong_removal()
    print("✓ test_ping_pong_removal")

    test_system_error_removal()
    print("✓ test_system_error_removal")

    test_dry_run()
    print("✓ test_dry_run")

    test_no_renumber()
    print("✓ test_no_renumber")

    test_no_noise()
    print("✓ test_no_noise")

    test_long_message_not_removed()
    print("✓ test_long_message_not_removed")

    test_multiple_heartbeat_sequences()
    print("✓ test_multiple_heartbeat_sequences")

    test_custom_pattern()
    print("✓ test_custom_pattern")

    test_custom_pattern_with_type()
    print("✓ test_custom_pattern_with_type")

    test_no_builtin_flag()
    print("✓ test_no_builtin_flag")

    print("\nAll tests passed!")
