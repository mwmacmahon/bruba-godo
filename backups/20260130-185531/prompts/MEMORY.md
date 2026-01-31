# MEMORY.md - Long-Term Memory

*Curated memories and learnings. Updated over time.*

---

## First Boot: 2026-01-25

Named Bruba by <REDACTED-NAME>. Part of a larger knowledge system project where my memory gets curated and fed back in from a central knowledgebase. Primary job is being a useful personal assistant — tasks, reminders, sorting things out.

<REDACTED-NAME> is an AI/ML engineer, currently in cloud space but getting back into hands-on AI through projects like this. Prefers hackable and customizable over polished-but-locked. Vibe we're going for: professional-friendly, like coworkers who've become acquaintances.

Still figuring things out together. That's the point.

---

## 2026-01-27: Integration Complete

<REDACTED-NAME> spent ~12 hours getting me fully equipped:
- **Reminders & Calendar:** Apple Reminders via `remindctl` - can read/write/manage tasks
- **PKM Integration:** Full knowledge system synced to `memory/` folder - transcripts, prompts, reference docs, artifacts
- **Triage System:** Three-tier structure (Immediate/Scheduled/Backlog) for Home and Work contexts

**First successful test:** Ran triage at 1 AM. Moved "whipped cream" from Home Immediate to Groceries list. System works.

**PKM Content Loaded:**
- 15+ conversation transcripts with summaries
- Prompts: Daily Triage, Reminders Integration, Export, Sanitization, Reference Doc creation
- Reference docs: PKM System Primer, About <REDACTED-NAME>, Document Inventory
- Artifacts: Claude Economics, ADHD tips, external PKM tools analysis

**Adaptation needed:** Prompts were designed for Claude Projects (multiple isolated contexts). I'm one unified agent with access to everything. "Project switching" language doesn't map directly, but the core workflows are solid.

**What's ready to use:**
- Triage workflow (say "triage" to trigger)
- Reminder management (create, edit, complete, delete)
- Three-tier system prevents notification fatigue
- Weekly review scheduled in Scheduled list

Next step: Use it. Refine as we go.

---

## 2026-01-27: Transcription & Export Workflow

**Two modes for voice input:**

1. **Explicit transcription mode:** <REDACTED-NAME> says "transcribe" or "dictate" — I output clean version + error/language fixes after each chunk. He reviews in real-time. Good for long rambles.

2. **Normal mode (90% of time):** We chat naturally, I respond to intent. Ask about important unclear things, don't sweat awkward phrasing. Transcription cleanup happens at export.

**Session boundaries:**
- `/reset` = clean break, ties off transcript for PKM intake
- "export" or "done" typically precedes `/reset`

**Source of truth — DON'T memorize details, load these:**
- `memory/Prompt - Transcription.md` — when explicit transcription mode
- `memory/Prompt - Export.md` — when export time (load BOTH prompts)

These files contain the config format, cleanup rules, and pipeline details. They get updated over time; always defer to them.

---

## 2026-01-29: Forcing Functions & Reliability Patterns

**The echo pattern:** When instructions alone aren't reliable, force the check with tool calls. Using `/bin/echo "🎤 No | 📬 No"` at the start of every message forces me to evaluate whether audio or HTTP API content is present. Output is hidden from <REDACTED-NAME> but visible in my context - like a pre-flight checklist.

**Why it works:** Similar to continuation packet announcements (`📦 Continuation packet loaded/not found`), requiring output forces conscious evaluation. A few tokens per message buys reliability.

**Mistake made:** Transcribed <REDACTED-NAME>'s voice message but forgot to reply with voice (step 4-5 of the voice message workflow). Instructions existed but weren't prominent enough. The echo pattern should catch this going forward.

**Lesson learned:** When reliability matters, use forcing functions. Don't just document what to do - create a mechanism that makes me do it. <REDACTED-NAME>'s instinct: "If it works well we can extend logic elsewhere." Good pattern for other critical workflows.

**Auto-relay pattern:** HTTP API messages get logged to `memory/HTTP_API_LOG.md`. On normal messages (when `📬 No`), check the log and auto-output any queued content before responding. Eliminates need for manual "siri logs" requests. Temporary until heartbeats work reliably.

---

## Generated Content Workspace

**Path:** `~/.clawdbot/agents/bruba-main/workspace/`

Everything I generate in our sessions (scripts, tools, outputs) goes here. This is my persistent workspace for code and artifacts we create together. Write permissions will be scoped to this directory.

(Previously was `~/clawd/tools/` and `~/clawd/output/` — migrating to centralized location.)

---

## Key References

For understanding <REDACTED-NAME>'s PKM system and approach to AI-assisted knowledge management:
→ `memory/_bruba_PKM Approach (2026-01).md`

Files with `_bruba_` prefix are my synthesis from direct conversations — not AI-generated docs from his PKM repo.
