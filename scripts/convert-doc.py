#!/usr/bin/env python3
"""Isolated LLM call for document conversion."""

import argparse
import os
import anthropic
from pathlib import Path
from dotenv import load_dotenv

# Load .env from repo root
load_dotenv(Path(__file__).parent.parent / ".env")

MODELS = {
    "opus": "claude-opus-4-5",
    "sonnet": "claude-sonnet-4-5",
    "haiku": "claude-haiku-4-5",
}


def main():
    parser = argparse.ArgumentParser(
        description="Isolated document conversion via Claude API",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python convert-doc.py input.md "Add YAML frontmatter"
  python convert-doc.py input.md "Analyze for CONFIG" --model sonnet
  python convert-doc.py input.md -m haiku
"""
    )
    parser.add_argument("file", help="Input file path")
    parser.add_argument("prompt", nargs="?",
                        default="Convert this document appropriately",
                        help="Prompt for the conversion (default: generic conversion)")
    parser.add_argument("--model", "-m", choices=MODELS.keys(), default="opus",
                        help="Model to use: opus, sonnet, haiku (default: opus)")

    args = parser.parse_args()

    input_file = Path(args.file)
    if not input_file.exists():
        parser.error(f"File not found: {args.file}")

    client = anthropic.Anthropic()  # uses ANTHROPIC_API_KEY env
    content = input_file.read_text()

    response = client.messages.create(
        model=MODELS[args.model],
        max_tokens=8192,
        messages=[{
            "role": "user",
            "content": f"{args.prompt}\n\n---\n\n{content}"
        }]
    )

    print(response.content[0].text)


if __name__ == "__main__":
    main()
