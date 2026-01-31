"""
Parsing utilities for conversation export processing.

This module handles parsing the two main structured elements in exports:
1. Message delimiters (=== MESSAGE N | ROLE ===) that separate conversation turns
2. EXPORT CONFIG blocks that control processing behavior

Contents:
    - parse_messages(): Split raw export into individual messages
    - clean_message_content(): Remove UI artifacts from message text
    - extract_config_block(): Extract the YAML-ish config block
    - parse_yaml_like_block(): Parse YAML-ish config into dict
    - parse_config_block(): Convert config dict to ExportConfig
    - detect_source(): Auto-detect conversation source from content patterns
    - extract_date_from_content(): Extract date from timestamps or filename
    - generate_slug(): Generate URL-safe slug from title and date
    - extract_title_hint(): Extract title hint from first user message
"""

import re
import logging
from datetime import datetime
from typing import List, Optional

try:
    import yaml
    YAML_AVAILABLE = True
except ImportError:
    YAML_AVAILABLE = False

from .models import (
    Message, ExportConfig, AnchorSpec, ReplacementSpec, MidConversationTranscription,
    # V2 types
    CanonicalConfig, SectionSpec, Sensitivity, SensitivityTerms, SensitivitySection,
    TranscriptionFix, CodeBlockSpec, Backmatter
)

# Pattern to identify message boundaries in raw exports
MESSAGE_DELIMITER_PATTERN = re.compile(
    r'^=== MESSAGE (\d+) \| (USER|ASSISTANT|UNKNOWN) ===$',
    re.MULTILINE
)

# Config block markers
CONFIG_START_MARKER = "=== EXPORT CONFIG ==="
CONFIG_END_MARKER = "=== END CONFIG ==="

# UI artifact patterns to clean from messages
UI_ARTIFACTS = [
    re.compile(r'^\d{1,2}:\d{2}\s*(?:AM|PM)\s*$', re.MULTILINE),  # "4:02 PM"
    re.compile(r'^Show more\d{1,2}:\d{2}\s*(?:AM|PM)\s*$', re.MULTILINE),  # "Show more11:34 AM"
    re.compile(r'^\d+\s*steps?\s*$', re.MULTILINE | re.IGNORECASE),  # "5 steps"
    re.compile(r'^\d+s\s*$', re.MULTILINE),  # "14s" (thinking time)
    re.compile(r'^Show more\s*$', re.MULTILINE),
    re.compile(r'^Show less\s*$', re.MULTILINE),
    re.compile(r'^PASTED\s*$', re.MULTILINE),
    re.compile(r'^pasted\s*$', re.MULTILINE),
    re.compile(r'^\d+\s*/\s*\d+\s*$', re.MULTILINE),  # "2 / 2" regeneration indicator
    re.compile(r'^Thought process\s*$', re.MULTILINE),
    re.compile(r'^Failed to view\s*$', re.MULTILINE),
    re.compile(r'^R\s*$', re.MULTILINE),
    re.compile(r'^\* \s*$', re.MULTILINE),
    re.compile(r'^1\. \s*$', re.MULTILINE),
    re.compile(r'^Claude\s*$', re.MULTILINE),
    re.compile(r'^---\s*$', re.MULTILINE),
]

# Pattern for Claude's thinking summaries
THINKING_SUMMARY_PATTERN = re.compile(
    r'^[A-Z][a-z].*?(?:ing|ed|ion)\s+.*?\.\s*$',
    re.MULTILINE
)

# Bruba/Signal message artifact patterns
# These transform Bruba-specific formats into clean, readable output

# Pattern: Media attachment with no transcript (audio-only message)
# Input: [media attached: ...]\nTo send an image...\n[Signal ... id:...] <media:audio>
# Output: [attached audio file with no transcript]
BRUBA_MEDIA_ONLY_PATTERN = re.compile(
    r'\[media attached:[^\]]*\]'  # [media attached: ...]
    r'(?:\s*\n.*?(?:To send an image|prefer the message tool).*?\n)*'  # instruction text
    r'\s*\[(?:Signal|Telegram)\s+\w+\s+id:[^\]]+\]\s*'  # [Signal/Telegram ... id:...]
    r'<media:audio>',  # <media:audio>
    re.DOTALL
)

