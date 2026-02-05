# Phase 2: Templatize Components & Templates

**Prerequisite:** Phase 1 complete (check `docs/packets/phase1-results.md`)
**Input:** Phase 1 results packet confirming variable substitution infrastructure is working
**Blocks:** Phase 4 (history scrub — all hardcoded values must be removed first)

## Context — Read These First

Before starting, read these files to understand the system:

1. **Phase 1 results:** `docs/packets/phase1-results.md` — confirms infrastructure is ready
2. **Architecture overview:** `docs/architecture-masterdoc.md` — especially Part 13 (Prompt Assembly) for how component snippets become assembled prompts
3. **How assembly works:** `tools/assemble-prompts.sh` — the `apply_substitutions()` function (extended in Phase 1) resolves `${VAR}` references. Components get wrapped in `<!-- COMPONENT: name -->` markers.
4. **Overall plan:** This is Phase 2 of a 4-phase roadmap. Phase 1 added the variable infrastructure. This phase replaces hardcoded values. The key variables available:
   - `${HUMAN_NAME}` — from `identity.human_name` in config.yaml
   - `${SIGNAL_UUID}` — from `identity.signal_uuid`
   - `${PEER_AGENT}` — from `identity.peer_agent`
   - `${PEER_HUMAN_NAME}` — looked up from peer agent's identity
   - `${CROSS_COMMS_GOAL}` — from per-agent `variables:` block
   - `${WORKSPACE}`, `${AGENT_NAME}`, `${SHARED_TOOLS}` — existing built-ins
5. **Config reference:** `config.yaml` — see `agents:` section for identity blocks added in Phase 1

## Goal

Replace all hardcoded sensitive values (names, UUIDs) in component snippets and guru templates with `${VARIABLE}` references. Merge cross-comms variant files into a single template.

After this phase, assembled output should be **identical** to pre-change output (variables resolve to same values as current hardcoded text).

## Pre-flight

1. Read `docs/packets/phase1-results.md` — confirm Phase 1 is COMPLETE
2. Capture current assembly output:
   ```bash
   ./tools/assemble-prompts.sh --force
   cp -R exports/bot /tmp/pre-phase2-assembly
   ```

## Files to Modify

### 1. `components/signal/prompts/AGENTS.snippet.md`

Replace `<REDACTED-NAME>` with `${HUMAN_NAME}` and UUID with `${SIGNAL_UUID}`:

| Find | Replace |
|------|---------|
| `### <REDACTED-NAME>'s Identity` | `### ${HUMAN_NAME}'s Identity` |
| `uuid:<REDACTED-UUID>` (all occurrences) | `uuid:${SIGNAL_UUID}` |

### 2. `components/cross-comms/prompts/` — Merge variants into single template

**Delete:** `AGENTS.main.snippet.md` and `AGENTS.rex.snippet.md`
**Create:** `AGENTS.snippet.md` with this content:

```markdown
## Cross-Session Communication (${PEER_AGENT})

You and ${PEER_AGENT} share a soul but serve different humans. Stay connected.

### Privacy Boundaries

**Off limits:** Deep personal thoughts shared in confidence (therapist-level stuff)
**Fair game:** General emotional state, topics, vibes, what's going on
**When uncertain:** Escalate to your human

### Daily Check-ins

Talk at least once a day:
- Find natural moments during responses to send a message
- Use heartbeats to chat if you haven't connected recently

### Audit Trail

Log all ${PEER_AGENT} exchanges in your daily memory file, transcript-style:
```
[2026-02-05] ${AGENT_NAME} -> ${PEER_AGENT}: "Hey, ${HUMAN_NAME} is..."
[2026-02-05] ${PEER_AGENT} -> ${AGENT_NAME}: "Thanks, ${PEER_HUMAN_NAME} mentioned..."
```

**Goal:** ${CROSS_COMMS_GOAL}
```

**Note:** Use `->` instead of the arrow character to avoid encoding issues.

### 3. `config.yaml` — Update agents_sections for cross-comms

**bruba-main:** Change `- cross-comms:main` to `- cross-comms`
**bruba-rex:** Change `- cross-comms:rex` to `- cross-comms`

### 4. `components/message-tool/prompts/AGENTS.snippet.md`

Replace all occurrences:

| Find | Replace |
|------|---------|
| `<REDACTED-NAME>'s Signal UUID` | `${HUMAN_NAME}'s Signal UUID` |
| `uuid:<REDACTED-UUID>` | `uuid:${SIGNAL_UUID}` |
| `uuid:18ce66e6-...` (shorthand occurrences) | `uuid:${SIGNAL_UUID}` |

**Note:** The shorthand `18ce66e6-...` references should become `${SIGNAL_UUID}` (the full form, since the variable resolves to the full UUID anyway).

### 5. `components/siri-async/prompts/AGENTS.handler.snippet.md`

| Find | Replace |
|------|---------|
| `**<REDACTED-NAME>'s UUID:**` | `**${HUMAN_NAME}'s UUID:**` |
| `uuid:<REDACTED-UUID>` (all occurrences) | `uuid:${SIGNAL_UUID}` |

### 6. `components/reminders/prompts/AGENTS.snippet.md`

