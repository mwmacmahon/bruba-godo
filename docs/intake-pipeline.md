# Intake Pipeline

How conversation sessions flow from raw JSONL to processed reference documents.

## Overview

```
JSONL Session → Pull → Markdown → Process → Reference Doc
     ↓            ↓        ↓          ↓           ↓
  (on bot)    /pull    parse-jsonl  (manual)   (local)
```

## The Pipeline

### Step 1: Sessions Accumulate

As you interact with the bot, conversations are recorded in JSONL files:

```
~/.clawdbot/agents/<agent-id>/sessions/
├── session-2026-01-29-abc123.jsonl    # Active session
├── session-2026-01-28-def456.jsonl    # Closed
└── session-2026-01-27-ghi789.jsonl    # Closed
```

Sessions are **closed** when you say `/reset` or start a new session.

### Step 2: Pull Sessions

Use `/pull` skill or `./tools/pull-sessions.sh` to download closed sessions:

```bash
./tools/pull-sessions.sh --verbose
```

This copies closed JSONL files to `sessions/` locally and tracks what's been pulled in `sessions/.pulled`.

### Step 3: Convert to Markdown

Convert a JSONL session to readable markdown:

```bash
python tools/helpers/parse-jsonl.py sessions/session-2026-01-28.jsonl > intake/2026-01-28-topic.md
```

This produces a clean transcript with:
- Human/Assistant message separation
- Timestamps
- Tool calls summarized

**With transcription corrections** (for voice messages):

```bash
python tools/helpers/parse-jsonl.py sessions/session.jsonl --corrections > intake/topic.md
```

See [Transcription Corrections](#transcription-corrections) below.

### Step 4: Process for Reference

Review the markdown and extract valuable content:

- Key decisions or insights
- Reference information worth keeping
- Code snippets or configurations

Move processed content to `reference/` for syncing back to the bot.

### Step 5: Push to Bot Memory

```bash
./tools/push.sh --verbose
```

This syncs `exports/bot/` to the bot's memory directory.

---

## JSONL Format

Each line in a session file is a JSON object:

```json
{"role": "human", "content": "Hello", "timestamp": "2026-01-29T10:00:00Z"}
{"role": "assistant", "content": "Hi there!", "timestamp": "2026-01-29T10:00:05Z"}
{"role": "tool_use", "name": "Bash", "input": {"command": "ls"}, "timestamp": "..."}
{"role": "tool_result", "content": "file1.txt\nfile2.txt", "timestamp": "..."}
```

**Roles:**
- `human` — User messages
- `assistant` — Bot responses
- `tool_use` — Tool invocations
- `tool_result` — Tool outputs
- `system` — System messages

---

## Simple vs Full Pipeline

### Simple Pipeline (bruba-godo)

1. Pull JSONL: `./tools/pull-sessions.sh`
2. Convert: `python tools/helpers/parse-jsonl.py session.jsonl > doc.md`
3. Review and extract manually
4. Push: `./tools/push.sh`

Good for quick extraction of specific content.

### Full Pipeline (Advanced)

1. Pull sessions with full processing
2. Canonicalize with frontmatter and tagging
3. Generate variants (redacted versions for different audiences)
4. Automatic mining into reference docs

Required for filtered exports with redaction. This would require a more sophisticated document processing pipeline.

---

## Tips

### Sessions are Immutable After Close

Once you say `/reset`, that session is closed. The JSONL file won't change. This means:
- Safe to pull once per session
- Can delete from bot after pulling
- No need to re-sync old sessions

### Active Session

The active session is still being written. Don't pull it — it's incomplete. Use `/convo` to view the active session without pulling.

### Large Sessions

Very long sessions produce large JSONL files. The markdown conversion handles this, but manual review becomes tedious. Consider:
- Breaking long conversations into topics
- Extracting only the valuable parts
- Using search/grep to find specific content

### Tool Output Noise

Tool outputs (especially file reads) can dominate transcripts. The parse-jsonl helper summarizes these, but you may want to filter further for clean documentation.

---

## Transcription Corrections

Voice messages transcribed by Whisper often have errors. The parser supports automatic corrections.

### Enabling Corrections

```bash
# Use default corrections file (config/corrections.yaml)
python tools/helpers/parse-jsonl.py session.jsonl --corrections

# Use custom corrections file
python tools/helpers/parse-jsonl.py session.jsonl --corrections-file /path/to/my-corrections.yaml
```

### Corrections File Format

The corrections file (`config/corrections.yaml`) uses simple YAML format:

```yaml
# AI/Tech Terms
chatgpt: ChatGPT
chat gpt: ChatGPT
openai: OpenAI
claude: Claude
clawdbot: Clawdbot
llm: LLM
api: API

# Programming Terms
javascript: JavaScript
github: GitHub

# Whisper Artifacts (removed entirely)
"[music]": ""
"[applause]": ""
```

Corrections are:
- Case-insensitive matching
- Case-preserving replacement (when possible)
- Empty values remove the match entirely

### Built-in Whisper Cleanup

Even without `--corrections`, the parser removes:
- Timestamp patterns (`[00:00:00.000 --> 00:00:05.000]`)
- Speaker labels (`[SPEAKER_00]`)
- Multiple spaces and orphaned punctuation

### Customizing Corrections

Edit `config/corrections.yaml` to add your own corrections:

```yaml
# Your name variations
john: John
johnny: John

# Project-specific terms
myproject: MyProject
```

---

## Files Reference

| File | Purpose |
|------|---------|
| `sessions/*.jsonl` | Raw pulled session files |
| `sessions/.pulled` | List of already-pulled session IDs |
| `intake/*.md` | Converted markdown awaiting processing |
| `reference/*.md` | Processed reference documents |
| `exports/bot/*.md` | Content ready to push to bot |

---

## Commands Quick Reference

```bash
# Pull closed sessions from bot
./tools/pull-sessions.sh

# View active session (without pulling)
# Use /convo skill

# Convert JSONL to markdown
python tools/helpers/parse-jsonl.py sessions/session.jsonl > intake/doc.md

# Convert with transcription corrections (for voice)
python tools/helpers/parse-jsonl.py sessions/session.jsonl --corrections > intake/doc.md

# Push content to bot memory
./tools/push.sh
```
