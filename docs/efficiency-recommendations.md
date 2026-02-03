# Sync Pipeline Efficiency Recommendations

Audit date: 2026-02-03

## Script Audit Summary

| Script | SSH Calls | Change Detection | Critical Issues |
|--------|-----------|------------------|-----------------|
| **mirror.sh** | 16-20+ | None | **N+1 pattern**: 1 SSH per file test |
| push.sh | 9 | MD5 hash of exports/ | Multiple rsync calls could batch |
| pull-sessions.sh | 3 | `.pulled` tracking | Good incremental design |
| assemble-prompts.sh | 0 | None needed | Pure local, efficient |
| sync-cronjobs.sh | 3+ | Name existence check | Parses YAML 9x per job |
| update-allowlist.sh | 5 | Early exit if unchanged | Good |
| update-agent-tools.sh | 4 | Local comparison | Good |
| detect-conflicts.sh | 0 | N/A | Pure local |

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

### Bidirectional cron sync

**Problem:** Current sync-cronjobs.sh is one-way (local → bot). Jobs created on bot aren't tracked locally.

**Proposed flow:**
```
1. Pull current state
   openclaw cron list --json → parse into bot_jobs map

2. Compare against local cronjobs/*.yaml
   - bot-only: Job on bot, no local YAML
   - local-only: YAML exists, not on bot
   - modified: Both exist, content differs
   - synced: Both exist, content matches

3. Interactive reconciliation
   [K]eep bot job (create local YAML)
   [D]elete from bot
   [L]ocal wins (update bot)
   [B]ot wins (update local YAML)
   [S]kip

4. State tracking: sync/cron-sync-state.yaml
   last_sync: timestamp
   jobs:
     <name>:
       local_hash: <md5 of yaml content>
       bot_id: <uuid>
       last_synced: <timestamp>
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
