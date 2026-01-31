"""
Canonicalize module for conversation export processing.

This module implements Step 1 of the two-step pipeline:
Raw input -> Canonical file with rich frontmatter

Step 1 (canonicalize) does:
- Parse CONFIG block (v1 or v2 format)
- Apply transcription corrections
- Structure content with clean frontmatter
- Preserve backmatter (summary/continuation)
- DO NOT remove sections yet (that's Step 2)

Step 2 (variants) does:
- Apply section removals
- Generate transcript, transcript-lite, summary
- Apply sensitivity redaction
"""

import re
import logging
from pathlib import Path
from datetime import datetime
from typing import List, Tuple, Optional, Dict, Any

try:
    import yaml
    YAML_AVAILABLE = True
except ImportError:
    YAML_AVAILABLE = False

from .models import (
    CanonicalConfig, TranscriptionFix, SectionSpec, Sensitivity,
    SensitivityTerms, SensitivitySection, CodeBlockSpec, Backmatter
)
from .parsing import (
    extract_config_block, parse_config_block_auto, detect_config_version,
    parse_messages, clean_all_messages, extract_backmatter,
    CONFIG_START_MARKER, CONFIG_END_MARKER
)
from .content import extract_full_transcript, strip_frontmatter


def load_corrections(corrections_path: Path) -> List[TranscriptionFix]:
    """
    Load transcription corrections from a YAML file.

    Expected format:
    corrections:
      - original: "misheard text"
        corrected: "correct text"
      - pattern: "chat gpt"
        replacement: "ChatGPT"

    Args:
        corrections_path: Path to corrections YAML file

    Returns:
        List of TranscriptionFix objects
    """
    if not corrections_path.exists():
        return []

    if not YAML_AVAILABLE:
        logging.warning("PyYAML not available, cannot load corrections file")
        return []

    try:
        with open(corrections_path, 'r', encoding='utf-8') as f:
            data = yaml.safe_load(f) or {}
    except Exception as e:
        logging.warning(f"Failed to load corrections file: {e}")
        return []

    corrections = []
    for item in data.get('corrections', []):
        if isinstance(item, dict):
            # Support both 'original'/'corrected' and 'pattern'/'replacement'
            original = item.get('original') or item.get('pattern', '')
            corrected = item.get('corrected') or item.get('replacement', '')
            if original and corrected:
                corrections.append(TranscriptionFix(
                    original=original,
                    corrected=corrected
                ))

    return corrections


def apply_corrections(
    content: str,
    corrections: List[TranscriptionFix],
    logger: Optional[logging.Logger] = None
) -> Tuple[str, List[TranscriptionFix]]:
    """
    Apply transcription corrections to content.

    Args:
        content: The content to process
        corrections: List of corrections to apply
        logger: Optional logger for reporting

    Returns:
        Tuple of (corrected_content, list_of_applied_fixes)
    """
    if logger is None:
        logger = logging.getLogger(__name__)

    result = content
    applied = []

    for fix in corrections:
        # Case-insensitive search
        pattern = re.compile(re.escape(fix.original), re.IGNORECASE)
        matches = pattern.findall(result)

        if matches:
            result = pattern.sub(fix.corrected, result)
            applied.append(fix)
            logger.debug(f"Applied correction: '{fix.original}' -> '{fix.corrected}' ({len(matches)} occurrences)")

    return result, applied


