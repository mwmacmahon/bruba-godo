#!/usr/bin/env python3
"""
Run all convo-processor tests.

Usage:
    python tests/run_tests.py              # Run all tests
    python tests/run_tests.py -v           # Verbose output
    python tests/run_tests.py test_parsing # Run specific module

Debug mode (full pipeline visibility):
    python tests/run_tests.py --debug 001-simple-v2
    python tests/run_tests.py --debug-file path/to/input.md
"""

import argparse
import importlib.util
import logging
import sys
import traceback
from datetime import datetime
from pathlib import Path

TESTS_DIR = Path(__file__).parent.resolve()
TOOL_ROOT = TESTS_DIR.parent
FIXTURES_DIR = TESTS_DIR / "fixtures"

# Add tool root to path for imports
sys.path.insert(0, str(TOOL_ROOT))


def discover_test_modules():
    """Find all test_*.py files in tests directory."""
    return sorted(TESTS_DIR.glob("test_*.py"))


def load_test_module(path: Path):
    """Load a test module and return it."""
    spec = importlib.util.spec_from_file_location(path.stem, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def get_test_functions(module):
    """Get all test_* functions from a module."""
    return [
        getattr(module, name)
        for name in dir(module)
        if name.startswith("test_") and callable(getattr(module, name))
    ]


def run_test(test_func, verbose: bool) -> bool:
    """Run a single test function. Returns True if passed."""
    try:
        test_func()
        if verbose:
            print(f"  ✓ {test_func.__name__}")
        return True
    except AssertionError as e:
        print(f"  ✗ {test_func.__name__}: {e}")
        if verbose:
            traceback.print_exc()
        return False
    except Exception as e:
        print(f"  ✗ {test_func.__name__}: {type(e).__name__}: {e}")
        if verbose:
            traceback.print_exc()
        return False


def run_module_tests(module, verbose: bool) -> tuple:
    """Run all tests in a module. Returns (passed, failed) counts."""
    tests = get_test_functions(module)
    passed = 0
    failed = 0

    for test in tests:
        if run_test(test, verbose):
            passed += 1
        else:
            failed += 1

    return passed, failed


def run_debug_pipeline(input_path: Path, output_dir: Path = None):
    """
    Run the full pipeline on an input file with full visibility.

    Creates an output directory with all intermediate files.
    """
    from components.distill.lib.canonicalize import canonicalize, load_corrections
    from components.distill.lib.variants import generate_variants

    if not input_path.exists():
        print(f"Error: Input file not found: {input_path}")
        return 1

    # Create output directory
    if output_dir is None:
        timestamp = datetime.now().strftime("%Y-%m-%d-%H%M%S")
        output_dir = TESTS_DIR / "debug-output" / timestamp

    output_dir.mkdir(parents=True, exist_ok=True)

    # Set up logging to file
    log_path = output_dir / "pipeline.log"
    logging.basicConfig(
        level=logging.DEBUG,
        format='%(asctime)s [%(levelname)s] %(message)s',
        handlers=[
            logging.FileHandler(log_path),
            logging.StreamHandler()
        ]
    )
    logger = logging.getLogger("debug-pipeline")

    print(f"\n{'=' * 60}")
    print("Debug Pipeline: Full Visibility Mode")
    print('=' * 60)
    print(f"Input: {input_path}")
    print(f"Output: {output_dir}")
    print()

    # Step 0: Copy input
    input_copy = output_dir / "00-input.md"
    input_copy.write_text(input_path.read_text())
    logger.info(f"Copied input to {input_copy}")

    # Load default corrections
    corrections_path = TOOL_ROOT / "components" / "distill" / "config" / "corrections.yaml"
    corrections = []
    if corrections_path.exists():
        corrections = load_corrections(corrections_path)
        logger.info(f"Loaded {len(corrections)} corrections")

    # Step 1: Canonicalize
    try:
        canonical_content, config, backmatter = canonicalize(
            input_path,
            corrections=corrections,
            logger=logger
        )
        canonical_path = output_dir / "01-canonical.md"
        canonical_path.write_text(canonical_content)
        logger.info(f"Wrote canonical: {canonical_path}")
        print(f"✓ Step 1: Canonicalize → {canonical_path.name}")
        print(f"  Title: {config.title}")
        print(f"  Has backmatter: summary={bool(backmatter.summary)}, continuation={bool(backmatter.continuation)}")
        print(f"  Slug: {config.slug}")
        print(f"  Sections to remove: {len(config.sections_remove)}")
        print(f"  Corrections applied: {len(config.transcription_fixes_applied)}")
    except Exception as e:
        logger.error(f"Canonicalize failed: {e}")
        print(f"✗ Step 1: Canonicalize failed: {e}")
        traceback.print_exc()
        return 1

    # Step 2: Generate variants
    try:
        result = generate_variants(canonical_path, logger=logger)

        if result.transcript:
            transcript_path = output_dir / "02-transcript.md"
            transcript_path.write_text(result.transcript)
            logger.info(f"Wrote transcript: {transcript_path}")
            print(f"✓ Step 2a: Transcript → {transcript_path.name}")

        if result.transcript_lite:
            lite_path = output_dir / "03-transcript-lite.md"
            lite_path.write_text(result.transcript_lite)
            logger.info(f"Wrote transcript-lite: {lite_path}")
            print(f"✓ Step 2b: Transcript-lite → {lite_path.name}")

        if result.summary:
            summary_path = output_dir / "04-summary.md"
            summary_path.write_text(result.summary)
            logger.info(f"Wrote summary: {summary_path}")
            print(f"✓ Step 2c: Summary → {summary_path.name}")
        else:
            print("  (No summary in backmatter)")

    except Exception as e:
        logger.error(f"Variants failed: {e}")
        print(f"✗ Step 2: Variants failed: {e}")
        traceback.print_exc()
        return 1

    print()
    print(f"{'=' * 60}")
    print("Pipeline complete. Output files:")
    print('=' * 60)
    for f in sorted(output_dir.glob("*.md")):
        size = f.stat().st_size
        print(f"  {f.name:30} ({size:,} bytes)")
    print(f"  {'pipeline.log':30} (processing log)")
    print()

    return 0


def main():
    parser = argparse.ArgumentParser(
        description="Run convo-processor tests",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Debug mode examples:
  python tests/run_tests.py --debug 001-simple-v2
  python tests/run_tests.py --debug-file ../exports/my-conversation.md
"""
    )
    parser.add_argument("-v", "--verbose", action="store_true",
                        help="Verbose output with tracebacks")
    parser.add_argument("module", nargs="?",
                        help="Specific test module to run (e.g., test_parsing)")
    parser.add_argument("--debug", metavar="FIXTURE",
                        help="Run debug pipeline on a fixture (e.g., 001-simple-v2)")
    parser.add_argument("--debug-file", metavar="PATH",
                        help="Run debug pipeline on any input file")
    parser.add_argument("--debug-output", metavar="DIR",
                        help="Output directory for debug mode (default: tests/debug-output/timestamp)")

    args = parser.parse_args()

    # Handle debug modes
    if args.debug:
        fixture_dir = FIXTURES_DIR / args.debug
        if not fixture_dir.exists():
            print(f"Fixture not found: {fixture_dir}")
            print(f"Available fixtures: {[d.name for d in FIXTURES_DIR.iterdir() if d.is_dir()]}")
            return 1
        input_path = fixture_dir / "input.md"
        output_dir = Path(args.debug_output) if args.debug_output else None
        return run_debug_pipeline(input_path, output_dir)

    if args.debug_file:
        input_path = Path(args.debug_file)
        output_dir = Path(args.debug_output) if args.debug_output else None
        return run_debug_pipeline(input_path, output_dir)

    # Normal test running
    if args.module:
        # Run specific module
        if not args.module.startswith("test_"):
            args.module = f"test_{args.module}"
        if not args.module.endswith(".py"):
            args.module = f"{args.module}.py"

        module_path = TESTS_DIR / args.module
        if not module_path.exists():
            print(f"Test module not found: {module_path}")
            return 1

        modules = [module_path]
    else:
        # Run all modules
        modules = discover_test_modules()

    total_passed = 0
    total_failed = 0

    print("=" * 60)
    print("convo-processor Test Suite")
    print("=" * 60)

    for module_path in modules:
        print(f"\n{module_path.stem}")
        print("-" * len(module_path.stem))

        try:
            module = load_test_module(module_path)
            passed, failed = run_module_tests(module, args.verbose)
            total_passed += passed
            total_failed += failed

            if not args.verbose:
                print(f"  {passed} passed, {failed} failed")

        except Exception as e:
            print(f"  ERROR loading module: {e}")
            if args.verbose:
                traceback.print_exc()
            total_failed += 1

    print("\n" + "=" * 60)
    print(f"TOTAL: {total_passed} passed, {total_failed} failed")
    print("=" * 60)

    return 0 if total_failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
