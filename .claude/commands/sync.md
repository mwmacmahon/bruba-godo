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
python -m components.distill.lib.cli export --profile bot --verbose
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
