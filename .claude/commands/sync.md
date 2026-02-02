# /sync - Full Pipeline Sync

Runs full sync: prompts + content pipeline.

## Instructions

### 1. Prompt Sync

#### Step 1: Mirror
```bash
./tools/mirror.sh
```

#### Step 2: Detect Conflicts (CRITICAL)
```bash
./tools/detect-conflicts.sh
```

**⚠️ IF CONFLICTS ARE DETECTED: STOP IMMEDIATELY.**

Do NOT proceed to assembly or push. Show the user the conflict summary and ask how to resolve each one:

**For new BOT-MANAGED sections:**
- Ask: "Bot added section 'X'. Keep it?"
- If yes: Add `bot:X` to exports.yaml agents_sections
- If no: Warn that it will be removed on push

**For new COMPONENT sections:**
- Ask: "Bot added component 'X'. Keep it?"
- If yes as component: Create `components/X/prompts/AGENTS.snippet.md` with content from mirror, add `X` to agents_sections
- If yes as bot-managed: Add `bot:X` to agents_sections
- If no: Warn that it will be removed on push

**For edited components:**
- Show diff with `./tools/detect-conflicts.sh --diff NAME`
- Ask: "Bot modified 'X'. Keep bot's version?"
- If yes: Copy changes to component source
- If no: Warn that bot's changes will be overwritten

Only after ALL conflicts are resolved, continue.

#### Step 3: Assemble (only if no conflicts)
```bash
./tools/assemble-prompts.sh --verbose
```

#### Step 4: Push
```bash
./tools/push.sh --verbose
```

#### Step 5: Validate Allowlist

Check component tool allowlist entries:

```bash
./tools/update-allowlist.sh --check
```

**IF DISCREPANCIES ARE DETECTED:**

Show the output to the user. The script reports:
- **Missing entries** (in components but not on bot) → need to add
- **Orphan entries** (on bot but not in components) → may need to remove

Ask user:
- [A] Add missing entries only
- [R] Remove orphan entries only
- [B] Both (add missing + remove orphans)
- [S] Skip

If user chooses to update:
```bash
./tools/update-allowlist.sh              # Both add and remove
./tools/update-allowlist.sh --add-only   # Only add missing
./tools/update-allowlist.sh --remove-only # Only remove orphans
```

#### Step 5b: Validate Agent Tool Configs

Check agent tool configs match config.yaml:

```bash
./tools/update-agent-tools.sh --check
```

**IF DISCREPANCIES ARE DETECTED:**

Show the output to the user. Ask:
- [A] Apply changes (sync config.yaml → bot)
- [S] Skip

If user chooses to apply:
```bash
./tools/update-agent-tools.sh --verbose
```

#### Step 6: Restart Daemon

Restart daemon to apply synced changes (prompts, allowlist, memory index):

```bash
./tools/bot openclaw daemon restart
```

---

### 2. Content Pipeline

#### Step 1: Pull new sessions

```bash
./tools/pull-sessions.sh --verbose
```

Report: new sessions pulled, converted to intake/

#### Step 2: Triage & Convert

**2a. Identify trivial files for deletion**

Scan for tiny conversations (≤4 messages OR <800 chars):

```bash
for f in intake/*.md; do
    msgs=$(grep -c "^=== MESSAGE" "$f" 2>/dev/null || echo 0)
    chars=$(wc -c < "$f" | tr -d ' ')
    if [ "$msgs" -le 4 ] || [ "$chars" -lt 800 ]; then
        echo "$f|$msgs|$chars"
    fi
done
```

If trivial files found, ask user:
- [D] Delete all trivial files
- [R] Review individually
- [S] Skip, keep all

**2b. Handle files needing CONFIG**

```bash
grep -L "=== EXPORT CONFIG ===" intake/*.md 2>/dev/null
```

If files need CONFIG, ask user:
- [A] Auto-CONFIG subset
- [C] Convert one-by-one
- [S] Skip (leave unconverted)

#### Step 3: Canonicalize ready files

```bash
grep -l "=== EXPORT CONFIG ===" intake/*.md 2>/dev/null
```

If files ready:
```bash
python -m components.distill.lib.cli canonicalize intake/<file>.md \
    -o reference/transcripts/ \
    -c components/distill/config/corrections.yaml \
    --move intake/processed
```

#### Step 4: Generate exports

```bash
python -m components.distill.lib.cli export --verbose
```

#### Step 5: Push to bot memory

```bash
./tools/push.sh --verbose
```

---

### 3. Summary

Show brief summary of what was synced.

## Related Skills

- `/prompt-sync` - Prompt assembly only (detailed conflict resolution)
- `/pull` - Pull sessions only
- `/convert` - Convert single file
- `/intake` - Batch canonicalize
- `/export` - Generate exports
- `/push` - Push to bot memory
