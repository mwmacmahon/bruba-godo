# TOOLS.md - Local Notes

Skills define *how* tools work. This file is for *your* specifics — the stuff that's unique to your setup.

---

## Memory Search — Use Frequently!

**`memory_search` is your most efficient discovery tool.** Use it liberally in ALL kinds of conversations:

- Casual chat about a topic? → `memory_search` to recall past conversations
- User mentions a person, project, or event? → `memory_search` for context
- Before answering any question? → Quick `memory_search` to check what you know
- Technical or research question? → `memory_search` for docs and transcripts

**It's fast, cheap, and indexed.** Don't hesitate to search multiple times per conversation. It's much more efficient than reading files manually.

```
memory_search "dentist"       → Past reminders, conversations about dentist
memory_search "project X"     → Notes, discussions about project X
memory_search "2026-01"       → Activity from January 2026
```

---

## File System

All file operations use **full host paths** (`/Users/bruba/...`).

| Directory | Path | Purpose |
|-----------|------|---------|
| **Agent workspace** | `${WORKSPACE}/` | Prompts, memory, working files |
| **Memory** | `${WORKSPACE}/memory/` | Docs, transcripts, repos |
| **Tools** | `${SHARED_TOOLS}/` | Scripts (protected — outside workspace) |
| **Shared packets** | `/Users/bruba/agents/bruba-shared/packets/` | Main↔Guru handoff |

### File Discovery

**Option 1: `memory_search`** (preferred for indexed content)
```
memory_search "topic"        → Returns paths
read ${WORKSPACE}/memory/docs/Doc - setup.md  → Contents
```

**Option 2: `exec` shell utilities** (for exploring directories)
```
exec /bin/ls ${WORKSPACE}/memory/
exec /usr/bin/find ${WORKSPACE}/memory/ -name "*.md"
exec /usr/bin/grep -r "pattern" ${WORKSPACE}/memory/
```

Both work. Use `memory_search` for indexed content; use `exec` when you need ls/find/grep.

### Memory Structure

```
${WORKSPACE}/memory/
├── transcripts/          # Transcript - *.md
├── docs/                 # Doc - *.md, Refdoc - *.md, CC Log - *.md
├── repos/bruba-godo/     # bruba-godo mirror (updated on sync)
└── workspace-snapshot/   # Copy of workspace/ at last sync
```

### Workspace Structure

```
${WORKSPACE}/
├── memory/              # Synced content (searchable via memory_search)
├── workspace/           # Working files
│   ├── output/          # Your outputs
│   ├── drafts/          # Work in progress
│   └── temp/            # Temporary files
└── continuation/        # CONTINUATION.md and archive/
```

### Tools

| Operation | Tool | Example |
|-----------|------|---------|
| **Read file** | `read` | `read ${WORKSPACE}/memory/docs/Doc - setup.md` |
| **Write file** | `write` | `write ${WORKSPACE}/workspace/output/result.md` |
| **Edit file** | `edit` | `edit ${WORKSPACE}/workspace/drafts/draft.md` |
| **List files** | `exec` | `exec /bin/ls ${WORKSPACE}/memory/` |
| **Find files** | `exec` | `exec /usr/bin/find ${WORKSPACE}/ -name "*.md"` |
| **Search content** | `exec` | `exec /usr/bin/grep -r "pattern" ${WORKSPACE}/` |
| **Run script** | `exec` | `exec ${SHARED_TOOLS}/tts.sh "hello" /tmp/out.wav` |

**Security:** Tools at `${SHARED_TOOLS}/` are outside your workspace — file tools (read/write/edit) can't modify them. Only exec can run them.

### File I/O Rules

**Always use native file tools for file operations:**
- `read` — read file contents
- `write` — create or overwrite file
- `edit` — modify existing file (append, replace sections)

**Never use exec for file I/O:**
- ❌ `exec echo "text" >> file` — WILL HANG (approval broken on Signal)
- ❌ `exec /bin/cat > file` — same problem
- ✅ `edit` or `write` — native tools, no approval needed

**Exec is for discovery and scripts only:**
- Discovery: `/bin/ls`, `/usr/bin/find`, `/usr/bin/grep`, `/bin/cat` (read-only)
- Scripts: `${SHARED_TOOLS}/*.sh`
- Apps: `/opt/homebrew/bin/remindctl`, `/opt/homebrew/bin/icalBuddy`

Remember, always use full paths for files!

**Why:** Exec approval is currently broken on Signal — approval requests never arrive, so commands hang indefinitely. Native file tools always work.

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