def generate_canonical_frontmatter(config: CanonicalConfig) -> str:
    """
    Generate v2 frontmatter YAML from a CanonicalConfig.

    Returns:
        YAML frontmatter string including --- delimiters
    """
    lines = ['---']

    # Identity section
    lines.append(f'title: "{config.title}"')
    lines.append(f'slug: {config.slug}')
    lines.append(f'date: {config.date}')
    lines.append(f'source: {config.source}')
    if config.description:
        lines.append(f'description: "{_escape_yaml_string(config.description)}"')
    if config.tags:
        lines.append(f'tags: [{", ".join(config.tags)}]')
    else:
        lines.append('tags: []')

    # Section handling
    if config.sections_remove:
        lines.append('')
        lines.append('sections_remove:')
        for spec in config.sections_remove:
            lines.append(f'  - start: "{_escape_yaml_string(spec.start)}"')
            lines.append(f'    end: "{_escape_yaml_string(spec.end)}"')
            if spec.description:
                lines.append(f'    description: "{_escape_yaml_string(spec.description)}"')

    if config.sections_lite_remove:
        lines.append('')
        lines.append('sections_lite_remove:')
        for spec in config.sections_lite_remove:
            lines.append(f'  - start: "{_escape_yaml_string(spec.start)}"')
            lines.append(f'    end: "{_escape_yaml_string(spec.end)}"')
            if spec.description:
                lines.append(f'    description: "{_escape_yaml_string(spec.description)}"')
            if spec.replacement:
                lines.append(f'    replacement: "{_escape_yaml_string(spec.replacement)}"')

    # Code blocks
    if config.code_blocks:
        lines.append('')
        lines.append('code_blocks:')
        for cb in config.code_blocks:
            lines.append(f'  - id: {cb.id}')
            lines.append(f'    language: {cb.language}')
            lines.append(f'    lines: {cb.lines}')
            if cb.description:
                lines.append(f'    description: "{_escape_yaml_string(cb.description)}"')
            lines.append(f'    action: {cb.action}')
            if cb.artifact_path:
                lines.append(f'    artifact_path: {cb.artifact_path}')

    # Transcription
    if config.transcription_fixes_applied:
        lines.append('')
        lines.append('transcription:')
        lines.append('  fixes_applied:')
        for fix in config.transcription_fixes_applied:
            lines.append(f'    - original: "{_escape_yaml_string(fix.original)}"')
            lines.append(f'      corrected: "{_escape_yaml_string(fix.corrected)}"')

    # Sensitivity
    if _has_sensitivity(config.sensitivity):
        lines.append('')
        lines.append('sensitivity:')
        if config.sensitivity.key:
            lines.append(f'  key: {config.sensitivity.key}')

        if _has_sensitivity_terms(config.sensitivity.terms):
            lines.append('  terms:')
            if config.sensitivity.terms.health:
                lines.append(f'    health: {", ".join(config.sensitivity.terms.health)}')
            if config.sensitivity.terms.personal:
                lines.append(f'    personal: {", ".join(config.sensitivity.terms.personal)}')
            if config.sensitivity.terms.names:
                lines.append(f'    names: {", ".join(config.sensitivity.terms.names)}')
            if config.sensitivity.terms.financial:
                lines.append(f'    financial: {", ".join(config.sensitivity.terms.financial)}')
            for cat, terms in config.sensitivity.terms.custom.items():
                if terms:
                    lines.append(f'    {cat}: {", ".join(terms)}')

        if config.sensitivity.sections:
            lines.append('  sections:')
            for sec in config.sensitivity.sections:
                lines.append(f'    - start: "{_escape_yaml_string(sec.start)}"')
                lines.append(f'      end: "{_escape_yaml_string(sec.end)}"')
                if sec.tags:
                    lines.append(f'      tags: [{", ".join(sec.tags)}]')
                if sec.description:
                    lines.append(f'      description: "{_escape_yaml_string(sec.description)}"')

    lines.append('---')
    lines.append('')

    return '\n'.join(lines)


def _escape_yaml_string(s: str) -> str:
    """Escape a string for YAML output."""
    return s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')


def _has_sensitivity(sensitivity: Sensitivity) -> bool:
    """Check if sensitivity has any content."""
    return (
        sensitivity.key is not None or
        _has_sensitivity_terms(sensitivity.terms) or
        len(sensitivity.sections) > 0
    )


def _has_sensitivity_terms(terms: SensitivityTerms) -> bool:
    """Check if sensitivity terms has any content."""
    return (
        len(terms.health) > 0 or
        len(terms.personal) > 0 or
        len(terms.names) > 0 or
        len(terms.financial) > 0 or
        len(terms.custom) > 0
    )


