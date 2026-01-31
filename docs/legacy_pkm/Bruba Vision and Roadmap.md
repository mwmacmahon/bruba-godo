---
version: 2.0.1
updated: 2026-01-28
type: vision
project: bruba
tags: [bruba, clawdbot, vision, planning, roadmap]
description: "Bruba PKM-integrated personal assistant vision and roadmap"
status: active
---
# Bruba Vision and Roadmap

> **Purpose:** Comprehensive synthesis of intentions, aspirations, concerns, and design philosophy for Bruba (Clawdbot instance) and its PKM integration. Master reference for decision-making and roadmap planning.
>
> **Note:** This document captures current thinking, not a fixed plan. Many aspects are deliberately uncertain — Bruba's role, capabilities, and boundaries will evolve organically based on what actually works.
>
> **Active security issues:** See `Bruba Security Overview.md` § Active Security Issues

> **Claude Code:** If discussions reveal new design principles, shifted priorities, or evolved thinking about Bruba's role, update this document. This is the philosophy doc — capture the "why" behind decisions, not just the "what". Furthermore, if sections of it are no longer true or are irrelevant, please remove them. Version bump accordingly.

Make sure to notify <REDACTED-NAME> about these changes with a loud callout in your output text, but you don't have to ask permission (he validates git diffs).

---

## Part 1: Why Bruba Exists

### The Core Problem

The PKM system works well for deep work at the computer. But there are gaps:

| Gap | Current State | What's Missing |
|-----|---------------|----------------|
| **Mobile capture** | Voice memos, notes apps | No AI processing, manual export |
| **Mobile lookup** | Obsidian (clunky), Claude Projects (web) | No quick access to PKM knowledge |
| **Privacy-first personal chat** | Claude Projects (cloud, shared context) | Truly private conversations that stay local |
| **Always-on assistant** | Claude Code (session-based) | Something that persists, can be checked on |
| **Agentic background work** | Nothing | Tasks that run while I'm away |

### What Bruba Could Become

Bruba isn't just one thing. Depending on how it evolves, it might fill several roles:

**Capture channel** — Quick voice/text capture from anywhere, flowing into PKM intake pipeline.

**Mobile PKM interface** — Query reference docs, prompts, system documentation on the go.

**Privacy-first personal assistant** — For sensitive conversations that shouldn't touch cloud AI or shared contexts. Possibly with local LLM for maximum privacy.

**Agentic worker** — Background tasks, nudges about getting things done, Claude Code-style work that's ready when I return.

**Backend for custom UIs** — Serving web interfaces to phone/iPad, better than current Gateway Dashboard limitations.

**The shape this takes is uncertain.** Maybe Bruba stays simple. Maybe there are multiple Brubas with different trust levels and capabilities. The vision is organic, not prescribed.

### What Bruba Is NOT (Probably)

| Bruba Probably Is | Bruba Probably Is NOT |
|-------------------|----------------------|
| Complement to existing tools | Replacement for Claude Code |
| Privacy-conscious by design | Wide-open to all content |
| Self-hosted, local-first | Cloud-dependent |
| Evolving capabilities | Fixed feature set |

---

## Part 2: Architecture Philosophy

### Local-First Principles

**Core belief:** Cloud AI services are ephemeral cache; local storage is truth.

```
Authoritative                              Ephemeral
    ←─────────────────────────────────────────────→
Git repo       Obsidian      Bruba memory    Claude API
(PKM)          vault         (derived)       (stateless)
```

**Implications:**
- Bruba can disappear tomorrow; knowledge persists in PKM
- No vendor lock-in to Clawdbot, Anthropic, or Telegram
- All data accessible offline in standard formats (Markdown, JSON)
- Cloud services used for intelligence, not storage

### Integration with PKM Architecture

Bruba plugs into the existing PKM system, not around it:

**Bundle-based filtering:** PKM already has bundles (work, general, meta) with redaction rules. Bruba gets a *bundle view* of PKM content, not raw access. This is the same pattern as Claude Projects bundles.

**Intake pipeline:** Bruba conversations flow through the same intake → canonicalize → variants pipeline as everything else. The `/convert` human-in-the-loop step applies here too.

**Scope boundaries:** The existing scope system (work, home, personal, meta) determines what flows where. Bruba's access is governed by this, not separate rules.

