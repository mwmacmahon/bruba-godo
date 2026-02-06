# Web Search Component

**Status:** Prompt Ready

Web research delegation via bruba-web agent. Provides consumer-side instructions for agents that need web research (bruba-main, bruba-rex) telling them how to call bruba-web via `sessions_send`.

## Architecture

bruba-web is a **peer agent** (not a subagent). It runs in its own session with dedicated web tools (`web_search`, `web_fetch`) and strict security isolation. Calling agents send requests via `sessions_send` and receive structured results back.

bruba-web's own system prompt lives in `templates/prompts/web/AGENTS.md`, assembled via the `web-base` section type.

## Files

```
components/web-search/
├── README.md
└── prompts/
    └── AGENTS.snippet.md    # Consumer snippet for main/rex
```

## Usage

Add `web-search` to `agents_sections` in config.yaml for any agent that needs web research:

```yaml
agents:
  my-agent:
    agents_sections:
      # ...
      - web-search    # How to use bruba-web
```

## No Tools or Allowlist

This is a prompt-only component. bruba-web's tools (`web_search`, `web_fetch`) are OpenClaw built-ins configured via `tools_allow` in config.yaml, not exec scripts.
