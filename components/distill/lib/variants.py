"""
Variants module for conversation export processing.

This module implements Step 2 of the two-step pipeline:
Canonical file -> transcript, transcript-lite, summary variants

Step 2 (variants) does:
- Parse canonical file (frontmatter + content + backmatter)
- Apply sections_remove -> transcript.md
- Apply sections_lite_remove + code_blocks -> transcript-lite.md
- Extract summary -> summary.md

The canonical file format:
---
frontmatter with sections_remove, sections_lite_remove, code_blocks
---
main content (conversation)
---
<!-- === BACKMATTER === -->
## Summary
...
## Continuation Context
...
"""

import re
import logging
from pathlib import Path
from dataclasses import dataclass, field
from typing import List, Tuple, Optional, Dict, Any

try:
    import yaml
    YAML_AVAILABLE = True
except ImportError:
    YAML_AVAILABLE = False

from .models import (
    CanonicalConfig, SectionSpec, CodeBlockSpec, Backmatter,
    Sensitivity, SensitivityTerms, SensitivitySection
)
from .parsing import (
    parse_v2_config_block, extract_backmatter
)


@dataclass
class VariantOptions:
    """Options for variant generation."""
    generate_transcript: bool = True
    generate_lite: bool = False  # Deprecated: use profile-based sync instead
    generate_summary: bool = True
    redact_categories: List[str] = field(default_factory=list)  # e.g., ['health', 'personal']
    output_dir: Optional[Path] = None  # For writing extracted code blocks


@dataclass
class VariantResult:
    """Result of variant generation."""
    transcript: str = ""
    transcript_lite: str = ""
    summary: str = ""
    config: Optional[CanonicalConfig] = None
    backmatter: Optional[Backmatter] = None


def parse_canonical_file(content: str) -> Tuple[CanonicalConfig, str, Backmatter]:
    """
    Parse a canonical file into its components.

    Args:
        content: Full canonical file content

    Returns:
        Tuple of (config, main_content, backmatter)

    Raises:
        ValueError: If frontmatter is missing or malformed
    """
    content = content.strip()

    # Extract frontmatter
    if not content.startswith('---'):
        raise ValueError("Canonical file must start with YAML frontmatter (---)")

    # Find end of frontmatter
    second_dash = content.find('\n---', 3)
    if second_dash == -1:
        raise ValueError("Canonical file frontmatter not properly closed (missing ---)")

    frontmatter_yaml = content[4:second_dash].strip()
    rest_of_content = content[second_dash + 4:].strip()  # Skip \n---

    # Parse frontmatter as v2 config
    config = parse_v2_config_block(frontmatter_yaml)

    # Separate main content from backmatter
    backmatter_markers = [
        '<!-- === BACKMATTER === -->',
        '<!-- BACKMATTER -->',
    ]

    main_content = rest_of_content
    backmatter_start = None

    for marker in backmatter_markers:
        pos = rest_of_content.find(marker)
        if pos != -1:
            # Look for --- before the marker
            search_area = rest_of_content[:pos]
            last_dash = search_area.rfind('\n---')
            if last_dash != -1:
                backmatter_start = last_dash
            else:
                backmatter_start = pos
            break

    if backmatter_start is not None:
        main_content = rest_of_content[:backmatter_start].strip()

    # Extract backmatter using existing function
    backmatter = extract_backmatter(content)

    return config, main_content, backmatter


