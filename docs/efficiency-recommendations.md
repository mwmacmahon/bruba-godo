# Sync Pipeline Efficiency Recommendations

Audit date: 2026-02-03

## Script Audit Summary

| Script | Purpose | Avg Runtime | SSH Calls | Pain Points |
|--------|---------|-------------|-----------|-------------|
| **mirror.sh** | Pull bot state | ~15s | 16-20+ | **N+1 anti-pattern** |
| push.sh | Push exports to bot | ~10s | 9 | Multiple rsync calls |
| pull-sessions.sh | Pull closed sessions | ~5s | 3 | Good design |
| assemble-prompts.sh | Assemble prompts | <1s | 0 | Pure local |
| sync-cronjobs.sh | Sync cron jobs | ~5s | 3+ | YAML parsed 9x/job |
| update-allowlist.sh | Update exec allowlist | ~3s | 5 | Good |
| update-agent-tools.sh | Update tool permissions | ~3s | 4 | Good |
| detect-conflicts.sh | Detect prompt conflicts | <1s | 0 | Pure local |

### Detailed Script Analysis (5-Question Audit)

#### mirror.sh
| Question | Answer |
|----------|--------|
| SSH connections opened? | **16-20+** — 1 per file existence test (N+1 anti-pattern) |
| Transfers unchanged files? | **Yes** — always copies, no mtime/hash comparison |
| Checksum skipping possible? | **Yes** — compare remote stat() vs local mtime |
| Parallelization possible? | **Limited** — could batch file tests, but single rsync is fine |
| SSH batching possible? | **Yes (critical)** — single `find` replaces all `test -f` calls |

#### push.sh
| Question | Answer |
|----------|--------|
| SSH connections opened? | **9** — 1 check + 8 rsync calls (per content type) |
| Transfers unchanged files? | **No** — rsync handles delta transfer |
| Checksum skipping possible? | **Already using** — MD5 hash of exports/ for early exit |
| Parallelization possible? | **Yes** — rsync calls are independent, could xargs -P |
| SSH batching possible? | **Moderate** — mkdir calls could batch, rsync calls inherently separate |

#### pull-sessions.sh
| Question | Answer |
|----------|--------|
| SSH connections opened? | **3** — list, check .pulled, copy new |
| Transfers unchanged files? | **No** — `.pulled` tracks processed sessions |
| Checksum skipping possible? | **N/A** — already incremental |
| Parallelization possible? | **No** — sequential by design (order matters for .pulled) |
| SSH batching possible? | **Minimal** — already efficient |

#### assemble-prompts.sh
| Question | Answer |
|----------|--------|
| SSH connections opened? | **0** — pure local |
| Transfers unchanged files? | **N/A** |
| Checksum skipping possible? | **N/A** |
| Parallelization possible? | **No** — prompt files have dependencies |
| SSH batching possible? | **N/A** |

#### sync-cronjobs.sh
| Question | Answer |
|----------|--------|
| SSH connections opened? | **3+** — list, per-job ops |
| Transfers unchanged files? | **Sometimes** — updates job even if content unchanged |
| Checksum skipping possible? | **Yes** — hash job YAML, skip if bot job matches |
| Parallelization possible? | **No** — cron API calls are sequential |
| SSH batching possible? | **N/A** — uses openclaw CLI, not SSH |

**Critical issue:** Parses YAML 9 times per job (once per field extraction).

#### update-allowlist.sh
| Question | Answer |
|----------|--------|
| SSH connections opened? | **5** — backup, read, compare, write, verify |
| Transfers unchanged files? | **No** — early exit if unchanged |
| Checksum skipping possible? | **Already using** — diff check before write |
| Parallelization possible? | **No** — single file operation |
| SSH batching possible? | **Minimal** — already reasonable |

#### update-agent-tools.sh
| Question | Answer |
|----------|--------|
| SSH connections opened? | **4** — read config, compare, write, verify |
| Transfers unchanged files? | **No** — compares before write |
| Checksum skipping possible? | **Already using** |
| Parallelization possible? | **No** — single config file |
| SSH batching possible? | **Minimal** |

#### detect-conflicts.sh
| Question | Answer |
|----------|--------|
| SSH connections opened? | **0** — pure local (reads mirror/) |
| Transfers unchanged files? | **N/A** |
| Checksum skipping possible? | **N/A** |
| Parallelization possible? | **N/A** |
| SSH batching possible? | **N/A** |

---

## Command Audit

