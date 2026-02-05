# Phase 1: Variable Substitution Infrastructure

**Prerequisite:** None (first phase)
**Depends on:** Nothing
**Blocks:** Phase 2 (templatize components)

## Context — Read These First

Before starting, read these files to understand the system:

1. **Architecture overview:** `docs/architecture-masterdoc.md` — especially Part 1 (Agent Topology) and Part 13 (Prompt Assembly and Components). This explains the five-agent architecture and how prompt assembly works.
2. **Overall plan:** `docs/packets/phase1-variable-substitution.md` is Phase 1 of a 4-phase roadmap to make agent identity config-driven and remove personally-identifying info from git-tracked files. The full roadmap:
   - Phase 1 (this): Variable substitution infrastructure
   - Phase 2 (`docs/packets/phase2-templatize-components.md`): Replace hardcoded names/UUIDs with `${VAR}` refs in ~11 files
   - Phase 3 (`docs/packets/phase3-cronjob-generation.md`): Config-driven cronjob generation
   - Phase 4 (`docs/packets/phase4-history-scrub.md`): `git filter-repo` to scrub git history
3. **Files you'll modify:**
   - `tools/lib.sh` — shared functions, especially `load_agent_config()` (lines 112-147)
   - `tools/assemble-prompts.sh` — prompt assembly, especially `apply_substitutions()` (lines 75-81)
   - `tools/detect-conflicts.sh` — conflict detection, especially `apply_substitutions()` (lines 72-81)
   - `config.yaml` — agent configuration (gitignored, not committed)
   - `config.yaml.example` — documented template (committed)

## Goal

Extend the existing `apply_substitutions()` system to support user-defined variables from config.yaml. After this phase, the assembly pipeline can resolve `${HUMAN_NAME}`, `${SIGNAL_UUID}`, `${PEER_AGENT}`, `${PEER_HUMAN_NAME}`, and arbitrary per-agent `${VARIABLE}` references — but no templates use them yet.

## Context

The current `apply_substitutions()` (in both `assemble-prompts.sh:75-81` and `detect-conflicts.sh:72-81`) handles exactly three variables:
```bash
echo "$content" | sed \
    -e "s|\${WORKSPACE}|$AGENT_WORKSPACE|g" \
    -e "s|\${AGENT_NAME}|$AGENT_NAME|g" \
    -e "s|\${SHARED_TOOLS}|$SHARED_TOOLS|g"
```

We need to extend this with identity-derived and custom variables loaded from config.yaml per-agent.

## Config Schema

Add two new blocks under each agent in config.yaml:

```yaml
agents:
  bruba-main:
    identity:
      human_name: "<REDACTED-NAME>"
      signal_uuid: "<REDACTED-UUID>"
      peer_agent: "bruba-rex"
    variables:
      CROSS_COMMS_GOAL: "Be siblings who actually talk, not strangers who happen to share a SOUL.md."
    # ... existing fields unchanged

  bruba-rex:
    identity:
      human_name: "<REDACTED-NAME>"
      peer_agent: "bruba-main"
    variables:
      CROSS_COMMS_GOAL: "Be siblings who actually talk, not strangers who happen to share a SOUL.md."
    # ... existing fields unchanged
```

Agents without identity blocks (bruba-manager, bruba-helper, bruba-web, bruba-guru) get empty defaults — their templates don't use these variables (yet). bruba-guru uses HUMAN_NAME and SIGNAL_UUID in its templates, so give it identity too:

```yaml
  bruba-guru:
    identity:
      human_name: "<REDACTED-NAME>"
      signal_uuid: "<REDACTED-UUID>"
    # ... existing fields unchanged
```

**Auto-derived variables from identity:**
- `${HUMAN_NAME}` ← `identity.human_name` of current agent
- `${SIGNAL_UUID}` ← `identity.signal_uuid` of current agent
- `${PEER_AGENT}` ← `identity.peer_agent` of current agent
- `${PEER_HUMAN_NAME}` ← looked up from peer agent's `identity.human_name`

**Resolution order:** built-in (`WORKSPACE`, `AGENT_NAME`, `SHARED_TOOLS`) -> identity-derived -> per-agent variables (last wins).

## Files to Modify

### 1. `config.yaml` — Add identity + variables blocks

Add `identity:` and `variables:` blocks to bruba-main, bruba-rex, and bruba-guru. Other agents don't need them yet.

