"""
Splitting utilities for large transcript files.

This module handles splitting large conversation transcripts along message
boundaries to stay under AI processing limits (~60k characters).

Key design decisions:
- Split only on === MESSAGE N | ROLE === boundaries (never mid-message)
- Minimum 5 messages per chunk to avoid tiny/useless splits
- CONFIG block copied to each chunk with part metadata
- Continuation notes added between parts
"""

import re
from pathlib import Path
from typing import List, Dict, Tuple, Optional
from dataclasses import dataclass

# Message delimiter pattern (same as parsing.py)
MESSAGE_DELIMITER_PATTERN = re.compile(
    r'^=== MESSAGE (\d+) \| (USER|ASSISTANT|UNKNOWN) ===$',
    re.MULTILINE
)

# Config block markers
CONFIG_START_MARKER = "=== EXPORT CONFIG ==="
CONFIG_END_MARKER = "=== END CONFIG ==="

# Minimum messages per chunk to avoid tiny splits
MIN_MESSAGES_PER_CHUNK = 5

# Default size limit (characters)
DEFAULT_MAX_CHARS = 60000


@dataclass
class ChunkInfo:
    """Information about a split chunk."""
    content: str
    part: int
    total_parts: int
    first_message: int
    last_message: int
    char_count: int


def should_split(content: str, max_chars: int = DEFAULT_MAX_CHARS) -> bool:
    """
    Check if content exceeds size limit and should be split.

    Args:
        content: Full file content
        max_chars: Maximum characters per chunk

    Returns:
        True if content should be split
    """
    return len(content) > max_chars


def get_message_count(content: str) -> int:
    """Count the number of messages in content."""
    return len(list(MESSAGE_DELIMITER_PATTERN.finditer(content)))


def extract_config_and_content(content: str) -> Tuple[str, str, str]:
    """
    Extract CONFIG block, main content, and any backmatter from file.

    Returns:
        Tuple of (config_block, main_content, backmatter)
        config_block includes the === markers
    """
    config_block = ""
    main_content = content
    backmatter = ""

    # Find CONFIG block
    config_start = content.find(CONFIG_START_MARKER)
    config_end = content.find(CONFIG_END_MARKER)

    if config_start != -1 and config_end != -1:
        # Include the end marker
        config_end = config_end + len(CONFIG_END_MARKER)
        config_block = content[config_start:config_end]

        # Main content is everything before CONFIG
        main_content = content[:config_start].strip()

        # Backmatter is everything after CONFIG
        after_config = content[config_end:].strip()
        if after_config:
            backmatter = after_config

    return config_block, main_content, backmatter


def find_message_boundaries(content: str) -> List[Tuple[int, int, int, str]]:
    """
    Find all message boundaries in content.

    Returns:
        List of (start_pos, end_pos, message_num, role) tuples
        end_pos is the start of the next message or end of content
    """
    matches = list(MESSAGE_DELIMITER_PATTERN.finditer(content))
    boundaries = []

    for i, match in enumerate(matches):
        msg_num = int(match.group(1))
        role = match.group(2)
        start = match.start()

        # End is start of next message or end of content
        if i + 1 < len(matches):
            end = matches[i + 1].start()
        else:
            end = len(content)

        boundaries.append((start, end, msg_num, role))

    return boundaries


