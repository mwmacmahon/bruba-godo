"""
Clawdbot JSONL session parser.

Converts Clawdbot session files (JSONL) to the delimited markdown format
that convo-processor expects.

Clawdbot stores sessions as JSONL with one JSON object per line:
- type: "session" - session metadata (skip)
- type: "custom" - internal events (skip)
- type: "message" - actual conversation messages

Message structure:
{
  "type": "message",
  "id": "79ac375c",
  "timestamp": "2026-01-26T06:03:04.901Z",
  "message": {
    "role": "user|assistant",
    "content": [
      {"type": "text", "text": "actual message"},
      {"type": "thinking", "thinking": "extended thinking"}
    ],
    "model": "claude-opus-4-5" | "delivery-mirror"
  }
}

Output format:
=== MESSAGE 1 | USER ===
user message content

=== MESSAGE 2 | ASSISTANT ===
assistant response
"""

import json
from pathlib import Path
from typing import List, Optional, Tuple
from dataclasses import dataclass
from datetime import datetime


@dataclass
class ClawdbotMessage:
    """A parsed message from a Clawdbot session."""
    index: int
    role: str  # "user" or "assistant"
    content: str
    timestamp: Optional[datetime] = None
    message_id: Optional[str] = None


# System messages to filter out (prefixes)
SYSTEM_MESSAGE_PREFIXES = [
    "A new session was started",
    "New session started",
    "[Queued messages while agent was busy]",
]

# Internal message patterns in user content
INTERNAL_USER_PATTERNS = [
    "[message_id:",  # Telegram message ID markers
]


def is_system_message(text: str) -> bool:
    """Check if a message is a system/internal message to filter out."""
    text_stripped = text.strip()
    for prefix in SYSTEM_MESSAGE_PREFIXES:
        if text_stripped.startswith(prefix):
            return True
    return False


def extract_text_content(content_blocks: list) -> str:
    """Extract text content from message content blocks, skipping thinking."""
    texts = []
    for block in content_blocks:
        if isinstance(block, dict):
            if block.get("type") == "text":
                text = block.get("text", "")
                # Skip if it's an internal user message marker
                if any(pattern in text for pattern in INTERNAL_USER_PATTERNS):
                    # Try to extract actual user content after markers
                    # Format: "...[message_id: N]" - take content before marker
                    if "[message_id:" in text:
                        # Check if there's content after queued messages header
                        if "---\nQueued #" in text:
                            # Extract the actual message from queued format
                            # "[Queued...]\n---\nQueued #1\n[Telegram...] actual message\n[message_id: N]"
                            parts = text.split("] ", 1)
                            if len(parts) > 1:
                                # Get content after the bracket, before message_id
                                msg = parts[-1]
                                if "[message_id:" in msg:
                                    msg = msg.rsplit("[message_id:", 1)[0].strip()
                                texts.append(msg)
                                continue
                        else:
                            # Simple case: content before [message_id:]
                            msg = text.rsplit("[message_id:", 1)[0].strip()
                            if msg:
                                texts.append(msg)
                                continue
                else:
                    texts.append(text)
            # Skip "thinking" type blocks
    return "\n".join(texts)


def parse_jsonl_line(line: str) -> Optional[dict]:
    """Parse a single JSONL line, returning None if invalid."""
    line = line.strip()
    if not line:
        return None
    try:
        return json.loads(line)
    except json.JSONDecodeError:
        return None