# Pattern: Audio message with transcript
# Input: [Audio] User text: [Signal ... id:...] <media:audio> Transcript: X
# Output: [Transcript] X
BRUBA_AUDIO_WITH_TRANSCRIPT_PATTERN = re.compile(
    r'\[Audio\]\s*User text:\s*'  # [Audio] User text:
    r'\[(?:Signal|Telegram)\s+\w+\s+id:[^\]]+\]\s*'  # [Signal/Telegram ... id:...]
    r'<media:audio>\s*'  # <media:audio>
    r'Transcript:\s*',  # Match "Transcript: " (will be replaced)
    re.DOTALL
)

# Pattern: Standalone Signal/Telegram metadata prefix (without media)
# Input: [Signal Michael id:uuid:... +5s 2026-01-26 18:49 EST] message text
# Output: message text
BRUBA_METADATA_PREFIX_PATTERN = re.compile(
    r'\[(?:Signal|Telegram)\s+\w+\s+id:[^\]]+\]\s*'
)

# Pattern: Standalone <media:audio> tag
BRUBA_MEDIA_TAG_PATTERN = re.compile(r'<media:audio>\s*')

# Whisper transcription noise patterns (inside transcript content)
# These appear within the transcript text and should be stripped

# Language detection header: "Detecting language using up to the first 30 seconds. Use `--language` to specify the language Detected language: English"
WHISPER_LANG_DETECTION_PATTERN = re.compile(
    r'Detecting language using up to the first \d+ seconds\.\s*'
    r'Use [`\']--language[`\']\s*to specify the language\s*'
    r'Detected language:\s*\w+\s*'
)

# Timestamp markers: [00:00.000 --> 00:04.000]
WHISPER_TIMESTAMP_PATTERN = re.compile(r'\[\d{2}:\d{2}\.\d{3}\s*-->\s*\d{2}:\d{2}\.\d{3}\]\s*')

# File system errors at end of transcript: "Skipping /path/... due to OSError: ..."
WHISPER_OSERROR_PATTERN = re.compile(
    r'\s*Skipping\s+/[^\s]+\s+due to OSError:\s*\[Errno \d+\][^\n]*'
)


def parse_messages(content: str) -> List[Message]:
    """
    Parse content into list of messages using === MESSAGE N | ROLE === delimiters.

    Args:
        content: Raw file content with message delimiters

    Returns:
        List of Message objects in order
    """
    messages = []

    # Find all message delimiters
    matches = list(MESSAGE_DELIMITER_PATTERN.finditer(content))

    if not matches:
        # No message delimiters found - treat whole content as single message
        return [Message(index=0, role="UNKNOWN", content=content, raw_content=content)]

    for i, match in enumerate(matches):
        msg_index = int(match.group(1))
        msg_role = match.group(2)

        # Content starts after this delimiter
        start = match.end()

        # Content ends at next delimiter or end of file
        if i + 1 < len(matches):
            end = matches[i + 1].start()
        else:
            end = len(content)

        raw_content = content[start:end].strip()
        messages.append(Message(
            index=msg_index,
            role=msg_role,
            content=raw_content,
            raw_content=raw_content
        ))

    return messages


def clean_bruba_artifacts(content: str) -> str:
    """
    Clean Bruba/Signal-specific message artifacts and Whisper transcription noise.

    Transforms:
    - Media-only messages -> [attached audio file with no transcript]
    - Audio with transcript -> Transcript: X (strips wrapper)
    - Signal/Telegram metadata prefixes -> removed
    - <media:audio> tags -> removed
    - Whisper language detection headers -> removed
    - Whisper timestamp markers -> removed
    - Whisper OSError messages -> removed

    Args:
        content: The message content to clean

    Returns:
        Cleaned content with Bruba artifacts transformed
    """
    result = content

    # Transform media-only messages (audio with no transcript)
    result = BRUBA_MEDIA_ONLY_PATTERN.sub('[attached audio file with no transcript]', result)

    # Transform audio messages with transcript - output "[Transcript] X"
    result = BRUBA_AUDIO_WITH_TRANSCRIPT_PATTERN.sub('[Transcript] ', result)

    # Remove standalone Signal/Telegram metadata prefixes
    result = BRUBA_METADATA_PREFIX_PATTERN.sub('', result)

    # Remove standalone media tags
    result = BRUBA_MEDIA_TAG_PATTERN.sub('', result)

    # Clean Whisper transcription noise from transcript content
    result = WHISPER_LANG_DETECTION_PATTERN.sub('', result)
    result = WHISPER_TIMESTAMP_PATTERN.sub('', result)
    result = WHISPER_OSERROR_PATTERN.sub('', result)

    return result


