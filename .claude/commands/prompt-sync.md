# /prompt-sync - Assemble and Push Prompts

Assemble prompts from config-driven sections, detect conflicts with bot's changes, and push to remote.

## Instructions

### 1. Mirror Current State

Pull bot's current prompts to detect changes:

```bash
./tools/mirror.sh
```

### 2. Detect Conflicts

Run the conflict detection script:

```bash
./tools/detect-conflicts.sh
```

This checks for:
- **New bot sections:** BOT-MANAGED blocks in mirror not listed in config
- **Bot edits to components:** Content in mirror differs from component source

**If conflicts are found, resolve them before proceeding** (see Conflict Resolution below).

### 3. Assemble Prompts

Build final prompts from config-driven section order:

```bash
./tools/assemble-prompts.sh --verbose
```

**Note:** Assembly will automatically block if conflicts are detected. Use `--force` to override (discards bot changes).

### 4. Push to Remote

Sync assembled prompts to bot using the push script (handles multi-destination routing):

```bash
./tools/push.sh --verbose
```

This syncs:
- `exports/bot/core-prompts/` → `~/clawd/` (AGENTS.md)
- `exports/bot/prompts/` → `~/clawd/memory/prompts/`
- `exports/bot/transcripts/` → `~/clawd/memory/transcripts/`
- Other subdirs → `~/clawd/memory/{subdir}/`

Or for specific files:
```bash
scp exports/bot/core-prompts/AGENTS.md bruba:/Users/bruba/clawd/AGENTS.md
```

## Conflict Resolution

### New Bot Section Detected

When mirror has `<!-- BOT-MANAGED: X -->` not in config:

1. **Show the section:**
   ```bash
   ./tools/detect-conflicts.sh --show-section X
   ```

2. **Ask user:** "Bot added section 'X'. Keep it?"

3. **If yes:**
   - Determine position (look at surrounding sections in mirror)
   - Edit `exports.yaml` to add `bot:X` to `agents_sections` at correct position
   - Example: If section appears after `safety`, add after `- safety` line

4. **If no:**
   - Section will be removed on push
   - Warn user this is destructive

### Bot Edited Component

When mirror's content for a section differs from assembled component:

1. **Show the diff:**
   ```bash
   ./tools/detect-conflicts.sh --diff session
   ```

2. **Ask user:** "Bot modified 'session'. Use bot's version?"

3. **If yes (keep bot's changes):**
   - Change `session` to `bot:session` in config
   - Bot must have wrapped with `<!-- BOT-MANAGED: session -->`
   - If not wrapped, help user add markers on remote

4. **If no (use component version):**
   - Bot's changes will be overwritten on push
   - Confirm this is intentional

## Arguments

$ARGUMENTS

Options:
- `--force` — Push without conflict check
- `--dry-run` — Show what would happen without pushing

## Quick Sync (No Conflicts)

If you're confident there are no conflicts:

```bash
./tools/mirror.sh && ./tools/assemble-prompts.sh && ./tools/push.sh
```

## Config-Driven Assembly

Sections are defined in `exports.yaml` under the bot profile:

```yaml
# exports.yaml
exports:
  bot:
    agents_sections:
  - header              # template section
  - http-api            # component
  - bot:exec-approvals  # bot-managed (preserved)
  - safety              # template section
  ...
```

Resolution order for each entry:
1. `bot:name` → extract from mirror's BOT-MANAGED blocks
2. Component → `components/{name}/prompts/AGENTS.snippet.md`
3. Template section → `templates/prompts/sections/{name}.md`

## Example Flow

```
User: /prompt-sync

Claude: [mirrors]
$ ./tools/mirror.sh
Mirror: 15 files

Claude: [checks conflicts]
$ ./tools/detect-conflicts.sh

⚠️  Conflicts detected:

1. NEW BOT SECTION: "my-notes"
   Location: after "heartbeats" section
   Preview:
   ## My Notes
   Some things I learned...

2. BOT EDITED: "memory" component
   Lines changed: 3 added, 1 removed

Options:
1. Resolve conflicts interactively
2. Show details
3. Force push (overwrite bot changes)
4. Abort

User: 1

Claude: [resolves each]
Keep bot section "my-notes"? [y/n]: y
→ Added "bot:my-notes" to config after "heartbeats"

Use bot's version of "memory"? [y/n]: n
→ Component version will be used (bot changes overwritten)

Claude: [assembles and pushes]
$ ./tools/assemble-prompts.sh
Assembled: AGENTS.md (18 sections)

$ rsync -avz assembled/prompts/ bruba:/Users/bruba/clawd/
Synced to bot.
```

## Related Skills

- `/sync` - Full pipeline sync (prompts + content)
- `/prompts` - Explain config system, manual conflict resolution
- `/mirror` - Mirror bot files locally
- `/push` - Push content to bot memory
- `/component` - Manage components