def apply_section_removals(
    content: str,
    sections: List[SectionSpec],
    logger: Optional[logging.Logger] = None
) -> Tuple[str, int]:
    """
    Apply anchor-based section removals to content.

    Args:
        content: The content to process
        sections: List of SectionSpec objects defining what to remove
        logger: Optional logger for reporting

    Returns:
        Tuple of (modified_content, sections_removed_count)
    """
    if logger is None:
        logger = logging.getLogger(__name__)

    result = content
    removed_count = 0

    for spec in sections:
        if not spec.start or not spec.end:
            logger.warning(f"Skipping section with missing start/end anchor")
            continue

        # Find start anchor
        start_pos = _fuzzy_find(result, spec.start)
        if start_pos is None:
            logger.warning(f"Start anchor not found: {spec.start[:50]}...")
            continue

        # Find end anchor (must be after start)
        end_pos = _fuzzy_find(result[start_pos:], spec.end)
        if end_pos is None:
            logger.warning(f"End anchor not found: {spec.end[:50]}...")
            continue

        # Convert relative position to absolute
        end_pos = start_pos + end_pos

        # Find the actual end (include the anchor text)
        end_anchor_match = re.search(re.escape(spec.end), result[end_pos:end_pos + len(spec.end) + 100])
        if end_anchor_match:
            end_pos = end_pos + end_anchor_match.end()

        if end_pos <= start_pos:
            logger.warning(f"End anchor appears before start anchor")
            continue

        # Build replacement text
        if spec.replacement:
            replacement = f"\n\n{spec.replacement}\n\n"
        elif spec.description:
            replacement = f"\n\n[Removed: {spec.description}]\n\n"
        else:
            replacement = "\n\n[Section removed]\n\n"

        result = result[:start_pos] + replacement + result[end_pos:]
        removed_count += 1
        logger.debug(f"Removed section: {spec.description or spec.start[:30]}...")

    return result, removed_count


def _fuzzy_find(content: str, anchor: str) -> Optional[int]:
    """
    Find anchor position using fuzzy matching.

    First tries exact match, then normalized matching.
    """
    # Try exact match first
    pos = content.find(anchor)
    if pos != -1:
        return pos

    # Try case-insensitive
    pos = content.lower().find(anchor.lower())
    if pos != -1:
        return pos

    # Try normalized (remove punctuation, collapse whitespace)
    normalized_anchor = _normalize_for_matching(anchor)
    if not normalized_anchor:
        return None

    # Search through content word by word
    anchor_words = normalized_anchor.split()
    if not anchor_words:
        return None

    first_word = anchor_words[0]
    search_start = 0

    while search_start < len(content):
        # Find first word
        idx = content.lower().find(first_word.lower(), search_start)
        if idx == -1:
            break

        # Check if the full normalized anchor matches
        chunk_end = min(idx + len(anchor) + 50, len(content))
        chunk = content[idx:chunk_end]
        normalized_chunk = _normalize_for_matching(chunk)

        if normalized_chunk.startswith(normalized_anchor):
            return idx

        search_start = idx + 1

    return None


def _normalize_for_matching(text: str) -> str:
    """Normalize text for fuzzy anchor matching."""
    normalized = re.sub(r'[,;:!?\-\—\–\.\'\"]', '', text)
    normalized = re.sub(r'\s+', ' ', normalized)
    return normalized.lower().strip()


