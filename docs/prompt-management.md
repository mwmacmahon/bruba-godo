---
version: 1.0.0
updated: 2026-02-03
type: refdoc
project: planning
tags: [bruba, prompts, assembly, components, budget, openclaw]
---

# Bruba Prompt Management Reference

How prompts are structured, assembled, and deployed. Covers the component system, character budgets, and best practices for keeping prompts effective without bloating.

---

## Executive Summary

**The constraint:** OpenClaw injects AGENTS.md into context at session start with a **hard limit of 20,000 characters**. Exceeding this causes truncation — the agent loses instructions mid-prompt.

**The system:** Prompts are assembled from modular components on the operator machine (bruba-godo), then pushed to the bot. This allows reuse across agents while customizing per-agent behavior.

**The discipline:** Every component must be concise. Verbose examples, duplicated explanations, and "nice to have" sections bloat the prompt and risk losing critical instructions.

---

## Part 1: The 20k Budget

### Why It Matters

OpenClaw reads workspace files (AGENTS.md, TOOLS.md, etc.) and injects them into the system prompt. Each file has a character limit:

| File | Limit | Purpose |
|------|-------|---------|
| AGENTS.md | 20,000 chars | Main behavioral instructions |
| TOOLS.md | 20,000 chars | Tool-specific guidance |
| HEARTBEAT.md | 20,000 chars | Heartbeat behavior (Manager) |
| IDENTITY.md | 20,000 chars | Persona, voice |
| SOUL.md | 20,000 chars | Values, personality |
| USER.md | 20,000 chars | User context |

When a file exceeds its limit, OpenClaw truncates with a head/tail approach and logs a warning:
```
workspace bootstrap file AGENTS.md is 34679 chars (limit 20000); truncating
```

**Truncation is silent to the agent** — it just loses instructions without knowing.

### Current Budget Status

As of 2026-02-03:

| Agent | AGENTS.md Size | Budget | Headroom |
|-------|----------------|--------|----------|
| bruba-main | 19,053 chars | 20,000 | ~950 chars |
| bruba-guru | ~8,000 chars | 20,000 | ~12,000 chars |
| bruba-manager | ~6,000 chars | 20,000 | ~14,000 chars |
| bruba-web | ~2,000 chars | 20,000 | ~18,000 chars |

**bruba-main is near capacity.** New components need to be offset by trimming existing ones.

### Checking Budget

```bash
# After assembly
wc -c agents/bruba-main/exports/core-prompts/AGENTS.md

# Or check deployed version
./tools/bot 'wc -c /Users/bruba/agents/bruba-main/AGENTS.md'
```

---

## Part 2: Assembly System

### Source → Assembly → Deploy

```
bruba-godo/                           Bot
────────────────────────────────────  ────────────────────────
config.yaml (section definitions)
        │
        ▼
┌─────────────────────────────┐
│   assemble-prompts.sh       │
│                             │
│   Resolves sections:        │
│   • base → templates/       │
│   • component → components/ │
│   • section → sections/     │
│   • bot:* → agents/*/mirror/ │
└─────────────────────────────┘
        │
        ▼
agents/{agent}/exports/core-prompts/  push.sh →    /Users/bruba/agents/{agent}/
        │                                                    │
   AGENTS.md (assembled)                               AGENTS.md (deployed)
   TOOLS.md (assembled)                                TOOLS.md (deployed)
```

### Section Types

| Type | Config Entry | Source Location | Notes |
|------|--------------|-----------------|-------|
| `base` | `base` | `templates/prompts/{NAME}.md` | Full file, starting point |
| `{agent}-base` | `guru-base` | `templates/prompts/guru/{NAME}.md` | Agent-specific base |
| `component` | `component-name` | `components/{name}/prompts/{NAME}.snippet.md` | Modular capability |
| `section` | `section-name` | `templates/prompts/sections/{name}.md` | Shared fragment |
| `bot-managed` | `bot:section-name` | `agents/{agent}/mirror/prompts/{NAME}.md` | Extracted from bot |

### Config Example

```yaml
# config.yaml
agents:
  bruba-main:
    agents_sections:
      - header              # → templates/prompts/sections/header.md
      - http-api            # → components/http-api/prompts/AGENTS.snippet.md
      - session             # → components/session/prompts/AGENTS.snippet.md
      - voice               # → components/voice/prompts/AGENTS.snippet.md
      - guru-routing        # → components/guru-routing/prompts/AGENTS.snippet.md
      # ... more components
    
    tools_sections:
      - base                # → templates/prompts/TOOLS.md
      - reminders           # → components/reminders/prompts/TOOLS.snippet.md
      - message-tool        # → components/message-tool/prompts/TOOLS.snippet.md

  bruba-guru:
    agents_sections:
      - guru-base           # → templates/prompts/guru/AGENTS.md
      - continuity          # → components/continuity/prompts/AGENTS.snippet.md
```