def generate_backmatter(backmatter: Backmatter) -> str:
    """
    Generate backmatter section from Backmatter object.

    Uses full_summary if available, which may include multiple sections:
    - ## Summary
    - ## What Was Discussed
    - ## Decisions Made
    - ## Work Products

    Returns:
        Backmatter string including delimiter
    """
    has_summary = backmatter.full_summary or backmatter.summary
    if not has_summary and not backmatter.continuation:
        return ''

    lines = ['', '---', '', '<!-- === BACKMATTER === -->', '']

    # Use full_summary if available (includes all subsections),
    # otherwise fall back to brief summary
    if backmatter.full_summary:
        # full_summary already includes "## Summary" heading
        lines.append(backmatter.full_summary)
        lines.append('')
    elif backmatter.summary:
        lines.append('## Summary')
        lines.append('')
        lines.append(backmatter.summary)
        lines.append('')

    if backmatter.continuation:
        lines.append('## Continuation Context')
        lines.append('')
        lines.append(backmatter.continuation)
        lines.append('')

    return '\n'.join(lines)


def extract_main_content(content: str) -> str:
    """
    Extract main content from raw input, excluding:
    - Frontmatter (if present)
    - CONFIG block

    Handles two formats:
    1. Claude exports: content first, CONFIG at end -> extract before CONFIG
    2. Bruba exports: CONFIG at start, content after -> extract after CONFIG
    """
    # Strip any existing frontmatter
    content = strip_frontmatter(content)

    # Find CONFIG block start
    config_start_patterns = [
        r'```yaml\s*\n\s*=== EXPORT CONFIG',
        r'=== EXPORT CONFIG',
    ]

    config_start = None
    for pattern in config_start_patterns:
        match = re.search(pattern, content)
        if match:
            if config_start is None or match.start() < config_start:
                config_start = match.start()

    # No CONFIG block found - return all content
    if config_start is None:
        return content.strip()

    # Find CONFIG block end
    config_end_patterns = [
        r'=== END CONFIG ===\s*```',
        r'=== END CONFIG ===',
    ]

    config_end = None
    for pattern in config_end_patterns:
        match = re.search(pattern, content)
        if match:
            config_end = match.end()
            break

    # Determine if CONFIG is at start or end of file
    # If CONFIG starts within first 50 chars (after stripping), it's at the start
    if config_start < 50:
        # CONFIG at start - extract content AFTER the end marker
        if config_end is not None:
            return content[config_end:].strip()
        else:
            # No end marker found, try to find end of CONFIG section
            return content[config_start:].strip()
    else:
        # CONFIG at end - extract content BEFORE it (original behavior)
        return content[:config_start].strip()


def canonicalize(
    input_path: Path,
    corrections: Optional[List[TranscriptionFix]] = None,
    logger: Optional[logging.Logger] = None
) -> Tuple[str, CanonicalConfig, Backmatter]:
    """
    Transform raw input into canonical format.

    This is Step 1 of the two-step pipeline.

    Args:
        input_path: Path to input file
        corrections: Optional list of transcription corrections
        logger: Optional logger

    Returns:
        Tuple of (canonical_content, config, backmatter)

    Raises:
        ValueError: If no CONFIG block found
    """
    if logger is None:
        logger = logging.getLogger(__name__)

    content = input_path.read_text(encoding='utf-8')

    # Extract CONFIG block
    config_block = extract_config_block(content)
    if not config_block:
        raise ValueError(f"No EXPORT CONFIG block found in {input_path}")

    # Parse config (auto-detects v1 vs v2)
    config = parse_config_block_auto(config_block)
    logger.info(f"Parsed config: {config.title or config.slug}")

    # Fill in missing date from filename if needed
    if not config.date:
        config.date = _extract_date_from_path(input_path)

    # Extract main content
    main_content = extract_main_content(content)

    # Clean UI artifacts from messages
    messages = parse_messages(main_content)
    cleaned_messages = clean_all_messages(messages)

    # Reconstruct content with cleaned messages
    cleaned_parts = []
    for msg in cleaned_messages:
        cleaned_parts.append(f"=== MESSAGE {msg.index} | {msg.role} ===")
        cleaned_parts.append(msg.content)
        cleaned_parts.append("")

    main_content = '\n'.join(cleaned_parts).strip()

    # Apply transcription corrections from config (v2 fixes_applied)
    if config.transcription_fixes_applied:
        main_content, applied = apply_corrections(main_content, config.transcription_fixes_applied, logger)
        if applied:
            logger.info(f"Applied {len(applied)} config transcription fixes")

    # Apply transcription corrections from external corrections file
    if corrections:
        main_content, applied = apply_corrections(main_content, corrections, logger)
        if applied:
            # Add applied corrections to config
            config.transcription_fixes_applied.extend(applied)
            logger.info(f"Applied {len(applied)} transcription corrections from corrections file")

    # Extract backmatter (summary, continuation)
    backmatter = extract_backmatter(content)

    # Generate canonical output
    frontmatter = generate_canonical_frontmatter(config)
    backmatter_str = generate_backmatter(backmatter)

    canonical_content = frontmatter + main_content + backmatter_str

    return canonical_content, config, backmatter


