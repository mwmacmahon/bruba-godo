# Test Fixtures

Sanitized conversation examples for testing the convo-processor pipeline.

## Fixture Structure

Each fixture directory contains:
- `input.md` - Raw conversation export (as copied from Claude Projects)
- `expected-canonical.md` - Expected output after canonicalization (optional)

## Creating Fixtures

### Source Material

Fixtures are based on **real conversation patterns** but with:
- All personal information removed (names, SSNs, addresses)
- Company-specific details genericized
- Technical content kept realistic

### Conversation Flow Pattern

Every fixture should follow the realistic export flow from `prompts/export.md`:

```
1. [Conversation happens - user and AI discuss something]
2. USER: "done, export" or "done, defaults" or similar
3. ASSISTANT:
   - "**Transcription scan:** ..." (if voice content)
   - "Before I produce the export: ..."
   - [checklist of options]
   - "---"
   - "```yaml"
   - "=== EXPORT CONFIG ==="
   - [config block]
   - "=== END CONFIG ==="
   - "```"
   - "---"
   - "## Summary" and other backmatter
```

### Voice Transcript Pattern

For transcription fixtures, show the actual cleanup:

```markdown
=== MESSAGE 0 | USER ===
[intro like "Here's a voice memo, please clean it up:"]

pasted

[Raw voice transcript with actual mishearings like:
- "lamb da" instead of "Lambda"
- "salmon" instead of "SAML"
- "easy to" instead of "EC2"
- filler words: "um", "uh", "like"
- false starts and repetitions]

=== MESSAGE 1 | ASSISTANT ===
Here's the cleaned transcript:

[Cleaned version with proper capitalization and terms]

---

**Error fixes:**

1. "original" → "corrected"
2. ...

**Language fixes:**

1. Removed "Um" throughout
2. ...
```

### Paste-and-Export Pattern

For exporting a conversation that happened in a previous session:

```markdown
=== MESSAGE 0 | USER ===
Here's a conversation I had earlier that I need exported:

pasted

---

**Previous conversation:**

USER: [original user message with voice transcript]

A: [AI's cleanup with **Error fixes:** section]

[rest of conversation]

---

Done, export please.

=== MESSAGE 1 | ASSISTANT ===
**Transcription scan:** Found 1 voice memo...

[export config with transcription_replacements]
```

The key difference: `transcription_replacements` contains the full original/cleaned text blocks for bulk substitution, whereas `mid_conversation_transcriptions` just marks anchors for inline cleanups.

### Config Block Requirements

The export config must:
1. **Reference actual content** - anchors in `sections_remove` must point to real text
2. **Match conversation events** - `mid_conversation_transcriptions` should list actual transcripts
3. **Use correct format** - v2 uses `title`/`slug`/`sections_remove`, v1 uses `filename_base`/`sections_to_remove`

## Fixture Categories

| Fixture | Tests | Key Patterns |
|---------|-------|--------------|
| 001-ui-artifacts | Timestamp removal, thinking summaries | Timestamps like "10:15 AM", "Show more", "14s" |
| 002-section-removal | Anchor-based removal | `sections_remove` and `sections_lite_remove` |
| 003-transcription-corrections | Voice memo cleanup | Raw transcript → cleaned → error fixes |
| 004-code-blocks | Code block processing | Multiple code blocks with actions |
| 005-full-export | Combined features | UI artifacts + sections + code + transcription |
| 006-v1-migration | Legacy format | v1 config field names |
| 007-paste-and-export | Pasted old conversation | `transcription_replacements` for bulk cleanup |

## Sensitivity Guidelines

**Never include:**
- Real names (use: Alice, Bob, Cyrus, User for generic names)
- Real SSNs, account numbers, addresses
- Actual company names or proprietary info
- Real health information
- Actual passwords or API keys

**Safe to include:**
- Generic technical discussions (AWS, coding, etc.)
- Fake project names
- Made-up tangent topics (sports, weather)
- Realistic voice transcription errors

## Validating Fixtures

```bash
# Run tests to verify fixtures work
python tests/run_tests.py

# Generate debug outputs to inspect processing
python tests/generate_debug_outputs.py

# Check specific fixture
python tests/generate_debug_outputs.py 003-transcription-corrections
```

## Adding a New Fixture

1. Create directory: `fixtures/NNN-description/`
2. Write `input.md` following the patterns above
3. Ensure export config references actual conversation content
4. Run tests to verify it parses correctly
5. Optionally add `expected-canonical.md` for exact output testing
