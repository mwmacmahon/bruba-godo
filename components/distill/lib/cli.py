#!/usr/bin/env python3
"""
Distill CLI - Process conversation sessions into knowledge.

Usage:
    python -m components.distill.lib.cli parse-jsonl <files>... [-o OUTPUT]
    python -m components.distill.lib.cli canonicalize <files>... [-o OUTPUT]
    python -m components.distill.lib.cli variants <directory>
    python -m components.distill.lib.cli export [--profile PROFILE]
    python -m components.distill.lib.cli split <files>... [-o OUTPUT] [--max-chars N]
    python -m components.distill.lib.cli parse <file>
    python -m components.distill.lib.cli --help

Commands:
    parse-jsonl   Convert Clawdbot JSONL sessions to delimited markdown
    canonicalize  Convert delimited markdown (with CONFIG) to canonical format
    variants      Generate variants (transcript, summary) from canonical files
    export        Generate filtered exports per exports.yaml profiles
    split         Split large files along message boundaries
    parse         Debug: show parsed CONFIG block from a file
"""

import argparse
import sys
import logging
from pathlib import Path

try:
    import yaml
    YAML_AVAILABLE = True
except ImportError:
    YAML_AVAILABLE = False


def cmd_parse_jsonl(args):
    """Convert JSONL session files to delimited markdown."""
    from .clawdbot_parser import (
        convert_session_file,
        generate_output_filename
    )

    output_dir = Path(args.output) if args.output else None

    for file_path in args.files:
        path = Path(file_path)
        if not path.exists():
            print(f"Warning: {file_path} not found, skipping")
            continue

        if not path.suffix == '.jsonl':
            print(f"Warning: {file_path} is not a JSONL file, skipping")
            continue

        print(f"Converting: {path.name}")
        try:
            # Determine output path
            if output_dir:
                output_dir.mkdir(parents=True, exist_ok=True)
                # Use session filename (with .md extension)
                out_name = path.stem + '.md'
                out_path = output_dir / out_name
            else:
                out_path = None

            content, session_id, session_start = convert_session_file(path, out_path)

            if out_path:
                print(f"  -> {out_path}")
                if args.verbose:
                    print(f"     Session ID: {session_id}")
                    print(f"     Session start: {session_start}")
            else:
                # Print to stdout if no output dir
                print(content)

        except Exception as e:
            print(f"  Error: {e}")
            if args.verbose:
                import traceback
                traceback.print_exc()


def cmd_canonicalize(args):
    """Convert delimited markdown with CONFIG to canonical format."""
    from .canonicalize import canonicalize, load_corrections

    # Load corrections if path provided
    corrections = []
    if args.corrections:
        corrections_path = Path(args.corrections)
        corrections = load_corrections(corrections_path)
        if corrections:
            print(f"Loaded {len(corrections)} corrections from {corrections_path}")

    output_dir = Path(args.output) if args.output else None
    if output_dir:
        output_dir.mkdir(parents=True, exist_ok=True)

    move_dir = Path(args.move) if args.move else None
    if move_dir:
        move_dir.mkdir(parents=True, exist_ok=True)

    for file_path in args.files:
        path = Path(file_path)
        if not path.exists():
            print(f"Warning: {file_path} not found, skipping")
            continue

        print(f"Canonicalizing: {path.name}")
        try:
            logger = logging.getLogger(__name__)
            if args.verbose:
                logging.basicConfig(level=logging.DEBUG)

            canonical_content, config, backmatter = canonicalize(
                path,
                corrections=corrections,
                logger=logger
            )

            if output_dir:
                # Generate output filename from config
                out_name = f"{config.slug}.md" if config.slug else path.stem + '-canonical.md'
                out_path = output_dir / out_name
                out_path.write_text(canonical_content, encoding='utf-8')
                print(f"  -> {out_path}")

                # Move source file if --move specified
                if move_dir:
                    import shutil
                    dest_path = move_dir / path.name
                    shutil.move(str(path), str(dest_path))
                    print(f"  moved to {dest_path}")
            else:
                print(canonical_content)

        except Exception as e:
            print(f"  Error: {e}")
            if args.verbose:
                import traceback
                traceback.print_exc()


