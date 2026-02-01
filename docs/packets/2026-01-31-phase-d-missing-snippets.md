# Packet: Phase D - Missing Prompt Snippets

**Created:** 2026-01-31
**From:** Claude Code
**For:** Bruba
**Priority:** MEDIUM
**Depends on:** Phase A (documentation clarity)

---

## Goal

Create missing AGENTS.snippet.md files for components that have tools but no prompt content.

## Problem

Two components have tools deployed but no prompt instructions:
- **web-search**: Has tools, no snippet - Bruba doesn't know how to use web search
- **reminders**: Has tools, no snippet - Bruba doesn't know about cleanup script

## Deliverables

1. **Create `components/web-search/prompts/AGENTS.snippet.md`**:
   - Explain web search via sandboxed reader agent
   - Document web-search.sh wrapper usage
   - Security model (why indirect access)

2. **Create `components/reminders/prompts/AGENTS.snippet.md`**:
   - Document remindctl usage (already in exec-approvals)
   - Explain cleanup-reminders.sh for maintenance
   - Best practices for reminder management

3. **Add to exports.yaml agents_sections**:
   - Add `web-search` entry (before or after tools section)
   - Add `reminders` entry

4. **Delete claude-code placeholder**:
   - Remove `components/claude-code/` directory entirely

## Files to Create/Modify

New:
- `components/web-search/prompts/AGENTS.snippet.md`
- `components/reminders/prompts/AGENTS.snippet.md`

Modify:
- `exports.yaml` (add to agents_sections)

Delete:
- `components/claude-code/` (empty placeholder)

## Verification

- [ ] Both new snippets exist and have content
- [ ] `./tools/assemble-prompts.sh` includes new sections
- [ ] New sections appear in assembled AGENTS.md
- [ ] claude-code directory removed
- [ ] No broken references to deleted component

---

## End of Packet