**bruba-main** (after `workspace:`, before `content_pipeline:`):
```yaml
    identity:
      human_name: "<REDACTED-NAME>"
      signal_uuid: "<REDACTED-UUID>"
      peer_agent: "bruba-rex"
    variables:
      CROSS_COMMS_GOAL: "Be siblings who actually talk, not strangers who happen to share a SOUL.md."
```

**bruba-guru** (after `workspace:`, before `prompts:`):
```yaml
    identity:
      human_name: "<REDACTED-NAME>"
      signal_uuid: "<REDACTED-UUID>"
```

**bruba-rex** (after `workspace:`, before `content_pipeline:`):
```yaml
    identity:
      human_name: "<REDACTED-NAME>"
      peer_agent: "bruba-main"
    variables:
      CROSS_COMMS_GOAL: "Be siblings who actually talk, not strangers who happen to share a SOUL.md."
```

### 2. `config.yaml.example` — Add documented placeholders

Under the `<agent-id>-main:` block, after `workspace:` and before `prompts:`, add:
```yaml
    # Per-agent identity (used for variable substitution in prompts)
    # identity:
    #   human_name: "<human-name>"           # Name of the human this agent serves
    #   signal_uuid: "<signal-uuid>"         # Human's Signal UUID (without uuid: prefix)
    #   peer_agent: "<agent-id>-user2"       # Cross-comms peer agent ID
    # Per-agent template variables (arbitrary, substituted as ${KEY} in prompts)
    # variables:
    #   CROSS_COMMS_GOAL: "Custom guidance for cross-agent communication"
```

### 3. `tools/lib.sh` — Extend `load_agent_config()` (lines 112-147)

**Step A:** Extend the Python `json.dumps()` block to include identity and variables:

Current (line 128-133):
```python
    print(json.dumps({
        'workspace': agent.get('workspace'),
        'prompts': agent.get('prompts', []),
        'remote_path': agent.get('remote_path', 'memory'),
        'content_pipeline': agent.get('content_pipeline', False)
    }))
```

Change to:
```python
    all_agents = config.get('agents', {})
    identity = agent.get('identity', {})
    peer_id = identity.get('peer_agent', '')
    peer_agent = all_agents.get(peer_id, {})
    peer_identity = peer_agent.get('identity', {})
    print(json.dumps({
        'workspace': agent.get('workspace'),
        'prompts': agent.get('prompts', []),
        'remote_path': agent.get('remote_path', 'memory'),
        'content_pipeline': agent.get('content_pipeline', False),
        'identity': identity,
        'peer_human_name': peer_identity.get('human_name', ''),
        'variables': agent.get('variables', {})
    }))
```

**Step B:** After the existing shell variable extraction (lines 138-141), add extraction of identity + variables:

```bash
# Identity fields
AGENT_HUMAN_NAME=$(echo "$agent_data" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('identity',{}).get('human_name',''))" 2>/dev/null)
AGENT_SIGNAL_UUID=$(echo "$agent_data" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('identity',{}).get('signal_uuid',''))" 2>/dev/null)
AGENT_PEER_AGENT=$(echo "$agent_data" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('identity',{}).get('peer_agent',''))" 2>/dev/null)
AGENT_PEER_HUMAN_NAME=$(echo "$agent_data" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('peer_human_name',''))" 2>/dev/null)

# Build sed args for custom variables
AGENT_VARIABLE_SED_ARGS=$(echo "$agent_data" | python3 -c "
import json, sys, shlex
d = json.load(sys.stdin)
parts = []
for k, v in d.get('variables', {}).items():
    # Escape sed special chars in value
    escaped = str(v).replace('|', '\\\\|').replace('&', '\\\\&')
    parts.append('-e')
    parts.append('s|\${' + k + '}|' + escaped + '|g')
print(' '.join(parts))
" 2>/dev/null)
```

### 4. `tools/assemble-prompts.sh` — Extend `apply_substitutions()` (lines 75-81)

Change from:
```bash
apply_substitutions() {
    local content="$1"
    echo "$content" | sed \
        -e "s|\${WORKSPACE}|$AGENT_WORKSPACE|g" \
        -e "s|\${AGENT_NAME}|$AGENT_NAME|g" \
        -e "s|\${SHARED_TOOLS}|$SHARED_TOOLS|g"
}
```

