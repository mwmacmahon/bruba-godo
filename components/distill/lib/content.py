"""
Content manipulation for conversation export processing.

This module handles the complex content transformations:
1. Anchor-based section removal (removing parts of conversations)
2. Anchor-based replacements (fixing transcription errors)
3. Summary extraction from the appended summary section
4. Full transcript assembly from messages
5. Content truncation at export config

Contents:
    - find_anchor_position(): Find text position with optional context
    - remove_by_anchors(): Remove content between start/end anchors
    - apply_replacement(): Find and replace text
    - extract_summary_section(): Pull out the summary section
    - extract_raw_transcript(): Get content before export config
    - extract_full_transcript(): Build formatted transcript from messages
    - truncate_at_export_config(): Remove config block and later content
"""

import re
import logging
from typing import List, Optional, Tuple

from .models import AnchorSpec, ReplacementSpec, Message, ExportConfig, MidConversationTranscription
from .parsing import CONFIG_START_MARKER, CONFIG_END_MARKER


def normalize_for_matching(text: str) -> str:
    """
    Normalize text for fuzzy anchor matching.

    Removes/normalizes punctuation and whitespace so that minor differences
    don't prevent matching.
    """
    normalized = re.sub(r'[,;:!?\-\—\–\.\'\"]', '', text)
    normalized = re.sub(r'\s+', ' ', normalized)
    normalized = normalized.lower().strip()
    return normalized


def fuzzy_find_anchor(content: str, anchor: str) -> Optional[int]:
    """
    Find anchor position using fuzzy matching.

    First tries exact match, then falls back to normalized matching.
    """
    pos = content.find(anchor)
    if pos != -1:
        return pos

    normalized_anchor = normalize_for_matching(anchor)
    if not normalized_anchor:
        return None

    anchor_words = normalized_anchor.split()
    if not anchor_words:
        return None

    first_word_pattern = re.compile(re.escape(anchor_words[0]), re.IGNORECASE)
    search_start = 0
    while search_start < len(content):
        match = first_word_pattern.search(content, search_start)
        if not match:
            break

        candidate_start = match.start()
        chunk_end = min(candidate_start + len(anchor) + 50, len(content))
        chunk = content[candidate_start:chunk_end]
        normalized_chunk = normalize_for_matching(chunk)

        if normalized_chunk.startswith(normalized_anchor):
            return candidate_start

        search_start = candidate_start + 1

    return None


def find_anchor_position(
    content: str,
    anchor: str,
    context: Optional[str] = None
) -> Optional[int]:
    """
    Find the position of an anchor in content.

    If context is provided, finds anchor that appears near the context.
    """
    if not anchor:
        return None

    anchor_escaped = re.escape(anchor)
    matches = list(re.finditer(anchor_escaped, content))

    if not matches:
        return None

    if len(matches) == 1 or not context:
        return matches[0].start()

    context_escaped = re.escape(context)

    for match in matches:
        start = max(0, match.start() - 500)
        end = min(len(content), match.end() + 500)
        surrounding = content[start:end]

        if re.search(context_escaped, surrounding):
            return match.start()

    return matches[0].start()


def remove_by_anchors(
    content: str,
    spec: AnchorSpec,
    logger: Optional[logging.Logger] = None
) -> Tuple[str, bool]:
    """
    Remove content between start and end anchors.

    Leaves a placeholder comment: [Removed: {reason}]
    """
    if logger is None:
        logger = logging.getLogger(__name__)

    start_pos = find_anchor_position(content, spec.start_anchor, spec.start_context)
    if start_pos is None:
        logger.warning(f"    Start anchor not found: {spec.start_anchor[:50]}...")
        return content, False

    end_pos = find_anchor_position(content, spec.end_anchor, spec.end_context)
    if end_pos is None:
        logger.warning(f"    End anchor not found: {spec.end_anchor[:50]}...")
        return content, False

    end_anchor_match = re.search(re.escape(spec.end_anchor), content[end_pos:])
    if end_anchor_match:
        end_pos = end_pos + end_anchor_match.end()

    if end_pos <= start_pos:
        logger.warning(f"    End anchor appears before start anchor")
        return content, False

    placeholder = f"\n\n[Removed: {spec.reason}]\n\n" if spec.reason else "\n\n[Content removed]\n\n"
    result = content[:start_pos] + placeholder + content[end_pos:]

    return result, True