### Data Flow Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                      PKM (Source of Truth)                          │
│  Git repo → reference/, prompts/, knowledge-capture/                │
└─────────────────────────────────────────────────────────────────────┘
        │                                         ▲
        │ PUSH (bundle-filtered)                  │ IMPORT (processed sessions)
        ▼                                         │
┌─────────────────────────────────────────────────────────────────────┐
│                            Bruba                                     │
│  ~/clawd/memory/ (searchable) ← Signal/WebChat conversations        │
└─────────────────────────────────────────────────────────────────────┘
        │
        │ MIRROR (backup, no processing)
        ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     reference/bruba-mirror/                          │
│  MEMORY.md, USER.md, journals — Bruba's own evolving files          │
└─────────────────────────────────────────────────────────────────────┘
```

**Three flows:**
| Flow | Direction | What Moves | Processing |
|------|-----------|------------|------------|
| **Push** | PKM → Bruba | Bundle-filtered content | Filter via config, sync, reindex |
| **Mirror** | Bruba → PKM | Bruba's living documents | Copy as-is, no modification |
| **Import** | Bruba → PKM | Closed sessions | parse-jsonl → /convert → intake pipeline |

### Trust Gradient

```
Most trusted                                    Least trusted
    ←─────────────────────────────────────────────────→
My code       Clawdbot       Docker sandbox    AI model
(adapters)    gateway        (tool execution)  (Claude)
```

**Variable trust is key.** Different Bruba configurations might have different trust levels:
- A "capture only" Bruba with minimal tools
- A "personal" Bruba with local LLM, no cloud API
- An "agentic" Bruba with more capabilities, after trust is established

### Multi-Agent Architecture

> **See also:** `docs/Bruba Setup SOP.md` section 1.10 — Config Architecture Reference with detailed clawdbot.json structure, inheritance model, and exec-approvals.json namespacing.

Bruba uses a subagent pattern for capability isolation:

```
┌─────────────────────────────────────────────────────────────────┐
│                    Bruba-Main Clawdbot Instance                 │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Main Agent (bruba-main)              │   │
│  │  Tools: read, write, edit, exec, memory_*, sessions_*   │   │
│  │  Denied: web_fetch, web_search, browser                 │   │
│  │  Access: Signal                                         │   │
│  └─────────────────────────┬───────────────────────────────┘   │
│                            │ sessions_send                      │
│  ┌─────────────────────────▼───────────────────────────────┐   │
│  │                   Reader Agent (web-reader)             │   │
│  │  Tools: web_search, web_fetch, read                     │   │
│  │  Denied: exec, write, edit, memory_*, sessions_*, ...   │   │
│  │  Sandbox: Docker (mode=all)                             │   │
│  │  Access: ONLY via sessions_send from main               │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

**Subagents vs separate instances:**
- Subagents share memory system, gateway, daemon process
- Use for: tool isolation (web search), task specialization
- Subagents CANNOT provide context/memory isolation