def clean_message_content(content: str, role: str = "UNKNOWN") -> str:
    """
    Remove UI artifacts from message content.

    Args:
        content: The message content to clean
        role: The message role (USER, ASSISTANT, UNKNOWN)

    Returns:
        Cleaned content
    """
    result = content

    # Apply Bruba/Signal artifact cleanup first (transforms format)
    result = clean_bruba_artifacts(result)

    # Remove UI artifact patterns
    for pattern in UI_ARTIFACTS:
        result = pattern.sub('', result)

    # Remove thinking summaries at the very start of ASSISTANT messages only
    # These are lines like "Thinking about how to help..." or "Evaluated options..."
    if role == "ASSISTANT":
        lines = result.split('\n')
        if lines and THINKING_SUMMARY_PATTERN.match(lines[0].strip()):
            first_line = lines[0].strip()
            if len(first_line) < 100 and first_line.endswith('.'):
                lines = lines[1:]
        result = '\n'.join(lines)

    # Collapse multiple blank lines into max 2
    result = re.sub(r'\n{4,}', '\n\n\n', result)

    # Strip leading/trailing whitespace
    result = result.strip()

    return result


def clean_all_messages(messages: List[Message]) -> List[Message]:
    """Apply cleanup to all messages."""
    for msg in messages:
        msg.content = clean_message_content(msg.content, msg.role)
    return messages


class TruncatedExportError(Exception):
    """Raised when an export appears to be truncated."""
    pass


def check_for_truncated_export(content: str) -> Optional[str]:
    """Check if content appears to be a truncated export."""
    has_export_config = "=== EXPORT CONFIG" in content
    has_end_config = "=== END CONFIG ===" in content

    if has_export_config and not has_end_config:
        return "Export appears truncated: found '=== EXPORT CONFIG ===' but no '=== END CONFIG ===' marker"

    return None


def extract_config_block(content: str) -> Optional[str]:
    """Extract the first EXPORT CONFIG block from file content."""
    truncation_error = check_for_truncated_export(content)
    if truncation_error:
        raise TruncatedExportError(truncation_error)

    blocks = extract_all_config_blocks(content)
    return blocks[0] if blocks else None


def extract_all_config_blocks(content: str) -> List[str]:
    """
    Extract all EXPORT CONFIG blocks from file content.

    Handles both labeled configs like "=== EXPORT CONFIG (Personal) ===" and
    plain "=== EXPORT CONFIG ===" markers.

    Returns:
        List of config block contents (without markers)
    """
    patterns = [
        # With yaml code fence, labeled
        re.compile(
            r'```yaml\s*\n\s*=== EXPORT CONFIG(?:\s*\([^)]+\))?\s*===\s*\n(.*?)\n\s*=== END CONFIG ===\s*\n```',
            re.DOTALL
        ),
        # Plain block, labeled
        re.compile(
            r'=== EXPORT CONFIG(?:\s*\([^)]+\))?\s*===\s*\n(.*?)\n\s*=== END CONFIG ===',
            re.DOTALL
        ),
    ]

    blocks = []
    for pattern in patterns:
        for match in pattern.finditer(content):
            blocks.append(match.group(1))

    # Deduplicate
    seen = set()
    unique_blocks = []
    for block in blocks:
        block_hash = hash(block.strip())
        if block_hash not in seen:
            seen.add(block_hash)
            unique_blocks.append(block)

    return unique_blocks


