# Distill Component

**Status:** Core — THE DIFFERENTIATOR

Transform conversations into searchable knowledge that feeds back to your bot.

## Overview

Without distill, bruba-godo is "Clawdbot installer with SSH access."

With distill, bruba-godo is **"A managed AI assistant where conversations become knowledge that feeds back in."**

The conversation → knowledge loop is what makes the system valuable:

```
conversations → pull → distill → knowledge → export → push → bot memory
```

## What Distill Does

1. **Canonicalize** — Convert raw JSONL to clean markdown with frontmatter
2. **Generate variants** — Create different versions (redacted, summarized)
3. **Extract knowledge** — Mine conversations for reusable reference content
4. **Filter for export** — Apply sensitivity filters before pushing to bot

## Prerequisites

- Python 3.8+
- Required packages (see setup.sh)

## Setup

```bash
./components/distill/setup.sh
```

The setup script will:
1. Check Python version
2. Create virtual environment (optional)
3. Install dependencies
4. Create initial config

## Usage

### Basic Pipeline

```bash
# Pull sessions from bot
./tools/pull-sessions.sh

# Process with distill (converts JSONL → markdown)
python -m components.distill.lib.cli process sessions/*.jsonl

# Generate variants (canonical, redacted, summary)
python -m components.distill.lib.cli variants reference/transcripts/

# Push processed content to bot
./tools/push.sh
```

### Via Skills

```bash
/pull           # Pull sessions from bot
/distill        # Process and generate variants
/push           # Push to bot memory
```

Or all at once:
```bash
/sync --full    # Pull → distill → push
```

## Configuration

Edit `components/distill/config.yaml`:

```yaml
# Output variants to generate
variants:
  - canonical    # Full transcript with metadata
  - transcript   # Clean readable version
  - summary      # AI-generated summary

# Redaction rules
redaction:
  names: true      # Replace real names with placeholders
  health: true     # Remove health-related content
  financial: false # Keep financial discussions

# LLM settings (for summary generation)
llm:
  model: claude-sonnet
  max_tokens: 1000
```

## Directory Structure

```
components/distill/
├── README.md              # This file
├── setup.sh               # Setup script
├── validate.sh            # Validate configuration
├── config.yaml            # Processing options
├── prompts/
│   ├── AGENTS.snippet.md  # Bot instructions for distill workflow
│   └── variant-*.md       # Prompts for generating variants
└── lib/
    ├── __init__.py
    ├── cli.py             # Entry point
    ├── processor.py       # Core processing
    ├── canonicalize.py    # JSONL → canonical markdown
    ├── variants.py        # Generate transcript/summary
    ├── redactor.py        # Sensitivity redaction
    └── frontmatter.py     # Metadata management
```

## Output Locations

| Output | Directory | Description |
|--------|-----------|-------------|
| Raw sessions | `sessions/` | JSONL pulled from bot |
| Converted | `sessions/converted/` | Markdown versions |
| Reference | `reference/transcripts/` | Processed transcripts |
| Exports | `exports/bot/` | Filtered for bot memory |

## Without Distill

The system still works without distill:
- Sessions stay as raw JSONL
- No automatic transcript processing
- Manual conversion with `parse-jsonl.py`
- No variants or redaction

Distill is what transforms the basic tooling into a **knowledge management system**.

## Troubleshooting

### "No module named components.distill"

Run from the bruba-godo root directory, or set PYTHONPATH:
```bash
export PYTHONPATH=/path/to/bruba-godo
```

### "Missing dependency: X"

Run setup again:
```bash
./components/distill/setup.sh
```

### "LLM API error"

Check your API credentials in `.env`:
```bash
ANTHROPIC_API_KEY=sk-ant-...
```

## Related

- [Intake Pipeline](../../docs/intake-pipeline.md) — How sessions flow through processing
- [Vision](../../docs/Vision.md) — Why distill matters
