#!/usr/bin/env python3
"""
Parse JSONL session files and convert to readable markdown.

Usage:
    parse-jsonl.py <file>                    # Convert to markdown
    parse-jsonl.py <file> --extract <lines>  # Extract specific line range
    parse-jsonl.py <file> --search <term>    # Find lines mentioning term

Examples:
    parse-jsonl.py session.jsonl
    parse-jsonl.py session.jsonl --extract 150-160
    parse-jsonl.py session.jsonl --search "cleanup-reminders.py"

Output format:
    ## Session: <id>
    **Started:** <timestamp>

    ### L123 | 2026-01-29 11:48 | User
    Message content here...

    ### L124 | 2026-01-29 11:50 | Assistant
    Response content here...
"""

import sys
import json
from datetime import datetime


def parse_timestamp(ts):
    """Parse various timestamp formats to datetime."""
    if isinstance(ts, (int, float)):
        # Unix timestamp (seconds or milliseconds)
        if ts > 1e12:
            ts = ts / 1000  # milliseconds
        return datetime.fromtimestamp(ts)
    elif isinstance(ts, str):
        # ISO format
        try:
            return datetime.fromisoformat(ts.replace('Z', '+00:00'))
        except ValueError:
            return None
    return None


def format_timestamp(ts):
    """Format timestamp for display."""
    dt = parse_timestamp(ts)
    if dt:
        return dt.strftime('%Y-%m-%d %H:%M')
    return str(ts)


def get_speaker(role):
    """Convert role to speaker name."""
    if role == 'user':
        return 'User'
    elif role == 'assistant':
        return 'Assistant'
    return role.capitalize()


def extract_message_text(entry):
    """Extract text content from a JSONL entry."""
    msg = entry.get('message', entry)

    # Handle content array format
    content = msg.get('content', [])
    if isinstance(content, list):
        texts = []
        for item in content:
            if isinstance(item, dict) and item.get('type') == 'text':
                texts.append(item.get('text', ''))
            elif isinstance(item, str):
                texts.append(item)
        return '\n'.join(texts)
    elif isinstance(content, str):
        return content

    return str(msg)


def parse_jsonl(filepath):
    """Parse JSONL file and yield (line_num, entry) tuples."""
    with open(filepath, 'r') as f:
        for i, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
                yield (i, entry)
            except json.JSONDecodeError:
                continue


def to_markdown(filepath, line_range=None):
    """Convert JSONL session to markdown format."""
    output = []
    session_id = None
    start_time = None

    for line_num, entry in parse_jsonl(filepath):
        # Apply line range filter if specified
        if line_range:
            start, end = line_range
            if line_num < start or line_num > end:
                continue

        # Get session metadata from first entry
        if session_id is None and 'sessionId' in entry:
            session_id = entry['sessionId'][:8] if len(entry.get('sessionId', '')) > 8 else entry.get('sessionId', 'unknown')

        if start_time is None and 'timestamp' in entry:
            start_time = format_timestamp(entry['timestamp'])

        # Extract message info
        msg = entry.get('message', entry)
        role = msg.get('role', entry.get('role', ''))
        timestamp = entry.get('timestamp', '')
        text = extract_message_text(entry)

        if not role or not text:
            continue

        speaker = get_speaker(role)
        ts_str = format_timestamp(timestamp) if timestamp else ''

        # Format as markdown section
        header = f"### L{line_num}"
        if ts_str:
            header += f" | {ts_str}"
        header += f" | {speaker}"

        output.append(header)
        output.append(text[:500] + ('...' if len(text) > 500 else ''))
        output.append('')

    # Add header
    header_lines = []
    if session_id:
        header_lines.append(f"## Session: {session_id}")
    if start_time:
        header_lines.append(f"**Started:** {start_time}")
    if header_lines:
        header_lines.append('')

    return '\n'.join(header_lines + output)


def search_jsonl(filepath, term):
    """Search JSONL for lines containing term, return line numbers."""
    matches = []
    for line_num, entry in parse_jsonl(filepath):
        text = extract_message_text(entry)
        if term.lower() in text.lower():
            matches.append(line_num)
    return matches


def main():
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        sys.exit(1)

    filepath = sys.argv[1]

    if len(sys.argv) >= 4 and sys.argv[2] == '--extract':
        # Extract line range
        try:
            parts = sys.argv[3].split('-')
            line_range = (int(parts[0]), int(parts[1]))
        except (ValueError, IndexError):
            print("Error: Range must be in format START-END (e.g., 150-160)", file=sys.stderr)
            sys.exit(1)
        print(to_markdown(filepath, line_range))

    elif len(sys.argv) >= 4 and sys.argv[2] == '--search':
        # Search for term
        term = sys.argv[3]
        matches = search_jsonl(filepath, term)
        if matches:
            print(f"Found {len(matches)} matches:")
            for m in matches:
                print(f"  L{m}")
        else:
            print("No matches found")

    else:
        # Full conversion
        print(to_markdown(filepath))


if __name__ == '__main__':
    main()