def parse_yaml_like_block(block: str) -> dict:
    """
    Parse YAML-like config block into a dict structure.

    Handles:
    - Simple key: value pairs
    - Lists with - items
    - Nested dicts with indentation
    - Inline lists [a, b, c]
    - Multiline strings with | or >
    """
    result = {}
    lines = block.strip().split('\n')

    current_key = None
    current_list = None
    current_dict = None
    current_dict_key = None
    base_indent = 0
    indent_stack = [(0, result)]

    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        if not stripped or stripped.startswith('#'):
            i += 1
            continue

        indent = len(line) - len(line.lstrip())

        # Check if this is a list item with nested dict
        if stripped.startswith('- ') and ':' in stripped[2:]:
            item_content = stripped[2:]

            if current_list is not None:
                item_dict = {}

                # Parse first key:value
                key, _, value = item_content.partition(':')
                key = key.strip()
                value = value.strip().strip('"\'')
                item_dict[key] = value

                # Look ahead for more keys
                base_indent = indent
                i += 1
                while i < len(lines):
                    next_line = lines[i]
                    next_stripped = next_line.strip()
                    next_indent = len(next_line) - len(next_line.lstrip())

                    if not next_stripped:
                        i += 1
                        continue

                    if next_indent <= base_indent and not next_stripped.startswith('- '):
                        break
                    if next_stripped.startswith('- ') and next_indent <= base_indent:
                        break

                    if ':' in next_stripped and not next_stripped.startswith('- '):
                        k, _, v = next_stripped.partition(':')
                        k = k.strip()
                        v = v.strip()

                        # Check for multiline value
                        if v == '|' or v == '>':
                            multiline_parts = []
                            i += 1
                            ml_base_indent = None
                            while i < len(lines):
                                ml_line = lines[i]
                                ml_stripped = ml_line.strip()
                                ml_indent = len(ml_line) - len(ml_line.lstrip())

                                if ml_base_indent is None and ml_stripped:
                                    ml_base_indent = ml_indent

                                if ml_stripped and ml_indent < (ml_base_indent or next_indent + 2):
                                    break

                                if ml_stripped:
                                    multiline_parts.append(ml_stripped)
                                elif multiline_parts:
                                    multiline_parts.append('')
                                i += 1

                            item_dict[k] = '\n'.join(multiline_parts).strip()
                            continue
                        else:
                            v = v.strip('"\'')
                            item_dict[k] = v
                    i += 1

                current_list.append(item_dict)
                continue

        # Simple list item
        elif stripped.startswith('- '):
            item = stripped[2:].strip().strip('"\'')
            if current_list is not None:
                current_list.append(item)
            i += 1
            continue

        # Key: value pair
        if ':' in stripped:
            key, _, value = stripped.partition(':')
            key = key.strip()
            value = value.strip()

            if value == '' or value == '[]':
                result[key] = []
                current_list = result[key]
                current_key = key
            elif value.lower() == 'none':
                result[key] = None
                current_list = None
            elif value.lower() in ['yes', 'true']:
                result[key] = True
                current_list = None
            elif value.lower() in ['no', 'false']:
                result[key] = False
                current_list = None
            elif value == '|' or value == '>':
                multiline_parts = []
                i += 1
                ml_base_indent = None
                while i < len(lines):
                    ml_line = lines[i]
                    ml_stripped = ml_line.strip()
                    ml_indent = len(ml_line) - len(ml_line.lstrip())

                    if ml_base_indent is None and ml_stripped:
                        ml_base_indent = ml_indent

                    if ml_stripped and ml_indent <= indent and ':' in ml_stripped:
                        break

                    if ml_stripped:
                        multiline_parts.append(ml_stripped)
                    elif multiline_parts:
                        multiline_parts.append('')
                    i += 1

                result[key] = '\n'.join(multiline_parts).strip()
                current_list = None
                continue
            else:
                result[key] = value.strip('"\'')
                current_list = None

        i += 1

    return result


