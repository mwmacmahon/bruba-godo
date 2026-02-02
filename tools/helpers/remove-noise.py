#!/usr/bin/env python3
"""Remove noise messages from intake files without loading into LLM context.

Noise patterns:
- Heartbeat sequences (exec denial + HEARTBEAT_OK response pairs)
- System errors (gateway timeouts, connection errors)
- Empty ping/pong exchanges ("test", "you up", etc.)
"""

import re
import sys
import json
import argparse
from pathlib import Path


# Message delimiter pattern
MSG_PATTERN = re.compile(r'^=== MESSAGE (\d+) \| (USER|ASSISTANT) ===$', re.MULTILINE)

# Noise patterns - if a message matches, it's noise
# Format: (compiled_regex, noise_type)
NOISE_PATTERNS = [
    # Heartbeat responses (standalone HEARTBEAT_OK)
    (re.compile(r'^\s*HEARTBEAT_OK\s*$'), 'heartbeat'),

    # Heartbeat triggers (exec denials for heartbeat)
    (re.compile(r'execution\s+denied.*heartbeat', re.IGNORECASE), 'heartbeat'),
    (re.compile(r'tool\s+call.*denied.*HEARTBEAT', re.IGNORECASE), 'heartbeat'),

    # System errors
    (re.compile(r'^\s*(?:502\s+bad\s+gateway|503\s+service\s+unavailable|gateway\s+timeout)', re.IGNORECASE), 'system-error'),
    (re.compile(r'^\s*(?:ETIMEDOUT|ECONNRESET|ECONNREFUSED)', re.IGNORECASE), 'system-error'),

    # Empty test messages - ONLY match if entire content (after wrapper) is just the word
    # Pattern: [Signal/Telegram wrapper] followed by ONLY "test" or "ping" etc
    (re.compile(r'^\[(?:Signal|Telegram)[^\]]+\]\s*(?:test|ping|you up\??)\s*$', re.IGNORECASE), 'ping'),

    # Generic "I'm here" responses to pings - must be the whole message
    (re.compile(r"^(?:Yeah,?\s+)?I'?m\s+(?:here|alive|up|awake)\.?\s*$", re.IGNORECASE), 'ping-response'),
]

# Patterns for messages that should be kept even if they look like noise
KEEP_PATTERNS = [
    # Substantive content mixed with heartbeat mention
    re.compile(r'.{200,}', re.DOTALL),  # Long messages are probably substantive
]


def parse_messages(content: str) -> list[dict]:
    """Parse file into list of message dicts with start/end positions."""
    messages = []

    for match in MSG_PATTERN.finditer(content):
        msg_num = int(match.group(1))
        role = match.group(2)
        start = match.start()
        messages.append({
            'num': msg_num,
            'role': role,
            'header_start': start,
            'content_start': match.end() + 1,  # +1 for newline after header
            'content': None,
            'end': None,
        })

    # Set content and end positions
    for i, msg in enumerate(messages):
        if i + 1 < len(messages):
            msg['end'] = messages[i + 1]['header_start']
        else:
            msg['end'] = len(content)
        msg['content'] = content[msg['content_start']:msg['end']].strip()

    return messages


def is_noise(msg: dict, extra_patterns: list[tuple] = None, skip_builtin: bool = False) -> tuple[bool, str]:
    """Check if a message is noise. Returns (is_noise, noise_type)."""
    content = msg['content']

    # Check keep patterns first
    for pattern in KEEP_PATTERNS:
        if pattern.search(content):
            return False, ''

    # Check built-in noise patterns
    if not skip_builtin:
        for pattern, noise_type in NOISE_PATTERNS:
            if pattern.search(content):
                return True, noise_type

    # Check custom patterns
    if extra_patterns:
        for pattern, noise_type in extra_patterns:
            if pattern.search(content):
                return True, noise_type

    return False, ''


def find_noise_sequences(messages: list[dict], extra_patterns: list[tuple] = None, skip_builtin: bool = False) -> list[dict]:
    """Find noise messages and related sequences (e.g., heartbeat pairs)."""
    noise_msgs = []
    skip_next = False

    for i, msg in enumerate(messages):
        if skip_next:
            skip_next = False
            continue

        is_noisy, noise_type = is_noise(msg, extra_patterns, skip_builtin)

        if is_noisy:
            noise_msgs.append({
                'msg': msg,
                'type': noise_type,
            })

            # If this is a heartbeat trigger, the next message is likely HEARTBEAT_OK
            if noise_type == 'heartbeat' and msg['role'] == 'USER':
                if i + 1 < len(messages):
                    next_msg = messages[i + 1]
                    next_is_noisy, next_type = is_noise(next_msg, extra_patterns, skip_builtin)
                    if next_is_noisy and next_type == 'heartbeat':
                        noise_msgs.append({
                            'msg': next_msg,
                            'type': next_type,
                        })
                        skip_next = True

            # If this is a ping, check if next is a ping response
            if noise_type == 'ping' and msg['role'] == 'USER':
                if i + 1 < len(messages):
                    next_msg = messages[i + 1]
                    next_is_noisy, next_type = is_noise(next_msg, extra_patterns, skip_builtin)
                    if next_is_noisy and next_type == 'ping-response':
                        noise_msgs.append({
                            'msg': next_msg,
                            'type': next_type,
                        })
                        skip_next = True

    return noise_msgs


