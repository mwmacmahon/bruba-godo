# /update - Update OpenClaw

Update OpenClaw to a new version. OpenClaw is installed from source on the bot account, so updates use git checkout + pnpm build via SSH.

> **Source location:** `~/src/openclaw/` (on bot account)
> **Access via:** `./tools/bot "..."`
> **Binary symlink:** `~/.npm-global/bin/openclaw` → source dist/entry.js

**User intervention may be needed for:**
- Interactive prompts (e.g., `pnpm approve-builds` if dependencies change)
- Sudo commands (e.g., re-protecting config file)

When these occur, provide the command and ask the user to run it.

## Instructions

### Phase 1: Pre-flight Checks

```bash
# Current version
./tools/bot openclaw --version

# Daemon status
./tools/bot openclaw daemon status

# Health check
./tools/bot openclaw doctor
```

Review doctor output for install issues or warnings.

**If daemon is running:** Note this — will need restart after update.

### Phase 1.5: Analyze Doctor Findings

**For each doctor finding, present to user:**

1. **What it is** — Plain English explanation of the issue
2. **Severity** — Critical / High / Medium / Low / Info
3. **Risk if ignored** — What could go wrong
4. **Risk if fixed** — What the fix might break (tradeoffs)
5. **Recommendation** — What to do and why

**Before suggesting permission changes:**
```bash
./tools/bot ls -la /Users/bruba/.openclaw/openclaw.json
```
Check ownership model (bruba-owned vs root-owned) — the correct action depends on which is deployed.

**When doctor offers `--fix`:**
- Never auto-apply — always present findings first
- Explain each fix's effect and tradeoff
- Let user decide which fixes to apply

### Phase 2: Gather Version Information

```bash
# Fetch latest from remote
./tools/bot "cd ~/src/openclaw && git fetch --all --tags"

# Get current checkout info
./tools/bot cd /Users/bruba/src/openclaw && echo 'HEAD:' && git rev-parse --short HEAD && echo 'Tag:' && git describe --tags --abbrev=0

# List recent releases (tagged versions)
./tools/bot cd /Users/bruba/src/openclaw && git tag -l 'v2026.*' | sort -V | tail -5

# Check main branch status
./tools/bot cd /Users/bruba/src/openclaw && echo 'main:' && git rev-parse --short origin/main && git log --oneline HEAD..origin/main | wc -l | xargs echo 'commits ahead:'

# Check for beta branches
./tools/bot cd /Users/bruba/src/openclaw && git branch -r | grep -E 'beta|rc' | head -5
```

### Phase 3: Security Advisory Check

**Ask user:** "Check for security advisories? (uses WebSearch)"

If yes, use WebSearch to search for:
- "openclaw moltbot security vulnerability CVE [current year]"
- "openclaw moltbot release notes security"

**Also check the repo's security commits:**
```bash
# Security-related commits since current version
./tools/bot cd /Users/bruba/src/openclaw && git log --oneline HEAD..origin/main --grep='security\|CVE\|vuln' | head -10

# Check if any recent releases mention security
./tools/bot cd /Users/bruba/src/openclaw && git tag -l --format='%(refname:short) %(contents:subject)' 'v2026.*' | tail -5
```

Summarize any security findings relevant to the decision.

### Phase 4: Present Options

Based on gathered information, present a comparison:

```
=== Update Options ===

Current: [version/commit]

Option 1: Latest Release ([tag])
  - Stable, tested
  - [X] commits behind main
  - Notable changes: [summary from release notes]
  - Security fixes: [if any]

Option 2: Main Branch ([short-hash])
  - [X] commits ahead of current
  - Notable changes: [summary key commits]
  - Security fixes: [list if any]
  - Risk: Unreleased, may have bugs

Option 3: Beta/RC ([branch/tag] if exists)
  - [summary]
  - Security fixes: [if any]

Recommendation: [which option and why]
```

**Ask user which option to install**, or if they want to stay on current.