def parse_config_block(block: str) -> ExportConfig:
    """Parse the YAML-like config block into structured data."""
    parsed = parse_yaml_like_block(block)

    config = ExportConfig(
        filename_base=parsed.get('filename_base', ''),
        project=parsed.get('project', ''),
        outputs=parsed.get('outputs', 'keep_all'),
        raw_block=block
    )

    # Parse sections_to_remove
    sections = parsed.get('sections_to_remove', [])
    if isinstance(sections, list):
        for item in sections:
            if isinstance(item, dict):
                config.sections_to_remove.append(AnchorSpec(
                    start_anchor=item.get('start_anchor', ''),
                    end_anchor=item.get('end_anchor', ''),
                    start_context=item.get('start_context'),
                    end_context=item.get('end_context'),
                    reason=item.get('reason', '')
                ))

    # Parse outputs_to_remove
    outputs = parsed.get('outputs_to_remove', [])
    if isinstance(outputs, list):
        for item in outputs:
            if isinstance(item, dict):
                config.outputs_to_remove.append(AnchorSpec(
                    start_anchor=item.get('start_anchor', ''),
                    end_anchor=item.get('end_anchor', ''),
                    start_context=item.get('start_context'),
                    end_context=item.get('end_context'),
                    reason=item.get('reason', '')
                ))

    # Parse transcription_replacements
    replacements = parsed.get('transcription_replacements', [])
    if isinstance(replacements, list):
        for item in replacements:
            if isinstance(item, dict):
                original = item.get('original_text', '') or item.get('find_anchor', '')
                cleaned = item.get('cleaned_text', '') or item.get('replace_with', '')
                original = original.replace('\\n', '\n')
                cleaned = cleaned.replace('\\n', '\n')
                config.transcription_replacements.append(ReplacementSpec(
                    original_text=original,
                    cleaned_text=cleaned,
                    find_anchor=original,
                    replace_with=cleaned
                ))

    # Parse mid_conversation_transcriptions
    mid_transcriptions = parsed.get('mid_conversation_transcriptions', [])
    if isinstance(mid_transcriptions, list):
        for item in mid_transcriptions:
            if isinstance(item, dict):
                raw_anchor = item.get('raw_anchor', '')
                cleaned_follows = item.get('cleaned_follows', True)
                if raw_anchor:
                    config.mid_conversation_transcriptions.append(MidConversationTranscription(
                        raw_anchor=raw_anchor,
                        cleaned_follows=cleaned_follows
                    ))

    # Parse transcription_errors_noted
    errors = parsed.get('transcription_errors_noted', [])
    if isinstance(errors, list):
        config.transcription_errors = [{'raw': e} if isinstance(e, str) else e for e in errors]

    config.continuation_packet = parsed.get('continuation_packet', False)

    return config


def extract_brief_description(content: str) -> str:
    """Extract brief_description from file content."""
    match = re.search(r'^brief_description:\s*(.+)$', content, re.MULTILINE)
    if match:
        desc = match.group(1).strip().strip('"\'')
        return desc
    return ""


# =============================================================================
# V2 Parsing Functions - New Canonical File Model
# =============================================================================

def detect_config_version(block: str) -> int:
    """
    Detect whether a config block is v1 or v2 format.

    V1 indicators: filename_base, sections_to_remove, outputs_to_remove
    V2 indicators: title, slug, sections_remove, sensitivity

    Returns:
        1 for v1 format, 2 for v2 format
    """
    # V2-specific fields
    v2_indicators = ['title:', 'slug:', 'sections_remove:', 'sensitivity:']
    # V1-specific fields
    v1_indicators = ['filename_base:', 'sections_to_remove:', 'outputs_to_remove:']

    v2_score = sum(1 for ind in v2_indicators if ind in block)
    v1_score = sum(1 for ind in v1_indicators if ind in block)

    return 2 if v2_score > v1_score else 1


def parse_sensitivity_terms(terms_dict: dict) -> SensitivityTerms:
    """Parse sensitivity terms from a dict into SensitivityTerms object."""
    def parse_term_list(value) -> List[str]:
        """Parse a term value (string or list) into a list of strings."""
        if isinstance(value, list):
            return value
        if isinstance(value, str):
            # Split by comma, strip whitespace
            return [t.strip() for t in value.split(',') if t.strip()]
        return []

    known_categories = ['health', 'personal', 'names', 'financial']
    custom = {}

    result = SensitivityTerms()
    for key, value in terms_dict.items():
        terms = parse_term_list(value)
        if key == 'health':
            result.health = terms
        elif key == 'personal':
            result.personal = terms
        elif key == 'names':
            result.names = terms
        elif key == 'financial':
            result.financial = terms
        else:
            result.custom[key] = terms

    return result


def parse_sensitivity_sections(sections_list: list) -> List[SensitivitySection]:
    """Parse sensitivity sections from a list of dicts."""
    result = []
    for item in sections_list:
        if isinstance(item, dict):
            tags = item.get('tags', [])
            if isinstance(tags, str):
                tags = [t.strip() for t in tags.split(',') if t.strip()]
            result.append(SensitivitySection(
                start=item.get('start', ''),
                end=item.get('end', ''),
                tags=tags,
                description=item.get('description', '')
            ))
    return result


def parse_inline_list(value) -> List[str]:
    """
    Parse a value that might be an inline list like [a, b, c] or a regular string/list.
    """
    if isinstance(value, list):
        # Already a list, but items might have bracket artifacts
        result = []
        for item in value:
            item = str(item).strip().strip('[]')
            result.append(item)
        return result
    if isinstance(value, str):
        value = value.strip()
        # Handle [item1, item2] format
        if value.startswith('[') and value.endswith(']'):
            inner = value[1:-1]
            return [t.strip() for t in inner.split(',') if t.strip()]
        # Handle comma-separated
        return [t.strip() for t in value.split(',') if t.strip()]
    return []