### Component Variants

Components can provide multiple prompt snippets for different agents or roles using the `component:variant` syntax.

**Why variants?** Some capabilities need different prompts depending on the agent's role:

| Component | Variant | Agent | Purpose |
|-----------|---------|-------|---------|
| `siri-async` | `:router` | bruba-manager | Receives HTTP, forwards to Main |
| `siri-async` | `:handler` | bruba-main | Processes forwarded requests |
| `web-search` | `:consumer` | bruba-main | How to use bruba-web |
| `web-search` | `:service` | bruba-web | How to be bruba-web (planned) |

**File naming:**
- Default: `components/{name}/prompts/{NAME}.snippet.md`
- Variant: `components/{name}/prompts/{NAME}.{variant}.snippet.md`

**Config example:**
```yaml
agents:
  bruba-main:
    agents_sections:
      - siri-async:handler    # → AGENTS.handler.snippet.md
      - web-search            # → AGENTS.snippet.md (default)

  bruba-manager:
    agents_sections:
      - siri-async:router     # → AGENTS.router.snippet.md
```

**No fallback rule:** If you specify `:variant`, that exact file must exist. The system won't fall back to the default file — this prevents silent misconfiguration.

### Allowlist Variants

Allowlist files can also have variants for component-specific exec permissions:

- Default: `components/{name}/allowlist.json`
- Variant: `components/{name}/allowlist.{variant}.json`

### Assembly Commands

```bash
# Assemble all agents
./tools/assemble-prompts.sh

# Force reassemble (even if sources unchanged)
./tools/assemble-prompts.sh --force

# Check output
wc -c agents/*/exports/core-prompts/AGENTS.md
```

### Conflict Detection

Before pushing, detect if the bot has made changes that would be overwritten:

```bash
./tools/detect-conflicts.sh                        # Check for conflicts
./tools/detect-conflicts.sh --diff siri-async:handler  # Show specific diff
```

**Conflict types:**
1. New bot-managed sections (bot created a new `<!-- BOT-MANAGED: x -->`)
2. Edited components (bot modified content inside a `<!-- COMPONENT: x -->`)

---

## Part 3: Component Anatomy

### File Structure

```
components/
├── voice/
│   ├── README.md                    # Documentation (not assembled)
│   └── prompts/
│       ├── AGENTS.snippet.md        # For AGENTS.md assembly
│       └── TOOLS.snippet.md         # For TOOLS.md assembly (if needed)
├── guru-routing/
│   ├── README.md
│   └── prompts/
│       └── AGENTS.snippet.md
└── message-tool/
    └── prompts/
        └── AGENTS.snippet.md
```

### Snippet Format

```markdown
<!-- COMPONENT: voice -->
## 🎤 Voice Messages

[Content here]

<!-- /COMPONENT: voice -->
```

The comment markers help identify component boundaries in the assembled output.

### Size Guidelines

| Component Type | Target Size | Max Size |
|----------------|-------------|----------|
| Simple capability | 500-800 chars | 1,200 chars |
| Medium capability | 800-1,500 chars | 2,000 chars |
| Complex capability | 1,500-2,500 chars | 3,500 chars |

**If a component exceeds 3,500 chars**, it's probably trying to do too much. Split it or move details to TOOLS.md.

---

## Part 4: Writing Concise Prompts

### What to Include

