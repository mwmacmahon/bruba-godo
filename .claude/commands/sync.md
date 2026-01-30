# /sync - Assemble and Push Prompts

Assemble prompts from templates + components + user, detect conflicts, and push to bot.

## Instructions

### 1. Mirror Current State

First, get the bot's current prompts to detect changes:

```bash
./tools/mirror.sh --verbose
```

### 2. Assemble Prompts

Build final prompts from all sources:

```bash
./tools/assemble-prompts.sh --verbose
```

This combines:
- `templates/prompts/` — Base prompts
- `components/*/prompts/*.snippet.md` — Component additions
- `user/prompts/*.snippet.md` — User customizations

Output goes to `assembled/prompts/`.

### 3. Detect Conflicts

Compare bot's current prompts (in `mirror/prompts/`) to assembled prompts:

```bash
# For each prompt file, check if bot has changes
for prompt in AGENTS.md TOOLS.md MEMORY.md; do
    if [[ -f "mirror/prompts/$prompt" ]] && [[ -f "assembled/prompts/$prompt" ]]; then
        diff -q "mirror/prompts/$prompt" "assembled/prompts/$prompt" || echo "Changed: $prompt"
    fi
done
```

**If conflicts detected:**
- Show which files differ
- Offer to show diff: `diff mirror/prompts/AGENTS.md assembled/prompts/AGENTS.md`
- Ask user: push anyway, review, or abort

### 4. Push Assembled Prompts

If no conflicts (or user approves), sync assembled prompts to bot:

```bash
# Rsync assembled prompts to bot workspace
rsync -avz assembled/prompts/ $SSH_HOST:$REMOTE_WORKSPACE/
```

Or use full push script for content as well:
```bash
./tools/push.sh --verbose
```

## Arguments

$ARGUMENTS

Options:
- `--force` — Push without conflict check
- `--dry-run` — Show what would happen

## Assembly Sources

| Source | Directory | Priority |
|--------|-----------|----------|
| Base templates | `templates/prompts/` | Applied first |
| Component snippets | `components/*/prompts/` | Added in order |
| User snippets | `user/prompts/` | Added last |

### Snippet Format

Snippets are wrapped with markers when assembled:

```markdown
<!-- COMPONENT: voice -->
## Voice Message Handling

When you receive a message with `[Audio]` tag...
<!-- /COMPONENT: voice -->
```

## Conflict Handling

**What counts as a conflict:**
- Bot's version differs from what we last pushed
- Bot made edits to prompts during operation

**Resolution options:**
1. **Push anyway** — Overwrites bot's changes
2. **Review diff** — See what bot changed
3. **Abort** — Keep bot's version, update templates manually

## Example

```
User: /sync

Claude: [mirrors current state]
Mirror: 8 files

Claude: [assembles prompts]
Assembled: 6 prompts (2 component snippets)

Claude: [checks for conflicts]
Comparing to bot's current prompts...
⚠️ AGENTS.md has local changes on bot

Changed sections:
  - Added note about specific tool behavior

Options:
1. Push anyway (overwrites bot's changes)
2. Show full diff
3. Abort

User: 2

Claude: [shows diff]
--- mirror/prompts/AGENTS.md
+++ assembled/prompts/AGENTS.md
@@ -45,0 +46,3 @@
+Note: When using remindctl, always specify timezone...

User: push anyway

Claude: [pushes]
Synced 6 prompts to bot.
```

## Related Skills

- `/mirror` - Mirror bot files locally
- `/push` - Push content to bot memory
- `/component` - Manage components (which add snippets)