def cmd_variants(args):
    """Generate variants from canonical transcripts."""
    from .variants import generate_variants, VariantOptions

    input_dir = Path(args.directory)
    if not input_dir.exists():
        print(f"Error: Directory {args.directory} not found")
        sys.exit(1)

    output_dir = Path(args.output) if args.output else input_dir.parent / 'variants'
    output_dir.mkdir(parents=True, exist_ok=True)

    options = VariantOptions(
        generate_transcript=True,
        generate_lite=args.lite,
        generate_summary=True,
        redact_categories=args.redact.split(',') if args.redact else [],
        output_dir=output_dir
    )

    logger = logging.getLogger(__name__)
    if args.verbose:
        logging.basicConfig(level=logging.DEBUG)

    results = {'transcript': 0, 'summary': 0, 'lite': 0}

    for md_file in input_dir.glob("*.md"):
        print(f"Processing: {md_file.name}")
        try:
            result = generate_variants(md_file, options, logger)

            if result.transcript:
                out_path = output_dir / f"{md_file.stem}-transcript.md"
                out_path.write_text(result.transcript, encoding='utf-8')
                results['transcript'] += 1
                print(f"  -> {out_path}")

            if result.summary:
                out_path = output_dir / f"{md_file.stem}-summary.md"
                out_path.write_text(result.summary, encoding='utf-8')
                results['summary'] += 1
                print(f"  -> {out_path}")

            if result.transcript_lite:
                out_path = output_dir / f"{md_file.stem}-lite.md"
                out_path.write_text(result.transcript_lite, encoding='utf-8')
                results['lite'] += 1
                print(f"  -> {out_path}")

        except Exception as e:
            print(f"  Error: {e}")
            if args.verbose:
                import traceback
                traceback.print_exc()

    print(f"\nGenerated: {results['transcript']} transcripts, {results['summary']} summaries")
    if args.lite:
        print(f"           {results['lite']} lite versions")


def cmd_parse(args):
    """Debug: show parsed CONFIG block from a file."""
    from .parsing import extract_config_block, parse_config_block_auto, detect_config_version

    path = Path(args.file)
    if not path.exists():
        print(f"Error: File {args.file} not found")
        sys.exit(1)

    content = path.read_text(encoding='utf-8')

    try:
        config_block = extract_config_block(content)
        if not config_block:
            print("No EXPORT CONFIG block found")
            sys.exit(1)

        version = detect_config_version(config_block)
        print(f"Config version: v{version}")
        print()

        config = parse_config_block_auto(config_block)

        print(f"Title: {config.title}")
        print(f"Slug: {config.slug}")
        print(f"Date: {config.date}")
        print(f"Source: {config.source}")
        print(f"Tags: {config.tags}")
        if config.description:
            print(f"Description: {config.description}")

        if config.sections_remove:
            print(f"\nSections to remove: {len(config.sections_remove)}")
            for spec in config.sections_remove:
                print(f"  - {spec.start[:40]}... -> {spec.end[:40]}...")

        if config.transcription_fixes_applied:
            print(f"\nTranscription fixes: {len(config.transcription_fixes_applied)}")
            for fix in config.transcription_fixes_applied[:5]:
                print(f"  - {fix.original} -> {fix.corrected}")
            if len(config.transcription_fixes_applied) > 5:
                print(f"  ... and {len(config.transcription_fixes_applied) - 5} more")

        if args.verbose:
            print(f"\n--- Raw config block ---")
            print(config_block)

    except Exception as e:
        print(f"Error parsing: {e}")
        if args.verbose:
            import traceback
            traceback.print_exc()
        sys.exit(1)


