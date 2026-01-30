#!/usr/bin/env python3
"""
Distill CLI - Process conversation sessions into knowledge.

Usage:
    python -m components.distill.lib.cli process <files>...
    python -m components.distill.lib.cli variants <directory>
    python -m components.distill.lib.cli --help

Commands:
    process   Convert JSONL sessions to markdown
    variants  Generate variants (redacted, summary) from canonical transcripts
"""

import argparse
import sys
from pathlib import Path


def cmd_process(args):
    """Process JSONL files into markdown."""
    from . import processor

    for file_path in args.files:
        path = Path(file_path)
        if not path.exists():
            print(f"Warning: {file_path} not found, skipping")
            continue

        if not path.suffix == '.jsonl':
            print(f"Warning: {file_path} is not a JSONL file, skipping")
            continue

        print(f"Processing: {path.name}")
        try:
            output = processor.process_session(path, args.output)
            print(f"  → {output}")
        except Exception as e:
            print(f"  Error: {e}")
            if args.verbose:
                import traceback
                traceback.print_exc()


def cmd_variants(args):
    """Generate variants from canonical transcripts."""
    from . import variants

    input_dir = Path(args.directory)
    if not input_dir.exists():
        print(f"Error: Directory {args.directory} not found")
        sys.exit(1)

    print(f"Generating variants from: {input_dir}")
    try:
        results = variants.generate_variants(input_dir, args.output)
        for variant, count in results.items():
            print(f"  {variant}: {count} files")
    except Exception as e:
        print(f"Error: {e}")
        if args.verbose:
            import traceback
            traceback.print_exc()
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(
        description="Distill - Convert conversations to knowledge"
    )
    parser.add_argument(
        '--verbose', '-v',
        action='store_true',
        help='Show detailed output'
    )

    subparsers = parser.add_subparsers(dest='command', help='Commands')

    # process command
    process_parser = subparsers.add_parser(
        'process',
        help='Process JSONL sessions to markdown'
    )
    process_parser.add_argument(
        'files',
        nargs='+',
        help='JSONL files to process'
    )
    process_parser.add_argument(
        '--output', '-o',
        default='sessions/converted',
        help='Output directory (default: sessions/converted)'
    )
    process_parser.set_defaults(func=cmd_process)

    # variants command
    variants_parser = subparsers.add_parser(
        'variants',
        help='Generate variants from canonical transcripts'
    )
    variants_parser.add_argument(
        'directory',
        help='Directory containing canonical transcripts'
    )
    variants_parser.add_argument(
        '--output', '-o',
        default='reference/transcripts',
        help='Output directory (default: reference/transcripts)'
    )
    variants_parser.set_defaults(func=cmd_variants)

    args = parser.parse_args()

    if args.command is None:
        parser.print_help()
        sys.exit(1)

    args.func(args)


if __name__ == '__main__':
    main()
