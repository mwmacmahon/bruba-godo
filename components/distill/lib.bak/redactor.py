"""
Redaction utilities for sensitive content.

Supports redacting:
- Names (via configurable mapping)
- Health information
- Financial details
- Locations
"""

import re
from typing import Dict


def apply_redaction(content: str, config: dict) -> str:
    """
    Apply redaction rules to content.

    Args:
        content: Text to redact
        config: Redaction configuration

    Returns:
        Redacted text
    """
    rules = config.get('rules', {})
    name_mappings = config.get('name_mappings', {})

    # Apply name mappings first
    for real_name, pseudonym in name_mappings.items():
        content = _replace_case_insensitive(content, real_name, pseudonym)

    # Apply rule-based redaction
    if rules.get('names'):
        content = _redact_names(content)

    if rules.get('health'):
        content = _redact_health(content)

    if rules.get('financial'):
        content = _redact_financial(content)

    if rules.get('locations'):
        content = _redact_locations(content)

    return content


def _replace_case_insensitive(text: str, old: str, new: str) -> str:
    """Replace text case-insensitively while preserving surrounding case."""
    pattern = re.compile(re.escape(old), re.IGNORECASE)
    return pattern.sub(new, text)


def _redact_names(content: str) -> str:
    """
    Redact common name patterns.

    This is a basic implementation - for production use,
    consider using NER (Named Entity Recognition).
    """
    # Common patterns that might be names (very basic)
    # In practice, you'd want explicit name mappings

    # Redact email addresses
    content = re.sub(
        r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b',
        '[EMAIL]',
        content
    )

    # Redact phone numbers
    content = re.sub(
        r'\b\+?1?[-.\s]?\(?[0-9]{3}\)?[-.\s]?[0-9]{3}[-.\s]?[0-9]{4}\b',
        '[PHONE]',
        content
    )

    return content


def _redact_health(content: str) -> str:
    """Redact health-related information."""
    # Basic health-related terms
    health_terms = [
        r'\b(diagnosis|diagnosed|symptom|medication|prescription|doctor|hospital|clinic|therapy|treatment)\b',
        r'\b(blood pressure|heart rate|temperature|pulse)\s*:?\s*\d+',
        r'\b\d+\s*(mg|ml|mcg|units?)\b',  # Dosages
    ]

    for pattern in health_terms:
        content = re.sub(pattern, '[HEALTH]', content, flags=re.IGNORECASE)

    return content


def _redact_financial(content: str) -> str:
    """Redact financial information."""
    # Credit card patterns
    content = re.sub(
        r'\b(?:\d{4}[-\s]?){3}\d{4}\b',
        '[CARD]',
        content
    )

    # Dollar amounts
    content = re.sub(
        r'\$[\d,]+\.?\d*',
        '[AMOUNT]',
        content
    )

    # Account numbers
    content = re.sub(
        r'\baccount\s*#?\s*\d+\b',
        '[ACCOUNT]',
        content,
        flags=re.IGNORECASE
    )

    return content


def _redact_locations(content: str) -> str:
    """Redact location information."""
    # Street addresses (basic pattern)
    content = re.sub(
        r'\b\d+\s+[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*\s+(?:St|Street|Ave|Avenue|Rd|Road|Blvd|Boulevard|Dr|Drive|Ln|Lane|Way|Ct|Court)\b',
        '[ADDRESS]',
        content
    )

    # ZIP codes
    content = re.sub(
        r'\b\d{5}(?:-\d{4})?\b',
        '[ZIP]',
        content
    )

    return content
