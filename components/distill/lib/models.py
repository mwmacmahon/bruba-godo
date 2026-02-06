"""
Data classes for conversation export processing.

This module defines the structured data types used to pass information
between processing stages. Using dataclasses provides clear contracts
and makes debugging easier by having well-defined shapes.

V1 Types (backwards compatibility):
    - AnchorSpec: Generic anchor-based removal specification
    - ReplacementSpec: Text replacement specification
    - MidConversationTranscription: Mid-conversation cleanup marker
    - ExportConfig: Parsed EXPORT CONFIG block (v1 format)

V2 Types (new canonical file model):
    - SectionSpec: Anchor-based section handling
    - SensitivityTerms: Sensitive terms by category
    - SensitivitySection: Sensitive section with anchor range
    - Sensitivity: Complete sensitivity configuration
    - TranscriptionFix: Single transcription correction
    - CodeBlockSpec: Code block processing instructions
    - CanonicalConfig: V2 frontmatter schema for canonical files
    - Backmatter: Summary and continuation content

Common Types:
    - Message: A single conversation message
    - ProcessingResult: Output of processing

These are stable data structures - changes here usually mean the
config format itself is changing.
"""

from dataclasses import dataclass, field
from pathlib import Path
from typing import List, Optional, Dict, Any, Union


@dataclass
class AnchorSpec:
    """Specification for finding and removing content by anchors.

    Used for both sections_to_remove and outputs_to_remove in config.
    """
    start_anchor: str
    end_anchor: str
    start_context: Optional[str] = None
    end_context: Optional[str] = None
    reason: str = ""


@dataclass
class ReplacementSpec:
    """Specification for transcription replacement.

    Supports both new field names (original_text/cleaned_text) and
    legacy field names (find_anchor/replace_with) for backwards compatibility.
    """
    original_text: str  # The exact raw text to find
    cleaned_text: str = ""  # What to replace it with
    # Legacy field names for backwards compatibility
    find_anchor: str = ""
    replace_with: str = ""


@dataclass
class MidConversationTranscription:
    """Specification for mid-conversation voice transcript cleanup.

    When a raw voice transcript was pasted and cleaned inline during
    the conversation, this marks the raw message for special handling:
    - Transcript file: raw replaced with placeholder
    - Full file: both raw and cleaned kept
    """
    raw_anchor: str  # First 15-25 words of the raw transcript message
    cleaned_follows: bool = True  # Whether cleaned version is in next assistant message


@dataclass
class ExportConfig:
    """Parsed EXPORT CONFIG block from an intake file."""
    filename_base: str
    project: str = ""
    outputs: str = "keep_all"  # finished_only | keep_all | omit_all
    sections_to_remove: List[AnchorSpec] = field(default_factory=list)
    outputs_to_remove: List[AnchorSpec] = field(default_factory=list)
    transcription_replacements: List[ReplacementSpec] = field(default_factory=list)
    mid_conversation_transcriptions: List['MidConversationTranscription'] = field(default_factory=list)
    transcription_errors: List[Dict[str, Any]] = field(default_factory=list)
    continuation_packet: bool = False
    brief_description: str = ""
    raw_block: str = ""  # Original config block text for reference


@dataclass
class Message:
    """A single message from a conversation transcript."""
    index: int
    role: str  # USER, ASSISTANT, UNKNOWN
    content: str
    raw_content: str  # Content before cleanup


@dataclass
class ProcessingResult:
    """Result of processing a conversation export."""
    success: bool
    summary_content: str = ""
    transcript_content: str = ""
    raw_content: str = ""
    error: Optional[str] = None
    sections_removed: int = 0
    outputs_removed: int = 0
    replacements_applied: int = 0


# =============================================================================
# V2 Types - New Canonical File Model
# =============================================================================

@dataclass
class SectionSpec:
    """
    V2 specification for anchor-based section handling.

    Used for sections_remove and sections_lite_remove in canonical files.
    """
    start: str  # Start anchor text
    end: str    # End anchor text
    description: str = ""  # Why this section is removed
    replacement: str = ""  # Optional replacement text (for lite versions)


@dataclass
class SensitivityTerms:
    """
    Sensitive terms organized by category.

    Each category contains comma-separated terms that should be redacted
    when that category is excluded from a profile.
    """
    health: List[str] = field(default_factory=list)
    personal: List[str] = field(default_factory=list)
    names: List[str] = field(default_factory=list)
    financial: List[str] = field(default_factory=list)
    # Additional categories can be added dynamically
    custom: Dict[str, List[str]] = field(default_factory=dict)

    def get_terms_for_categories(self, categories: List[str]) -> List[str]:
        """Get all terms for the specified categories."""
        terms = []
        for cat in categories:
            if cat == 'health':
                terms.extend(self.health)
            elif cat == 'personal':
                terms.extend(self.personal)
            elif cat == 'names':
                terms.extend(self.names)
            elif cat == 'financial':
                terms.extend(self.financial)
            elif cat in self.custom:
                terms.extend(self.custom[cat])
        return terms