def parse_v2_config_block(block: str) -> CanonicalConfig:
    """
    Parse a v2 EXPORT CONFIG block into CanonicalConfig.

    V2 format uses:
    - title, slug, date, source, tags for identity
    - sections_remove (not sections_to_remove)
    - sensitivity.terms and sensitivity.sections
    - transcription.fixes_applied

    Uses PyYAML if available for proper nested structure parsing,
    falls back to YAML-like parser otherwise.
    """
    # Strip code fences if present (```yaml ... ```)
    block = block.strip()
    if block.startswith('```'):
        lines = block.split('\n')
        # Remove first line (```yaml or ```) and last line (```)
        if len(lines) >= 2:
            # Find the closing ``` line
            end_idx = len(lines) - 1
            while end_idx > 0 and not lines[end_idx].strip().startswith('```'):
                end_idx -= 1
            if end_idx > 0:
                block = '\n'.join(lines[1:end_idx])
            else:
                block = '\n'.join(lines[1:])

    # Try to use real YAML parser for v2 configs (they're proper YAML)
    if YAML_AVAILABLE:
        try:
            parsed = yaml.safe_load(block) or {}
        except yaml.YAMLError:
            # Fall back to YAML-like parser on error
            parsed = parse_yaml_like_block(block)
    else:
        parsed = parse_yaml_like_block(block)

    # Parse identity fields
    title = parsed.get('title', '')
    slug = parsed.get('slug', '')
    date = parsed.get('date', '')
    # Handle datetime objects from YAML parser
    if hasattr(date, 'strftime'):
        date = date.strftime('%Y-%m-%d')
    elif date:
        date = str(date)
    source = parsed.get('source', 'claude-projects')
    tags = parse_inline_list(parsed.get('tags', []))
    description = parsed.get('description', '')

    # Parse sections_remove
    sections_remove = []
    sr_list = parsed.get('sections_remove', [])
    if isinstance(sr_list, list):
        for item in sr_list:
            if isinstance(item, dict):
                sections_remove.append(SectionSpec(
                    start=item.get('start', ''),
                    end=item.get('end', ''),
                    description=item.get('description', ''),
                    replacement=item.get('replacement', '')
                ))

    # Parse sections_lite_remove
    sections_lite_remove = []
    slr_list = parsed.get('sections_lite_remove', [])
    if isinstance(slr_list, list):
        for item in slr_list:
            if isinstance(item, dict):
                sections_lite_remove.append(SectionSpec(
                    start=item.get('start', ''),
                    end=item.get('end', ''),
                    description=item.get('description', ''),
                    replacement=item.get('replacement', '')
                ))

    # Parse code_blocks
    code_blocks = []
    cb_list = parsed.get('code_blocks', [])
    if isinstance(cb_list, list):
        for item in cb_list:
            if isinstance(item, dict):
                code_blocks.append(CodeBlockSpec(
                    id=int(item.get('id', 0)),
                    language=item.get('language', ''),
                    lines=int(item.get('lines', 0)),
                    description=item.get('description', ''),
                    action=item.get('action', 'keep'),
                    artifact_path=item.get('artifact_path')
                ))

    # Parse transcription
    transcription_fixes = []
    transcription = parsed.get('transcription', {})
    if isinstance(transcription, dict):
        fixes = transcription.get('fixes_applied', [])
        if isinstance(fixes, list):
            for item in fixes:
                if isinstance(item, dict):
                    transcription_fixes.append(TranscriptionFix(
                        original=item.get('original', ''),
                        corrected=item.get('corrected', '')
                    ))

    # Parse sensitivity - handle both nested and flat formats
    sensitivity = Sensitivity()
    sens_dict = parsed.get('sensitivity', {})
    if isinstance(sens_dict, dict):
        sensitivity.key = sens_dict.get('key')
        terms_dict = sens_dict.get('terms', {})
        if isinstance(terms_dict, dict):
            sensitivity.terms = parse_sensitivity_terms(terms_dict)
        sections_list = sens_dict.get('sections', [])
        if isinstance(sections_list, list):
            sensitivity.sections = parse_sensitivity_sections(sections_list)

    # Also check for flat sensitivity fields (sensitivity_terms_health, etc.)
    # This handles cases where the YAML-like parser flattens nested structures
    for key, value in parsed.items():
        if key.startswith('sensitivity_terms_'):
            category = key.replace('sensitivity_terms_', '')
            terms = parse_inline_list(value) if value else []
            if category == 'health':
                sensitivity.terms.health = terms
            elif category == 'personal':
                sensitivity.terms.personal = terms
            elif category == 'names':
                sensitivity.terms.names = terms
            elif category == 'financial':
                sensitivity.terms.financial = terms
            else:
                sensitivity.terms.custom[category] = terms

    return CanonicalConfig(
        title=title,
        slug=slug,
        date=date,
        source=source,
        tags=tags,
        description=description,
        sections_remove=sections_remove,
        sections_lite_remove=sections_lite_remove,
        code_blocks=code_blocks,
        transcription_fixes_applied=transcription_fixes,
        sensitivity=sensitivity,
        raw_block=block
    )


