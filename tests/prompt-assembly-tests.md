# Prompt Assembly Test Suite

Manual tests for verifying the config-driven prompt assembly system.

**Last run:** 2026-01-30

---

## Test 1: Basic Assembly

**Verify assembly produces correct section order from config.**

```bash
# Run assembly
./tools/assemble-prompts.sh --verbose

# Check section markers in output
grep -E '^<!-- (SECTION|COMPONENT|BOT-MANAGED):' assembled/prompts/AGENTS.md
```

**Expected:**
- 18 sections assembled (10 components, 6 template, 2 bot)
- Sections in order matching `agents_sections` in config.yaml
- Bot sections (exec-approvals, packets) in correct position

**Result:** PASS

---

## Test 2: Conflict Detection (Current State)

**Verify no false positives with current setup.**

```bash
./tools/detect-conflicts.sh
```

**Expected:**
- "No conflicts detected" (since config already has both bot sections)

**Result:** PASS

---

## Test 3: Simulate Bot Adding a Section

**Add a fake BOT-MANAGED section to mirror, verify detection.**

### Step 3a: Backup and add test section
```bash
# Backup mirror file
cp mirror/prompts/AGENTS.md mirror/prompts/AGENTS.md.bak

# Insert test section (add before "## Make It Yours")
# Content:
# <!-- BOT-MANAGED: test-section -->
# ## Test Section
#
# This is a test section added by the bot.
#
# It contains multiple lines to verify the detection and extraction work correctly.
# <!-- /BOT-MANAGED: test-section -->
```

### Step 3b: Run conflict detection
```bash
./tools/detect-conflicts.sh
```

**Expected:**
- Detects "NEW BOT SECTION: test-section"
- Reports position
- Shows preview of content

### Step 3c: Add to config
Edit `config.yaml` to add `bot:test-section` after `heartbeats`:
```yaml
  - heartbeats            # Component: Proactive behavior
  - bot:test-section      # TEST: temporary test section
  - signal                # Component: Signal messaging
```

### Step 3d: Re-run assembly
```bash
./tools/assemble-prompts.sh --verbose
```

**Expected:**
- Test section appears in assembled output
- 19 sections total (3 bot instead of 2)
- Position is between heartbeats and signal

### Step 3e: Verify no conflicts
```bash
./tools/detect-conflicts.sh
```

**Expected:**
- "No conflicts detected"

### Step 3f: Clean up
```bash
# Restore original mirror
mv mirror/prompts/AGENTS.md.bak mirror/prompts/AGENTS.md

# Remove test section from config (revert the edit)

# Re-assemble
./tools/assemble-prompts.sh
```

**Result:** PASS

---

## Test 4: Full Sync Cycle

**Complete round-trip: local changes → push → mirror → verify.**

### Step 4a: Push assembled to remote
```bash
rsync -avz assembled/prompts/AGENTS.md bruba:/Users/bruba/clawd/AGENTS.md
```

### Step 4b: Mirror back
```bash
./tools/mirror.sh
```

### Step 4c: Verify no conflicts
```bash
./tools/detect-conflicts.sh
```

**Expected:**
- No conflicts (we just pushed what we assembled)

### Step 4d: Re-assemble and compare
```bash
./tools/assemble-prompts.sh
diff mirror/prompts/AGENTS.md assembled/prompts/AGENTS.md
```

**Expected:**
- No differences (files should be identical)

**Result:** PASS (exit code 0, files byte-identical)

---

## Test 5: Bot Edits Detection (Optional)

**Verify detection when bot modifies a component section.**

This requires actual bot edits, so it's manual:

1. Edit `mirror/prompts/AGENTS.md` to change content within a `<!-- COMPONENT: memory -->` block
2. Run `./tools/detect-conflicts.sh --diff memory`
3. Should show the difference

**Result:** SKIPPED (requires bot edits)

---

## Summary

| Test | Status |
|------|--------|
| Test 1: Basic Assembly | PASS |
| Test 2: Conflict Detection | PASS |
| Test 3: Bot Section Simulation | PASS |
| Test 4: Full Sync Cycle | PASS |
| Test 5: Bot Edits Detection | SKIPPED |

**All critical tests pass.** The prompt assembly system is working correctly.

---

## Running All Tests

Quick checklist for future test runs:

```bash
# 1. Basic assembly
./tools/assemble-prompts.sh --verbose
# Verify: 18 sections (10 components, 6 template, 2 bot)

# 2. No false positives
./tools/detect-conflicts.sh
# Verify: "No conflicts detected"

# 3. Full sync (requires bot connectivity)
rsync -avz assembled/prompts/AGENTS.md bruba:/Users/bruba/clawd/AGENTS.md
./tools/mirror.sh
./tools/detect-conflicts.sh
./tools/assemble-prompts.sh
diff mirror/prompts/AGENTS.md assembled/prompts/AGENTS.md
# Verify: exit code 0 (no diff)
```

For Test 3 (simulated bot section), see detailed steps above.