def remove_noise(content: str, noise_msgs: list[dict]) -> str:
    """Remove noise messages from content."""
    if not noise_msgs:
        return content

    # Sort by position descending so we can remove from end to start
    noise_msgs = sorted(noise_msgs, key=lambda x: x['msg']['header_start'], reverse=True)

    result = content
    for noise in noise_msgs:
        msg = noise['msg']
        result = result[:msg['header_start']] + result[msg['end']:]

    # Clean up multiple blank lines
    result = re.sub(r'\n{3,}', '\n\n', result)

    return result


def renumber_messages(content: str) -> str:
    """Renumber messages sequentially after removal."""
    counter = [0]  # Use list to allow modification in nested function

    def replace_msg_num(match):
        counter[0] += 1
        return f"=== MESSAGE {counter[0]} | {match.group(1)} ==="

    return re.sub(r'=== MESSAGE \d+ \| (USER|ASSISTANT) ===', replace_msg_num, content)


def load_custom_patterns(pattern_args: list[str], pattern_file: str = None) -> list[tuple]:
    """Load custom patterns from arguments or file.

    Patterns can be:
    - Simple regex: "pattern" (type defaults to 'custom')
    - With type: "pattern::type"
    - From JSON file: [{"pattern": "...", "type": "..."}, ...]
    """
    custom = []

    # Load from file if provided
    if pattern_file:
        with open(pattern_file) as f:
            data = json.load(f)
            for item in data:
                if isinstance(item, str):
                    custom.append((re.compile(item), 'custom'))
                else:
                    custom.append((
                        re.compile(item['pattern'], re.IGNORECASE if item.get('ignorecase') else 0),
                        item.get('type', 'custom')
                    ))

    # Load from command line
    for p in pattern_args:
        if '::' in p:
            pattern, ptype = p.rsplit('::', 1)
        else:
            pattern, ptype = p, 'custom'
        custom.append((re.compile(pattern, re.IGNORECASE), ptype))

    return custom


def main():
    parser = argparse.ArgumentParser(
        description="Remove noise messages from intake files"
    )
    parser.add_argument("file", help="Target file path")
    parser.add_argument("--dry-run", action="store_true",
                        help="Show what would be removed without modifying file")
    parser.add_argument("--no-renumber", action="store_true",
                        help="Don't renumber messages after removal")
    parser.add_argument("--pattern", "-p", action="append", default=[],
                        help="Custom regex pattern (can be repeated). Use 'pattern::type' to set type.")
    parser.add_argument("--pattern-file", "-f",
                        help="JSON file with custom patterns")
    parser.add_argument("--no-builtin", action="store_true",
                        help="Skip built-in patterns, only use custom")

    args = parser.parse_args()

    # Load custom patterns
    custom_patterns = load_custom_patterns(args.pattern, args.pattern_file)

    filepath = Path(args.file)
    if not filepath.exists():
        print(f"Error: {filepath} does not exist", file=sys.stderr)
        sys.exit(1)

    content = filepath.read_text()
    messages = parse_messages(content)
    noise_msgs = find_noise_sequences(messages, custom_patterns, args.no_builtin)

    if not noise_msgs:
        print(f"No noise found in {filepath}")
        sys.exit(0)

    # Report findings
    print(f"Found {len(noise_msgs)} noise message(s):")
    for noise in noise_msgs:
        msg = noise['msg']
        preview = msg['content'][:60].replace('\n', ' ')
        if len(msg['content']) > 60:
            preview += '...'
        print(f"  msg {msg['num']}: [{noise['type']}] {preview}")

    if args.dry_run:
        print("\n(dry run - no changes made)")
        sys.exit(0)

    # Remove noise
    result = remove_noise(content, noise_msgs)

    # Renumber unless disabled
    if not args.no_renumber:
        result = renumber_messages(result)

    # Write back
    filepath.write_text(result)
    print(f"\nRemoved {len(noise_msgs)} noise message(s) from {filepath}")


if __name__ == "__main__":
    main()
