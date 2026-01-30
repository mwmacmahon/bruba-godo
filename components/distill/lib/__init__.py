"""
Distill - Conversation to knowledge pipeline.

This component transforms raw conversation sessions (JSONL) into
processed, searchable knowledge that feeds back to the bot.

Core modules:
- cli: Command-line interface
- processor: Main processing pipeline
- canonicalize: JSONL to markdown conversion
- variants: Generate different versions (redacted, summary)
- redactor: Sensitivity-based content filtering
- frontmatter: YAML metadata handling
"""

__version__ = "0.1.0"
