# Packet: Phase C - Exec-Approvals Automation

**Created:** 2026-01-31
**From:** Claude Code
**For:** Bruba
**Priority:** HIGH
**Depends on:** Phase B (tools must be synced first)

---

## Goal

Automate exec-approvals allowlist updates when component tools change.

## Problem

Currently requires manual ssh + jq:
```bash
ssh bruba 'cat ~/.clawdbot/exec-approvals.json | jq ... > /tmp/ea.json && mv ...'
```

This is:
- Error-prone (jq syntax)
- Easy to forget after adding tools
- No way to know what is needed vs what is present

## Deliverables

1. **Create `tools/update-allowlist.sh`**:
   - Read required allowlist entries from component metadata
   - Compare with current bot allowlist
   - Add missing entries
   - Report what was added/already present

2. **Create component allowlist metadata format**:
   - `components/*/allowlist.json` with required entries
   - Example:
     ```json
     {
       "entries": [
         {"pattern": "/Users/bruba/clawd/tools/web-search.sh", "id": "web-search-wrapper"}
       ]
     }
     ```

3. **Integration options** (pick one):
   - Standalone `/allowlist` skill
   - Part of `/push` with `--update-allowlist` flag
   - Automatic after tool sync

## Files to Create/Modify

New:
- `tools/update-allowlist.sh`
- `components/voice/allowlist.json`
- `components/web-search/allowlist.json`
- `components/reminders/allowlist.json`

Optional:
- `.claude/commands/allowlist.md` (if standalone skill)

## Verification

- [ ] Running script shows current vs required entries
- [ ] Missing entries are added automatically
- [ ] Existing entries are preserved (not duplicated)
- [ ] Daemon restart reminder shown if changes made

---

## End of Packet