def parse_config_block_auto(block: str) -> CanonicalConfig:
    """
    Parse a config block, auto-detecting v1 or v2 format.

    Returns a CanonicalConfig in all cases (converts v1 if needed).
    """
    version = detect_config_version(block)
    if version == 2:
        return parse_v2_config_block(block)
    else:
        v1_config = parse_config_block(block)
        return CanonicalConfig.from_v1_config(v1_config)


def extract_backmatter(content: str) -> Backmatter:
    """
    Extract backmatter sections (Summary, Continuation Context) from content.

    Backmatter appears after main content, typically marked by:
    ---
    <!-- === BACKMATTER === -->
    ## Summary
    ...
    ## Continuation Context
    ...

    Also handles the existing format where summary appears after EXPORT CONFIG.
    """
    result = Backmatter()

    # Look for backmatter delimiter
    backmatter_markers = [
        '<!-- === BACKMATTER === -->',
        '<!-- BACKMATTER -->',
        '<!-- === BACKMATTER: -->',
    ]

    backmatter_start = None
    for marker in backmatter_markers:
        pos = content.find(marker)
        if pos != -1:
            backmatter_start = pos
            break

    # If no explicit marker, look for summary after config block
    if backmatter_start is None:
        config_end = content.find(CONFIG_END_MARKER)
        if config_end != -1:
            backmatter_start = config_end + len(CONFIG_END_MARKER)

    if backmatter_start is None:
        return result

    backmatter_content = content[backmatter_start:]

    # Extract brief ## Summary section (first paragraph only)
    summary_patterns = [
        r'## Summary\s*\n(.*?)(?=\n## |\n---\s*$|\Z)',
        r'## Long Summary\s*\n(.*?)(?=\n## |\n---\s*$|\Z)',
    ]

    for pattern in summary_patterns:
        match = re.search(pattern, backmatter_content, re.DOTALL)
        if match:
            result.summary = match.group(1).strip()
            break

    # Extract FULL summary content: everything from ## Summary up to
    # ## Continuation Context (or similar). This captures:
    # - ## Summary
    # - ## What Was Discussed
    # - ## Decisions Made
    # - ## Work Products
    # - etc.
    full_summary_pattern = r'(## Summary\s*\n.*?)(?=\n## Continuation|\n## Context for Follow-up|\Z)'
    full_match = re.search(full_summary_pattern, backmatter_content, re.DOTALL)
    if full_match:
        result.full_summary = full_match.group(1).strip()
    elif result.summary:
        # Fall back to brief summary if no multi-section structure
        result.full_summary = f"## Summary\n\n{result.summary}"

    # Extract ## Continuation Context section
    continuation_patterns = [
        r'## Continuation Context\s*\n(.*?)(?=\n## |\n---\s*$|\Z)',
        r'## Context for Follow-up\s*\n(.*?)(?=\n## |\n---\s*$|\Z)',
    ]

    for pattern in continuation_patterns:
        match = re.search(pattern, backmatter_content, re.DOTALL)
        if match:
            result.continuation = match.group(1).strip()
            break

    return result


# =============================================================================
# Source Detection and Auto-CONFIG Generation
# =============================================================================

