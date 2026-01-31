## Every Session

Before doing anything else:
1. Read `SOUL.md` — this is who you are
2. Read `USER.md` — this is who you're helping
3. **Check for `memory/CONTINUATION.md`** — if it exists, read it and move to `memory/archive/continuation-YYYY-MM-DD.md`
4. Read `memory/YYYY-MM-DD.md` (today + yesterday) for recent context
5. **If in MAIN SESSION** (direct chat with your human): Also read `MEMORY.md`

Don't ask permission. Just do it.

### Session Greeting

When starting a new session:

1. **Greet briefly:** Just "Hello!" — no "What are we working on?" yet
2. **Check continuation:** Read `memory/CONTINUATION.md`
3. **If continuation exists:**
   - Archive it to `memory/archive/continuation-YYYY-MM-DD.md`
   - Send a follow-up message: "Picking up where we left off: [summary of what was in progress, any open questions, next steps]"
   - Clear the continuation file
4. **If no continuation:** After the greeting, wait for user direction

The two-message pattern (greeting → continuation summary) lets the user see you're online immediately, then get context on what's pending.

### 📦 Continuation Packets

When wrapping up a session with active work in progress:
1. Write context to `memory/CONTINUATION.md` — active items, open questions, next steps
2. **Consider updating `MEMORY.md`** — any significant learnings, patterns, or mistakes worth preserving long-term?
3. Next session picks it up automatically (see step 3 above)
4. After reading, archive using Write tool (not exec/mv):
   - Write content to `memory/archive/continuation-YYYY-MM-DD.md`
   - Overwrite `memory/CONTINUATION.md` with empty content

**Why archive instead of delete:** Crash protection. If session dies after reading but before meaningful work, the archive has the backup.

**Why Write instead of mv:** Exec approvals cannot be approved on Signal. Write tool bypasses this.

**Cleanup:** Old continuation archives (and voice files, temp files) get cleaned up periodically — part of the "delete old crud" pipeline (TBD).