def apply_redaction(
    content: str,
    sensitivity: Optional[Sensitivity],
    categories: List[str],
    logger: Optional[logging.Logger] = None
) -> Tuple[str, int]:
    """
    Apply sensitivity redaction to content.

    Redaction is applied in two ways:
    1. Term-based: Find/replace sensitive terms with [REDACTED]
    2. Section-based: Replace anchor ranges with replacement text

    Args:
        content: The content to redact
        sensitivity: Sensitivity config from canonical file (may be None)
        categories: List of categories to redact (e.g., ['health', 'personal'])
        logger: Optional logger for reporting

    Returns:
        Tuple of (redacted_content, redaction_count)
    """
    if logger is None:
        logger = logging.getLogger(__name__)

    if not categories:
        return content, 0

    if sensitivity is None:
        logger.debug("No sensitivity config - skipping redaction")
        return content, 0

    redaction_count = 0
    result = content

    # 1. Term-based redaction
    if sensitivity.terms:
        terms = sensitivity.terms.get_terms_for_categories(categories)
        for term in terms:
            if not term or not term.strip():
                continue
            term = term.strip()
            # Case-insensitive replacement
            pattern = re.compile(re.escape(term), re.IGNORECASE)
            new_result, count = pattern.subn('[REDACTED]', result)
            if count > 0:
                result = new_result
                redaction_count += count
                logger.debug(f"Redacted term '{term}' ({count} occurrences)")

    # 2. Section-based redaction
    if sensitivity.sections:
        for section in sensitivity.sections:
            # Check if any of this section's tags match our categories
            matching_tags = set(section.tags) & set(categories)
            if not matching_tags:
                continue

            # Find section anchors
            start_pos = _fuzzy_find(result, section.start)
            if start_pos is None:
                logger.debug(f"Could not find section start anchor: {section.start[:40]}...")
                continue

            end_pos = _fuzzy_find(result[start_pos:], section.end)
            if end_pos is None:
                logger.debug(f"Could not find section end anchor: {section.end[:40]}...")
                continue

            end_pos = start_pos + end_pos + len(section.end)

            # Build replacement text
            if section.description:
                replacement = f"\n\n[Redacted: {section.description}]\n\n"
            else:
                tags_str = ', '.join(matching_tags)
                replacement = f"\n\n[Redacted: {tags_str} content]\n\n"

            result = result[:start_pos] + replacement + result[end_pos:]
            redaction_count += 1
            logger.debug(f"Redacted section: {section.description or section.start[:30]}...")

    return result, redaction_count


def process_code_blocks(
    content: str,
    blocks: List[CodeBlockSpec],
    logger: Optional[logging.Logger] = None,
    output_dir: Optional[Path] = None
) -> Tuple[str, int]:
    """
    Process code blocks according to their action specifications.

    Actions:
    - keep: Leave the code block as-is
    - summarize: Replace code with a summary comment
    - remove: Remove the code block entirely
    - extract: Write code to artifact_path file, replace with placeholder

    Args:
        content: The content to process
        blocks: List of CodeBlockSpec objects
        logger: Optional logger for reporting
        output_dir: Base directory for extracted artifacts (required for extract action)

    Returns:
        Tuple of (modified_content, blocks_processed_count)
    """
    if logger is None:
        logger = logging.getLogger(__name__)

    if not blocks:
        return content, 0

    result = content
    processed_count = 0

    # Find all code blocks in content
    code_block_pattern = re.compile(
        r'```(\w*)\n(.*?)```',
        re.DOTALL
    )

    # Build a list of (match, index) for replacement
    matches = list(code_block_pattern.finditer(result))

    # Process blocks in reverse order to preserve positions
    for i, match in enumerate(reversed(matches)):
        block_idx = len(matches) - 1 - i  # 0-indexed from start

        # Find the corresponding spec (by id, which should match position)
        spec = None
        for s in blocks:
            if s.id == block_idx + 1:  # IDs are 1-indexed
                spec = s
                break

        if spec is None:
            # No spec for this block, keep as-is
            continue

        language = match.group(1) or spec.language
        code_content = match.group(2)

        if spec.action == 'keep':
            # Keep as-is
            continue

        elif spec.action == 'summarize':
            # Replace with summary
            summary = spec.description or f"{language} code block ({spec.lines} lines)"
            replacement = f"\n[Code: {summary}]\n"
            result = result[:match.start()] + replacement + result[match.end():]
            processed_count += 1
            logger.debug(f"Summarized code block {spec.id}: {summary[:40]}...")

        elif spec.action == 'remove':
            # Remove entirely
            result = result[:match.start()] + result[match.end():]
            processed_count += 1
            logger.debug(f"Removed code block {spec.id}")

        elif spec.action == 'extract':
            # Write extracted code to artifact file
            if spec.artifact_path and output_dir:
                artifact_path = output_dir / spec.artifact_path
                # Create parent directories if needed
                artifact_path.parent.mkdir(parents=True, exist_ok=True)
                # Write the extracted code (strip trailing newline from code_content)
                artifact_path.write_text(code_content.rstrip('\n') + '\n', encoding='utf-8')
                logger.info(f"Extracted code block {spec.id} to {artifact_path}")
                path_note = f" to {spec.artifact_path}"
            elif spec.artifact_path:
                # No output_dir, just note the path
                logger.warning(f"Cannot extract code block {spec.id}: no output directory specified")
                path_note = f" (artifact: {spec.artifact_path})"
            else:
                path_note = ""

            replacement = f"\n[Code extracted{path_note}]\n"
            result = result[:match.start()] + replacement + result[match.end():]
            processed_count += 1

    return result, processed_count


