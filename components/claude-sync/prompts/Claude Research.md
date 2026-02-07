---
type: prompt
scope: meta
title: "Claude Research"
output_name: "Claude Research"
---

# Claude Research

Send research questions to Claude.ai Project conversations via browser automation. Each project has persistent context (uploaded docs, prior conversations) making it ideal for domain-specific research.

## How to Use

```json
{
  "tool": "exec",
  "command": "${SHARED_TOOLS}/claude-research.sh --project \"<PROJECT_URL>\" --question \"<QUESTION>\""
}
```

The tool prints the output file path to stdout on success. Read the result file to get the response.

## Available Projects

> **Note:** Project URLs will be populated after initial setup. Check with Gus for current project list.

| Project | URL | Use For |
|---------|-----|---------|
| (to be configured) | | |

## Arguments

| Arg | Required | Default | Description |
|-----|----------|---------|-------------|
| `--project` | Yes | — | Claude.ai project URL |
| `--question` | Yes | — | Research question text |
| `--output` | No | Auto-generated | Output file path |
| `--timeout` | No | 120 | Max seconds to wait |

## Response Format

Results are saved as markdown with YAML frontmatter:

```markdown
---
source: claude-research
project: "project-id"
timestamp: "2026-02-06T12:00:00Z"
url: "https://claude.ai/chat/..."
---

# Research: Your question here

Response content in markdown...
```

## Example Workflow

```json
// 1. Send the research question
{
  "tool": "exec",
  "command": "${SHARED_TOOLS}/claude-research.sh --project \"https://claude.ai/project/abc123\" --question \"What are the tradeoffs between SQLite and PostgreSQL for local-first apps?\""
}
// stdout: /Users/bruba/claude-sync/results/20260206-143022-what-are-the-tradeoffs.md

// 2. Read the result
{
  "tool": "read",
  "path": "/Users/bruba/claude-sync/results/20260206-143022-what-are-the-tradeoffs.md"
}
```

## Exit Codes

| Code | Meaning | Action |
|------|---------|--------|
| 0 | Success | Read the output file |
| 1 | Error | Check stderr for details |
| 2 | Auth expired | Tell Gus: "Claude.ai auth expired, run setup.sh --login" |

## Tips

- **Be specific** — include context about what you need, just like messaging bruba-web
- **One question per call** — don't batch multiple questions
- **Projects have memory** — the project's uploaded docs and prior conversations provide context
- **Timeout for long answers** — use `--timeout 180` or `--timeout 240` for complex questions
- **Auth expires** — if you get exit code 2, the browser session needs manual re-auth

## Differences from bruba-web

| | Claude Research | bruba-web |
|---|---|---|
| **Source** | Claude.ai Projects | Live web search |
| **Context** | Project docs + history | Fresh per query |
| **Best for** | Domain knowledge, analysis | Current events, URLs |
| **Speed** | 30-120s | 10-30s |
| **Auth** | Needs browser session | Always available |