def cmd_export(args):
    """Generate filtered exports per exports.yaml profiles."""
    from .variants import generate_variants, VariantOptions, parse_canonical_file

    if not YAML_AVAILABLE:
        print("Error: PyYAML is required for export command")
        print("Install with: pip install pyyaml")
        sys.exit(1)

    # Find exports.yaml
    exports_path = Path(args.config) if args.config else Path('exports.yaml')
    if not exports_path.exists():
        print(f"Error: {exports_path} not found")
        sys.exit(1)

    # Load exports config
    with open(exports_path, 'r') as f:
        exports_config = yaml.safe_load(f)

    exports = exports_config.get('exports', {})
    defaults = exports_config.get('defaults', {})

    if not exports:
        print("No export profiles defined in exports.yaml")
        sys.exit(1)

    # Filter to specific profile if requested
    if args.profile:
        if args.profile not in exports:
            print(f"Error: Profile '{args.profile}' not found")
            print(f"Available profiles: {', '.join(exports.keys())}")
            sys.exit(1)
        exports = {args.profile: exports[args.profile]}

    # Find canonical files in reference/
    input_dir = Path(args.input) if args.input else Path('reference')
    canonical_files = []
    if input_dir.exists():
        canonical_files = list(input_dir.rglob("*.md"))

    # Also scan component prompts
    prompt_files = []
    for prompt_path in Path('components').glob('*/prompts/*.md'):
        if prompt_path.name == 'AGENTS.snippet.md':
            continue
        prompt_files.append(prompt_path)
        canonical_files.append(prompt_path)

    if not canonical_files:
        print("No files found to export")
        sys.exit(0)

    ref_count = len(canonical_files) - len(prompt_files)
    print(f"Found {len(canonical_files)} files ({ref_count} in reference/, {len(prompt_files)} prompts)")

    logger = logging.getLogger(__name__)
    if args.verbose:
        logging.basicConfig(level=logging.DEBUG)

    # Process each export profile
    for profile_name, profile_config in exports.items():
        print(f"\n=== Profile: {profile_name} ===")
        print(f"  {profile_config.get('description', 'No description')}")

        output_dir = Path(profile_config.get('output_dir', f'exports/{profile_name}'))
        output_dir.mkdir(parents=True, exist_ok=True)

        # Get filtering rules
        include_rules = profile_config.get('include', {})
        exclude_rules = profile_config.get('exclude', {})
        redaction_categories = profile_config.get('redaction', defaults.get('redaction', []))

        if isinstance(redaction_categories, str):
            redaction_categories = [redaction_categories]

        # Process each canonical file
        processed = 0
        skipped = 0

        for canonical_path in canonical_files:
            try:
                content = canonical_path.read_text(encoding='utf-8')
                is_prompt = 'components' in str(canonical_path)

                if is_prompt:
                    # Prompts: simple frontmatter + content, no backmatter
                    config = _parse_prompt_frontmatter(content)
                    if config is None:
                        if args.verbose:
                            print(f"  Skip (no frontmatter): {canonical_path.name}")
                        skipped += 1
                        continue

                    # Apply include/exclude filters (pass profile name for targeting)
                    if not _matches_prompt_filters(config, include_rules, exclude_rules, profile_name):
                        if args.verbose:
                            print(f"  Skip (filtered): {canonical_path.name}")
                        skipped += 1
                        continue

                    # Use output_name from frontmatter if specified, otherwise use stem
                    output_name = config.get('output_name', canonical_path.stem)
                    # Prompts go to prompts/ subdirectory
                    prompts_dir = output_dir / "prompts"
                    prompts_dir.mkdir(parents=True, exist_ok=True)
                    out_path = prompts_dir / f"Prompt - {output_name}.md"
                    out_path.write_text(content, encoding='utf-8')
                    processed += 1
                    if args.verbose:
                        print(f"  -> {out_path}")

                else:
                    # Canonical files: full parsing with backmatter
                    config, main_content, backmatter = parse_canonical_file(content)

                    # Apply include/exclude filters
                    if not _matches_filters(config, include_rules, exclude_rules):
                        if args.verbose:
                            print(f"  Skip (filtered): {canonical_path.name}")
                        skipped += 1
                        continue

                    # Determine output subdirectory and prefix based on content type
                    subdir, prefix = _get_content_subdirectory_and_prefix(canonical_path, config)
                    content_output_dir = output_dir / subdir
                    content_output_dir.mkdir(parents=True, exist_ok=True)

                    # Generate variants with redaction
                    options = VariantOptions(
                        generate_transcript=True,
                        generate_lite=False,
                        generate_summary=True,
                        redact_categories=redaction_categories,
                        output_dir=content_output_dir
                    )

                    result = generate_variants(canonical_path, options, logger)

                    # Write transcript (main output) with prefix
                    if result.transcript:
                        out_name = f"{prefix}{canonical_path.stem}.md" if prefix else f"{canonical_path.stem}.md"
                        out_path = content_output_dir / out_name
                        out_path.write_text(result.transcript, encoding='utf-8')
                        processed += 1
                        if args.verbose:
                            print(f"  -> {out_path}")

            except Exception as e:
                print(f"  Error processing {canonical_path.name}: {e}")
                if args.verbose:
                    import traceback
                    traceback.print_exc()
                skipped += 1

        print(f"  Processed: {processed}, Skipped: {skipped}")
        print(f"  Output: {output_dir}/")

    print("\nExport complete.")


