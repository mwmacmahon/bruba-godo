"""
Distill - Conversation to knowledge pipeline.

This component transforms raw conversation sessions (JSONL) into
processed, searchable knowledge that feeds back to the bot.

Two-step pipeline:
1. parse-jsonl: JSONL -> delimited markdown (=== MESSAGE N | ROLE ===)
2. canonicalize: delimited + CONFIG -> canonical file with frontmatter
3. variants: canonical file -> transcript, summary (with redaction)

Core modules:
- clawdbot_parser: JSONL -> delimited markdown
- models: Data classes for all types
- parsing: CONFIG block extraction and parsing
- canonicalize: Raw -> canonical transformation
- variants: Canonical -> output variants
- content: Content manipulation utilities
- output: File writing utilities
"""

__version__ = "2.0.0"

# === V2 Pipeline (recommended) ===
from .canonicalize import canonicalize, canonicalize_from_content, load_corrections
from .variants import generate_variants, generate_variants_from_content, VariantOptions, VariantResult

# V2 Data structures
from .models import (
    CanonicalConfig,
    SectionSpec,
    CodeBlockSpec,
    TranscriptionFix,
    Backmatter,
    Sensitivity,
    SensitivityTerms,
    SensitivitySection,
)

# Parsing utilities (v1/v2)
from .parsing import (
    extract_config_block,
    extract_all_config_blocks,
    parse_config_block_auto,
    extract_backmatter,
    detect_config_version,
    parse_messages,
)

# Clawdbot parser
from .clawdbot_parser import (
    parse_clawdbot_session,
    convert_session_file,
    format_as_delimited_markdown,
    ClawdbotMessage,
)

# === V1 Pipeline (legacy compatibility) ===
from .models import (
    AnchorSpec,
    ReplacementSpec,
    MidConversationTranscription,
    ExportConfig,
    Message,
    ProcessingResult,
)
from .parsing import parse_config_block
from .content import (
    remove_by_anchors,
    apply_replacement,
    extract_summary_section,
    extract_full_transcript,
    truncate_at_export_config,
)

__all__ = [
    # V2 Functions
    "canonicalize",
    "canonicalize_from_content",
    "generate_variants",
    "generate_variants_from_content",
    "load_corrections",
    # Clawdbot parser
    "parse_clawdbot_session",
    "convert_session_file",
    "format_as_delimited_markdown",
    "ClawdbotMessage",
    # V2 Data structures
    "CanonicalConfig",
    "SectionSpec",
    "CodeBlockSpec",
    "TranscriptionFix",
    "Backmatter",
    "Sensitivity",
    "SensitivityTerms",
    "SensitivitySection",
    "VariantOptions",
    "VariantResult",
    # Parsing utilities
    "extract_config_block",
    "extract_all_config_blocks",
    "parse_config_block_auto",
    "extract_backmatter",
    "detect_config_version",
    "parse_messages",
    # V1 Legacy
    "AnchorSpec",
    "ReplacementSpec",
    "MidConversationTranscription",
    "ExportConfig",
    "Message",
    "ProcessingResult",
    "parse_config_block",
    "remove_by_anchors",
    "apply_replacement",
    "extract_summary_section",
    "extract_full_transcript",
    "truncate_at_export_config",
]
