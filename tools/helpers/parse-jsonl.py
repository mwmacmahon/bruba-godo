#!/usr/bin/env python3
"""
Parse JSONL session files and convert to readable markdown.

Usage:
    parse-jsonl.py <file>                    # Convert to markdown
    parse-jsonl.py <file> --extract <lines>  # Extract specific line range
    parse-jsonl.py <file> --search <term>    # Find lines mentioning term
    parse-jsonl.py <file> --corrections      # Apply transcription corrections

Examples:
    parse-jsonl.py session.jsonl
    parse-jsonl.py session.jsonl --corrections
    parse-jsonl.py session.jsonl --extract 150-160
    parse-jsonl.py session.jsonl --search "cleanup-reminders.py"

Options:
    --corrections    Apply transcription corrections from config/corrections.yaml
    --corrections-file <path>  Use custom corrections file

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
import re
import os
from datetime import datetime
from pathlib import Path


def load_corrections(corrections_file=None):
    """Load transcription corrections from YAML file."""
    if corrections_file is None:
        # Default location: config/corrections.yaml relative to repo root
        script_dir = Path(__file__).parent
        repo_root = script_dir.parent.parent
        corrections_file = repo_root / "config" / "corrections.yaml"
    else:
        corrections_file = Path(corrections_file)

    if not corrections_file.exists():
        return {}

    corrections = {}
    try:
        # Simple YAML parsing without external dependency
        with open(corrections_file, 'r') as f:
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if not line or line.startswith('#'):
                    continue
                # Parse key: value pairs
                if ':' in line:
                    # Handle quoted values
                    match = re.match(r'^"?([^"]+)"?\s*:\s*"?([^"]*)"?$', line)
                    if match:
                        wrong, correct = match.groups()
                        # Skip if value is explicitly empty (removal entries)
                        corrections[wrong.strip()] = correct.strip()
    except Exception as e:
        print(f"Warning: Could not load corrections file: {e}", file=sys.stderr)
        return {}

    return corrections


def apply_corrections(text, corrections):
    """Apply transcription corrections to text."""
    if not corrections or not text:
        return text

    result = text

    # Apply simple replacements (case-insensitive)
    for wrong, correct in corrections.items():
        if not wrong:
            continue
        # Create case-insensitive pattern
        pattern = re.compile(re.escape(wrong), re.IGNORECASE)

        def replace_match(m):
            # If correct is empty, remove the match
            if not correct:
                return ''
            # Try to preserve case of first character
            matched = m.group(0)
            if matched[0].isupper() and correct[0].islower():
                return correct[0].upper() + correct[1:]
            elif matched[0].islower() and correct[0].isupper():
                return correct[0].lower() + correct[1:]
            return correct

        result = pattern.sub(replace_match, result)

    # Clean up whisper artifacts
    result = clean_whisper_artifacts(result)

    return result


def clean_whisper_artifacts(text):
    """Remove common whisper-cpp artifacts from text."""
    if not text:
        return text

    # Remove timestamp patterns like [00:00:00.000 --> 00:00:05.000]
    text = re.sub(r'\[\d{2}:\d{2}(?::\d{2})?(?:\.\d+)?\s*(?:-->|->)\s*\d{2}:\d{2}(?::\d{2})?(?:\.\d+)?\]', '', text)

    # Remove standalone timestamps like [00:00] or [00:00:00]
    text = re.sub(r'\[\d{2}:\d{2}(?::\d{2})?\]', '', text)

    # Remove speaker labels like [SPEAKER_00]
    text = re.sub(r'\[SPEAKER_\d+\]', '', text)

    # Clean up multiple spaces
    text = re.sub(r'  +', ' ', text)

    # Clean up spaces around punctuation
    text = re.sub(r'\s+([.,!?;:])', r'\1', text)

    # Clean up leading/trailing whitespace
    text = text.strip()

    return text


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
            if isinstance(item, dict):
                if item.get('type') == 'text':
                    texts.append(item.get('text', ''))
                # Skip thinking blocks
                elif item.get('type') == 'thinking':
                    continue
            elif isinstance(item, str):
                texts.append(item)
        return '\n'.join(texts)
    elif isinstance(content, str):
        return content

    return str(msg)


def should_skip_entry(entry):
    """Determine if an entry should be skipped in output."""
    # Skip session metadata
    if entry.get('type') == 'session':
        return True
    if entry.get('type') == 'custom':
        return True

    # Skip delivery mirrors (duplicates)
    if entry.get('model') == 'delivery-mirror':
        return True

    # Get message content
    msg = entry.get('message', entry)
    role = msg.get('role', entry.get('role', ''))

    # Skip system messages about session start
    if role == 'system':
        text = extract_message_text(entry)
        if 'New session started' in text or 'Session started' in text:
            return True

    return False


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


def to_markdown(filepath, line_range=None, corrections=None):
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

        # Skip entries that shouldn't appear in output
        if should_skip_entry(entry):
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

        # Apply corrections if provided
        if corrections:
            text = apply_corrections(text, corrections)

        # Clean up [message_id: N] markers
        text = re.sub(r'\[message_id:\s*\d+\]', '', text)

        speaker = get_speaker(role)
        ts_str = format_timestamp(timestamp) if timestamp else ''

        # Format as markdown section
        header = f"### L{line_num}"
        if ts_str:
            header += f" | {ts_str}"
        header += f" | {speaker}"

        output.append(header)
        output.append(text[:2000] + ('...' if len(text) > 2000 else ''))
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
    corrections = None
    corrections_file = None

    # Parse arguments
    i = 2
    while i < len(sys.argv):
        arg = sys.argv[i]

        if arg == '--corrections':
            corrections = load_corrections(corrections_file)
            i += 1

        elif arg == '--corrections-file' and i + 1 < len(sys.argv):
            corrections_file = sys.argv[i + 1]
            corrections = load_corrections(corrections_file)
            i += 2

        elif arg == '--extract' and i + 1 < len(sys.argv):
            try:
                parts = sys.argv[i + 1].split('-')
                line_range = (int(parts[0]), int(parts[1]))
            except (ValueError, IndexError):
                print("Error: Range must be in format START-END (e.g., 150-160)", file=sys.stderr)
                sys.exit(1)
            print(to_markdown(filepath, line_range, corrections))
            return
            i += 2

        elif arg == '--search' and i + 1 < len(sys.argv):
            term = sys.argv[i + 1]
            matches = search_jsonl(filepath, term)
            if matches:
                print(f"Found {len(matches)} matches:")
                for m in matches:
                    print(f"  L{m}")
            else:
                print("No matches found")
            return
            i += 2

        else:
            i += 1

    # Default: full conversion
    print(to_markdown(filepath, corrections=corrections))


if __name__ == '__main__':
    main()
