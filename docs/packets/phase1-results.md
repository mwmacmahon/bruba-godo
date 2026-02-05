# Phase 1 Results: Variable Substitution Infrastructure

## Status: COMPLETE

## What was done
- [x] config.yaml: added identity + variables blocks to bruba-main, bruba-guru, bruba-rex
- [x] config.yaml.example: added documented placeholders
- [x] lib.sh: extended load_agent_config() with identity/variables extraction
- [x] assemble-prompts.sh: extended apply_substitutions() with new variables
- [x] detect-conflicts.sh: mirrored apply_substitutions() changes

## Variables now available
- ${HUMAN_NAME} - from identity.human_name
- ${SIGNAL_UUID} - from identity.signal_uuid
- ${PEER_AGENT} - from identity.peer_agent
- ${PEER_HUMAN_NAME} - looked up from peer agent's identity
- ${CROSS_COMMS_GOAL} - from per-agent variables block
- (Any arbitrary key in agent's variables: block)

## Implementation note

The packet spec used sed args for custom variable substitution, but this breaks on multi-word values (shell word-splitting). Replaced with Python-based substitution via environment variable (`VARS`) — same semantics, works with any value content.

## Verification results
- Assembly diff: PASS - no differences (new variables exist but no templates use them yet)
- Detect-conflicts: PASS - runs correctly, 3 pre-existing conflicts (group-chats, reminders) unrelated to changes
- Commit hash: 7f2689b

## Notes for Phase 2
- All infrastructure is ready. Phase 2 can replace hardcoded values with ${VAR} references.
- No templates use the new variables yet - assembly output is unchanged.
