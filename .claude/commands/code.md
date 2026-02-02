# /code - Review and Migrate Staged Code

Review code staged in the bot's workspace and migrate approved tools to production.

## Instructions

### Step 1: List Staged Code

Check what's in the workspace code directory:

```bash
./tools/bot ls -la /Users/bruba/.openclaw/agents/bruba-main/workspace/code/
```

If empty or directory doesn't exist, report "No staged code found" and exit.

### Step 2: Detect Updates vs New Code

For each staged file, check if it already exists in production:

```bash
# Check for shell scripts in tools/
./tools/bot ls /Users/bruba/agents/bruba-main/tools/{script}.sh

# Check for Python helpers in tools/helpers/
./tools/bot ls /Users/bruba/agents/bruba-main/tools/helpers/{script}.py
```

**If file exists in production:**
- Label as "**UPDATE**" (not "NEW")
- Show diff between staged and production versions:
  ```bash
  ssh bruba 'diff ~/clawd/tools/{script}.sh ~/.openclaw/agents/bruba-main/workspace/code/{script}.sh'
  # Or for Python:
  ssh bruba 'diff ~/clawd/tools/helpers/{script}.py ~/.openclaw/agents/bruba-main/workspace/code/{script}.py'
  ```
- Frame review as "approving changes to existing tool" not "approving new code"

**If file doesn't exist:** Label as "**NEW**"

### Step 3: Find Conversation Context

Search **ALL** archived sessions for exact filename matches, then show relevant excerpts upfront.

#### 3a. Find Sessions with Matches

For each staged file, search all sessions:

```bash
# Find all sessions mentioning the exact filename
ssh bruba 'grep -l "cleanup-reminders.py" ~/.openclaw/agents/bruba-main/sessions/*.jsonl'
```

Then get line numbers within each matching session:

```bash
ssh bruba 'grep -n "cleanup-reminders.py" ~/.openclaw/agents/bruba-main/sessions/{session}.jsonl'
```

**Display logic:**
- Show excerpts from recent sessions (past 7 days) by default
- If older sessions have matches, mention: "Also found in 3 older sessions (Dec 2025). Want to see those?"

#### 3b. Extract Context Around Each Match

For each hit, grab the matching line plus 2-3 lines before/after:

```bash
# If match is at line 162, grab 159-165
ssh bruba 'sed -n "159,165p" ~/.openclaw/agents/bruba-main/sessions/{session}.jsonl'
```

#### 3c. Parse JSONL and Extract Key Fields

Use the helper script or parse manually. Each line is JSON. Extract:
- **Line number** (from grep -n)
- **Full date+time** (from `timestamp` field, convert UTC→local)
- **Speaker** (`message.role`: "user" → "User", "assistant" → "Assistant")
- **Message text** (from `message.content[0].text`, truncate to ~80 chars with `...`)

```bash
python3 tools/helpers/parse-jsonl.py sessions/{session}.jsonl --extract 159-165
```

#### 3d. Format and Present Excerpts

```
=== Conversation Context: cleanup-reminders.py ===

Session a613d9a3 (Jan 29):
  ... L162 | 2026-01-29 11:48 | User: "Can we delete everything over a year old that's completed?"
  ... L181 | 2026-01-29 11:50 | User: "Save all the old reminders we clean up to a text file..." ...
  ... L440 | 2026-01-29 14:51 | User: "for groceries...prune more aggressively (anything completed..." ...

Session 562630db (Jan 29):
  ... L16 | 2026-01-29 15:09 | User: "want to discuss cleanup-reminders.sh and helpers/cleanup-reminders.py..." ...

Dig deeper into a conversation cluster? (e.g., "a613 430-470" or "skip")
```

**Key formatting:**
- `...` prepended inline to first excerpt line (not separate line)
- `...` appended inline to last excerpt line if message truncated
- Full date (2026-01-29), not just time
- Speaker name ("User" or "Assistant"), not role
- Message truncated with `...` if over ~80 chars

#### 3e. Iterative Expansion

When user specifies a range (e.g., "a613 430-470"):
1. Extract those lines from the session
2. Parse and display full messages
3. Offer to expand further (earlier/later lines)

Goal: hit each conversation cluster around the code, then iteratively find the rest.

### Step 4: Present Code Review

Read each staged file:

```bash
./tools/bot cat /Users/bruba/.openclaw/agents/bruba-main/workspace/code/{filename}
```

Present a review for each file:
- **Status:** UPDATE or NEW (from Step 2)
- **Purpose:** What the script does
- **Changes:** (for updates) Summary of what changed vs production
- **Paths:** Hardcoded paths it uses
- **Dependencies:** What tools/scripts it calls
- **Security:** Check for hardcoded secrets, unsafe operations, path escaping
- **Recommendation:** Approve, needs changes, or reject

