# TOOLS.md - Local Notes

Skills define *how* tools work. This file is for *your* specifics — the stuff that's unique to your setup.

---

## File System (Sandbox Mode)

You run in a Docker container. Your workspace is mounted at `/workspace/`:

| Directory | Path | Access | Purpose |
|-----------|------|--------|---------|
| **Workspace root** | `/workspace/` | Read-write | Your prompts, memory, working files |
| **Memory** | `/workspace/memory/` | Read-write | Docs, transcripts, repos (synced by operator) |
| **Tools** | `/workspace/tools/` | Read-only | Scripts (exec uses host paths) |
| Shared packets | `/workspaces/shared/packets/` | Read-write | Main↔Guru handoff |
| Shared context | `/workspaces/shared/context/` | Read-write | Shared context files |
| Shared repo | `/workspaces/shared/repo/` | Read-only | bruba-godo reference |

### File Discovery

Use `memory_search` to discover files, then `read` to access them:
```
memory_search "topic"        → Returns paths like /workspace/memory/docs/Doc - setup.md
read /workspace/memory/docs/Doc - setup.md  → File contents
```

**DO NOT use exec for file discovery.** Commands like `ls`, `find` are not available in sandbox.

### Memory Structure

```
/workspace/memory/
├── transcripts/     # Transcript - *.md
├── docs/            # Doc - *.md, Refdoc - *.md, Claude Code Log - *.md
├── repos/bruba-godo/  # bruba-godo mirror (updated on sync)
└── workspace-snapshot/  # Copy of workspace/ at last sync (searchable)
```

### Workspace Structure

```
/workspace/
├── memory/          # Synced content (searchable via memory_search)
├── output/          # Your working outputs
├── drafts/          # Work in progress
├── temp/            # Temporary files
└── continuation/    # CONTINUATION.md and archive/
```

**CRITICAL — Path Split:**

| Tool | Runs Where | Use Path |
|------|------------|----------|
| `read`, `write`, `edit` | Container | `/workspace/...` (rw) |
| `exec` | Host | `/Users/bruba/...` |

**Examples:**
```
# Read from memory:
read /workspace/memory/docs/Doc - setup.md
read /workspace/memory/repos/bruba-godo/config.yaml

# Write to workspace:
write /workspace/output/analysis.md
write /workspace/continuation/CONTINUATION.md

# Exec uses host paths:
exec /Users/bruba/agents/bruba-main/tools/tts.sh "hello" /tmp/out.wav
```

**Write failures:** If you get "read-only filesystem", you're trying to write to `/workspace/tools/` (read-only for security).

---

## File & System Commands

**Status:** Depends on sandbox mode and exec-approvals configuration

**Use full paths:** Allowlist pattern matching is literal. Always use full binary paths — never shorten to bare commands (`grep` won't work, `/usr/bin/grep` will):
- `/usr/bin/wc -c <file>` — byte count (divide by 4 for rough token estimate)
- `/usr/bin/wc -l <file>` — line count
- `/bin/ls -la <dir>` — list with sizes
- `/usr/bin/head -n <file>` / `/usr/bin/tail -n <file>` — preview without loading full file
- `/usr/bin/grep -l "term" <dir>/*.md` — find files containing term
- `/usr/bin/du -sh <dir>` — directory size

**Pipes:** Each command in a pipe must use full path:
- ✅ `/usr/bin/grep "pattern" file.md | /usr/bin/head -10`
- ❌ `/usr/bin/grep "pattern" file.md | head -10`

**Redirections:** May not be supported in allowlist mode. Check your config.

**Token reporting:** When loading any file >2000 tokens, report to the user:
- What file you're loading and why
- Approximate tokens being added

This helps track context burn and adjust if needed. For smaller files, load freely.

---

## Context Check

When asked for context usage, use `session_status` and reply with just the key line:
```
📚 **26k / 200k** (13%) · 0 compactions
```

**Threshold warnings:** Alert on crossing:
- 50k (25%)
- 75k (37%)
- 100k (50%)
- 150k (75%)
- 180k (90%)

**Auto-check every ~10 messages:** If no context check in a while, include:
`Periodic context check: 📚 **Xk / 200k** (Y%)`

---

## Why Separate?

Skills are shared. Your setup is yours. Keeping them apart means you can update skills without losing your notes, and share skills without leaking your infrastructure.

---

## Add Your Tools Here

*(Document your specific tools, paths, and configurations below)*
