"""
Core session processing pipeline.

Converts raw JSONL sessions into canonical markdown with frontmatter.
"""

import json
from datetime import datetime
from pathlib import Path
from typing import Optional

from . import canonicalize, frontmatter


def process_session(
    input_path: Path,
    output_dir: str = "sessions/converted"
) -> Path:
    """
    Process a single JSONL session file into markdown.

    Args:
        input_path: Path to the JSONL file
        output_dir: Directory for output (relative to repo root)

    Returns:
        Path to the generated markdown file
    """
    # Load config
    config = _load_config()

    # Parse JSONL (clawdbot format)
    raw_entries = []
    with open(input_path, 'r') as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    raw_entries.append(json.loads(line))
                except json.JSONDecodeError as e:
                    print(f"  Warning: Invalid JSON line: {e}")

    # Extract actual messages from clawdbot format
    # Format: {"type":"message", "message": {"role":"...", "content":[...]}}
    messages = []
    for entry in raw_entries:
        if entry.get('type') == 'message' and 'message' in entry:
            msg = entry['message']
            # Flatten content array if present
            content = msg.get('content', '')
            if isinstance(content, list):
                # Extract text from content blocks
                text_parts = []
                for block in content:
                    if isinstance(block, dict):
                        if block.get('type') == 'text':
                            text_parts.append(block.get('text', ''))
                        elif block.get('type') == 'tool_use':
                            # Preserve tool_use blocks as separate messages
                            messages.append({
                                'role': 'tool_use',
                                'name': block.get('name', 'unknown'),
                                'input': block.get('input', {})
                            })
                        elif block.get('type') == 'tool_result':
                            messages.append({
                                'role': 'tool_result',
                                'content': block.get('content', '')
                            })
                    elif isinstance(block, str):
                        text_parts.append(block)
                content = '\n'.join(text_parts)

            # Map roles (clawdbot uses 'user' not 'human')
            role = msg.get('role', 'unknown')
            if role == 'user':
                role = 'human'

            if content:  # Only add if there's actual content
                messages.append({
                    'role': role,
                    'content': content
                })

    if not messages:
        raise ValueError(f"No valid messages found in {input_path}")

    # Extract metadata (from raw entries, not filtered messages)
    metadata = _extract_metadata(raw_entries, input_path)

    # Convert to markdown
    content = canonicalize.messages_to_markdown(messages, config)

    # Add frontmatter
    full_content = frontmatter.add_frontmatter(content, metadata)

    # Write output
    output_path = _get_output_path(input_path, output_dir)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    with open(output_path, 'w') as f:
        f.write(full_content)

    return output_path


def _load_config() -> dict:
    """Load distill config."""
    config_path = Path(__file__).parent.parent / "config.yaml"
    if config_path.exists():
        import yaml
        with open(config_path) as f:
            return yaml.safe_load(f)
    return {}


def _extract_metadata(messages: list, input_path: Path) -> dict:
    """Extract metadata from session messages."""
    metadata = {
        "source": input_path.name,
        "processed": datetime.now().isoformat(),
        "message_count": len(messages),
    }

    # Try to extract timestamps
    timestamps = []
    for msg in messages:
        if 'timestamp' in msg:
            timestamps.append(msg['timestamp'])

    if timestamps:
        metadata["started"] = min(timestamps)
        metadata["ended"] = max(timestamps)

    return metadata


def _get_output_path(input_path: Path, output_dir: str) -> Path:
    """Generate output path from input filename."""
    # Convert session-abc123.jsonl to abc123.md
    stem = input_path.stem
    if stem.startswith("session-"):
        stem = stem[8:]  # Remove "session-" prefix

    # Find repo root (where config.yaml is)
    repo_root = Path(__file__).parent.parent.parent.parent

    return repo_root / output_dir / f"{stem}.md"
