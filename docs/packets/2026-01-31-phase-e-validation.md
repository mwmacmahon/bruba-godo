# Packet: Phase E - Validation Tooling

**Created:** 2026-01-31
**From:** Claude Code
**For:** Bruba
**Priority:** LOW
**Depends on:** Phases A-D complete

---

## Goal

Create validation script to ensure component consistency going forward.

## Problem

Without validation, drift will recur:
- New tools added without allowlist entries
- New components without snippets
- README status becoming stale

## Deliverables

1. **Create `tools/validate-components.sh`**:

   Checks to perform:
   - Every component with tools/ has allowlist.json
   - Every allowlist.json entry exists in bot exec-approvals
   - Every component with snippet is in agents_sections
   - README status matches actual directory contents
   - No orphaned snippets (in dir but not in config)

2. **Output format**:
   ```
   Validating components...

   ✓ signal: Active (snippet, setup, validate)
   ✓ voice: Partial (snippet, tools, allowlist)
   ✗ web-search: Missing snippet in agents_sections

   Summary: 14 OK, 1 warning, 1 error
   ```

3. **Integration**:
   - Add to CI/pre-commit if applicable
   - Run before `/push` to catch issues early

## Files to Create

- `tools/validate-components.sh`

## Verification

- [ ] Script runs without errors on current state
- [ ] Detects intentionally broken component
- [ ] Clear output showing what passed/failed
- [ ] Exit code reflects validation result

---

## End of Packet