@dataclass
class SensitivitySection:
    """
    A section of content marked as sensitive.

    Uses anchor-based ranges (same as SectionSpec) but with sensitivity tags
    instead of removal instructions.
    """
    start: str  # Start anchor text
    end: str    # End anchor text
    tags: List[str] = field(default_factory=list)  # e.g., ['health', 'personal']
    description: str = ""  # Human-readable description


@dataclass
class Sensitivity:
    """
    Complete sensitivity configuration for a canonical file.

    Contains both term-level and section-level sensitivity markers.
    """
    key: Optional[str] = None  # Optional key name for token substitution
    terms: SensitivityTerms = field(default_factory=SensitivityTerms)
    sections: List[SensitivitySection] = field(default_factory=list)


@dataclass
class TranscriptionFix:
    """A single transcription correction that was applied."""
    original: str  # The original (incorrect) text
    corrected: str  # What it was corrected to


@dataclass
class CodeBlockSpec:
    """
    Processing instructions for a code block.

    Used to control how code blocks are handled in variant generation.
    """
    id: int  # Sequential ID for the code block
    language: str = ""  # Programming language
    lines: int = 0  # Number of lines
    description: str = ""  # What the code does
    action: str = "keep"  # summarize | keep | extract | remove
    artifact_path: Optional[str] = None  # For 'extract' action


@dataclass
class Backmatter:
    """
    Backmatter content extracted from canonical file.

    Summary and continuation live in backmatter (after main content),
    not in frontmatter YAML.

    The export format may include multiple sections after ## Summary:
    - ## Summary (brief paragraph)
    - ## What Was Discussed
    - ## Decisions Made
    - ## Work Products
    - etc.

    These are all captured in `full_summary`, while `summary` contains
    just the brief paragraph for quick reference.
    """
    summary: str = ""           # Brief summary paragraph only
    full_summary: str = ""      # Full summary including all subsections
    continuation: str = ""


@dataclass
class CanonicalConfig:
    """
    V2 frontmatter schema for canonical files.

    This represents the structured metadata for a canonical conversation
    or artifact file. All processing instructions are encoded here.
    """
    # === IDENTITY ===
    title: str
    slug: str  # e.g., "2026-01-24-topic-slug"
    date: str  # YYYY-MM-DD
    source: str = "claude"  # claude | bruba | manual
    tags: List[str] = field(default_factory=list)
    type: str = ""  # doc | refdoc | transcript | prompt
    scope: str = ""  # Legacy/informational — not used for filtering (type is sufficient)
    description: str = ""  # One-line summary for inventory display

    # === AGENT ROUTING ===
    agents: List[str] = field(default_factory=list)

    # === USER ROUTING ===
    users: List[str] = field(default_factory=list)

    # === SECTION HANDLING ===
    sections_remove: List[SectionSpec] = field(default_factory=list)
    sections_lite_remove: List[SectionSpec] = field(default_factory=list)

    # === CODE BLOCKS ===
    code_blocks: List[CodeBlockSpec] = field(default_factory=list)

    # === TRANSCRIPTION ===
    transcription_fixes_applied: List[TranscriptionFix] = field(default_factory=list)

    # === SENSITIVITY ===
    sensitivity: Sensitivity = field(default_factory=Sensitivity)

    # === RAW CONFIG BLOCK (for reference) ===
    raw_block: str = ""

    @classmethod
    def from_v1_config(cls, v1: 'ExportConfig') -> 'CanonicalConfig':
        """
        Convert a v1 ExportConfig to v2 CanonicalConfig.

        Provides backwards compatibility for old-format CONFIG blocks.
        """
        # Extract date from filename_base if present
        date = ""
        slug = v1.filename_base
        if len(v1.filename_base) >= 10:
            potential_date = v1.filename_base[:10]
            parts = potential_date.split('-')
            if len(parts) == 3 and all(p.isdigit() for p in parts):
                date = potential_date

        # Convert sections_to_remove to sections_remove
        sections_remove = [
            SectionSpec(
                start=spec.start_anchor,
                end=spec.end_anchor,
                description=spec.reason
            )
            for spec in v1.sections_to_remove
        ]

        # Convert transcription_replacements to fixes_applied
        fixes = [
            TranscriptionFix(
                original=spec.original_text or spec.find_anchor,
                corrected=spec.cleaned_text or spec.replace_with
            )
            for spec in v1.transcription_replacements
        ]

        return cls(
            title=v1.filename_base,  # Best guess for title
            slug=slug,
            date=date,
            source="claude-projects",  # Default assumption
            tags=[v1.project] if v1.project else [],
            description="",  # v1 format has no description
            sections_remove=sections_remove,
            transcription_fixes_applied=fixes,
            raw_block=v1.raw_block
        )