def cmd_split(args):
    """Split large files along message boundaries."""
    from .splitting import should_split, split_by_message_boundaries, split_file

    output_dir = Path(args.output) if args.output else None
    max_chars = args.max_chars
    min_messages = args.min_messages

    total_files = 0
    split_files = 0
    chunks_created = 0

    for file_path in args.files:
        path = Path(file_path)
        if not path.exists():
            print(f"Warning: {file_path} not found, skipping")
            continue

        total_files += 1
        content = path.read_text(encoding='utf-8')
        file_size = len(content)

        if not should_split(content, max_chars):
            if args.verbose:
                print(f"  {path.name}: {file_size:,} chars (no split needed)")
            continue

        print(f"Splitting: {path.name} ({file_size:,} chars)")

        try:
            chunks = split_by_message_boundaries(content, max_chars, min_messages)

            if len(chunks) == 1:
                print(f"  No split needed after analysis")
                continue

            split_files += 1
            chunks_created += len(chunks)

            # Determine output directory
            out_dir = output_dir if output_dir else path.parent
            out_dir.mkdir(parents=True, exist_ok=True)

            for chunk in chunks:
                out_name = f"{path.stem}-part-{chunk.part}.md"
                out_path = out_dir / out_name
                out_path.write_text(chunk.content, encoding='utf-8')
                print(f"  -> {out_path} (msgs {chunk.first_message}-{chunk.last_message}, {chunk.char_count:,} chars)")

        except Exception as e:
            print(f"  Error: {e}")
            if args.verbose:
                import traceback
                traceback.print_exc()

    print(f"\nSummary: {split_files}/{total_files} files split into {chunks_created} chunks")


def _parse_prompt_frontmatter(content: str) -> dict:
    """
    Parse simple YAML frontmatter from a prompt file.

    Returns dict with frontmatter fields, or None if no frontmatter.
    """
    if not content.startswith('---'):
        return None

    # Find end of frontmatter
    end_marker = content.find('\n---', 3)
    if end_marker == -1:
        return None

    frontmatter_yaml = content[4:end_marker].strip()
    try:
        return yaml.safe_load(frontmatter_yaml) or {}
    except Exception:
        return {}


