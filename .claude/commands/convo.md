# /convo - Load Active Conversation

Load the bot's active session into context and summarize it.

## Instructions

### Step 1: Get Active Session Info

```bash
./tools/bot cat /Users/bruba/.clawdbot/agents/bruba-main/sessions/sessions.json 2>/dev/null
```

Parse the JSON to find the active session ID (look for `sessionId` in the nested structure).

### Step 2: Check If Already Loaded

**Remember these values across the conversation:**
- `bot_session_id` — the session ID you last loaded
- `bot_lines_read` — how many lines you've already read

**If this is a repeat call (same session ID):**
1. Get current line count:
   ```bash
   ./tools/bot wc -l /Users/bruba/.clawdbot/agents/bruba-main/sessions/{SESSION_ID}.jsonl
   ```
2. If line count == `bot_lines_read`: "No new messages since last check."
3. If line count > `bot_lines_read`: Fetch only new lines (Step 2b)

### Step 2b: Fetch Only New Lines

```bash
./tools/bot tail -n +{bot_lines_read + 1} /Users/bruba/.clawdbot/agents/bruba-main/sessions/{SESSION_ID}.jsonl
```

Update `bot_lines_read` to current line count, then skip to Step 4.

### Step 3: Initial Load (First Call or New Session)

Check file size and line count:
```bash
./tools/bot wc -c -l /Users/bruba/.clawdbot/agents/bruba-main/sessions/{SESSION_ID}.jsonl
```

**Token estimation:** bytes / 4 ≈ tokens
- Full-read threshold: 60KB (~15k tokens)
- Partial-read target: ~40KB (~10k tokens)

**If file < 60KB:** Read entire file
```bash
./tools/bot cat /Users/bruba/.clawdbot/agents/bruba-main/sessions/{SESSION_ID}.jsonl
```

**If file > 60KB:** Estimate lines needed:

1. Calculate average bytes per line: `total_bytes / total_lines`
2. Estimate lines for ~40KB: `40000 / avg_bytes_per_line`
3. Verify size before fetching:
   ```bash
   ./tools/bot tail -{estimated_lines} /path/to/file.jsonl | wc -c
   ```
4. Adjust if needed, then fetch

**After reading, remember:**
- `bot_session_id` = current session ID
- `bot_lines_read` = total lines in file

### Step 4: Summarize & Offer Next

**For initial load:**
- Main topics discussed
- Any decisions made or actions taken
- Outstanding items/questions
- Current state/context

**For incremental update:**
- "X new messages since last check"
- Brief summary of what's new

**Always offer one option:**
- **If partial read:** "Would you like me to read back further?"
- **If full read:** "Would you like me to load the previous conversation?"

To get previous session:
```bash
./tools/bot 'ls -t /Users/bruba/.clawdbot/agents/bruba-main/sessions/*.jsonl | head -2'
```

## Arguments

$ARGUMENTS

## Example Output

**Initial full read:**
```
=== Bot Conversation ===
Session: abc12345 (full, 79 lines, ~27k tokens)

Summary:
- Discussed workflow improvements
- Decided to add retry logic to script
- Currently waiting for user input

Would you like me to load the previous conversation?
```

**Repeat call, no changes:**
```
=== Bot Conversation ===
Session: abc12345 — no new messages since last check (still 79 lines)
```

## Related Skills

- `/status` - Check daemon and session status
- `/pull` - Pull closed sessions
