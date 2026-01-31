# /prompts - Manage Bot Prompts

Help manage the prompt assembly system: resolve conflicts, explain configuration, reorder sections, and troubleshoot issues.

## Context

Read these files to understand current state:
- `exports.yaml` — section order in `exports.bot.agents_sections`
- `templates/prompts/README.md` — full system documentation
- `mirror/prompts/AGENTS.md` — current remote state (has BOT-MANAGED sections)
- `exports/bot/core-prompts/AGENTS.md` — last assembled output

## Commands

The user may ask for help with:

### Explain the System
If user asks "how does this work" or seems confused:
1. Read `templates/prompts/README.md`
2. Summarize the key concepts:
   - Config defines section order
   - Three types: component, template section, bot-managed
   - `bot:name` prefix for bot-owned sections
   - Assembly resolves each entry and concatenates

### Show Current Config
```bash
grep -A 50 "agents_sections:" exports.yaml | head -30
```

### Show Section Order Comparison
Compare mirror (remote) vs assembled:
```bash
echo "=== REMOTE ===" && grep "^## " mirror/prompts/AGENTS.md
echo ""
echo "=== ASSEMBLED ===" && grep "^## " exports/bot/core-prompts/AGENTS.md
```

### Reorder Sections
If user wants to move a section:
1. Show current `agents_sections` from exports.yaml
2. Edit `exports.yaml` to move the entry (under `exports.bot.agents_sections`)
3. Run `./tools/assemble-prompts.sh`
4. Show the new order

### Add New Section
If user wants to add a section:
1. Ask: component or template section?
2. For component: create `components/{name}/prompts/AGENTS.snippet.md`
3. For template: create `templates/prompts/sections/{name}.md`
4. Add entry to `agents_sections` at desired position
5. Run assembly

### Disable Section
Comment out the entry in `agents_sections`:
```yaml
# - section-name  # disabled
```

### Convert to Bot-Managed
If bot has customized a component and user wants to keep bot's version:
1. Change `name` to `bot:name` in config
2. Ensure mirror has `<!-- BOT-MANAGED: name -->` markers
3. Run assembly

## Conflict Resolution

When called during sync with conflicts, help resolve:

### New Bot Section Detected
If mirror has a `<!-- BOT-MANAGED: X -->` not in config:

1. Show the section content
2. Ask: "Bot added section 'X'. Keep it? Where should it go?"
3. If yes:
   - Determine position (ask user or detect from mirror context)
   - Add `bot:X` to config at that position
4. If no:
   - Warn that it will be removed on next push

### Bot Edited Component
If mirror's content for a section differs from component:

1. Show the diff
2. Ask: "Bot modified '{section}'. Use bot's version?"
3. If yes:
   - Change `section` to `bot:section` in config
   - Content will come from mirror's BOT-MANAGED block
4. If no:
   - Component version will overwrite on push

## Troubleshooting

### Missing Section Error
```
! Missing: X (not found as component or section)
```

Check:
1. Is it a bot section? → needs `bot:` prefix and BOT-MANAGED markers in mirror
2. Is spelling correct?
3. Does file exist?
   - Component: `components/X/prompts/AGENTS.snippet.md`
   - Section: `templates/prompts/sections/X.md`

### Bot Section Not Appearing
1. Check mirror has markers: `grep "BOT-MANAGED" mirror/prompts/AGENTS.md`
2. Check config has `bot:name` entry
3. Run `/mirror` to refresh from remote

### Wrong Section Order
Edit `agents_sections` in exports.yaml and move entries to desired positions.

## Quick Reference

| Task | Action |
|------|--------|
| See config | `grep -A 30 "agents_sections:" exports.yaml` |
| Assemble | `./tools/assemble-prompts.sh` |
| Verbose assemble | `./tools/assemble-prompts.sh --verbose` |
| Dry run | `./tools/assemble-prompts.sh --dry-run` |
| Compare sections | `grep "^## " mirror/prompts/AGENTS.md exports/bot/core-prompts/AGENTS.md` |
| Find bot sections | `grep "BOT-MANAGED" mirror/prompts/AGENTS.md` |
| Mirror remote | `./tools/mirror.sh` |

## Section Types Cheatsheet

```
agents_sections:
  - header              # → templates/prompts/sections/header.md
  - http-api            # → components/http-api/prompts/AGENTS.snippet.md
  - bot:exec-approvals  # → mirror's <!-- BOT-MANAGED: exec-approvals -->
```

Resolution order: bot: prefix → component → template section → error