def generate_variants(
    canonical_path: Path,
    options: Optional[VariantOptions] = None,
    logger: Optional[logging.Logger] = None
) -> VariantResult:
    """
    Generate transcript, transcript-lite, and summary variants from a canonical file.

    Args:
        canonical_path: Path to the canonical file
        options: VariantOptions controlling which variants to generate
        logger: Optional logger for reporting

    Returns:
        VariantResult with generated content

    Raises:
        ValueError: If the canonical file is malformed
        FileNotFoundError: If the canonical file doesn't exist
    """
    if logger is None:
        logger = logging.getLogger(__name__)

    if options is None:
        options = VariantOptions()

    if not canonical_path.exists():
        raise FileNotFoundError(f"Canonical file not found: {canonical_path}")

    content = canonical_path.read_text(encoding='utf-8')

    # Parse the canonical file
    config, main_content, backmatter = parse_canonical_file(content)
    logger.info(f"Parsed canonical: {config.title or config.slug}")

    result = VariantResult(config=config, backmatter=backmatter)

    # Generate transcript (main content with sections_remove applied)
    if options.generate_transcript:
        transcript = main_content
        if config.sections_remove:
            transcript, removed = apply_section_removals(
                transcript, config.sections_remove, logger
            )
            logger.info(f"Applied {removed} section removals for transcript")

        # Apply redaction if categories specified
        if options.redact_categories:
            transcript, redacted = apply_redaction(
                transcript, config.sensitivity, options.redact_categories, logger
            )
            if redacted > 0:
                logger.info(f"Redacted {redacted} items in transcript")

        result.transcript = _build_transcript_output(config, transcript)

    # Generate transcript-lite (sections_lite_remove + code_blocks processed)
    if options.generate_lite:
        lite = main_content

        # Apply sections_remove first (same as transcript)
        if config.sections_remove:
            lite, _ = apply_section_removals(lite, config.sections_remove, logger)

        # Then apply sections_lite_remove
        if config.sections_lite_remove:
            lite, removed = apply_section_removals(
                lite, config.sections_lite_remove, logger
            )
            logger.info(f"Applied {removed} lite section removals")

        # Process code blocks (pass output_dir for extraction)
        if config.code_blocks:
            lite, processed = process_code_blocks(
                lite, config.code_blocks, logger, output_dir=options.output_dir
            )
            logger.info(f"Processed {processed} code blocks for lite")

        # Apply redaction if categories specified
        if options.redact_categories:
            lite, redacted = apply_redaction(
                lite, config.sensitivity, options.redact_categories, logger
            )
            if redacted > 0:
                logger.info(f"Redacted {redacted} items in transcript-lite")

        result.transcript_lite = _build_transcript_output(config, lite, is_lite=True)

    # Generate summary
    if options.generate_summary:
        if backmatter.summary:
            result.summary = _build_summary_output(config, backmatter)
        else:
            logger.warning("No summary found in backmatter")

    return result


