# Phase 4: Git History Scrub

**Prerequisite:** Phases 1-3 complete (check `docs/packets/phase3-results.md`)
**Input:** All hardcoded sensitive values removed from git-tracked files

## Context — Read These First

Before starting, read these files to understand the system:

1. **Phase 3 results:** `docs/packets/phase3-results.md` — confirms all phases complete
2. **Architecture overview:** `docs/architecture-masterdoc.md` — skim for any remaining hardcoded references (the doc itself may reference names/UUIDs in examples — decide whether to clean those too)
3. **Overall plan:** This is Phase 4 (final) of a 4-phase roadmap. Phases 1-3 removed all hardcoded names/UUIDs/phone numbers from git-tracked template and component files. This phase rewrites git history to remove them from all past commits too.
4. **What's gitignored:** `.gitignore` — config.yaml is gitignored (sensitive values there are fine). The concern is git-tracked files like components/, templates/, cronjobs/, and docs/ that had hardcoded values in past commits.
5. **What to scrub:** UUIDs, phone numbers, and human names (<REDACTED-NAME>, <REDACTED-NAME>) from all git history. These appear in component snippets, guru templates, cronjobs, bindings examples, and architecture docs.

## Goal

Remove UUIDs, phone numbers, and names from all git history using `git filter-repo`.

## Pre-flight

1. Confirm all prior phases are complete:
   ```bash
   cat docs/packets/phase1-results.md
   cat docs/packets/phase2-results.md
   cat docs/packets/phase3-results.md
   ```

2. Verify no remaining hardcoded sensitive values in tracked files:
   ```bash
   # UUID
   git grep "18ce66e6"
   # Phone numbers
   git grep "<REDACTED-PHONE>"
   git grep "<REDACTED-PHONE>"
   # Names in template/component files (config.yaml is gitignored, so safe)
   git grep -w "<REDACTED-NAME>" -- '*.md' '*.yaml' ':!config.yaml' ':!docs/packets/' ':!docs/architecture*' ':!CLAUDE.md'
   git grep -w "<REDACTED-NAME>" -- '*.md' '*.yaml' ':!config.yaml' ':!docs/packets/' ':!CLAUDE.md'
   ```
   Expected: zero matches in tracked files (except docs/packets/ which we'll handle).

3. Commit any outstanding changes and push.

## Tool

```bash
brew install git-filter-repo
```

## Replacements File

Create `expressions.txt` (in scratchpad, NOT committed):

```
literal:<REDACTED-UUID>==><REDACTED-UUID>
literal:<REDACTED-PHONE>==><REDACTED-PHONE>
literal:<REDACTED-PHONE>==><REDACTED-PHONE>
regex:(?<![a-zA-Z])<REDACTED-NAME>(?![a-zA-Z])==><REDACTED-NAME>
regex:(?<![a-zA-Z])<REDACTED-NAME>(?![a-zA-Z])==><REDACTED-NAME>
```

**Note:** The name regex uses lookahead/lookbehind to avoid false positives ("Augustus", "Rexford" won't match). But review results carefully — "<REDACTED-NAME>" and "<REDACTED-NAME>" are short common words.

## Execution

1. **Fresh clone** (never run filter-repo on your working copy):
   ```bash
   cd /tmp
   git clone /Users/dadbook/source/bruba-godo bruba-godo-filtered
   cd bruba-godo-filtered
   ```

2. **Create expressions.txt:**
   ```bash
   cat > /tmp/expressions.txt << 'EOF'
   literal:<REDACTED-UUID>==><REDACTED-UUID>
   literal:<REDACTED-PHONE>==><REDACTED-PHONE>
   literal:<REDACTED-PHONE>==><REDACTED-PHONE>
   regex:(?<![a-zA-Z])<REDACTED-NAME>(?![a-zA-Z])==><REDACTED-NAME>
   regex:(?<![a-zA-Z])<REDACTED-NAME>(?![a-zA-Z])==><REDACTED-NAME>
   EOF
   ```

3. **Run filter-repo:**
   ```bash
   git filter-repo --replace-text /tmp/expressions.txt
   ```

4. **Verify — spot-check key commits:**
   ```bash
   # Check that UUID is gone from all history
   git log --all -p | grep -c "18ce66e6"
   # Should be 0

   # Check phone numbers
   git log --all -p | grep -c "<REDACTED-PHONE>"
   git log --all -p | grep -c "<REDACTED-PHONE>"
   # Should be 0

   # Spot-check a recent commit
   git log --oneline -5
   git show HEAD -- components/signal/prompts/AGENTS.snippet.md
   ```

5. **Review name replacements** (most important — check for false positives):
   ```bash
   # See what got replaced
   git log --all -p | grep "<REDACTED-NAME>" | head -30
   ```
   Verify these all look correct (no code variables, filenames, or unrelated text got mangled).

6. **Add remote and force-push:**
   ```bash
   git remote add origin <your-remote-url>
   git push --force-with-lease origin main
   ```

7. **Re-clone locally:**
   ```bash
   cd /Users/dadbook/source
   mv bruba-godo bruba-godo-backup
   git clone <your-remote-url> bruba-godo
   cd bruba-godo
   cp ../bruba-godo-backup/config.yaml .
   # Copy any other gitignored local state you need
   cp -R ../bruba-godo-backup/mirror .
   cp -R ../bruba-godo-backup/sessions .
   cp -R ../bruba-godo-backup/intake .
   cp -R ../bruba-godo-backup/reference .
   cp -R ../bruba-godo-backup/exports .
   cp -R ../bruba-godo-backup/logs .
   ```

## Risks

- **All commit hashes change.** This is a single-user repo so it's acceptable.
- **Must coordinate with any other clones** (bot's repo-reference copy, etc.). Re-push after scrub.
- **"<REDACTED-NAME>" and "<REDACTED-NAME>" are common words.** The word-boundary regex helps but review results before force-pushing.
- **docs/packets/ files contain the names.** Either:
  - Remove/gitignore the packets before scrub (they're implementation artifacts)
  - Or accept that `<REDACTED-NAME>` will appear in them after scrub

## Post-scrub Cleanup

1. Delete backup: `rm -rf /Users/dadbook/source/bruba-godo-backup`
2. Delete filtered clone: `rm -rf /tmp/bruba-godo-filtered`
3. Delete expressions.txt: `rm /tmp/expressions.txt`
4. Re-push repo-reference to bot: `./tools/push.sh` (or next `/sync`)
5. Archive packets: move `docs/packets/phase*` to `docs/packets/archive/` or delete

## Results Packet

After completing, write `docs/packets/phase4-results.md`:

```markdown
# Phase 4 Results: Git History Scrub

## Status: COMPLETE

## What was done
- [ ] Created expressions.txt with replacement rules
- [ ] Fresh clone + git filter-repo --replace-text
- [ ] Verified: zero remaining UUIDs, phone numbers in history
- [ ] Verified: name replacements are correct (no false positives)
- [ ] Force-pushed to remote
- [ ] Re-cloned locally with config.yaml restored
- [ ] Re-pushed repo-reference to bot

## Verification results
- UUID grep in history: [0 matches]
- Phone grep in history: [0 matches]
- Name replacement review: [PASS — N replacements, all correct]
- Working tree clean after re-clone: [PASS/FAIL]
- Assembly still works: [PASS/FAIL]

## Notes
- All commit hashes changed
- Backup deleted: [yes/no]
- Any false positives found: [list or "none"]
```