### Step 5: Discuss with User

Wait for user input. Options:
- "migrate" — proceed to migration
- "view {file}" — show full code
- "diff {file}" — show diff vs production (for updates)
- "discuss" — explain something about the code
- User may request changes (edit on bot side or reject)

### Step 6: Migrate Approved Code

Check existing tools to avoid conflicts:

```bash
./tools/bot ls /Users/bruba/agents/bruba-main/tools/
./tools/bot ls /Users/bruba/agents/bruba-main/tools/helpers/
```

Migrate files to production:
- Shell wrappers (.sh) → `/Users/bruba/agents/bruba-main/tools/`
- Python helpers (.py) → `/Users/bruba/agents/bruba-main/tools/helpers/`

```bash
# Use ssh directly for cp (quoting issues with bot wrapper)
ssh bruba 'cp ~/.openclaw/agents/bruba-main/workspace/code/script.sh ~/clawd/tools/'
ssh bruba 'chmod +x ~/clawd/tools/script.sh'
```

### Step 7: Update Allowlist

Add new tools to exec-approvals.json:

```bash
# View current allowlist
./tools/bot cat /Users/bruba/.openclaw/exec-approvals.json

# Add new entry (use ssh for JSON manipulation)
ssh bruba 'cat ~/.openclaw/exec-approvals.json | jq ".agents[\"bruba-main\"].allowlist += [{\"pattern\": \"/Users/bruba/agents/bruba-main/tools/script.sh\", \"id\": \"script-name\"}]" > /tmp/ea.json && mv /tmp/ea.json ~/.openclaw/exec-approvals.json'
```

### Step 8: Restart Daemon & Verify

```bash
ssh bruba 'openclaw daemon restart'
ssh bruba 'openclaw gateway health'
```

### Step 9: Optional Cleanup

**Note:** Bot cannot delete from its own workspace — cleanup must be done from operator side.

Ask user if they want to remove migrated files from workspace/code/:

```bash
# Run via ssh (not via bot wrapper)
ssh bruba 'rm ~/.openclaw/agents/bruba-main/workspace/code/script.sh'
```

## Arguments

$ARGUMENTS

## Example Output

```
=== Staged Code ===
  cleanup-reminders.py (4.4 KB) — UPDATE (exists in production)
  cleanup-reminders.sh (330 bytes) — UPDATE (exists in production)

=== Diff: cleanup-reminders.py ===
< old_line
---
> new_line
(Shows diff between staged and production versions)

=== Conversation Context: cleanup-reminders.py ===

Session abc123d4 (Jan 28):
  ... L450 | 2026-01-28 14:32 | User: "Can we delete everything over a year old that's completed?"
  ... L512 | 2026-01-28 14:45 | User: "Save all the old reminders we clean up to a text file..." ...
  ... L890 | 2026-01-28 16:20 | Assistant: "I've updated cleanup-reminders.py to archive before deleting..." ...

Session def456e7 (Jan 26):
  ... L120 | 2026-01-26 09:15 | User: "want to discuss cleanup-reminders.sh wrapper..."
  ... L340 | 2026-01-26 10:30 | User: "add a --dry-run flag that shows what would be deleted..." ...

Also found in 2 older sessions (Dec 2025). Want to see those?

Dig deeper into a conversation cluster? (e.g., "abc1 440-520" or "skip")

=== Code Review: cleanup-reminders.sh [UPDATE] ===
Status: UPDATE — modifying existing production tool
Purpose: Wrapper that calls cleanup-reminders.py with standard args
Changes: Added --archive-path flag, updated default retention to 30 days
Paths:
  - ~/clawd/tools/helpers/cleanup-reminders.py (called)
  - ~/clawd/output/reminders_archive/ (for backups)
Dependencies: python3, cleanup-reminders.py
Security: ✓ No hardcoded secrets, ✓ Uses dry-run by default
Recommendation: Approve changes

=== Code Review: cleanup-reminders.py [UPDATE] ===
Status: UPDATE — modifying existing production tool
Purpose: Archive completed reminders older than retention threshold
Changes: New archive path parameter, improved error handling
Paths: Uses ~/clawd/output/reminders_archive/ for backup storage
Dependencies: remindctl (already allowlisted), json, pathlib
Security: ✓ No hardcoded secrets, ✓ Creates backup before delete
Recommendation: Approve changes

Ready to migrate? (migrate/view/diff/discuss)
```

## Related Skills

- `/status` - Check daemon and session status
- `/convo` - Load full conversation for context
- `/restart` - Restart daemon after config changes