### Phase 5: Backup Config

Only proceed to backup if user chose to update.

```bash
BACKUP_DIR=~/clawd/backups/$(date +%Y-%m-%d)
mkdir -p "$BACKUP_DIR"

# Backup bot's config to main account
./tools/bot "tar -czf - .openclaw/" > "$BACKUP_DIR/bruba-openclaw-config.tar.gz"

# Verify backup
ls -la "$BACKUP_DIR/"
```

### Phase 6: Perform Update

Based on user's choice:

**For tagged release:**
```bash
# Checkout the tag
./tools/bot "cd ~/src/openclaw && git checkout [TAG]"
```

**For main branch:**
```bash
# Checkout main
./tools/bot "cd ~/src/openclaw && git checkout main && git pull"
```

**For beta/other branch:**
```bash
# Checkout specific branch/commit
./tools/bot "cd ~/src/openclaw && git checkout [BRANCH]"
```

**Then build:**
```bash
# Rebuild
./tools/bot "cd ~/src/openclaw && pnpm install && pnpm build"

# Relink global
./tools/bot "cd ~/src/openclaw && pnpm link --global"

# Verify
./tools/bot "openclaw --version"
```

**If `pnpm install` prompts for build approval:** Ask user to run interactively:
```bash
./tools/bot
cd ~/src/openclaw
pnpm approve-builds  # Select packages as needed
pnpm rebuild node-llama-cpp  # If llama-cpp changed
exit
```

### Phase 7: Post-update Verification

**Restart daemon and verify:**
```bash
./tools/bot "openclaw daemon restart"
sleep 3

# Quick health check (compact output)
./tools/bot openclaw gateway health

# Security audit summary
./tools/bot openclaw security audit --json | jq '.summary'
```

Expected health output:
```
Gateway Health
OK (Xms)
Telegram: configured
Signal: ok (Xms)
```

**If issues detected**, run full diagnostics:
```bash
./tools/bot openclaw doctor
./tools/bot openclaw security audit
```

**Verify config permissions:**
```bash
./tools/bot ls -la /Users/bruba/.openclaw/openclaw.json
```

### Phase 8: Log Update

Append to `logs/updates.md` (create if needed):

```markdown
## [DATE] - Updated to [VERSION]

- Previous: [old version]
- New: [new version]
- Source: release / main / beta
- Daemon restarted: yes/no
- Security fixes included: [list or none]
- Issues: none / [description]
```

## Rollback

If something goes wrong:

```bash
# Find previous version
./tools/bot cd /Users/bruba/src/openclaw && git tag -l | grep 2026 | sort -V | tail -5

# Checkout previous (replace [previous-version])
./tools/bot "cd ~/src/openclaw && git checkout [previous-version]"

# Rebuild
./tools/bot "cd ~/src/openclaw && pnpm install && pnpm build && pnpm link --global"

# Restart daemon
./tools/bot "openclaw daemon restart"
```

## Arguments

$ARGUMENTS

Flags:
- `--dry-run` — Show options without executing any updates
- `--skip-security` — Skip security advisory WebSearch (still checks git history)

## Example Output

```
=== Bot Update ===

Pre-flight:
  Current: v2026.1.24-1
  Daemon: running (pid 25866)
  Doctor: 1 install note, 1 state warning

=== Update Options ===

Current: v2026.1.24-1 (tag)

Option 1: Latest Release (v2026.1.24-1)
  - Already installed
  - No action needed

Option 2: Main Branch (a7534dc)
  - 127 commits ahead
  - Notable: Moltbot rename, compile cache perf, Telegram improvements
  - Security fixes: PATH injection fix, timing attack fix, file serving hardening
  - Risk: Unreleased, includes major branding change

Recommendation: Stay on v2026.1.24-1 (stable) unless you need security fixes

User choice: [awaiting input]
```

## Related Skills

- `/status` - Check current version and daemon state
- `/restart` - Restart daemon after config changes
- `/launch` - Start daemon if stopped