def apply_replacement(
    content: str,
    spec: ReplacementSpec,
    logger: Optional[logging.Logger] = None
) -> Tuple[str, bool]:
    """
    Find original_text and replace with cleaned_text.

    Only searches in conversation content BEFORE the config block.
    Supports prefix matching: if original_text ends with '...'.
    """
    if logger is None:
        logger = logging.getLogger(__name__)

    search_text = spec.original_text or spec.find_anchor
    replace_text = spec.cleaned_text or spec.replace_with

    if not search_text:
        logger.warning("    Replacement has no original_text to search for")
        return content, False

    config_start = content.find(CONFIG_START_MARKER)
    search_area = content[:config_start] if config_start != -1 else content

    is_prefix_match = search_text.rstrip().endswith('...')
    if is_prefix_match:
        prefix_text = search_text.rstrip()[:-3].rstrip()
        logger.info(f"    Using prefix match for: {prefix_text[:40]}...")

        pos = find_anchor_position(search_area, prefix_text, None)
        if pos is None:
            logger.warning(f"    Prefix text not found: {prefix_text[:50]}...")
            return content, False

        rest_of_content = search_area[pos:]
        end_patterns = [
            r'\n\n---\n',
            r'\n=== MESSAGE \d+',
            r'\n## Message \d+',
            r'\n\*\*Error fixes:\*\*',
            r'\n\*\*Language fixes:\*\*',
        ]

        end_pos = len(search_area)
        for pattern in end_patterns:
            match = re.search(pattern, rest_of_content)
            if match:
                candidate_end = pos + match.start()
                if candidate_end < end_pos:
                    end_pos = candidate_end

        result = content[:pos] + replace_text + content[end_pos:]
        return result, True

    pos = find_anchor_position(search_area, search_text, None)
    if pos is None:
        logger.warning(f"    Replacement text not found: {search_text[:50]}...")
        return content, False

    anchor_match = re.search(re.escape(search_text), search_area[pos:])
    if not anchor_match:
        return content, False

    end_pos = pos + anchor_match.end()
    result = content[:pos] + replace_text + content[end_pos:]

    return result, True


def apply_mid_conversation_markers(
    content: str,
    specs: List[MidConversationTranscription],
    logger: Optional[logging.Logger] = None
) -> Tuple[str, int]:
    """
    Mark mid-conversation raw transcripts for removal from transcript file.
    """
    if logger is None:
        logger = logging.getLogger(__name__)

    count = 0
    result = content

    for spec in specs:
        if not spec.raw_anchor:
            continue

        anchor_pos = fuzzy_find_anchor(result, spec.raw_anchor)
        if anchor_pos is None:
            logger.warning(f"    Mid-conversation anchor not found: {spec.raw_anchor[:50]}...")
            continue

        search_area = result[:anchor_pos]
        header_match = None
        for match in re.finditer(r'(?:^|\n)(## Message \d+ - \w+)\n', search_area, re.MULTILINE):
            header_match = match

        if not header_match:
            logger.warning(f"    Could not find message header for anchor: {spec.raw_anchor[:50]}...")
            continue

        message_start = header_match.end()
        rest_of_content = result[message_start:]

        end_patterns = [
            r'\n---\n\n## Message \d+',
            r'\n=== EXPORT CONFIG ===',
            r'\n---\n\n## End of Transcript',
        ]

        message_end = len(result)
        for pattern in end_patterns:
            end_match = re.search(pattern, rest_of_content)
            if end_match:
                potential_end = message_start + end_match.start()
                if potential_end < message_end:
                    message_end = potential_end

        placeholder = "\n[Raw transcription removed - cleaned version follows]\n"
        result = result[:message_start] + placeholder + result[message_end:]
        count += 1
        logger.info(f"    Marked raw transcript for removal: {spec.raw_anchor[:40]}...")

    return result, count


def extract_summary_section(content: str) -> str:
    """
    Extract the summary section from the export.

    The summary section appears after the EXPORT CONFIG block.
    """
    config_end_match = re.search(re.escape(CONFIG_END_MARKER), content)
    if not config_end_match:
        return ""

    search_start = config_end_match.end()
    search_content = content[search_start:]

    patterns = [
        r'^## Long Summary\s*\n',
        r'\n## Long Summary\s*\n',
        r'^## Summary\s*\n',
        r'\n## Summary\s*\n',
        r'^Long Summary\s*\n',
        r'\nLong Summary\s*\n',
        r'^Summary\s*\n',
        r'\nSummary\s*\n',
    ]

    start = None
    for pattern in patterns:
        match = re.search(pattern, search_content, re.MULTILINE)
        if match:
            start = search_start + match.start()
            if content[start] == '\n':
                start += 1
            break

    if start is None:
        return ""

    end_patterns = [
        r'\nbrief_description:',
        r'\n---\s*\ntype: continuation-packet',
        r'\n```\s*\nbrief_description:',
    ]

    end = len(content)
    for pattern in end_patterns:
        end_match = re.search(pattern, content[start:])
        if end_match:
            end = min(end, start + end_match.start())

    return content[start:end].strip()