✅ **Always include:**
- Trigger conditions (when does this apply?)
- Core behavior (what should the agent do?)
- Critical syntax (exact command format)
- One minimal example (if pattern isn't obvious)

### What to Exclude

❌ **Cut ruthlessly:**
- Multiple examples showing the same pattern
- "Why this works" explanations (agent doesn't need to understand why)
- Troubleshooting sections (agent can figure it out)
- Edge cases that rarely occur
- Duplicate information covered elsewhere

### Before/After Examples

**Verbose (bad):**
```markdown
## Voice Messages

### Receiving Voice Messages

When <REDACTED-NAME> sends a voice note, you'll see a message that looks like this:
```
[Signal <REDACTED-NAME> id:uuid:18ce66e6-... +5s 2026-02-03 10:30 EST] 
[media attached: /Users/bruba/.openclaw/media/signal/voice-xxxx.m4a type:audio/mp4 size:45KB duration:12s]
[message_id: 1234567890]
```

The media attached line tells you where the audio file is located on the filesystem.
The type will be audio/mp4 for voice messages.
The duration tells you how long the voice note is.

### Processing Voice Input

To process the voice input, you need to:

1. **Transcribe** the audio using whisper:
   The whisper-clean.sh script will take the audio file and output text.
   ```
   exec /Users/bruba/agents/bruba-main/tools/whisper-clean.sh "/path/to/audio.m4a"
   ```
   
2. **Process** the transcribed content:
   Once you have the text, understand what <REDACTED-NAME> is asking or saying.
   Think about what response would be appropriate.

3. **Formulate** your text response:
   Write out what you want to say back to <REDACTED-NAME>.

### Sending Voice Response

4. **Generate TTS** audio file:
   Use the text-to-speech script to convert your response to audio.
   ```
   exec /Users/bruba/agents/bruba-main/tools/tts.sh "Your response text here" /tmp/response.wav
   ```
   The first argument is the text to speak.
   The second argument is where to save the audio file.

[...continues for 50 more lines...]
```

**Concise (good):**
```markdown
## 🎤 Voice Messages

**Receive:** `[media attached: /path/to/voice.m4a ...]`

**Process:**
1. `exec /Users/bruba/agents/bruba-main/tools/whisper-clean.sh "/path/to/audio.m4a"` → transcription
2. Process content, formulate response
3. `exec /Users/bruba/agents/bruba-main/tools/tts.sh "response" /tmp/response.wav`
4. `message action=send target=uuid:18ce66e6-... filePath=/tmp/response.wav message="response"`
5. `NO_REPLY`

**Why NO_REPLY?** Prevents duplicate — message tool already delivered to Signal.
```

**Savings:** ~2,000 chars → ~500 chars (75% reduction)

### Inline vs Block Examples

**Block examples (verbose):**
```markdown
### Example: Creating a Reminder

```
User: remind me to call the dentist tomorrow

You: I'll create that reminder for you.

exec remindctl add --list "Immediate" --title "Call the dentist" --due "tomorrow 9am"

Done! I've set a reminder to call the dentist for tomorrow at 9 AM.
```
```

**Inline examples (concise):**
```markdown
**Reminder:** `exec remindctl add --list "Immediate" --title "Call dentist" --due "tomorrow 9am"`
```

Use block examples only when the multi-step flow is critical and non-obvious.

---

## Part 5: TOOLS.md vs AGENTS.md Split

### When to Put in AGENTS.md

- **Behavioral guidance** — when to do something, how to decide
- **Integration patterns** — how components work together
- **Trigger conditions** — what activates this behavior
- **Brief syntax** — just enough to show the pattern

### When to Put in TOOLS.md

- **Detailed syntax** — all parameters, options, variations
- **Tool-specific examples** — multiple use cases of one tool
- **Error handling** — what to do when tool fails
- **Reference tables** — option lists, flag meanings

### Example Split

**AGENTS.md (behavioral):**
```markdown
## Voice Messages

Voice input → transcribe → process → TTS → message tool → NO_REPLY

See TOOLS.md for whisper and tts syntax.
```

**TOOLS.md (reference):**
```markdown
### whisper-clean.sh
Transcribe audio to text.
`exec /Users/bruba/agents/bruba-main/tools/whisper-clean.sh "/path/to/audio"`
Output: transcribed text to stdout

### tts.sh
Generate speech from text.
`exec /Users/bruba/agents/bruba-main/tools/tts.sh "text" /output/path.wav`
Args: 1=text, 2=output path
```

---

## Part 6: Adding New Components

### Pre-Flight Check

Before adding a component:

1. **Check current budget:**
   ```bash
   wc -c agents/bruba-main/exports/core-prompts/AGENTS.md
   ```

2. **Estimate new component size:**
   ```bash
   wc -c components/new-component/prompts/AGENTS.snippet.md
   ```

3. **Verify headroom:**
   - Current + New < 19,500 chars → Safe
   - Current + New > 19,500 chars → Need to trim elsewhere first

### Adding to Config

```yaml
# config.yaml
agents:
  bruba-main:
    agents_sections:
      # ... existing sections ...
      - new-component    # Add at logical position
```

### Post-Add Verification

```bash
# Reassemble
./tools/assemble-prompts.sh --force

# Check size
wc -c agents/bruba-main/exports/core-prompts/AGENTS.md
# Must be < 20000

# Deploy
./tools/push.sh

# Verify no truncation warning
./tools/bot 'tail -20 ~/.openclaw/logs/gateway.log | grep -i truncat'
```

---

## Part 7: Trimming Workflow

When you need to reduce prompt size:

### 1. Identify Targets

```bash
# Get section sizes from assembled output
# Look for <!-- COMPONENT: name --> markers

grep -n "COMPONENT:" agents/bruba-main/exports/core-prompts/AGENTS.md
```

### 2. Prioritize Cuts

| Priority | What to Cut |
|----------|-------------|
| High | Duplicate information (already covered elsewhere) |
| High | Multiple examples of same pattern |
| Medium | Verbose explanations |
| Medium | Troubleshooting sections |
| Low | Useful but rarely-needed details |
| Never | Core behavioral triggers |
| Never | Critical syntax (exact commands) |

### 3. Edit Components

Edit the source files in `components/` or `templates/`, not the assembled output.

### 4. Verify

```bash
./tools/assemble-prompts.sh --force
wc -c agents/bruba-main/exports/core-prompts/AGENTS.md

# Test critical flows still work
./tools/bot 'openclaw agent --agent bruba-main --message "test voice workflow"'
```

### 5. Document

Create a CC log documenting what was trimmed:

```markdown
---
type: claude_code_log
title: "AGENTS.md Trimming"
---

# Summary
Reduced from X to Y chars (Z% reduction)

## Changes by Component
| Component | Before | After | Saved |
|-----------|--------|-------|-------|
| voice | 2,756 | 967 | 1,789 |
...
```

---

## Part 8: Component Inventory

Current components and their sizes (as of 2026-02-03):

### bruba-main AGENTS.md Components

| Component | Size | Purpose |
|-----------|------|---------|
| header | ~300 | Identity, basic behavior |
| http-api | ~920 | Siri integration patterns |
| session | ~650 | Session management |
| continuity | ~1,200 | Continuation packets |
| distill | ~1,500 | PKM/memory integration |
| voice | ~970 | Voice message handling |
| signal | ~790 | Signal-specific patterns |
| guru-routing | ~1,630 | Technical routing to Guru |
| group-chats | ~850 | Group chat behavior |
| web-search | ~900 | Web search via bruba-web |
| cc-packets | ~900 | Claude Code packet format |
| repo-reference | ~800 | bruba-godo reference |
| reminders | ~1,500 | Apple Reminders integration |
| signal-media-filter | ~400 | Media handling |
| **Total** | **~19,000** | |

### Where Headroom Exists

- bruba-guru: ~12,000 chars available
- bruba-manager: ~14,000 chars available  
- bruba-web: ~18,000 chars available
- TOOLS.md files: Generally underutilized

**Strategy:** Move detailed reference content from AGENTS.md to TOOLS.md to free up behavioral budget.

---

## Part 9: Best Practices Summary

### Do

- ✅ Check budget before adding components
- ✅ Use inline examples over block examples
- ✅ Split behavioral (AGENTS) from reference (TOOLS)
- ✅ Include one example, not three
- ✅ Document cuts when trimming
- ✅ Test critical flows after changes

### Don't

- ❌ Add "nice to have" explanations
- ❌ Duplicate information across components
- ❌ Include troubleshooting in AGENTS.md
- ❌ Use verbose formatting (bullets, headers) when inline works
- ❌ Edit assembled output directly (edit sources)
- ❌ Forget to verify size after changes

### Golden Rule

**If it's not essential for the agent to succeed at its task, cut it.**

The agent is smart. It can figure out edge cases. What it can't do is recover instructions that were truncated.

---

## Part 10: Quick Reference

### File Locations

| What | Where |
|------|-------|
| Component sources | `bruba-godo/components/{name}/prompts/` |
| Section sources | `bruba-godo/templates/prompts/sections/` |
| Base templates | `bruba-godo/templates/prompts/` |
| Assembly config | `bruba-godo/config.yaml` |
| Assembled output | `bruba-godo/agents/{agent}/exports/core-prompts/` |
| Deployed prompts | `/Users/bruba/agents/{agent}/` |

### Commands

```bash
# Check budget
wc -c agents/bruba-main/exports/core-prompts/AGENTS.md

# Assemble
./tools/assemble-prompts.sh --force

# Deploy
./tools/push.sh

# Verify no truncation
./tools/bot 'grep -i truncat ~/.openclaw/logs/gateway.log | tail -5'
```

### Limits

| Constraint | Value |
|------------|-------|
| AGENTS.md limit | 20,000 chars |
| Safe target | 19,500 chars |
| Comfort zone | 18,000 chars |
| bruba-main current | ~19,000 chars |

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.1.0 | 2026-02-06 | Merged from masterdoc: component variants, allowlist variants, conflict detection. Removed stale WARNING header. |
| 1.0.0 | 2026-02-03 | Initial version after AGENTS.md trimming effort |