For full isolation (sensitive content that shouldn't touch Claude API):

```
┌─────────────────────────────┐     ┌─────────────────────────────┐
│   Bruba-Main (Claude API)   │     │  Bruba-Private (Local LLM)  │
│   Subagents: web-reader     │     │  Fully isolated instance    │
│   Memory: general context   │     │  Memory: private only       │
└─────────────────────────────┘     └─────────────────────────────┘
```

Bruba-Private is backlog/aspirational — implement when needed.

---

## Part 3: Security & Privacy

> **Full reference:** `docs/Bruba Security Overview.md` — Comprehensive security model, threat analysis, permission architecture, and operational guidelines.

### Core Security Philosophy

**What I'm protecting against:**
1. **Cross-contamination** — Work content leaking into personal assistant
2. **Cloud exposure** — Sensitive personal/health/financial content hitting Anthropic servers
3. **Prompt injection** — Malicious content manipulating Bruba
4. **Over-privileged access** — Bruba able to do things it shouldn't

**Defense layers:** Isolated macOS account → Channel lockdown → Tool deny list → Exec allowlist → Bundle-based filtering.

See Security Overview for implementation details and current status of each layer.

### Privacy-First Content Routing

Different content needs different paths — not just "sync or don't sync" but "which path?"

| Content Type | Approach |
|--------------|----------|
| **Meta** (PKM docs, prompts) | Sync to Bruba freely |
| **Home** (household, family) | Sync after trust established |
| **Personal** (health, relationships) | May never sync — local LLM or separate instance |
| **Work** | NEVER touches Bruba (absolute boundary) |

### Deal-Breakers (Non-Negotiable)

- ❌ Work content touches Bruba (absolute boundary)
- ❌ Cloud embeddings required (privacy violation)
- ❌ FDA required (security concern)
- ❌ Friction exceeds value (won't get used)
- ❌ Vendor lock-in emerges

---

## Part 4: Roadmap

### Phase 0: Foundation (Complete)

**January 2026 — Week 1-2**

Core infrastructure established:
- Clawdbot source install with local embeddings (sqlite-vec, hybrid BM25 + vector)
- Bruba service account with SSH isolation
- Telegram bot via BotFather
- Security hardening: sandboxed Docker, read-only workspace, no exec tools, network disabled
- Initial context files: SOUL.md, USER.md, IDENTITY.md, MEMORY.md

Key milestone: First successful Telegram conversation with memory search working.

### Phase 1: PKM Integration + Channels (Complete)

**January 2026 — Week 3-4**

> **PKM startup awareness:** Bruba's `AGENTS.md` now includes inventory awareness, key prompts table, and sync transparency. See `reference/bruba-mirror/main/prompts/AGENTS.md` section "PKM Knowledge Resources".

Three-flow architecture implemented:

| Flow | Direction | What Moves |
|------|-----------|------------|
| **Push** | PKM → Bruba | Filtered knowledge bundles |
| **Mirror** | Bruba → PKM | Bruba's files (backup, no processing) |
| **Import** | Bruba → PKM | Closed sessions → processed transcripts |

Channel migration:
- Signal for mobile: True E2EE, native voice messages, transcription pipeline
- Gateway Dashboard via Tailscale: Accessible from anywhere, HTTPS required
- Telegram deprecated (no E2EE)

Infrastructure delivered:
- Shell scripts: `mirror-bruba.sh`, `sync-to-bruba.sh`, `pull-bruba-sessions.sh`
- Session import pipeline: `parse-jsonl` → `/convert` → `canonicalize` → `variants`
- PKM skills: `/bruba:sync`, `/bruba:pull`, `/bruba:push`, `/bruba:status`
- State tracking via `~/.pkm-state/pulled-bruba-sessions.txt`

### Phase 2: Plugins + Bidirectional Intelligence (Current)

**Target: February 2026**

**Plugins to enable:**
| Plugin | Trust Level | Benefit | Status |
|--------|-------------|---------|--------|
| Voice transcription (local) | Low | Privacy-first voice processing | ✅ Working (Python whisper) |
| Apple Reminders | Medium | "Remind me to..." from anywhere | ✅ Working |
| Apple Calendar | Medium | Scheduling, context awareness | ✅ Working |

**Intelligence goals:**
- Bruba learns from PKM content via pushed bundles (curated, not raw dump)
- PKM learns from Bruba conversations via imported sessions
- Cross-reference capability: Bruba can surface relevant PKM docs during conversation

**Open design question:** How much context should flow each direction? Full knowledge graph or filtered summaries?

### Phase 3: Custom UI + Automation (Future)

**Target: Q2 2026**

**Custom UI vision:**
- Gateway Dashboard is admin-focused, not chat-optimized
- Build or adopt a chat UI with PKM-specific features:
  - Multiple profiles/contexts (switch between work-context, home-context)
  - Parallel conversations
  - Better conversation management than Signal
  - Integrated with pipeline (direct export to intake)
- Served via Tailscale, accessible from phone/iPad/laptop

**Automation:**
- Scheduled syncs via launchd (daily mirror, weekly full sync)
- Auto-detection of closed sessions ready for import
- Notification when sessions need `/convert` review
- Possible: Bruba-initiated PKM updates for high-signal conversations

**Explicit non-goal:** Fully automated `/convert`. Human judgment on metadata (title, scope, sensitivity) is worth the friction.

### Future Possibilities

**Multiple Brubas:**
| Instance | Backend | Trust Level | Purpose |
|----------|---------|-------------|---------|
| bruba-general | Claude API | Medium | Daily capture, PKM lookup |
| bruba-personal | Local LLM | High (local only) | Sensitive personal conversations |
| bruba-agentic | Claude API | Higher (more tools) | Background tasks, automation |

**Agentic Capabilities:**
- Task nudges — "You haven't looked at X in a while"
- Morning briefings — "Here's what's on your plate today"
- Background work — Run Claude Code-style tasks, results ready when I return
- Reminder integration — Bridge to Apple Reminders

**Infrastructure Evolution:**
| Phase | Infrastructure | Mobile Interface | Desktop Interface |
|-------|---------------|------------------|-------------------|
| Now | MacBook Air (M4) + caffeinate | Signal | Gateway Dashboard |
| Soon | Mac Mini (M4 base) | Signal | Gateway Dashboard |
| Future | Mac Mini | Signal + Custom UI | Custom PKM UI |

**Hardware note:** Mac required (not Linux) because iCloud Drive E2EE doesn't work on Linux. Mac Mini (even base tier M4) is the target always-on server.

---

## Part 5: Design Principles

### Core Principles (Stable)

1. **Friction Kills Adoption**
   - If capture requires >5 seconds and >2 taps, it won't happen
   - Low friction above all else

2. **Save Everything, Process Later**
   - Capture is cheap, judgment can wait
   - Sessions are authoritative (journals can fail silently)
   - ADHD-friendly: don't require decisions in the moment

3. **Human Judgment for Metadata**
   - /convert requires review (intentional friction)
   - AI can suggest, human decides
   - Automation would produce lower-quality archives

4. **Local-First Always**
   - Git repo is source of truth
   - Cloud AI is ephemeral cache
   - All data accessible offline
   - No vendor lock-in

5. **Privacy by Default**
   - Default to most private option
   - Explicit opt-in for data sharing
   - Work content isolation absolute
   - Prefer local transcription when feasible

6. **Platform Independence**
   - Standard formats (Markdown, JSON, Git)
   - System survives tool disappearance
   - "bruba" not "clawdbot" — prepared for alternatives

### Operational Principles (Evolving)

7. **Integrate with PKM, Don't Reinvent**
   - Use existing bundle system for filtering
   - Use existing intake pipeline for processing
   - Bruba is a channel, PKM is the system

8. **Variable Trust, Variable Capability**
   - Start locked down, expand carefully
   - Different instances can have different permissions
   - Trust is earned, not assumed

9. **Organic Evolution**
   - Don't over-plan
   - Build what's needed, see what works
   - The vision will change based on actual use

---

## Part 6: Concerns & Risks

### Technical Concerns

| Concern | Severity | Mitigation |
|---------|----------|------------|
| **Complexity creep** | High | Question every new feature, simplify regularly |
| **Reliability** | High | Sessions as authoritative, comprehensive SOPs |
| **Documentation drift** | Medium | Single source of truth, consolidation |
| **Gateway crashes** | Medium | Daemon management, recovery docs |

### Operational Concerns

| Concern | Severity | Thinking |
|---------|----------|----------|
| **Will I actually use this?** | High | Start simple, prove value before expanding |
| **Maintenance burden** | High | "Set and forget" as goal |
| **Human-in-the-loop bottleneck** | Medium | Accept some backlog, don't let perfect block good |
| **Long sessions daunting** | Medium | Need better approach — batching? splitting? |

### Red Flags to Watch

Signs Bruba is going wrong:
1. **Complexity exceeds value** — Setup/maintenance harder than benefit
2. **Friction increase** — More steps for basic things over time
3. **Privacy erosion** — Pressure for cloud services "just this once"
4. **Scope creep** — Adding features nobody asked for
5. **Work boundary blur** — Temptation to sync work content

**If these happen:** Stop, reassess, simplify or abandon.

---

## Part 7: Success Criteria

### Minimum Viable Success

- [x] Can capture via Signal → appears in PKM intake
- [x] Can query PKM knowledge via Signal/WebChat
- [x] Work content never touches Bruba
- [x] Stays running for days without intervention
- [x] Actually use it weekly

### What "Working Well" Looks Like

- [x] Bruba is go-to for quick capture (lower friction than alternatives)
- [x] PKM grows from Bruba conversations (after /convert review)
- [x] Bruba has useful PKM knowledge without manual intervention
- [x] Friction low enough that I reach for it naturally

### Aspirational Success

- [ ] Multiple Bruba instances with appropriate trust levels
- [ ] Custom web UI better than Gateway Dashboard
- [ ] Agentic features that actually help (nudges, briefings)
- [ ] Personal content handled privately (local LLM or fully segregated)
- [ ] "Just works" — don't think about the infrastructure

### Failure Modes

- Needs frequent debugging
- More friction than value
- Never actually use it
- Creates more problems than it solves

---

## Part 8: Open Questions

### Architecture

- [ ] Multiple Brubas: worth the complexity?
- [ ] Local LLM for personal content: feasible? worth it?
- [ ] Session merging across multiple sessions?
- [ ] Port 443 reclaim: what else might need Tailscale serve?

### Integration

- [ ] How does personal content flow? (To Bruba? Which Bruba? Local LLM?)
- [x] Reminders integration: share specific lists with bruba account
- [x] Calendar access: read-only on main, write to Bruba calendar?
- [ ] Agentic action approval workflow?
- [ ] Cross-context memory: should Bruba know about Claude Projects conversations?

### Custom UI (Future)

- [ ] Build vs adopt existing chat UI?
- [ ] What PKM-specific features matter most?
- [ ] How to handle multiple profiles/contexts in UI?
- [ ] Direct pipeline integration (export to intake from UI)?

### Operational

- [ ] Sustainable maintenance burden?
- [ ] Backup/restore strategy?
- [ ] Update testing approach?
- [ ] Retention policy for raw sessions?

### Clawdbot Features (Researched)

- [ ] Heartbeat.md — how does proactive messaging work?
- [ ] Can Bruba initiate messages or only respond?
- [x] Web UI capabilities? — **Gateway Dashboard: admin + basic chat, not optimized for conversation**
- [x] Multiple agent configurations? — **Yes, per-agent model/tools/permissions**
- [x] Backend swapping (Claude API vs local LLM)? — **Fully supported via config**
- [x] Best replacement for Telegram UX — **Signal (mobile) + Gateway Dashboard (desktop fallback)**
- [x] Remote access approach — **Manual Tailscale serve (not Clawdbot's built-in)**

---

## Part 9: Decision Log

| Decision | Date | Rationale |
|----------|------|-----------|
| Separate Mac account | 2026-01-25 | Isolation during trust-building |
| Telegram only (no iMessage) | 2026-01-25 | Avoid FDA requirement |
| Start with meta scope | 2026-01-25 | Prove value before expanding |
| Local embeddings | 2026-01-25 | Privacy > convenience |
| Source install | 2026-01-25 | Control > simplicity |
| Human-in-the-loop /convert | 2026-01-26 | Quality > automation |
| Sessions as authoritative | 2026-01-26 | Journals unreliable |
| Three-flow architecture | 2026-01-26 | Clear separation of concerns |
| Bundle-based sync | 2026-01-26 | Integrate with PKM system |
| Signal for mobile interface | 2026-01-26 | True E2EE, native voice, no Telegram privacy leak |
| Gateway Dashboard for desktop | 2026-01-26 | Admin + fallback chat, not primary interface |
| Manual Tailscale serve | 2026-01-26 | Simpler than Clawdbot's built-in; avoids bind conflicts |
| Defer custom UI | 2026-01-26 | Gateway Dashboard sufficient for now |
| Mac Mini required (not Linux) | 2026-01-26 | iCloud Drive E2EE doesn't work on Linux |
| Python whisper (not whisper.cpp) | 2026-01-26 | Handles m4a format from Signal |
| Full path in daemon config | 2026-01-26 | Daemon doesn't load .zshrc |
| Prefer local transcription | 2026-01-26 | Privacy; cloud APIs only when local fails |
| Exec lockdown (gateway + allowlist) | 2026-01-27 | sandbox.mode: off alone doesn't enforce allowlist |
| Token economics accepted (~8k base) | 2026-01-27 | 10x more efficient than Claude Projects |
| `_bruba_` prefix convention | 2026-01-27 | Distinguish Bruba-origin synthesis from inherited AI docs |
| Context tracking via session_status | 2026-01-27 | Threshold warnings at 100k/150k/180k |
| Unscoped filesystem commands | 2026-01-27 | Approval UX broken; account isolation sufficient for now |
| Local TTS (sherpa-onnx) | 2026-01-27 | Privacy-first voice responses; no cloud TTS |
| Exec self-escalation documented | 2026-01-27 | Agent can edit exec-approvals.json; security theater until fixed |
| Prompt-driven voice (not auto) | 2026-01-28 | Clawdbot's tools.media.audio CLI provider doesn't invoke wrapper scripts; manual transcription via exec is reliable |
| Web search via reader subagent | 2026-01-28 | Tool isolation for injection safety; Opus for both agents; explicit user permission required |

---

**End of Vision & Roadmap Document**

*This document captures current thinking about Bruba's potential. It's deliberately uncertain in places — the vision will evolve based on what actually works in practice.*

> **Note:** Key learnings and operational gotchas are in `Bruba Setup SOP.md` Part 8.
