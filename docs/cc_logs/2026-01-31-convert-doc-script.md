---
type: claude_code_log
scope: reference
title: "Convert-Doc Script Implementation"
---

# Convert-Doc Script Implementation

Implemented `scripts/convert-doc.py` - an isolated LLM document conversion script for reducing CC context bloat when processing multiple documents. Integrated with `/convert` skill.

## Problem

CC's context bloats when processing multiple docs with inline LLM calls. Each conversion prompt and response accumulates in the conversation.

## Solution

Minimal Python script that makes a single isolated Anthropic API call. The conversion context dies when the script exits - CC only sees the result.

## Files Created/Modified

### `scripts/convert-doc.py`

```python
#!/usr/bin/env python3
"""Isolated LLM call for document conversion."""

import argparse
import anthropic
from pathlib import Path

MODELS = {
    "opus": "claude-opus-4-20250514",
    "sonnet": "claude-sonnet-4-20250514",
    "haiku": "claude-haiku-4-20250514",
}

def main():
    parser = argparse.ArgumentParser(description="Isolated document conversion via Claude API")
    parser.add_argument("file", help="Input file path")
    parser.add_argument("prompt", nargs="?", default="Convert this document appropriately")
    parser.add_argument("--model", "-m", choices=MODELS.keys(), default="opus",
                        help="Model to use: opus, sonnet, haiku (default: opus)")
    args = parser.parse_args()

    client = anthropic.Anthropic()
    content = Path(args.file).read_text()

    response = client.messages.create(
        model=MODELS[args.model],
        max_tokens=8192,
        messages=[{"role": "user", "content": f"{args.prompt}\n\n---\n\n{content}"}]
    )
    print(response.content[0].text)

if __name__ == "__main__":
    main()
```

**Usage:**
```bash
# Basic (uses opus by default)
python scripts/convert-doc.py input.md "Add YAML frontmatter"

# With model selection
python scripts/convert-doc.py input.md "Analyze for CONFIG" --model sonnet
python scripts/convert-doc.py input.md "Quick analysis" -m haiku
```

### `.claude/commands/convert.md`

Updated `/convert` skill to use the script for document operations:

1. **Analysis** - Script analyzes document for noise, sections to remove, sensitivity
2. **CONFIG generation** - Script generates CONFIG block with approved decisions
3. **Backmatter generation** - Script generates summary backmatter

CC handles the interactive review loop (user approvals). Document content stays out of CC's context.

### `tests/test_convert_doc.py`

Comprehensive test suite with 15 tests:

**CLI tests (5):**
- `test_missing_file_arg_shows_usage` - Verifies usage message
- `test_missing_api_key_error` - Verifies API key required
- `test_nonexistent_file_error` - Handles missing files
- `test_help_flag` - Shows model options in help
- `test_invalid_model_rejected` - Rejects invalid model choices

**Unit tests (7):**
- `test_script_structure` - Shebang, imports, main function
- `test_script_uses_env_api_key` - Reads from environment
- `test_prompt_formatting` - Prompt + content combined
- `test_default_prompt_provided` - Has fallback prompt
- `test_max_tokens_reasonable` - Sane token limit (8192)
- `test_model_flag_structure` - MODELS dict with opus/sonnet/haiku, default opus
- `test_model_ids_correct` - Valid Claude model identifiers

**Integration tests (3, require `ANTHROPIC_API_KEY`):**
- `test_integration_with_api_key` - Basic API call works
- `test_multi_invocation_workflow` - Full flow: exploratory → initial config → refined config
- `test_different_prompts_same_file` - Confirms stateless behavior

## CC Workflow

The script supports an iterative workflow:

1. CC decides to convert a doc
2. CC runs: `python convert-doc.py doc.md "instructions" --model opus`
3. Script returns converted content to stdout
4. CC shows user the result
5. User says "good" → CC writes to file
6. User says "tweak X" → CC runs again with adjusted prompt

CC handles the interactive loop. Script is stateless.

## Documentation Updated

- `components/distill/README.md` - Added Context Isolation Script section
- `docs/pipeline.md` - Added note about context isolation in Stage 2
- `docs/intake-pipeline.md` - Added context isolation note in Step 2
- `tests/README.md` - Updated test counts (136 total: 57 Python + 79 Shell)

## Verification

```bash
# Run tests
python3 tests/test_convert_doc.py

# Via test runner
python3 tests/run_tests.py test_convert_doc

# Test model flag
python3 scripts/convert-doc.py --help
```

All 15 tests pass. Integration tests skip gracefully when `ANTHROPIC_API_KEY` is not set.

## Dependencies

```bash
pip install anthropic
```