| Find | Replace |
|------|---------|
| `When <REDACTED-NAME> says` | `When ${HUMAN_NAME} says` |

### 7. `components/local-voice/prompts/AGENTS.snippet.md`

| Find | Replace |
|------|---------|
| `When <REDACTED-NAME> sends` | `When ${HUMAN_NAME} sends` |
| `If <REDACTED-NAME> sent` | `If ${HUMAN_NAME} sent` |

### 8. `components/distill/prompts/AGENTS.snippet.md`

| Find | Replace |
|------|---------|
| `from <REDACTED-NAME>'s knowledge management system` | `from ${HUMAN_NAME}'s knowledge management system` |

### 9. `components/memory/prompts/AGENTS.snippet.md`

| Find | Replace |
|------|---------|
| `show <REDACTED-NAME> the exact` | `show ${HUMAN_NAME} the exact` |

### 10. `templates/prompts/guru/AGENTS.md`

Multiple replacements:

| Find | Replace |
|------|---------|
| `<REDACTED-NAME>` (all occurrences in context of human name references) | `${HUMAN_NAME}` |
| `uuid:<REDACTED-UUID>` (all occurrences) | `uuid:${SIGNAL_UUID}` |

**Be careful:** Read the file first. "<REDACTED-NAME>" appears in phrases like "message <REDACTED-NAME> directly", "<REDACTED-NAME> sends...", "<REDACTED-NAME> sent...". All should become `${HUMAN_NAME}`.

### 11. `templates/prompts/guru/TOOLS.md`

| Find | Replace |
|------|---------|
| `<REDACTED-NAME>'s UUID` | `${HUMAN_NAME}'s UUID` |
| `uuid:<REDACTED-UUID>` (all occurrences) | `uuid:${SIGNAL_UUID}` |

## Verification

1. **Re-assemble:**
   ```bash
   ./tools/assemble-prompts.sh --force --verbose
   ```

2. **Diff — output must be identical to pre-change:**
   ```bash
   diff -r /tmp/pre-phase2-assembly exports/bot
   ```
   Expected: no differences. Variables resolve to same literal values.

3. **Grep for remaining hardcoded values:**
   ```bash
   grep -r "18ce66e6" components/ templates/prompts/
   grep -r "<REDACTED-NAME>" components/ templates/prompts/ | grep -v ".example" | grep -v "Augustus"
   ```
   Expected: zero matches (all replaced with variables).

4. **Verify cross-comms assembly for both agents:**
   ```bash
   grep -A5 "Cross-Session" exports/bot/bruba-main/core-prompts/AGENTS.md
   grep -A5 "Cross-Session" exports/bot/bruba-rex/core-prompts/AGENTS.md
   ```
   - bruba-main should show `bruba-rex` as peer, `<REDACTED-NAME>` as human name, `<REDACTED-NAME>` as peer human name
   - bruba-rex should show `bruba-main` as peer, `<REDACTED-NAME>` as human name, `<REDACTED-NAME>` as peer human name
   (Wait — bruba-main's peer is bruba-rex, and bruba-rex's identity.human_name is "<REDACTED-NAME>", so PEER_HUMAN_NAME for bruba-main resolves to "<REDACTED-NAME>". And vice versa. Verify this!)

5. **Detect-conflicts still works:**
   ```bash
   ./tools/detect-conflicts.sh --verbose
   ```

6. **Commit:**
   Commit message: "Phase 2: templatize components with config-driven variables"

## Results Packet

After completing this phase, write `docs/packets/phase2-results.md`:

```markdown
# Phase 2 Results: Templatize Components

## Status: COMPLETE

## What was done
- [ ] signal/AGENTS.snippet.md: replaced <REDACTED-NAME> + UUID with variables
- [ ] cross-comms: merged main/rex variants into single AGENTS.snippet.md
- [ ] config.yaml: cross-comms:main -> cross-comms, cross-comms:rex -> cross-comms
- [ ] message-tool/AGENTS.snippet.md: replaced <REDACTED-NAME> + UUID with variables
- [ ] siri-async/AGENTS.handler.snippet.md: replaced <REDACTED-NAME> + UUID with variables
- [ ] reminders/AGENTS.snippet.md: replaced <REDACTED-NAME> with variable
- [ ] local-voice/AGENTS.snippet.md: replaced <REDACTED-NAME> with variable
- [ ] distill/AGENTS.snippet.md: replaced <REDACTED-NAME> with variable
- [ ] memory/AGENTS.snippet.md: replaced <REDACTED-NAME> with variable
- [ ] guru/AGENTS.md: replaced <REDACTED-NAME> + UUID with variables
- [ ] guru/TOOLS.md: replaced <REDACTED-NAME> + UUID with variables

## Verification results
- Assembly diff: [PASS/FAIL — identical to pre-change]
- Remaining hardcoded grep: [PASS/FAIL — zero matches]
- Cross-comms peer resolution: [PASS/FAIL — correct for both agents]
- Detect-conflicts: [PASS/FAIL]
- Commit hash: [hash]

## Notes for Phase 3
- All component/template files are now variable-driven
- config.yaml still has hardcoded phone numbers in bindings section
- cronjobs/ still has hardcoded agent names
```