def truncate_at_export_config(content: str) -> str:
    """
    Truncate content at the export config block.

    Returns content up to (but not including) the config block.
    """
    config_patterns = [
        r'=== EXPORT CONFIG ===',
        r'```yaml\s*\n\s*=== EXPORT CONFIG ===',
    ]

    config_start = len(content)
    for pattern in config_patterns:
        match = re.search(pattern, content)
        if match:
            config_start = min(config_start, match.start())

    if config_start == len(content):
        return content.strip()

    before_config = content[:config_start]
    last_header = before_config.rfind('## Message ')
    if last_header != -1:
        return content[:last_header].strip()

    return before_config.strip()


def strip_frontmatter(content: str) -> str:
    """Remove YAML frontmatter from content if present."""
    stripped = content.strip()
    if not stripped.startswith('---'):
        return content

    end_match = re.search(r'\n---\s*\n', stripped[3:])
    if end_match:
        return stripped[3 + end_match.end():].strip()

    return content


def extract_raw_transcript(content: str) -> str:
    """
    Extract everything BEFORE the export config block from raw content.

    This is the raw conversation without config/summary/continuation.
    """
    config_patterns = [
        r'```yaml\s*\n\s*=== EXPORT CONFIG ===',
        r'=== EXPORT CONFIG ===',
    ]

    config_start = len(content)
    for pattern in config_patterns:
        match = re.search(pattern, content)
        if match:
            config_start = min(config_start, match.start())

    if config_start == len(content):
        return strip_frontmatter(content).strip()

    return strip_frontmatter(content[:config_start]).strip()


def infer_message_roles(messages: List[Message]) -> List[Message]:
    """Infer roles for UNKNOWN messages based on conversation patterns."""
    for msg in messages:
        if msg.role == "UNKNOWN":
            first_line = msg.content.split('\n')[0].strip() if msg.content else ""
            if first_line and (first_line[0].islower() or first_line.endswith('?')):
                msg.role = "USER"
            elif first_line and re.match(r'^[A-Z][a-z]+(?:ing|ed|ion)\s', first_line):
                msg.role = "ASSISTANT"

    for i in range(len(messages) - 1):
        if messages[i].role in ("USER", "ASSISTANT") and messages[i+1].role == "UNKNOWN":
            messages[i+1].role = "ASSISTANT" if messages[i].role == "USER" else "USER"

    for i in range(len(messages) - 1, 0, -1):
        if messages[i].role in ("USER", "ASSISTANT") and messages[i-1].role == "UNKNOWN":
            messages[i-1].role = "USER" if messages[i].role == "ASSISTANT" else "ASSISTANT"

    return messages


def extract_full_transcript(messages: List[Message], config: Optional[ExportConfig] = None) -> str:
    """
    Build the full transcript from cleaned messages.

    Note: Message numbers in output use 0-based indexing during processing.
    Call renumber_messages_one_indexed() on final output to convert to 1-based.
    """
    messages = infer_message_roles(messages)

    parts = []

    for msg in messages:
        if not msg.content.strip():
            continue

        if msg.role == "USER":
            role_display = "User"
        elif msg.role == "ASSISTANT":
            role_display = "Assistant"
        else:
            role_display = "Unknown"

        header = f"## Message {msg.index} - {role_display}"

        parts.append(header)
        parts.append("")
        parts.append(msg.content)
        parts.append("")
        parts.append("---")
        parts.append("")

    return '\n'.join(parts)


def renumber_messages_one_indexed(content: str) -> str:
    """Convert 0-indexed message numbers to 1-indexed for human readability."""
    def increment_match(match):
        num = int(match.group(1))
        role = match.group(2)
        return f"## Message {num + 1} - {role}"

    return re.sub(
        r'## Message (\d+) - (User|Assistant|Unknown)',
        increment_match,
        content
    )