def _matches_prompt_filters(config: dict, include_rules: dict, exclude_rules: dict, profile_name: str = None) -> bool:
    """
    Check if a prompt config (dict) matches the include/exclude filters.

    Returns True if the prompt should be included in the export.

    Args:
        config: Parsed frontmatter dict from the prompt file
        include_rules: Include rules from exports.yaml profile
        exclude_rules: Exclude rules from exports.yaml profile
        profile_name: Name of the export profile being run (e.g., 'bot', 'claude')
    """
    # Check profile targeting first (highest priority filter)
    # If prompt has a profile field, it must match the current profile
    prompt_profile = config.get('profile')
    if prompt_profile:
        if profile_name and prompt_profile != profile_name:
            return False

    # Check include.type
    include_type = include_rules.get('type', [])
    if include_type:
        if isinstance(include_type, str):
            include_type = [include_type]
        file_type = config.get('type', '')
        if file_type not in include_type:
            return False

    # Check include.scope
    include_scope = include_rules.get('scope', [])
    if include_scope:
        if isinstance(include_scope, str):
            include_scope = [include_scope]
        file_scope = config.get('scope', '')
        if isinstance(file_scope, str):
            file_scope = [file_scope]
        if not any(s in include_scope for s in file_scope):
            # Also check if 'meta' is in include_scope (prompts are meta by default)
            if 'meta' not in include_scope:
                return False

    return True


def _get_content_subdirectory_and_prefix(canonical_path: Path, config) -> tuple:
    """
    Determine output subdirectory and filename prefix based on content type.

    Returns (subdirectory, prefix) tuple:
    - ('transcripts', 'Transcript - ') for conversation transcripts
    - ('refdocs', 'Refdoc - ') for reference documents
    - ('docs', 'Doc - ') for documentation
    - ('artifacts', 'Artifact - ') for artifacts
    """
    # Check source path first
    path_str = str(canonical_path)
    if 'transcripts' in path_str:
        return ('transcripts', 'Transcript - ')
    if 'refdocs' in path_str:
        return ('refdocs', 'Refdoc - ')

    # Check scope/tags from config
    scopes = set(config.tags) if config.tags else set()
    if 'transcripts' in scopes:
        return ('transcripts', 'Transcript - ')
    if 'refdocs' in scopes or 'reference' in scopes:
        return ('refdocs', 'Refdoc - ')

    # Check for type in frontmatter if available
    if hasattr(config, 'type'):
        file_type = getattr(config, 'type', '')
        if file_type == 'doc':
            return ('docs', 'Doc - ')
        if file_type == 'artifact':
            return ('artifacts', 'Artifact - ')

    # Default to transcripts for conversation-like content
    return ('transcripts', 'Transcript - ')