To:
```bash
apply_substitutions() {
    local content="$1"
    local result
    result=$(echo "$content" | sed \
        -e "s|\${WORKSPACE}|$AGENT_WORKSPACE|g" \
        -e "s|\${AGENT_NAME}|$AGENT_NAME|g" \
        -e "s|\${SHARED_TOOLS}|$SHARED_TOOLS|g" \
        -e "s|\${HUMAN_NAME}|$AGENT_HUMAN_NAME|g" \
        -e "s|\${SIGNAL_UUID}|$AGENT_SIGNAL_UUID|g" \
        -e "s|\${PEER_AGENT}|$AGENT_PEER_AGENT|g" \
        -e "s|\${PEER_HUMAN_NAME}|$AGENT_PEER_HUMAN_NAME|g")
    # Apply custom per-agent variables
    if [[ -n "$AGENT_VARIABLE_SED_ARGS" ]]; then
        result=$(echo "$result" | sed $AGENT_VARIABLE_SED_ARGS)
    fi
    echo "$result"
}
```

### 5. `tools/detect-conflicts.sh` — Mirror the same change (lines 72-81)

The `apply_substitutions()` in detect-conflicts.sh takes a second `$workspace` parameter. Update it the same way:

Change from:
```bash
apply_substitutions() {
    local content="$1"
    local workspace="$2"
    echo "$content" | sed \
        -e "s|\${WORKSPACE}|$workspace|g" \
        -e "s|\${AGENT_NAME}|$AGENT_NAME|g" \
        -e "s|\${SHARED_TOOLS}|$SHARED_TOOLS|g"
}
```

To:
```bash
apply_substitutions() {
    local content="$1"
    local workspace="$2"
    local result
    result=$(echo "$content" | sed \
        -e "s|\${WORKSPACE}|$workspace|g" \
        -e "s|\${AGENT_NAME}|$AGENT_NAME|g" \
        -e "s|\${SHARED_TOOLS}|$SHARED_TOOLS|g" \
        -e "s|\${HUMAN_NAME}|$AGENT_HUMAN_NAME|g" \
        -e "s|\${SIGNAL_UUID}|$AGENT_SIGNAL_UUID|g" \
        -e "s|\${PEER_AGENT}|$AGENT_PEER_AGENT|g" \
        -e "s|\${PEER_HUMAN_NAME}|$AGENT_PEER_HUMAN_NAME|g")
    # Apply custom per-agent variables
    if [[ -n "$AGENT_VARIABLE_SED_ARGS" ]]; then
        result=$(echo "$result" | sed $AGENT_VARIABLE_SED_ARGS)
    fi
    echo "$result"
}
```

**IMPORTANT:** detect-conflicts.sh also calls `load_agent_config` (line 285) in its main loop, so it already gets the new identity variables.

## Verification

1. **Capture pre-change output:**
   ```bash
   ./tools/assemble-prompts.sh --force --verbose
   cp -R exports/bot /tmp/pre-change-assembly
   ```

2. **Make all changes, then re-assemble:**
   ```bash
   ./tools/assemble-prompts.sh --force --verbose
   ```

3. **Diff — output must be identical:**
   ```bash
   diff -r /tmp/pre-change-assembly exports/bot
   ```
   Expected: no differences (new variables exist but no templates use them yet).

4. **Verify detect-conflicts still works:**
   ```bash
   ./tools/detect-conflicts.sh --verbose
   ```

5. **Commit:**
   Commit message: "Phase 1: config-driven variable substitution infrastructure"

## Results Packet

After completing this phase, write `docs/packets/phase1-results.md` with:

```markdown
# Phase 1 Results: Variable Substitution Infrastructure

## Status: COMPLETE

## What was done
- [ ] config.yaml: added identity + variables blocks to bruba-main, bruba-guru, bruba-rex
- [ ] config.yaml.example: added documented placeholders
- [ ] lib.sh: extended load_agent_config() with identity/variables extraction
- [ ] assemble-prompts.sh: extended apply_substitutions() with new variables
- [ ] detect-conflicts.sh: mirrored apply_substitutions() changes

## Variables now available
- ${HUMAN_NAME} - from identity.human_name
- ${SIGNAL_UUID} - from identity.signal_uuid
- ${PEER_AGENT} - from identity.peer_agent
- ${PEER_HUMAN_NAME} - looked up from peer agent's identity
- ${CROSS_COMMS_GOAL} - from per-agent variables block
- (Any arbitrary key in agent's variables: block)

## Verification results
- Assembly diff: [PASS/FAIL - no differences expected]
- Detect-conflicts: [PASS/FAIL]
- Commit hash: [hash]

## Notes for Phase 2
- All infrastructure is ready. Phase 2 can replace hardcoded values with ${VAR} references.
- No templates use the new variables yet - assembly output is unchanged.
```