def _extract_date_from_path(path: Path) -> str:
    """Extract date from filename if it starts with YYYY-MM-DD pattern."""
    name = path.stem
    # Check for date pattern at start
    match = re.match(r'^(\d{4}-\d{2}-\d{2})', name)
    if match:
        return match.group(1)
    # Default to today
    return datetime.now().strftime('%Y-%m-%d')


def canonicalize_from_content(
    content: str,
    filename: str = "unnamed",
    corrections: Optional[List[TranscriptionFix]] = None,
    logger: Optional[logging.Logger] = None
) -> Tuple[str, CanonicalConfig, Backmatter]:
    """
    Transform raw content string into canonical format.

    Same as canonicalize() but takes content directly instead of file path.

    Args:
        content: Raw content string
        filename: Optional filename for date extraction
        corrections: Optional list of transcription corrections
        logger: Optional logger

    Returns:
        Tuple of (canonical_content, config, backmatter)
    """
    if logger is None:
        logger = logging.getLogger(__name__)

    # Extract CONFIG block
    config_block = extract_config_block(content)
    if not config_block:
        raise ValueError("No EXPORT CONFIG block found in content")

    # Parse config
    config = parse_config_block_auto(config_block)
    logger.info(f"Parsed config: {config.title or config.slug}")

    # Fill in missing date
    if not config.date:
        match = re.match(r'^(\d{4}-\d{2}-\d{2})', filename)
        if match:
            config.date = match.group(1)
        else:
            config.date = datetime.now().strftime('%Y-%m-%d')

    # Extract main content
    main_content = extract_main_content(content)

    # Clean UI artifacts from messages
    messages = parse_messages(main_content)
    cleaned_messages = clean_all_messages(messages)

    # Reconstruct content with cleaned messages
    cleaned_parts = []
    for msg in cleaned_messages:
        cleaned_parts.append(f"=== MESSAGE {msg.index} | {msg.role} ===")
        cleaned_parts.append(msg.content)
        cleaned_parts.append("")

    main_content = '\n'.join(cleaned_parts).strip()

    # Apply transcription corrections from config (v2 fixes_applied)
    if config.transcription_fixes_applied:
        main_content, applied = apply_corrections(main_content, config.transcription_fixes_applied, logger)
        if applied:
            logger.info(f"Applied {len(applied)} config transcription fixes")

    # Apply corrections from external file
    if corrections:
        main_content, applied = apply_corrections(main_content, corrections, logger)
        if applied:
            config.transcription_fixes_applied.extend(applied)
            logger.info(f"Applied {len(applied)} transcription corrections from corrections file")

    # Extract backmatter
    backmatter = extract_backmatter(content)

    # Generate output
    frontmatter = generate_canonical_frontmatter(config)
    backmatter_str = generate_backmatter(backmatter)

    canonical_content = frontmatter + main_content + backmatter_str

    return canonical_content, config, backmatter