def _build_transcript_output(
    config: CanonicalConfig,
    content: str,
    is_lite: bool = False
) -> str:
    """Build the full transcript output with frontmatter."""
    lines = ['---']

    lines.append(f'title: "{config.title}"')
    lines.append(f'slug: {config.slug}')
    lines.append(f'date: {config.date}')
    lines.append(f'type: {"transcript-lite" if is_lite else "transcript"}')
    if config.description:
        lines.append(f'description: "{config.description}"')
    if config.tags:
        lines.append(f'tags: [{", ".join(config.tags)}]')

    lines.append('---')
    lines.append('')
    lines.append(content)
    lines.append('')
    lines.append('---')
    lines.append('')
    lines.append('## End of Transcript')
    lines.append('')

    return '\n'.join(lines)


def _build_summary_output(config: CanonicalConfig, backmatter: Backmatter) -> str:
    """
    Build the summary output with frontmatter.

    Uses full_summary which may include multiple sections:
    - ## Summary
    - ## What Was Discussed
    - ## Decisions Made
    - ## Work Products
    """
    lines = ['---']

    lines.append(f'title: "{config.title} - Summary"')
    lines.append(f'slug: {config.slug}')
    lines.append(f'date: {config.date}')
    lines.append('type: summary')
    if config.description:
        lines.append(f'description: "{config.description}"')
    if config.tags:
        lines.append(f'tags: [{", ".join(config.tags)}]')

    lines.append('---')
    lines.append('')
    lines.append(f'# {config.title}')
    lines.append('')

    # Use full_summary if available (includes all subsections),
    # otherwise fall back to brief summary
    if backmatter.full_summary:
        # full_summary already includes "## Summary" heading, so we strip it
        # to avoid duplication since we have the title as # heading
        summary_content = backmatter.full_summary
        # Remove the leading "## Summary" if present since we have title
        if summary_content.startswith('## Summary'):
            summary_content = summary_content[len('## Summary'):].lstrip('\n')
        lines.append(summary_content)
    elif backmatter.summary:
        lines.append(backmatter.summary)

    if backmatter.continuation:
        lines.append('')
        lines.append('---')
        lines.append('')
        lines.append('## Continuation Context')
        lines.append('')
        lines.append(backmatter.continuation)

    lines.append('')

    return '\n'.join(lines)


def generate_variants_from_content(
    content: str,
    options: Optional[VariantOptions] = None,
    logger: Optional[logging.Logger] = None
) -> VariantResult:
    """
    Generate variants from canonical content string (instead of file path).

    Same as generate_variants() but takes content directly.
    """
    if logger is None:
        logger = logging.getLogger(__name__)

    if options is None:
        options = VariantOptions()

    # Parse the canonical file
    config, main_content, backmatter = parse_canonical_file(content)
    logger.info(f"Parsed canonical: {config.title or config.slug}")

    result = VariantResult(config=config, backmatter=backmatter)

    # Generate transcript
    if options.generate_transcript:
        transcript = main_content
        if config.sections_remove:
            transcript, removed = apply_section_removals(
                transcript, config.sections_remove, logger
            )
            logger.info(f"Applied {removed} section removals for transcript")
        result.transcript = _build_transcript_output(config, transcript)

    # Generate transcript-lite
    if options.generate_lite:
        lite = main_content
        if config.sections_remove:
            lite, _ = apply_section_removals(lite, config.sections_remove, logger)
        if config.sections_lite_remove:
            lite, removed = apply_section_removals(
                lite, config.sections_lite_remove, logger
            )
            logger.info(f"Applied {removed} lite section removals")
        if config.code_blocks:
            lite, processed = process_code_blocks(
                lite, config.code_blocks, logger, output_dir=options.output_dir
            )
            logger.info(f"Processed {processed} code blocks for lite")
        result.transcript_lite = _build_transcript_output(config, lite, is_lite=True)

    # Generate summary
    if options.generate_summary:
        if backmatter.summary:
            result.summary = _build_summary_output(config, backmatter)
        else:
            logger.warning("No summary found in backmatter")

    return result