def split_by_message_boundaries(
    content: str,
    max_chars: int = DEFAULT_MAX_CHARS,
    min_messages: int = MIN_MESSAGES_PER_CHUNK
) -> List[ChunkInfo]:
    """
    Split content along message boundaries into roughly equal chunks.

    Strategy:
    1. Calculate how many chunks needed based on total size
    2. Distribute messages roughly evenly across chunks
    3. Always split on message boundaries (never mid-message)
    4. Ensure each chunk has at least min_messages

    Args:
        content: Full file content (with or without CONFIG block)
        max_chars: Maximum characters per chunk
        min_messages: Minimum messages per chunk (to avoid tiny splits)

    Returns:
        List of ChunkInfo objects for each chunk
    """
    # Extract components
    config_block, main_content, backmatter = extract_config_and_content(content)

    # Find message boundaries in main content
    boundaries = find_message_boundaries(main_content)

    if not boundaries:
        # No messages found, return as single chunk
        return [ChunkInfo(
            content=content,
            part=1,
            total_parts=1,
            first_message=0,
            last_message=0,
            char_count=len(content)
        )]

    # Calculate overhead for each chunk (CONFIG + continuation notes)
    config_overhead = len(config_block) + 200  # Extra for continuation notes

    # Calculate how many chunks we need
    total_content_size = len(main_content)
    available_per_chunk = max_chars - config_overhead

    if total_content_size <= available_per_chunk:
        # No split needed
        first_msg = boundaries[0][2]
        last_msg = boundaries[-1][2]
        return [ChunkInfo(
            content=content,
            part=1,
            total_parts=1,
            first_message=first_msg,
            last_message=last_msg,
            char_count=len(content)
        )]

    # Calculate optimal number of chunks
    num_chunks = max(2, (total_content_size + available_per_chunk - 1) // available_per_chunk)

    # Ensure we have enough messages for min_messages per chunk
    num_messages = len(boundaries)
    max_possible_chunks = num_messages // min_messages
    if max_possible_chunks < num_chunks:
        num_chunks = max(1, max_possible_chunks)

    if num_chunks == 1:
        first_msg = boundaries[0][2]
        last_msg = boundaries[-1][2]
        return [ChunkInfo(
            content=content,
            part=1,
            total_parts=1,
            first_message=first_msg,
            last_message=last_msg,
            char_count=len(content)
        )]

    # Distribute messages evenly across chunks
    # Use ceiling division to ensure we don't exceed num_chunks
    messages_per_chunk = (num_messages + num_chunks - 1) // num_chunks

    # Build chunks by grouping messages
    chunks = []
    for chunk_idx in range(num_chunks):
        first_idx = chunk_idx * messages_per_chunk
        # Last chunk gets all remaining messages
        if chunk_idx == num_chunks - 1:
            last_idx = num_messages - 1
        else:
            last_idx = min(first_idx + messages_per_chunk - 1, num_messages - 1)

        # Skip if we've run out of messages
        if first_idx >= num_messages:
            break

        first_start = boundaries[first_idx][0]
        last_end = boundaries[last_idx][1]

        chunks.append({
            'main_content': main_content[first_start:last_end],
            'first_message': boundaries[first_idx][2],
            'last_message': boundaries[last_idx][2],
            'first_idx': first_idx,
            'last_idx': last_idx
        })

    # If we ended up with just one chunk, return original
    if len(chunks) == 1:
        first_msg = boundaries[0][2]
        last_msg = boundaries[-1][2]
        return [ChunkInfo(
            content=content,
            part=1,
            total_parts=1,
            first_message=first_msg,
            last_message=last_msg,
            char_count=len(content)
        )]

    # Build final chunk content with CONFIG and continuation notes
    total_parts = len(chunks)
    result = []

    for i, chunk in enumerate(chunks):
        part_num = i + 1
        chunk_content = build_chunk_content(
            config_block=config_block,
            main_content=chunk['main_content'],
            part=part_num,
            total_parts=total_parts,
            first_message=chunk['first_message'],
            last_message=chunk['last_message'],
            include_backmatter=(i == len(chunks) - 1),
            backmatter=backmatter
        )

        result.append(ChunkInfo(
            content=chunk_content,
            part=part_num,
            total_parts=total_parts,
            first_message=chunk['first_message'],
            last_message=chunk['last_message'],
            char_count=len(chunk_content)
        ))

    return result


def build_chunk_content(
    config_block: str,
    main_content: str,
    part: int,
    total_parts: int,
    first_message: int,
    last_message: int,
    include_backmatter: bool = False,
    backmatter: str = ""
) -> str:
    """
    Build the full content for a chunk with CONFIG and continuation notes.
    """
    lines = []

    # Continuation note at start (for parts after first)
    if part > 1:
        lines.append(f"**[Continued from Part {part - 1} of {total_parts}]**")
        lines.append("")

    # Main content
    lines.append(main_content.strip())
    lines.append("")

    # Continuation note at end (for parts before last)
    if part < total_parts:
        lines.append("---")
        lines.append(f"**[Conversation continues in Part {part + 1} of {total_parts}]**")
        lines.append("")

    # CONFIG block (always at end, before backmatter)
    if config_block:
        # Update CONFIG with part metadata
        updated_config = update_config_with_part_info(
            config_block, part, total_parts, first_message, last_message
        )
        lines.append(updated_config)

    # Backmatter (only in last chunk)
    if include_backmatter and backmatter:
        lines.append("")
        lines.append(backmatter)

    return "\n".join(lines)


def update_config_with_part_info(
    config_block: str,
    part: int,
    total_parts: int,
    first_message: int,
    last_message: int
) -> str:
    """
    Update CONFIG block with part metadata.

    Adds:
    - part: N
    - total_parts: M
    - messages: "X-Y"
    - Updates slug to include -part-N
    """
    lines = config_block.split('\n')
    result = []
    slug_updated = False
    part_info_added = False

    for line in lines:
        # Update slug to include part number
        if line.strip().startswith('slug:') and not slug_updated:
            # Extract current slug value
            slug_match = re.match(r'^(\s*slug:\s*)(.+)$', line)
            if slug_match:
                prefix = slug_match.group(1)
                slug_value = slug_match.group(2).strip().strip('"\'')
                # Add part suffix if not already there
                if f'-part-{part}' not in slug_value:
                    slug_value = f"{slug_value}-part-{part}"
                result.append(f'{prefix}"{slug_value}"')
                slug_updated = True

                # Add part info right after slug
                indent = len(prefix) - len(prefix.lstrip())
                indent_str = ' ' * indent
                result.append(f'{indent_str}part: {part}')
                result.append(f'{indent_str}total_parts: {total_parts}')
                result.append(f'{indent_str}messages: "{first_message}-{last_message}"')
                part_info_added = True
                continue

        result.append(line)

    # If slug wasn't found, add part info before END CONFIG
    if not part_info_added:
        for i, line in enumerate(result):
            if CONFIG_END_MARKER in line:
                result.insert(i, f'part: {part}')
                result.insert(i + 1, f'total_parts: {total_parts}')
                result.insert(i + 2, f'messages: "{first_message}-{last_message}"')
                break

    return '\n'.join(result)


def split_file(
    input_path: Path,
    output_dir: Path,
    max_chars: int = DEFAULT_MAX_CHARS,
    min_messages: int = MIN_MESSAGES_PER_CHUNK
) -> List[Path]:
    """
    Split a file if needed and write chunks to output directory.

    Args:
        input_path: Path to input file
        output_dir: Directory to write chunks to
        max_chars: Maximum characters per chunk
        min_messages: Minimum messages per chunk

    Returns:
        List of output file paths (just the input path if no split needed)
    """
    content = input_path.read_text(encoding='utf-8')

    if not should_split(content, max_chars):
        return [input_path]

    chunks = split_by_message_boundaries(content, max_chars, min_messages)

    if len(chunks) == 1:
        # No split needed after analysis
        return [input_path]

    # Write chunks
    output_dir.mkdir(parents=True, exist_ok=True)
    output_paths = []
    stem = input_path.stem

    for chunk in chunks:
        out_name = f"{stem}-part-{chunk.part}.md"
        out_path = output_dir / out_name
        out_path.write_text(chunk.content, encoding='utf-8')
        output_paths.append(out_path)

    return output_paths
