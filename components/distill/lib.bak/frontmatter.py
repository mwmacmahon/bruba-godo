"""
YAML frontmatter utilities for markdown files.
"""

from typing import Tuple, Optional
import re


def add_frontmatter(content: str, metadata: dict) -> str:
    """
    Add YAML frontmatter to markdown content.

    Args:
        content: Markdown content
        metadata: Dict of metadata to include

    Returns:
        Content with frontmatter prepended
    """
    # Filter out None values
    meta = {k: v for k, v in metadata.items() if v is not None}

    if not meta:
        return content

    import yaml
    frontmatter = yaml.dump(meta, default_flow_style=False, allow_unicode=True)

    return f"---\n{frontmatter}---\n\n{content}"


def parse_frontmatter(content: str) -> Tuple[dict, str]:
    """
    Parse YAML frontmatter from markdown content.

    Args:
        content: Markdown content with potential frontmatter

    Returns:
        Tuple of (metadata dict, content without frontmatter)
    """
    # Check for frontmatter
    if not content.startswith('---'):
        return {}, content

    # Find the closing ---
    match = re.match(r'^---\n(.*?)\n---\n?(.*)', content, re.DOTALL)
    if not match:
        return {}, content

    frontmatter_str = match.group(1)
    body = match.group(2)

    try:
        import yaml
        metadata = yaml.safe_load(frontmatter_str) or {}
    except Exception:
        metadata = {}

    return metadata, body


def update_frontmatter(content: str, updates: dict) -> str:
    """
    Update specific frontmatter fields.

    Args:
        content: Markdown content with frontmatter
        updates: Dict of fields to update

    Returns:
        Content with updated frontmatter
    """
    metadata, body = parse_frontmatter(content)
    metadata.update(updates)
    return add_frontmatter(body, metadata)


def get_field(content: str, field: str) -> Optional[str]:
    """
    Get a specific frontmatter field.

    Args:
        content: Markdown content with frontmatter
        field: Field name to retrieve

    Returns:
        Field value or None
    """
    metadata, _ = parse_frontmatter(content)
    return metadata.get(field)
