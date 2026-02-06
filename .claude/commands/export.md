# /export - Generate Filtered Exports

Generate filtered and redacted exports from canonical transcripts.

## Arguments

$ARGUMENTS

Options:
- `--profile <name>` - Run specific profile only (default: all)
- `--profile agent:<name>` - Run specific agent profile (e.g., `agent:bruba-rex`)
- `--dry-run` - Show what would be exported without writing

## Instructions

### 1. Run Export Command

For all profiles (standalone + agent profiles):
```bash
python -m components.distill.lib.cli export --verbose
```

For specific standalone profile:
```bash
python -m components.distill.lib.cli export --profile claude --verbose
```

For specific agent profile:
```bash
python -m components.distill.lib.cli export --profile agent:bruba-rex --verbose
```

### 2. Report Results

Show for each profile:
- How many files processed
- How many files skipped (filtered out or not routed to this agent)
- Output location
- Redaction categories applied

## Export Profiles

### Standalone Profiles (in `exports:` section of config.yaml)

Process all canonical files regardless of `agents:` frontmatter:

```yaml
exports:
  claude:
    description: "Prompts for Claude Projects / Claude Code"
    output_dir: exports/claude
    include:
      scope: [meta, reference, transcripts]
    redaction: [names, health]
```

### Agent Profiles (auto-generated from `agents:` section)

Agents with `content_pipeline: true` AND `include:` rules automatically get export profiles. Files are routed via the `agents:` field in frontmatter:

- File with `agents: [bruba-main]` -> exported to `agents/bruba-main/exports/`
- File with `agents: [bruba-main, bruba-rex]` -> exported to both
- File with no `agents:` field -> defaults to `[bruba-main]`

To supply a transcript to another agent's memory, add that agent to the `agents:` list in the file's frontmatter.

## Filter Rules

**include.scope** - File must match at least one scope:
- `transcripts` - All canonical transcript files (always matches)
- `reference` - Files tagged as reference material
- `meta` - Meta/documentation files

**include.tags** - File must have at least one of these tags

**exclude.sensitivity** - Skip files with these sensitivity levels:
- `sensitive` - Marked as sensitive
- `restricted` - Highly restricted content

**agents: frontmatter** (agent profiles only) - File must list this agent in its `agents:` field

### Sections Remove

The `sections_remove` entries from each file's frontmatter are applied:
- Content between `start` and `end` anchors is removed
- Replaced with `[Removed: description]`
- Use for walls of pasted text, large code blocks, debug tangents

### Redaction

Categories specified in `redaction` list are redacted:
- `names` - Personal names
- `health` - Medical/health information
- `personal` - Personal details (addresses, etc.)
- `financial` - Financial information

Redaction uses the `sensitivity.terms` defined in each file's frontmatter.

## Example Output

```
=== /export ===

Found 12 canonical files

=== Profile: claude ===
  Prompts for Claude Projects / Claude Code
  Written: 10, Unchanged: 1, Skipped: 1
  Output: exports/claude/

=== Agent: bruba-main ===
  Content for bruba-main memory
  Written: 11, Unchanged: 0, Skipped: 1
  Output: agents/bruba-main/exports/

=== Agent: bruba-rex ===
  Content for bruba-rex memory
  Written: 3, Unchanged: 0, Skipped: 9
  Output: agents/bruba-rex/exports/

Export complete.
```

## Pipeline Position

```
/pull
  ↓
agents/{agent}/intake/*.md
  ↓
/convert (sets agents: field)
  ↓
/intake (canonicalizes with --agent)
  ↓
reference/transcripts/*.md (agents: in frontmatter)
  ↓
/export (this skill)  ← YOU ARE HERE
  ↓
agents/{agent}/exports/*.md (per-agent filtered + redacted)
  ↓
/push (syncs content_pipeline agents)
  ↓
bot memory
```

## Verification

After export, verify output:

```bash
# Check per-agent export counts
find agents/bruba-main/exports -name "*.md" | wc -l
find agents/bruba-rex/exports -name "*.md" | wc -l

# Verify multi-agent routing (file in both dirs)
ls agents/bruba-main/exports/transcripts/ agents/bruba-rex/exports/transcripts/
```

## Related Skills

- `/sync` - Full pipeline sync (prompts + content)
- `/intake` - Canonicalize intake files (prerequisite)
- `/push` - Push exports to bot memory
- `/prompt-sync` - Prompt assembly only