def detect_source(content: str) -> str:
    """
    Detect conversation source from content patterns.

    Returns:
        'bruba' | 'claude-projects' | 'voice-memo'
    """
    # Check for Bruba markers (Signal/Telegram metadata prefixes)
    if BRUBA_METADATA_PREFIX_PATTERN.search(content):
        return 'bruba'

    # Check for voice memo indicators
    if '[Transcript]' in content or '[attached audio file' in content:
        return 'voice-memo'

    # Default to claude-projects
    return 'claude-projects'


# Pattern for Signal timestamps: 2026-01-31 10:00 EST
SIGNAL_TIMESTAMP_PATTERN = re.compile(
    r'(\d{4}-\d{2}-\d{2})\s+\d{2}:\d{2}\s*(?:EST|EDT|CST|CDT|MST|MDT|PST|PDT|UTC)?'
)

# Pattern for date in filename: YYYY-MM-DD prefix or UUID
FILENAME_DATE_PATTERN = re.compile(r'^(\d{4}-\d{2}-\d{2})')


def extract_date_from_content(content: str, filename: str) -> str:
    """
    Extract date from content timestamps, filename, or return today's date.

    Checks in order:
    1. Signal timestamp pattern in content
    2. YYYY-MM-DD prefix in filename
    3. Falls back to today's date

    Args:
        content: The file content to search
        filename: The filename (without path)

    Returns:
        Date string in YYYY-MM-DD format
    """
    # Try Signal timestamp pattern in content
    match = SIGNAL_TIMESTAMP_PATTERN.search(content)
    if match:
        return match.group(1)

    # Try filename pattern (YYYY-MM-DD prefix)
    match = FILENAME_DATE_PATTERN.match(filename)
    if match:
        return match.group(1)

    # Fall back to today's date
    return datetime.now().strftime('%Y-%m-%d')


def generate_slug(title: str, date: str) -> str:
    """
    Generate a URL-safe slug from title and date.

    Format: YYYY-MM-DD-slugified-title

    Args:
        title: The conversation title
        date: Date in YYYY-MM-DD format

    Returns:
        Slug string like "2026-01-31-my-conversation-title"
    """
    # Slugify the title
    slug_title = title.lower()

    # Replace common separators with hyphens
    slug_title = re.sub(r'[\s_/\\]+', '-', slug_title)

    # Remove non-alphanumeric characters (except hyphens)
    slug_title = re.sub(r'[^a-z0-9-]', '', slug_title)

    # Collapse multiple hyphens
    slug_title = re.sub(r'-+', '-', slug_title)

    # Trim hyphens from ends
    slug_title = slug_title.strip('-')

    # Truncate to reasonable length (keep ~50 chars for title portion)
    if len(slug_title) > 50:
        slug_title = slug_title[:50].rsplit('-', 1)[0]

    return f"{date}-{slug_title}" if slug_title else date


def extract_title_hint(content: str) -> Optional[str]:
    """
    Extract a title hint from the first substantial user message.

    Looks for the first USER message and extracts the first ~60 characters
    of meaningful content. Handles Bruba/Signal artifacts and voice transcripts.

    Args:
        content: The file content

    Returns:
        Title string (up to 60 chars) or None if no suitable content found
    """
    # Parse messages
    messages = parse_messages(content)

    # Find first USER message with substantial content
    for msg in messages:
        if msg.role != 'USER':
            continue

        # Clean the content - apply Bruba artifact cleanup first
        text = clean_bruba_artifacts(msg.content.strip())

        # Handle voice transcripts: strip "[Transcript] " prefix
        if text.startswith('[Transcript]'):
            text = text[len('[Transcript]'):].strip()

        # Skip messages that are just artifacts or very short
        if len(text) < 10:
            continue

        # Skip messages that look like remaining metadata or commands
        if text.startswith('[') or text.startswith('==='):
            continue

        # Get first line or first 60 chars
        first_line = text.split('\n')[0].strip()

        # Remove common conversational prefixes
        first_line = re.sub(r'^(Hey|Hi|Hello|OK|Okay|So|Well|Um|Uh),?\s*', '', first_line, flags=re.IGNORECASE)

        # Truncate to 60 chars at word boundary
        if len(first_line) > 60:
            first_line = first_line[:60].rsplit(' ', 1)[0]
            if not first_line.endswith(('.', '!', '?')):
                first_line = first_line.rstrip('.,!?;:') + '...'

        # Skip if too short after processing
        if len(first_line) < 5:
            continue

        return first_line

    return None