| Command | Calls Scripts | Typical Duration | User Friction |
|---------|---------------|------------------|---------------|
| /sync | 7 (assemble, push, pull, etc.) | ~30s | Conflicts block; many decisions |
| /prompt-sync | 4 (assemble, detect-conflicts, push) | ~15s | Manual config edits for conflicts |
| /pull | 1 (pull-sessions.sh) | ~5s | Requires /convert next |
| /convert | 3 Python helpers | ~2s/file | Script failures opaque |
| /intake | distill CLI | variable | Triage slows batch |
| /export | distill CLI | ~3s | Anchor mismatches silent |
| /push | 2 (push.sh, update-allowlist) | ~10s | Export fallback unfiltered |

### Command Friction Details

**`/sync`** — Full pipeline, most moving parts:
- Runs assemble → detect-conflicts → push → pull → convert (optional)
- Conflicts halt entire pipeline requiring manual config.yaml edits
- User must decide: keep local, keep bot, or merge for each conflict
- Many prompts/decisions before completion

**`/prompt-sync`** — Prompt-focused subset:
- Runs assemble-prompts → detect-conflicts → push
- Conflict detection blocks push until resolved
- Manual editing of config.yaml `*_sections` arrays required

**`/pull`** — Clean but incomplete:
- Runs pull-sessions.sh only
- Creates intake/*.md files requiring /convert next
- Two-step workflow friction

**`/convert`** — AI-assisted but fragile:
- Uses Claude to generate CONFIG blocks
- Python helper failures produce cryptic errors
- No batch mode — one file at a time

**`/intake`** — Batch but slow:
- Uses distill CLI for canonicalization
- Triage mode adds decision overhead
- Silent failures on malformed CONFIG

**`/export`** — Filter mismatches silent:
- Anchor pattern mismatches produce no output
- User doesn't know if file was filtered or failed
- Fallback to unfiltered export can surprise

**`/push`** — Generally reliable:
- Runs push.sh + update-allowlist.sh
- Export directory fallback can push unfiltered content
- Good rsync delta handling

---

## Quick Wins (< 1 hour each)

### sync-cronjobs.sh: Parse YAML once per job

**Current:** 9 separate `python3 -c` calls per job to extract individual fields.

**Fix:** Single parse returning all fields as JSON or tab-separated values.

```bash
# Before (per job):
name=$(python3 -c "..." "$yaml_file")
schedule=$(python3 -c "..." "$yaml_file")
# ... 7 more calls

# After:
read -r name schedule command <<< $(python3 helpers/parse-yaml.py --all "$yaml_file")
```

**Expected:** ~8x faster per job.

---

### push.sh: Batch mkdir -p calls

**Current:** Creates directories inside rsync loop.

**Fix:** Collect all remote directories, create in single SSH call before loop.

**Expected:** Minor improvement, cleaner code.

---

## Medium Effort (1-4 hours)

### mirror.sh N+1 fix

**Current pattern (critical):**
```bash
# 8+ SSH calls just for core files:
bot_cmd "test -f $WORKSPACE/IDENTITY.md" && ...
bot_cmd "test -f $WORKSPACE/AGENTS.md" && ...
bot_cmd "test -f $WORKSPACE/TOOLS.md" && ...
# ... for each file
```

**Fix:** Single find command, iterate locally:
```bash
# Get all .md files in one call
remote_files=$(bot_cmd "find $WORKSPACE -maxdepth 1 -name '*.md' -type f")

# Iterate locally
for file in $remote_files; do
    # ... copy logic
done
```

**Expected:** Reduce 20+ SSH calls to ~3.

---

### mirror.sh incremental mode

**Current:** Always copies all files regardless of changes.

**Fix:** Compare remote mtime vs local mtime, skip unchanged files.

```bash
# Get mtimes in single call
bot_cmd "stat -f '%m %N' $WORKSPACE/*.md"

# Compare locally, only copy changed
```

**Expected:** Skip ~80% of copies on typical runs.

---

### SSH ControlMaster for connection reuse

**Add to lib.sh:**
```bash
SSH_CONTROL_PATH="/tmp/bruba-ssh-%r@%h:%p"
SSH_OPTS="-o ControlMaster=auto -o ControlPath=$SSH_CONTROL_PATH -o ControlPersist=60"

bot_cmd() {
    ssh $SSH_OPTS "$BOT_HOST" "$@"
}
```

**Benefits:**
- First connection establishes master
- Subsequent calls reuse connection (no handshake overhead)
- 60-second persist covers typical script runs

**Expected:** Significant reduction in SSH overhead across all scripts.

---

## Larger Refactors (4+ hours)

### Bidirectional Cron Sync Design

#### Problem

Current `sync-cronjobs.sh` is one-way (local → bot). Jobs created on bot aren't tracked locally. This causes:
- Manual bot job creation gets lost on next sync
- No visibility into what's actually running on bot
- Risk of accidentally deleting bot-created jobs

#### Proposed Flow

**Step 1: Pull current state**
```bash
# Get all jobs from bot as JSON
./tools/bot openclaw cron list --json > /tmp/bot-cron-state.json
```

**Step 2: Compare against local cronjobs/*.yaml**

Classification:
| Category | Definition | Example |
|----------|------------|---------|
| bot-only | Job on bot, no local YAML | Created via `openclaw cron add` directly |
| local-only | YAML exists, not on bot | New job pending first sync |
| modified | Both exist, content differs | Either side changed since last sync |
| synced | Both exist, content matches | No action needed |

**Step 3: Interactive reconciliation**

For **bot-only** jobs:
```
[nightly-weather-check] exists on bot but not locally.
  [K]eep (add to local cronjobs/)
  [D]elete from bot
  [S]kip (leave as-is, don't track)
>
```

For **modified** jobs:
```
[reminder-check] differs between local and bot.
  Local:  schedule="0 9,14,18 * * *"
  Bot:    schedule="0 10,15,19 * * *"
  [L]ocal wins (overwrite bot)
  [B]ot wins (update local yaml)
  [S]kip
>
```

**Step 4: State tracking file**

```yaml
# sync/cron-sync-state.yaml
last_sync: 2026-02-03T17:00:00-05:00
jobs:
  nightly-reset-prep:
    local_hash: abc123def456
    bot_id: 5ad704f1-2b3c-4d5e-6f7a-8b9c0d1e2f3a
    last_synced: 2026-02-03T17:00:00-05:00
    status: synced
  reminder-check:
    local_hash: 789xyz012abc
    bot_id: 1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d
    last_synced: 2026-02-03T17:00:00-05:00
    status: synced
  nightly-weather-check:
    local_hash: null  # bot-only, not tracked locally
    bot_id: 9f8e7d6c-5b4a-3c2d-1e0f-9a8b7c6d5e4f
    last_synced: null
    status: bot-only
```

#### Implementation Notes

**Hash calculation:**
```bash
# Hash the meaningful content, not metadata
cat cronjobs/reminder-check.yaml | grep -v '^#' | md5sum | cut -d' ' -f1
```

**YAML generation for bot-only jobs:**
```bash
# When user selects [K]eep, generate YAML from bot JSON
./tools/helpers/cron-to-yaml.py "$job_json" > cronjobs/$job_name.yaml
```

**Sync modes:**
```bash
./tools/sync-cronjobs.sh              # Interactive (default)
./tools/sync-cronjobs.sh --local      # Local wins, no prompts
./tools/sync-cronjobs.sh --bot        # Bot wins, no prompts
./tools/sync-cronjobs.sh --dry-run    # Show what would change
```

---

### Manifest-based sync

**Problem:** Current sync can't detect deletions without full diff.

**Solution:** Track what was synced in manifest file:
```yaml
# sync/manifest.yaml
last_sync: 2026-02-03T10:30:00Z
files:
  exports/bot/transcripts/2026-01-15-morning-chat.md:
    hash: abc123
    synced_to: memory/transcripts/
  exports/bot/prompts/coding-guidelines.md:
    hash: def456
    synced_to: memory/prompts/
```

On next sync: files in manifest but not in exports/ → delete from bot.

---

### Parallel agent operations

**Problem:** mirror.sh and push.sh process agents sequentially.

**Solution:** Use `xargs -P` or background jobs for concurrent processing:
```bash
# Process multiple agents in parallel
echo "${agents[@]}" | xargs -P4 -I{} ./process-agent.sh {}
```

**Considerations:**
- SSH connection limits
- Output interleaving (needs careful logging)
- Error handling more complex

---

## Priority Order

1. **SSH ControlMaster** - Easy, benefits all scripts
2. **mirror.sh N+1 fix** - Biggest single improvement
3. **sync-cronjobs.sh YAML parsing** - Quick win
4. **mirror.sh incremental** - Good follow-up to N+1 fix
5. **Bidirectional cron sync** - Quality of life improvement
6. **Manifest-based sync** - Enables proper deletion handling

---

## Testing

Efficiency improvements are validated by `tests/test-efficiency.sh` (17 tests):

```bash
./tests/test-efficiency.sh           # Run all efficiency tests
./tests/test-efficiency.sh --quick   # Same (no SSH tests)
./tests/test-efficiency.sh --verbose # Detailed output
```

**Test categories:**
- YAML parsing efficiency (single-parse pattern)
- SSH call patterns (N+1 avoidance)
- Change detection mechanisms
- Rsync efficiency settings
- SSH ControlMaster configuration
- Pure local script verification
- Documentation completeness

See `tests/README.md` for full test documentation.