def add_transcript_references(
    summary_content: str,
    transcript_filenames: List[str]
) -> str:
    """Add a "Related Transcripts:" section to summary content after frontmatter."""
    if not transcript_filenames:
        return summary_content

    if len(transcript_filenames) == 1:
        ref_line = f"**Related Transcripts:** {transcript_filenames[0]}"
    else:
        ref_line = "**Related Transcripts:**\n" + "\n".join(f"- {f}" for f in transcript_filenames)

    if summary_content.strip().startswith('---'):
        lines = summary_content.split('\n')
        in_frontmatter = False
        end_idx = 0

        for i, line in enumerate(lines):
            if line.strip() == '---':
                if not in_frontmatter:
                    in_frontmatter = True
                else:
                    end_idx = i + 1
                    break

        if end_idx > 0:
            before = '\n'.join(lines[:end_idx])
            after = '\n'.join(lines[end_idx:]).lstrip('\n')
            return f"{before}\n\n{ref_line}\n\n{after}"

    return f"{ref_line}\n\n{summary_content}"


def consolidate_transcription_fixes(
    content: str,
    logger: Optional[logging.Logger] = None
) -> str:
    """
    Scan for **Error fixes:** and **Language fixes:** sections and consolidate
    them into a Transcription Patterns section at the end of the transcript.
    """
    if logger is None:
        logger = logging.getLogger(__name__)

    error_fixes = []
    language_fixes = []

    message_pattern = re.compile(r'## Message (\d+) - (User|Assistant|Unknown)')

    error_section_pattern = re.compile(
        r'\*\*Error fixes:\*\*\s*\n((?:(?:\d+\.|-).*\n?)+)',
        re.MULTILINE
    )

    for match in error_section_pattern.finditer(content):
        section_text = match.group(1).strip()
        before_match = content[:match.start()]
        msg_matches = list(message_pattern.finditer(before_match))
        msg_num = msg_matches[-1].group(1) if msg_matches else "?"

        for line in section_text.split('\n'):
            line = line.strip()
            if line and (line[0].isdigit() or line.startswith('-')):
                fix = re.sub(r'^[\d]+\.\s*|^-\s*', '', line).strip()
                if fix and '->' in fix:
                    error_fixes.append((fix, f"Message {msg_num}"))

    language_section_pattern = re.compile(
        r'\*\*Language fixes:\*\*\s*\n((?:(?:\d+\.|-).*\n?)+)',
        re.MULTILINE
    )

    for match in language_section_pattern.finditer(content):
        section_text = match.group(1).strip()
        before_match = content[:match.start()]
        msg_matches = list(message_pattern.finditer(before_match))
        msg_num = msg_matches[-1].group(1) if msg_matches else "?"

        for line in section_text.split('\n'):
            line = line.strip()
            if line and (line[0].isdigit() or line.startswith('-')):
                fix = re.sub(r'^[\d]+\.\s*|^-\s*', '', line).strip()
                if fix:
                    language_fixes.append((fix, f"Message {msg_num}"))

    if not error_fixes and not language_fixes:
        logger.info("  No transcription fixes found to consolidate")
        return content

    logger.info(f"  Consolidating {len(error_fixes)} error fixes and {len(language_fixes)} language fixes")

    consolidated = [
        "",
        "---",
        "",
        "## Transcription Patterns (Consolidated)",
        "",
    ]

    if error_fixes:
        consolidated.append("### Error Fixes")
        consolidated.append("")
        consolidated.append("| Original | Corrected | Context |")
        consolidated.append("|----------|-----------|---------|")
        for fix, context in error_fixes:
            if '->' in fix:
                parts = fix.split('->', 1)
                original = parts[0].strip().strip('"')
                corrected = parts[1].strip().strip('"')
                extra_context = ""
                if '(' in corrected:
                    idx = corrected.rfind('(')
                    extra_context = corrected[idx:].strip('()')
                    corrected = corrected[:idx].strip().strip('"')
                context_str = f"{context}" + (f" - {extra_context}" if extra_context else "")
                consolidated.append(f'| "{original}" | "{corrected}" | {context_str} |')
        consolidated.append("")

    if language_fixes:
        consolidated.append("### Language Fixes")
        consolidated.append("")
        consolidated.append("| Fix Type | Description | Context |")
        consolidated.append("|----------|-------------|---------|")
        for fix, context in language_fixes:
            fix_lower = fix.lower()
            if 'removed' in fix_lower and ('filler' in fix_lower or 'um' in fix_lower or 'uh' in fix_lower):
                fix_type = "Filler removal"
            elif 'removed' in fix_lower:
                fix_type = "Removal"
            elif 'false start' in fix_lower or 'repetition' in fix_lower:
                fix_type = "False start"
            elif 'cleaned' in fix_lower:
                fix_type = "Cleanup"
            else:
                fix_type = "Language fix"
            consolidated.append(f"| {fix_type} | {fix} | {context} |")
        consolidated.append("")

    return content + '\n'.join(consolidated)
