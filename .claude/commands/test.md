# /test - Run Test Suite

Run the test suite and discuss results.

## Arguments

$ARGUMENTS

Options:
- `--verbose` or `-v` - Show verbose output
- `--file <path>` - Run specific test file only
- `--filter <pattern>` - Run tests matching pattern (pytest -k)

## Instructions

### 1. Run Tests

```bash
python3 -m pytest tests/ -v
```

If `--file` specified:
```bash
python3 -m pytest <file> -v
```

If `--filter` specified:
```bash
python3 -m pytest tests/ -v -k "<pattern>"
```

### 2. Report Results

Summarize:
- Total tests: X
- Passed: Y
- Failed: Z (if any)

### 3. Discuss Failures

If any tests failed:
1. Show the failure output
2. Identify the likely cause
3. Suggest fixes

If all tests passed, confirm the test suite is green.

## Example Session

```
=== /test ===

Running test suite...

24 tests collected
24 passed ✓

Test suite is green.
```

Or with failures:

```
=== /test ===

Running test suite...

24 tests collected
23 passed, 1 failed

=== FAILURE: test_section_removal_applied ===
AssertionError: Expected "foo" but got "bar"

Analysis: The section removal logic isn't handling edge case X.
Suggested fix: Update the regex pattern in variants.py:123
```
