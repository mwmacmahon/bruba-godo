# Phase 3: Config-Driven Cronjob Generation

**Prerequisite:** Phase 2 complete (check `docs/packets/phase2-results.md`)
**Input:** Phase 2 results confirming all templates are variable-driven
**Blocks:** Phase 4 (history scrub)

## Context — Read These First

Before starting, read these files to understand the system:

1. **Phase 2 results:** `docs/packets/phase2-results.md` — confirms templates are variable-driven
2. **Architecture overview:** `docs/architecture-masterdoc.md` — especially Part 6 (Cron System) for how cronjobs work, and Part 8 (Operations) for the nightly reset pattern
3. **Current cronjobs:** Read all files in `cronjobs/` — these are the YAML definitions that get pushed to the bot via `openclaw cron add`. Key ones: `nightly-reset-prep.yaml`, `nightly-reset-execute.yaml`, `nightly-reset-wake.yaml`, `morning-briefing.yaml`
4. **Existing patterns in lib.sh:** `tools/lib.sh` — see `get_content_pipeline_agents()` (lines 89-106) for the pattern of querying agents by flag. You'll add similar `get_reset_agents()` / `get_wake_agents()` functions.
5. **How push works:** `tools/push.sh` — check how it handles cronjob files to understand where generated YAML needs to go
6. **Overall plan:** This is Phase 3 of a 4-phase roadmap. Phases 1-2 made prompts config-driven. This phase does the same for cronjobs. Phase 4 scrubs git history.

## Goal

Make cronjob agent lists config-driven instead of hardcoded. Create a generation script that reads agent participation from config.yaml and produces the YAML cronjob files. Also templatize the "<REDACTED-NAME>" reference in morning-briefing.yaml.

## Context

### Current hardcoded agent references in cronjobs/

These files reference specific agent names in their `message:` blocks:

| File | Hardcoded agents |
|------|------------------|
| `nightly-reset-prep.yaml` | bruba-main, bruba-guru, bruba-rex |
| `nightly-reset-execute.yaml` | bruba-main, bruba-guru, bruba-rex |
| `nightly-reset-wake.yaml` | bruba-main, bruba-guru, bruba-web, bruba-rex |
| `nightly-reset-manager.yaml` | bruba-manager (via bruba-main) |
| `morning-briefing.yaml` | "briefing for <REDACTED-NAME>" (hardcoded name) |

The non-nightly files (reminder-check, staleness-check, calendar-prep) only reference bruba-manager and don't need templating.

### Design approach

Add per-agent flags to config.yaml:
```yaml
agents:
  bruba-main:
    reset_cycle: true    # Include in nightly reset (prep + execute)
    wake_cycle: true     # Include in post-reset wake
  bruba-guru:
    reset_cycle: true
    wake_cycle: true
  bruba-web:
    # No reset_cycle (stateless, no continuation needed)
    wake_cycle: true
  bruba-rex:
    reset_cycle: true
    wake_cycle: true
  bruba-manager:
    # Manager is reset separately by nightly-reset-manager.yaml
```

Create `tools/generate-cronjobs.sh` that:
1. Reads reset/wake agent lists from config
2. Generates the `message:` blocks with proper `sessions_send` lines
3. Writes to `assembled/cronjobs/` (gitignored)
4. Push mechanism picks up from assembled/ instead of cronjobs/

