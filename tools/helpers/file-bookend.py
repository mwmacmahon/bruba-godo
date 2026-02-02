#!/usr/bin/env python3
"""Append or prepend content to a file without reading it into memory."""

import sys
import argparse
import tempfile
import shutil
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(
        description="Append or prepend content to a file"
    )
    parser.add_argument("file", help="Target file path")
    parser.add_argument("--prepend", action="store_true", help="Prepend instead of append")
    parser.add_argument("--content", help="Content to add (or read from stdin if not provided)")

    args = parser.parse_args()

    filepath = Path(args.file)
    if not filepath.exists():
        print(f"Error: {filepath} does not exist", file=sys.stderr)
        sys.exit(1)

    # Get content from --content or stdin
    if args.content:
        content = args.content
    else:
        content = sys.stdin.read()

    if not content:
        print("Error: No content provided", file=sys.stderr)
        sys.exit(1)

    if args.prepend:
        # Prepend: write content + original to temp, then move
        with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.tmp') as tmp:
            tmp.write(content)
            if not content.endswith('\n'):
                tmp.write('\n')
            with open(filepath, 'r') as orig:
                shutil.copyfileobj(orig, tmp)
            tmp_path = tmp.name
        shutil.move(tmp_path, filepath)
        print(f"Prepended to {filepath}")
    else:
        # Append: just open in append mode
        with open(filepath, 'a') as f:
            if not content.startswith('\n'):
                f.write('\n')
            f.write(content)
            if not content.endswith('\n'):
                f.write('\n')
        print(f"Appended to {filepath}")


if __name__ == "__main__":
    main()
