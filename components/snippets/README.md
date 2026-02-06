# Snippets

Prompt-only components consolidated into a single directory using variant naming.

## What This Is

Small, self-contained prompt additions that don't need setup scripts, tools, or config.
Each snippet adds a section to a prompt file (currently all AGENTS.md).

## Available Variants

| Config name | Description |
|-------------|-------------|
| `snippets:continuity` | Continuation packet handling for session handoffs |
| `snippets:cross-comms` | Cross-session communication between peer agents |
| `snippets:emotional-intelligence` | Tone, empathy, and wellbeing guidelines |
| `snippets:group-chats` | Social behavior in group chat contexts |
| `snippets:heartbeats` | Proactive behavior on heartbeat polls |
| `snippets:memory` | Memory management workflow and file conventions |
| `snippets:message-tool` | Direct message tool (Signal delivery) documentation |
| `snippets:repo-reference` | Read-only bruba-godo repository access |
| `snippets:session` | Session startup workflow and greeting behavior |
| `snippets:siri-handler` | Siri async handler (Main processes forwarded requests) |
| `snippets:siri-router` | Siri async router (Manager forwards to Main) |
| `snippets:workspace` | Generated content paths and write permissions |

## Usage

In `config.yaml`, use `snippets:variant-name` in section lists:

```yaml
agents:
  my-agent:
    agents_sections:
      - header
      - snippets:session
      - snippets:continuity
      - snippets:memory
      # ...
```

## File Naming Convention

```
components/snippets/prompts/AGENTS.{variant-name}.snippet.md
```

The assembly system resolves `snippets:variant-name` to
`components/snippets/prompts/AGENTS.variant-name.snippet.md` automatically.

## Adding New Snippets

1. Create `components/snippets/prompts/AGENTS.{name}.snippet.md`
2. Add `snippets:{name}` to the relevant agents' `agents_sections` in config.yaml
3. Update this README
4. Run `./tools/assemble-prompts.sh --verbose` to verify