Also add `identity.human_name` to the morning-briefing agent (bruba-manager doesn't have it yet — add it, or use a global variable, or just template the briefing to use a variable).

## Files to Modify/Create

### 1. `config.yaml` — Add reset_cycle/wake_cycle flags

Under each agent, add the appropriate flags:
```yaml
  bruba-main:
    reset_cycle: true
    wake_cycle: true
    # ... existing config

  bruba-manager:
    # No reset/wake flags (reset separately)

  bruba-web:
    wake_cycle: true
    # ... existing config

  bruba-guru:
    reset_cycle: true
    wake_cycle: true
    # ... existing config

  bruba-rex:
    reset_cycle: true
    wake_cycle: true
    # ... existing config
```

Also add identity to bruba-manager for morning briefing:
```yaml
  bruba-manager:
    identity:
      human_name: "<REDACTED-NAME>"
    # ... existing config
```

### 2. `config.yaml.example` — Document new flags

Add comments under agent blocks:
```yaml
    # Nightly reset cycle participation
    # reset_cycle: true    # Include in nightly reset prep + execute
    # wake_cycle: true     # Include in post-reset wake
```

### 3. `tools/lib.sh` — Add helper functions

```bash
# Get agents with reset_cycle: true
get_reset_agents() {
    local config_file="$ROOT_DIR/config.yaml"
    python3 -c "
import yaml, sys
try:
    with open('$config_file') as f:
        config = yaml.safe_load(f)
    for name, cfg in config.get('agents', {}).items():
        if cfg.get('reset_cycle', False):
            print(name)
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null
}

# Get agents with wake_cycle: true
get_wake_agents() {
    local config_file="$ROOT_DIR/config.yaml"
    python3 -c "
import yaml, sys
try:
    with open('$config_file') as f:
        config = yaml.safe_load(f)
    for name, cfg in config.get('agents', {}).items():
        if cfg.get('wake_cycle', False):
            print(name)
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null
}
```

### 4. Move current cronjobs to `templates/cronjobs/`

```bash
mkdir -p templates/cronjobs
cp cronjobs/nightly-reset-prep.yaml templates/cronjobs/
cp cronjobs/nightly-reset-execute.yaml templates/cronjobs/
cp cronjobs/nightly-reset-wake.yaml templates/cronjobs/
cp cronjobs/morning-briefing.yaml templates/cronjobs/
```

Keep the non-templated ones (reminder-check, staleness-check, calendar-prep, nightly-reset-manager) in `cronjobs/` as-is — they don't need generation.

### 5. Create `tools/generate-cronjobs.sh`

Script that:
1. Sources lib.sh, loads config
2. Reads reset/wake agent lists
3. For each template in `templates/cronjobs/`:
   - `nightly-reset-prep.yaml`: Generate numbered `sessions_send` lines for each reset agent with continuation packet instructions
   - `nightly-reset-execute.yaml`: Generate numbered `sessions_send` lines for each reset agent with `/reset`
   - `nightly-reset-wake.yaml`: Generate numbered `sessions_send` lines for each wake agent with good morning message (reset agents get CONTINUATION.md hint, non-reset agents get plain wake)
   - `morning-briefing.yaml`: Replace `<REDACTED-NAME>` with manager's HUMAN_NAME
4. Writes generated files to `assembled/cronjobs/`
5. Copies non-templated cronjobs from `cronjobs/` to `assembled/cronjobs/`

**Key detail:** The message blocks in the generated YAML must match the current format exactly:
- Numbered steps: `1. sessions_send to agent:NAME:main: "message"`
- Continuation packet message for prep (reset agents only)
- `/reset` message for execute (reset agents only)
- Good morning message for wake (all wake agents, with CONTINUATION.md hint for reset agents)

### 6. Update push mechanism

Check `tools/push.sh` to see where it reads cronjobs from. Update it to read from `assembled/cronjobs/` instead of `cronjobs/`. Or have generate-cronjobs.sh write directly to `cronjobs/` and gitignore the generated ones.

**Simpler approach:** Have generate-cronjobs.sh overwrite the files in `cronjobs/` directly. The templates live in `templates/cronjobs/` as the source of truth. Running generate produces the final YAML. Gitignore the generated files in `cronjobs/` (nightly-reset-prep, nightly-reset-execute, nightly-reset-wake, morning-briefing). Keep the non-generated ones tracked.

### 7. Update `.gitignore`

Add:
```
cronjobs/nightly-reset-prep.yaml
cronjobs/nightly-reset-execute.yaml
cronjobs/nightly-reset-wake.yaml
cronjobs/morning-briefing.yaml
```

Or use `assembled/cronjobs/` pattern instead if you prefer keeping generated output separate.

## Verification

1. **Generate cronjobs:**
   ```bash
   ./tools/generate-cronjobs.sh --verbose
   ```

2. **Diff against current:**
   ```bash
   diff cronjobs/nightly-reset-prep.yaml /tmp/pre-phase3/nightly-reset-prep.yaml
   diff cronjobs/nightly-reset-execute.yaml /tmp/pre-phase3/nightly-reset-execute.yaml
   diff cronjobs/nightly-reset-wake.yaml /tmp/pre-phase3/nightly-reset-wake.yaml
   ```
   Expected: identical content.

3. **Test push still works** (dry-run if available)

4. **Commit:**
   Commit message: "Phase 3: config-driven cronjob generation"

## Results Packet

After completing, write `docs/packets/phase3-results.md`:

```markdown
# Phase 3 Results: Config-Driven Cronjobs

## Status: COMPLETE

## What was done
- [ ] config.yaml: added reset_cycle/wake_cycle flags per agent
- [ ] config.yaml: added identity to bruba-manager
- [ ] config.yaml.example: documented new flags
- [ ] lib.sh: added get_reset_agents() and get_wake_agents()
- [ ] templates/cronjobs/: moved template sources
- [ ] tools/generate-cronjobs.sh: created generation script
- [ ] .gitignore: excluded generated cronjob files
- [ ] push mechanism updated to use generated files

## Verification results
- Generated cronjobs diff: [PASS/FAIL — identical to originals]
- Push dry-run: [PASS/FAIL]
- Commit hash: [hash]

## Notes for Phase 4
- All hardcoded names, UUIDs, and agent lists are now config-driven
- Ready for git history scrub
- Remaining hardcoded sensitive data in git-tracked files:
  - config.yaml bindings section: phone numbers (these are in .gitignore? Check!)
  - config.yaml identity blocks: names/UUIDs (acceptable — config.yaml is gitignored)
```