def _matches_filters(config, include_rules: dict, exclude_rules: dict) -> bool:
    """
    Check if a canonical config matches the include/exclude filters.

    Returns True if the file should be included in the export.
    """
    # Check exclude rules first (exclude takes precedence)
    exclude_sensitivity = exclude_rules.get('sensitivity', [])
    if exclude_sensitivity:
        if isinstance(exclude_sensitivity, str):
            exclude_sensitivity = [exclude_sensitivity]
        # Check if file has any excluded sensitivity levels
        # This requires sensitivity info in the config
        if hasattr(config, 'sensitivity') and config.sensitivity:
            # Check if any sensitivity sections have excluded tags
            for section in getattr(config.sensitivity, 'sections', []):
                for tag in getattr(section, 'tags', []):
                    if tag in exclude_sensitivity:
                        return False

    # Check include rules
    include_scope = include_rules.get('scope', [])
    if include_scope:
        if isinstance(include_scope, str):
            include_scope = [include_scope]
        # Check if file matches any of the required scopes
        # Scopes are matched against tags or source
        file_scopes = set(config.tags) if config.tags else set()
        if config.source:
            file_scopes.add(config.source)
        # Add implicit scopes based on content type
        file_scopes.add('transcripts')  # All canonical files are transcripts

        if not any(scope in file_scopes for scope in include_scope):
            return False

    include_tags = include_rules.get('tags', [])
    if include_tags:
        if isinstance(include_tags, str):
            include_tags = [include_tags]
        file_tags = set(config.tags) if config.tags else set()
        if not any(tag in file_tags for tag in include_tags):
            return False

    return True


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

    # parse-jsonl command
    parse_jsonl_parser = subparsers.add_parser(
        'parse-jsonl',
        help='Convert Clawdbot JSONL sessions to delimited markdown'
    )
    parse_jsonl_parser.add_argument(
        'files',
        nargs='+',
        help='JSONL files to convert'
    )
    parse_jsonl_parser.add_argument(
        '--output', '-o',
        help='Output directory (if not specified, prints to stdout)'
    )
    parse_jsonl_parser.set_defaults(func=cmd_parse_jsonl)

    # canonicalize command
    canonicalize_parser = subparsers.add_parser(
        'canonicalize',
        help='Convert delimited markdown (with CONFIG) to canonical format'
    )
    canonicalize_parser.add_argument(
        'files',
        nargs='+',
        help='Markdown files to canonicalize'
    )
    canonicalize_parser.add_argument(
        '--output', '-o',
        help='Output directory (if not specified, prints to stdout)'
    )
    canonicalize_parser.add_argument(
        '--corrections', '-c',
        help='Path to corrections.yaml file'
    )
    canonicalize_parser.add_argument(
        '--move', '-m',
        help='Move source files to this directory after successful canonicalization (e.g., intake/processed)'
    )
    canonicalize_parser.set_defaults(func=cmd_canonicalize)

    # variants command
    variants_parser = subparsers.add_parser(
        'variants',
        help='Generate variants from canonical transcripts'
    )
    variants_parser.add_argument(
        'directory',
        help='Directory containing canonical markdown files'
    )
    variants_parser.add_argument(
        '--output', '-o',
        help='Output directory (default: <input>/../variants)'
    )
    variants_parser.add_argument(
        '--lite',
        action='store_true',
        help='Also generate transcript-lite versions'
    )
    variants_parser.add_argument(
        '--redact',
        help='Comma-separated categories to redact (e.g., health,names)'
    )
    variants_parser.set_defaults(func=cmd_variants)

    # parse command (debug)
    parse_parser = subparsers.add_parser(
        'parse',
        help='Debug: show parsed CONFIG block from a file'
    )
    parse_parser.add_argument(
        'file',
        help='File to parse'
    )
    parse_parser.set_defaults(func=cmd_parse)

    # export command
    export_parser = subparsers.add_parser(
        'export',
        help='Generate filtered exports per exports.yaml profiles'
    )
    export_parser.add_argument(
        '--profile', '-p',
        help='Specific profile to run (default: all profiles)'
    )
    export_parser.add_argument(
        '--input', '-i',
        help='Input directory with canonical files (default: reference/transcripts)'
    )
    export_parser.add_argument(
        '--config', '-c',
        help='Path to exports.yaml (default: exports.yaml)'
    )
    export_parser.set_defaults(func=cmd_export)

    # split command
    split_parser = subparsers.add_parser(
        'split',
        help='Split large files along message boundaries'
    )
    split_parser.add_argument(
        'files',
        nargs='+',
        help='Files to check and split if needed'
    )
    split_parser.add_argument(
        '--output', '-o',
        help='Output directory (default: same as input file)'
    )
    split_parser.add_argument(
        '--max-chars',
        type=int,
        default=60000,
        help='Maximum characters per chunk (default: 60000)'
    )
    split_parser.add_argument(
        '--min-messages',
        type=int,
        default=5,
        help='Minimum messages per chunk (default: 5)'
    )
    split_parser.set_defaults(func=cmd_split)

    args = parser.parse_args()

    if args.command is None:
        parser.print_help()
        sys.exit(1)

    args.func(args)


if __name__ == '__main__':
    main()
