"""
Output formatting for conversation export processing.

This module handles formatting and writing processed output files.
"""

import logging
from pathlib import Path
from typing import Optional
from datetime import datetime


def generate_frontmatter(
    doc_type: str,
    project: str = "",
    filename_base: str = ""
) -> str:
    """
    Generate YAML frontmatter for an output file.

    Args:
        doc_type: Type of document (transcript, summary, raw)
        project: Optional project name
        filename_base: Optional filename base for date extraction

    Returns:
        YAML frontmatter string including trailing newlines
    """
    # Extract date from filename_base if available
    date_str = datetime.now().strftime('%Y-%m-%d')
    if filename_base and len(filename_base) >= 10:
        potential_date = filename_base[:10]
        if len(potential_date.split('-')) == 3:
            date_str = potential_date

    lines = [
        "---",
        "version: 1.0.0",
        f"updated: {date_str}",
        f"type: {doc_type}",
    ]

    if project:
        lines.append(f"project: {project}")

    lines.extend([
        "tags: []",
        "---",
        "",
    ])

    return '\n'.join(lines)


def format_transcript(
    content: str,
    filename_base: str,
    project: str = ""
) -> str:
    """
    Format transcript content with frontmatter.

    Args:
        content: Transcript content (already processed)
        filename_base: Base filename for metadata
        project: Optional project name

    Returns:
        Complete transcript with frontmatter
    """
    frontmatter = generate_frontmatter('transcript', project, filename_base)
    return frontmatter + content


def format_summary(
    content: str,
    filename_base: str,
    project: str = ""
) -> str:
    """
    Format summary content with frontmatter if not present.

    Args:
        content: Summary content
        filename_base: Base filename for metadata
        project: Optional project name

    Returns:
        Complete summary with frontmatter
    """
    if content.strip().startswith('---'):
        return content

    frontmatter = generate_frontmatter('summary', project, filename_base)
    return frontmatter + content


def write_output(
    content: str,
    output_path: Path,
    dry_run: bool = False,
    logger: Optional[logging.Logger] = None
) -> Optional[Path]:
    """
    Write content to an output file.

    Args:
        content: Content to write
        output_path: Path to write to
        dry_run: If True, don't actually write
        logger: Optional logger for reporting

    Returns:
        Path to written file, or None if dry_run
    """
    if logger is None:
        logger = logging.getLogger(__name__)

    if dry_run:
        logger.info(f"  WOULD WRITE: {output_path} ({len(content)} bytes)")
        return None

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(content, encoding='utf-8')
    logger.info(f"  -> {output_path}")
    return output_path
