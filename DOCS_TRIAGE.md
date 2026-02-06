# Documentation Triage

Analysis and action plan from the Packet 1 manifest (112 tracked markdown files). This document captures the findings, completed cleanups, and actionable plans for follow-up.

- **Date:** 2026-02-06
- **Source:** `DOCS_MANIFEST.md` observations

---

## 1. Completed Cleanups

- [x] **Deleted orphaned backup** — `components/distill/lib.bak/` (7 Python files, pre-refactor snapshot)
- [x] **Renamed for consistency** — `docs/bruba_web_docker_migration.md` → `docs/bruba-web-docker-migration.md`
- [x] **Updated DOCS_MANIFEST.md** — all 3 references to old filename corrected, resolved observations struck through

---

## 2. Masterdoc Split Plan

`docs/architecture-masterdoc.md` — 2187 lines, 90 KB, 14 parts. Too large for practical reference. Proposed split:

### Keep in masterdoc (~650 lines, core architecture)

These parts are tightly coupled and form the architectural foundation:

| Part | Lines | Topic |
|------|------:|-------|
| Part 1: Agent Topology | 84 | Foundational — everything depends on this |
| Part 2: Tool Policy Mechanics | 57 | Core design constraint |
| Part 3: Agent Specifications | 190 | Frequently referenced |
| Part 4: Communication Patterns | 233 | Tightly coupled to topology |
| Part 5: Heartbeat vs Cron | 68 | Key architectural decision |
| Quick Reference | 36 | Belongs with the architecture |
| Version History | 32 | Changelog for the doc |

### Extract to new/existing docs (~1340 lines)

| Part | Lines | Target | Notes |
|------|------:|--------|-------|
| Part 6: Cron System | 203 | `docs/cron-system.md` (new) | Self-contained operations reference |
| Part 7: Security Model | 394 | Merge into `docs/security-model.md` | Significant overlap expected |
| Part 8: Operations | 238 | Merge into `docs/operations-guide.md` | Same topic |
| Part 9: Troubleshooting | 86 | Merge into `docs/troubleshooting.md` | Same topic |
| Part 10: Configuration Reference | 163 | `docs/configuration-reference.md` (new) | Standalone reference |
| Part 13: Prompt Assembly | 127 | Already in `docs/prompt-management.md` | Deduplicate — compare and keep the better version |
| Part 14: Vault Mode | 75 | Already in `docs/vault-strategy.md` | Deduplicate — compare and keep the better version |

### Archive (stale or tracking, not architecture)

| Part | Lines | Recommendation |
|------|------:|----------------|
| Part 11: Known Issues | 100 | Move to `docs/known-issues.md` or track in GitHub Issues |
| Part 12: Implementation Status | 33 | Archive to `docs/cc_logs/` — project status checklist, not reference |
| Cost Estimates | 11 | Fold into operations guide |

### Cross-reference notes

After extraction, add cross-links:
- Part 7 (security) → references Part 2 (tool policy)
- Part 8 (operations) → references Part 7 (security)
- Part 6 (cron) → references Part 5 (heartbeat)
- Parts 1–5 are tightly coupled — keep together, don't split further

---

## 3. Navigation Consolidation Plan

**Problem:** `docs/README.md` and `docs/INDEX.md` both serve as navigation for `docs/`. Redundant and diverging.

**Decision: INDEX.md wins** — it has categorized tables and naming conventions.

### Merge from README.md into INDEX.md

1. **Task-based quick navigation** — the "What you need → Start here" table (README lines 12–19). Add as new top section in INDEX.md.
2. **Prose descriptions** — the 6 doc blurbs (README lines 25–41). Add as descriptions in INDEX.md table entries.
3. **Component links** — the Components section (README lines 52–59). Add as new "Components" subsection in INDEX.md.
4. **Frontmatter** — copy `type: doc`, `scope: reference` from README.md to INDEX.md so exports still work.

### Then delete `docs/README.md`

**Test impact:** `tests/test_export.py:136` uses `Path("docs/README.md")` as a test fixture for export routing (`type: doc` + `scope: reference` → routes to "docs" subdirectory). The test doesn't read the file, just routes the path. Update to use `Path("docs/INDEX.md")` after adding frontmatter to INDEX.md, or use any other `docs/` file with the same frontmatter.

---

## 4. Index Staleness Fixes

Changes needed in `docs/INDEX.md`:

### Missing entries

| File | Add under |
|------|-----------|
| `per-agent-pipeline.md` | Pipeline & Prompts |
| `bruba-web-docker-migration.md` | Technical Deep-Dives |
| `channel-integrations.md` | Core Documentation (or new section) |

### Ghost references

INDEX.md links to `cc_logs/` and `cc_logs/INDEX.md` — these are gitignored. Keep the references (the directory exists locally with content), but annotate:

```markdown
| [cc_logs/](cc_logs/) | Claude Code work logs *(gitignored — local only)* |
```

### Update timestamp

Change from `2026-02-03` to current date when executing.

---

## Execution Order

For the remaining work (steps 2–4), recommended order:

1. **Index staleness fixes** (step 4) — quick, no risk
2. **Navigation consolidation** (step 3) — merge README.md into INDEX.md, update test, delete README.md
3. **Masterdoc split** (step 2) — largest effort, do section-by-section with diff review

Each step is independent and can be done in a separate session.
