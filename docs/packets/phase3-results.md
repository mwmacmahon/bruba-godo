# Phase 3 Results: Config-Driven Cronjobs

## Status: COMPLETE

## What was done
- [x] config.yaml: added reset_cycle/wake_cycle flags per agent
- [x] config.yaml: added continuation_type: technical for bruba-guru
- [x] config.yaml.example: documented new flags (reset_cycle, wake_cycle, continuation_type)
- [x] lib.sh: added get_reset_agents() and get_wake_agents()
- [x] templates/cronjobs/: created template sources (4 files with {{AGENT_MESSAGES}} / {{HUMAN_NAME}} placeholders)
- [x] tools/generate-cronjobs.sh: created generation script
- [x] .gitignore: excluded generated cronjob files (4 entries)
- [x] bruba-manager identity: already had human_name: "<REDACTED-NAME>" from Phase 2 — no change needed

## Push mechanism: no change needed

`tools/push.sh` does not handle cronjob files — they're pushed separately via `openclaw cron add`. The generated files in `cronjobs/` are the same YAML definitions used by that command. No push changes required.

## Verification results

- **nightly-reset-prep.yaml**: IDENTICAL to pre-phase3 baseline
- **nightly-reset-execute.yaml**: IDENTICAL to pre-phase3 baseline
- **morning-briefing.yaml**: IDENTICAL to pre-phase3 baseline
- **nightly-reset-wake.yaml**: DIFFERS — agent ordering only (see below)

## Known diff: wake agent ordering

The original hand-crafted `nightly-reset-wake.yaml` listed agents as:
1. bruba-main, 2. bruba-guru, 3. bruba-web, 4. bruba-rex

The generated version lists them in config.yaml iteration order:
1. bruba-main, 2. bruba-web, 3. bruba-guru, 4. bruba-rex

This is semantically equivalent — all agents get woken up in the same isolated session; the order of `sessions_send` calls doesn't matter. The correct CONTINUATION.md hint is still applied (reset agents get it, bruba-web doesn't).

## Design decisions

### 1. continuation_type config field

The original `nightly-reset-prep.yaml` had agent-specific prep messages:
- bruba-main/bruba-rex: "Session Summary, In Progress, Open Questions, Next Steps"
- bruba-guru: "Technical Session Summary, In Progress (debugging/analysis), Open Questions (technical), Handoff Notes"

To preserve this distinction while being config-driven, added `continuation_type: technical` to bruba-guru. The script has two built-in message templates (standard and technical) and selects based on this field.

### 2. Template structure

Templates contain everything except the generated message lines:
- Static YAML (name, schedule, execution) stays in the template
- `{{AGENT_MESSAGES}}` placeholder marks where generated `sessions_send` lines go
- `{{HUMAN_NAME}}` in morning-briefing gets substituted with bruba-manager's identity.human_name

### 3. Environment variable substitution

Initially used Python triple-quoted strings for multi-line substitution, but this caused quoting issues (extra newlines). Switched to passing content via environment variables (`TMPL` and `MSGS`) to Python, which handles multi-line strings cleanly.

### 4. No assembled/ directory

The packet offered two approaches: write to `assembled/cronjobs/` or write directly to `cronjobs/`. Went with the simpler approach — generate-cronjobs.sh writes directly to `cronjobs/`, and the generated files are gitignored. Templates in `templates/cronjobs/` are the source of truth.

## Files modified/created

| File | Action | Description |
|------|--------|-------------|
| config.yaml | modified | Added reset_cycle, wake_cycle, continuation_type flags |
| config.yaml.example | modified | Documented new flags |
| tools/lib.sh | modified | Added get_reset_agents(), get_wake_agents() |
| tools/generate-cronjobs.sh | created | Cronjob generation script |
| templates/cronjobs/nightly-reset-prep.yaml | created | Template |
| templates/cronjobs/nightly-reset-execute.yaml | created | Template |
| templates/cronjobs/nightly-reset-wake.yaml | created | Template |
| templates/cronjobs/morning-briefing.yaml | created | Template |
| .gitignore | modified | Added 4 generated cronjob entries |

## Notes for Phase 4
- All hardcoded names, UUIDs, and agent lists are now config-driven
- Ready for git history scrub
- Remaining hardcoded sensitive data in git-tracked files:
  - config.yaml: names, UUIDs, phone numbers — gitignored, not in history
  - components/message-tool/README.md: hardcoded <REDACTED-NAME> + UUID — developer docs, will become \<REDACTED\> after filter-repo (acceptable)
  - cronjobs/morning-briefing.yaml: was "<REDACTED-NAME>", now generated (gitignored)
- Commit hash: (not yet committed)