def parse_clawdbot_session(
    jsonl_path: Path,
    include_timestamps: bool = False
) -> Tuple[List[ClawdbotMessage], Optional[str], Optional[datetime]]:
    """
    Parse a Clawdbot JSONL session file.

    Args:
        jsonl_path: Path to the .jsonl session file
        include_timestamps: Whether to include timestamps in output

    Returns:
        Tuple of (messages, session_id, session_start_time)
    """
    messages: List[ClawdbotMessage] = []
    session_id: Optional[str] = None
    session_start: Optional[datetime] = None
    message_index = 0

    with open(jsonl_path, 'r', encoding='utf-8') as f:
        for line in f:
            obj = parse_jsonl_line(line)
            if obj is None:
                continue

            obj_type = obj.get("type")

            # Extract session metadata
            if obj_type == "session":
                session_id = obj.get("id")
                ts = obj.get("timestamp")
                if ts:
                    try:
                        session_start = datetime.fromisoformat(ts.replace("Z", "+00:00"))
                    except ValueError:
                        pass
                continue

            # Skip non-message types
            if obj_type != "message":
                continue

            msg_data = obj.get("message", {})

            # Skip delivery-mirror duplicates (clawdbot internal)
            if msg_data.get("model") == "delivery-mirror":
                continue

            role = msg_data.get("role", "").lower()
            if role not in ("user", "assistant"):
                continue

            content_blocks = msg_data.get("content", [])
            if not content_blocks:
                continue

            content = extract_text_content(content_blocks)
            if not content:
                continue

            # Skip system messages
            if is_system_message(content):
                continue

            # Parse timestamp
            timestamp = None
            ts = obj.get("timestamp")
            if ts:
                try:
                    timestamp = datetime.fromisoformat(ts.replace("Z", "+00:00"))
                except ValueError:
                    pass

            message_index += 1
            messages.append(ClawdbotMessage(
                index=message_index,
                role=role,
                content=content,
                timestamp=timestamp,
                message_id=obj.get("id")
            ))

    return messages, session_id, session_start


def format_as_delimited_markdown(
    messages: List[ClawdbotMessage],
    include_timestamps: bool = False
) -> str:
    """
    Convert parsed messages to delimited markdown format.

    Output format:
    === MESSAGE 1 | USER ===
    message content

    === MESSAGE 2 | ASSISTANT ===
    response content
    """
    lines = []

    for msg in messages:
        role_upper = msg.role.upper()
        delimiter = f"=== MESSAGE {msg.index} | {role_upper} ==="

        lines.append(delimiter)
        lines.append(msg.content)
        lines.append("")  # Blank line between messages

    return "\n".join(lines)


def convert_session_file(
    input_path: Path,
    output_path: Optional[Path] = None,
    include_timestamps: bool = False
) -> Tuple[str, Optional[str], Optional[datetime]]:
    """
    Convert a Clawdbot JSONL session to delimited markdown.

    Args:
        input_path: Path to input .jsonl file
        output_path: Optional path to write output (if None, just returns content)
        include_timestamps: Whether to include timestamps

    Returns:
        Tuple of (markdown_content, session_id, session_start_time)
    """
    messages, session_id, session_start = parse_clawdbot_session(
        input_path,
        include_timestamps
    )

    if not messages:
        return "", session_id, session_start

    content = format_as_delimited_markdown(messages, include_timestamps)

    if output_path:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, 'w', encoding='utf-8') as f:
            f.write(content)

    return content, session_id, session_start


def generate_output_filename(
    session_id: Optional[str],
    session_start: Optional[datetime]
) -> str:
    """
    Generate output filename from session metadata.

    Format: YYYY-MM-DD-{session_id_first8}.md
    """
    date_str = "unknown-date"
    if session_start:
        date_str = session_start.strftime("%Y-%m-%d")

    id_suffix = "unknown"
    if session_id:
        id_suffix = session_id[:8]

    return f"{date_str}-{id_suffix}.md"


if __name__ == "__main__":
    import sys

    if len(sys.argv) < 2:
        print("Usage: python clawdbot_parser.py <session.jsonl> [output.md]")
        sys.exit(1)

    input_file = Path(sys.argv[1])
    output_file = Path(sys.argv[2]) if len(sys.argv) > 2 else None

    content, session_id, session_start = convert_session_file(input_file, output_file)

    if output_file:
        print(f"Converted {input_file} -> {output_file}")
        print(f"Session ID: {session_id}")
        print(f"Session start: {session_start}")
    else:
        print(content)
