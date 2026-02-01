"""
Generate variants of canonical transcripts.

Variants include:
- canonical: Full transcript with all metadata
- transcript: Clean readable version
- summary: AI-generated summary (requires LLM API)
"""

from pathlib import Path
from typing import Dict

from . import frontmatter, redactor


def generate_variants(
    input_dir: Path,
    output_dir: str = "reference/transcripts"
) -> Dict[str, int]:
    """
    Generate variants from canonical transcripts.

    Args:
        input_dir: Directory containing canonical markdown files
        output_dir: Base output directory

    Returns:
        Dict mapping variant name to count of files generated
    """
    config = _load_config()
    variant_types = config.get('variants', ['canonical', 'transcript'])

    # Find repo root
    repo_root = Path(__file__).parent.parent.parent.parent
    out_base = repo_root / output_dir

    results = {v: 0 for v in variant_types}

    for md_file in input_dir.glob("*.md"):
        content = md_file.read_text()
        meta, body = frontmatter.parse_frontmatter(content)

        for variant in variant_types:
            variant_content = _generate_variant(variant, body, meta, config)
            if variant_content:
                variant_dir = out_base / variant
                variant_dir.mkdir(parents=True, exist_ok=True)

                out_path = variant_dir / md_file.name
                out_path.write_text(variant_content)
                results[variant] += 1

    return results


def _generate_variant(
    variant: str,
    content: str,
    metadata: dict,
    config: dict
) -> str:
    """Generate a specific variant."""

    if variant == 'canonical':
        # Full version with all metadata
        return frontmatter.add_frontmatter(content, metadata)

    elif variant == 'transcript':
        # Clean readable version, optionally redacted
        redaction_config = config.get('redaction', {})
        if redaction_config.get('enabled', False):
            content = redactor.apply_redaction(content, redaction_config)

        # Simplified metadata
        simple_meta = {
            'source': metadata.get('source'),
            'date': metadata.get('started', '')[:10] if metadata.get('started') else None,
        }
        return frontmatter.add_frontmatter(content, simple_meta)

    elif variant == 'summary':
        # AI-generated summary
        return _generate_summary(content, metadata, config)

    else:
        print(f"Unknown variant: {variant}")
        return None


def _generate_summary(content: str, metadata: dict, config: dict) -> str:
    """Generate an AI summary of the transcript."""
    try:
        import anthropic
    except ImportError:
        print("  Skipping summary: anthropic not installed")
        return None

    import os
    api_key = os.environ.get('ANTHROPIC_API_KEY')
    if not api_key:
        print("  Skipping summary: ANTHROPIC_API_KEY not set")
        return None

    llm_config = config.get('llm', {})
    model = llm_config.get('model', 'claude-sonnet')
    max_tokens = llm_config.get('max_tokens', 1000)

    # Map friendly names to model IDs
    model_map = {
        'claude-sonnet': 'claude-sonnet-4-5',
        'claude-haiku': 'claude-haiku-4-5',
    }
    model_id = model_map.get(model, model)

    client = anthropic.Anthropic(api_key=api_key)

    prompt = f"""Summarize this conversation transcript in 3-5 bullet points.
Focus on:
- Key decisions or conclusions
- Important information exchanged
- Action items or next steps

Transcript:
{content[:10000]}  # Truncate for context limits
"""

    try:
        response = client.messages.create(
            model=model_id,
            max_tokens=max_tokens,
            messages=[{"role": "user", "content": prompt}]
        )
        summary = response.content[0].text

        summary_meta = {
            'type': 'summary',
            'source': metadata.get('source'),
            'generated': True,
        }
        return frontmatter.add_frontmatter(summary, summary_meta)

    except Exception as e:
        print(f"  Summary generation failed: {e}")
        return None


def _load_config() -> dict:
    """Load distill config."""
    config_path = Path(__file__).parent.parent / "config.yaml"
    if config_path.exists():
        import yaml
        with open(config_path) as f:
            return yaml.safe_load(f)
    return {}
