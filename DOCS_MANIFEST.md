# Documentation Manifest

Inventory of all tracked markdown files in bruba-godo.

- **Date:** 2026-02-06
- **Total files:** 112
- **Total size:** ~706 KB
- **Method:** `git ls-files '*.md'` — only tracked files; gitignored content (cc_logs/, packets/, exports/) excluded

---

## By Type

| Type | Count | Description |
|------|------:|-------------|
| skill | 24 | Claude Code skill definitions (`.claude/commands/`) |
| prompt-snippet | 21 | Component prompt snippets for assembly pipeline |
| template | 16 | Prompt templates and role-specific variants |
| reference | 16 | Architecture docs, guides, deep-dives |
| readme | 14 | Directory overviews |
| test-fixture | 10 | Test input/reference files for distill pipeline |
| template-section | 6 | Small AGENTS.md section fragments |
| wip-log | 3 | Work-in-progress notes (`_` prefixed in `docs/`) |
| test-doc | 1 | Manual test procedures |
| config-doc | 1 | Repo-level configuration (`CLAUDE.md`) |

---

## By Location

```
bruba-godo/
├── .claude/commands/           24 files   Skills (Claude Code slash commands)
├── components/                  1 file    Component registry README
│   ├── distill/                 1 file    README
│   │   └── prompts/            3 files   AGENTS snippet, Export, Transcription
│   ├── guru-routing/            1 file    README
│   │   └── prompts/            1 file    AGENTS snippet
│   ├── local-voice/             1 file    README
│   │   └── prompts/            1 file    AGENTS snippet
│   ├── reminders/               1 file    README
│   │   └── prompts/            2 files   AGENTS + TOOLS snippets
│   ├── signal/                  1 file    README
│   │   └── prompts/            1 file    AGENTS snippet
│   └── snippets/                1 file    README
│       └── prompts/           13 files   Prompt-only component snippets
├── cronjobs/                    1 file    README
├── docs/                       21 files   Reference docs, guides, WIP notes
├── templates/prompts/           8 files   Base templates + README
│   ├── guru/                   3 files   Guru role templates
│   ├── helper/                  1 file    Helper role README
│   ├── manager/                5 files   Manager role templates
│   ├── sections/               6 files   AGENTS.md section fragments
│   └── web/                    1 file    Web role AGENTS template
├── tests/                       2 files   Test README + assembly tests
│   └── fixtures/                1 file    FIXTURES.md
│       ├── 001-ui-artifacts/    1 file    input.md
│       ├── 002-section-removal/ 1 file    input.md
│       ├── 003-transcription-corrections/ 1 file  input.md
│       ├── 004-code-blocks/     1 file    input.md
│       ├── 005-full-export/     1 file    input.md
│       ├── 006-v1-migration/    1 file    input.md
│       ├── 007-paste-and-export/ 1 file   input.md
│       ├── 008-filter-test/     1 file    canonical-with-sensitivity.md
│       └── 009-e2e-pipeline/    1 file    input.md
├── CLAUDE.md                    1 file    Repo instructions for Claude Code
└── README.md                    1 file    Repo overview
```

---

## Full Inventory

### Root

| Path | Type | Size | Lines | Purpose |
|------|------|-----:|------:|---------|
| `CLAUDE.md` | config-doc | 9.7 KB | 288 | Instructions for Claude Code when working in this repo |
| `README.md` | readme | 5.9 KB | 137 | Repo overview: what bruba-godo is, quick start, directory map |

### `.claude/commands/` — Skills

| Path | Type | Size | Lines | Purpose |
|------|------|-----:|------:|---------|
| `bruba-help.md` | skill | 2.1 KB | 74 | Meta-help: suggests relevant skills for a given question |
| `code.md` | skill | 8.5 KB | 251 | Review and migrate staged code to bot |
| `component.md` | skill | 4.0 KB | 155 | Enable/disable/configure components |
| `config-sync.md` | skill | 3.5 KB | 182 | Sync config.yaml settings to openclaw.json |
| `config.md` | skill | 5.4 KB | 187 | Configure heartbeat, exec allowlist interactively |
| `convert.md` | skill | 11.2 KB | 377 | AI-assisted: add CONFIG block + summary to intake file |
| `convo.md` | skill | 3.1 KB | 116 | Load active conversation from bot |
| `export.md` | skill | 4.3 KB | 164 | Generate filtered exports from canonical files |
| `intake.md` | skill | 9.4 KB | 326 | Batch canonicalize intake files with CONFIG blocks |
| `launch.md` | skill | 0.9 KB | 56 | Start the bot daemon |
| `mirror.md` | skill | 0.8 KB | 46 | Pull bot files locally for inspection |
| `morning-check.md` | skill | 1.1 KB | 47 | Verify post-reset wake succeeded |
| `prompt-sync.md` | skill | 4.6 KB | 189 | Assemble prompts + push with conflict detection |
| `prompts.md` | skill | 4.4 KB | 135 | Manage prompt assembly, resolve conflicts, explain config |
| `pull.md` | skill | 2.3 KB | 83 | Pull closed sessions + convert to intake |
| `push.md` | skill | 3.5 KB | 136 | Sync exports and content to bot memory |
| `restart.md` | skill | 0.9 KB | 55 | Restart the bot daemon |
| `status.md` | skill | 1.0 KB | 54 | Show daemon + local state |
| `stop.md` | skill | 0.7 KB | 46 | Stop the bot daemon |
| `sync.md` | skill | 5.6 KB | 223 | Full pipeline sync (prompts + config + content + vault) |
| `test.md` | skill | 1.2 KB | 76 | Run test suite |
| `update.md` | skill | 7.3 KB | 288 | Update openclaw version on bot |
| `vault-sync.md` | skill | 1.5 KB | 66 | Commit vault repo changes |
| `wake.md` | skill | 1.1 KB | 59 | Wake all agents |

### `components/` — Component Docs

| Path | Type | Size | Lines | Purpose |
|------|------|-----:|------:|---------|
| `components/README.md` | readme | 3.9 KB | 113 | Component registry: list, status, how to add new ones |
| `components/distill/README.md` | readme | 10.7 KB | 324 | Distill pipeline: conversation-to-knowledge processing |
| `components/distill/prompts/AGENTS.snippet.md` | prompt-snippet | 1.5 KB | 47 | AGENTS.md snippet for distill capabilities |
| `components/distill/prompts/Export.md` | prompt-snippet | 9.9 KB | 310 | LLM prompt for export filtering and redaction |
| `components/distill/prompts/Transcription.md` | prompt-snippet | 6.3 KB | 170 | LLM prompt for transcription cleanup |
| `components/guru-routing/README.md` | readme | 5.0 KB | 161 | Guru routing: forward technical questions to specialist agent |
| `components/guru-routing/prompts/AGENTS.snippet.md` | prompt-snippet | 1.6 KB | 47 | AGENTS.md snippet for guru routing behavior |
| `components/local-voice/README.md` | readme | 0.9 KB | 40 | Local voice: speech input/output via whisper + TTS |
| `components/local-voice/prompts/AGENTS.snippet.md` | prompt-snippet | 0.8 KB | 28 | AGENTS.md snippet for voice capabilities |
| `components/reminders/README.md` | readme | 5.7 KB | 187 | Reminders: Apple Reminders integration |
| `components/reminders/prompts/AGENTS.snippet.md` | prompt-snippet | 1.1 KB | 31 | AGENTS.md snippet for reminders behavior |
| `components/reminders/prompts/TOOLS.snippet.md` | prompt-snippet | 2.5 KB | 69 | TOOLS.md snippet for reminder tool definitions |
| `components/signal/README.md` | readme | 15.4 KB | 572 | Signal: full setup guide for Signal messaging channel |
| `components/signal/prompts/AGENTS.snippet.md` | prompt-snippet | 0.8 KB | 33 | AGENTS.md snippet for Signal messaging behavior |
| `components/snippets/README.md` | readme | 2.0 KB | 57 | Snippets: prompt-only components using variant naming |
| `components/snippets/prompts/AGENTS.continuity.snippet.md` | prompt-snippet | 1.1 KB | 46 | Session continuity and context-passing guidance |
| `components/snippets/prompts/AGENTS.cross-comms.snippet.md` | prompt-snippet | 0.8 KB | 25 | Cross-agent communication protocol |
| `components/snippets/prompts/AGENTS.emotional-intelligence.snippet.md` | prompt-snippet | 2.1 KB | 23 | Emotional awareness and empathy guidelines |
| `components/snippets/prompts/AGENTS.group-chats.snippet.md` | prompt-snippet | 0.2 KB | 3 | Group chat behavior stub |
| `components/snippets/prompts/AGENTS.heartbeats.snippet.md` | prompt-snippet | 2.8 KB | 71 | Heartbeat scheduling and behavior |
| `components/snippets/prompts/AGENTS.memory.snippet.md` | prompt-snippet | 2.1 KB | 40 | Memory management and knowledge retention |
| `components/snippets/prompts/AGENTS.message-tool.snippet.md` | prompt-snippet | 1.7 KB | 63 | Message tool usage rules and formatting |
| `components/snippets/prompts/AGENTS.repo-reference.snippet.md` | prompt-snippet | 1.4 KB | 48 | Repo file referencing in responses |
| `components/snippets/prompts/AGENTS.session.snippet.md` | prompt-snippet | 0.6 KB | 20 | Session lifecycle and cleanup behavior |
| `components/snippets/prompts/AGENTS.siri-handler.snippet.md` | prompt-snippet | 0.9 KB | 28 | Siri request handling behavior |
| `components/snippets/prompts/AGENTS.siri-router.snippet.md` | prompt-snippet | 0.8 KB | 16 | Siri intent routing rules |
| `components/snippets/prompts/AGENTS.web-search.snippet.md` | prompt-snippet | 1.0 KB | 34 | Web search tool usage guidelines |
| `components/snippets/prompts/AGENTS.workspace.snippet.md` | prompt-snippet | 0.6 KB | 17 | Workspace file management rules |

### `cronjobs/`

| Path | Type | Size | Lines | Purpose |
|------|------|-----:|------:|---------|
| `cronjobs/README.md` | readme | 2.3 KB | 58 | Cron job system: definitions and generation process |

### `docs/` — Reference Documentation

| Path | Type | Size | Lines | Purpose |
|------|------|-----:|------:|---------|
| `docs/INDEX.md` | readme | 2.5 KB | 66 | Quick reference index for docs/ directory |
| `docs/README.md` | readme | 3.0 KB | 59 | Navigation hub for docs/ with task-based quick links |
| `docs/architecture-masterdoc.md` | reference | 89.8 KB | 2187 | **Largest file.** Master reference for multi-agent architecture |
| `docs/bruba-vision.md` | reference | 17.3 KB | 484 | Bot-agnostic operator design philosophy and decision log |
| `docs/bruba-web-docker-migration.md` | reference | 14.3 KB | 387 | Docker sandbox migration plan for bruba-web |
| `docs/component-status.md` | reference | 3.5 KB | 81 | Component inventory with statuses |
| `docs/efficiency-recommendations.md` | reference | 12.9 KB | 412 | Sync pipeline optimization recommendations |
| `docs/filesystem-guide.md` | reference | 54.4 KB | 1235 | Directory structure, file locations, path conventions |
| `docs/operations-guide.md` | reference | 14.1 KB | 481 | Day-to-day bot operations and maintenance |
| `docs/per-agent-pipeline.md` | reference | 3.2 KB | 94 | Per-agent content pipeline architecture |
| `docs/pipeline.md` | reference | 21.3 KB | 742 | Content pipeline: intake through export |
| `docs/prompt-management.md` | reference | 16.2 KB | 567 | Prompt assembly system deep-dive |
| `docs/security-model.md` | reference | 17.0 KB | 506 | Threat model, permissions, exec allowlists |
| `docs/session-lifecycles.md` | reference | 19.9 KB | 605 | Agent session management and reset patterns |
| `docs/setup.md` | reference | 20.4 KB | 882 | End-to-end setup guide for OpenClaw |
| `docs/troubleshooting.md` | reference | 15.8 KB | 581 | Common issues and solutions by symptom |
| `docs/vault-strategy.md` | reference | 6.9 KB | 187 | Vault mode: symlink-based private content management |
| `docs/voice-integration.md` | reference | 19.6 KB | 625 | Voice handling (STT/TTS) and Siri integration |
| `docs/_agentic-system-overhaul-notes.md` | wip-log | 18.9 KB | 591 | WIP: Agentic system redesign notes |
| `docs/_agentic-system-overhaul-prompts.md` | wip-log | 23.5 KB | 875 | WIP: Prompt snippets for planned overhaul |
| `docs/_node-host-migration-plan.md` | wip-log | 21.5 KB | 729 | WIP: Node host migration planning |

### `templates/prompts/` — Prompt Templates

| Path | Type | Size | Lines | Purpose |
|------|------|-----:|------:|---------|
| `templates/prompts/README.md` | readme | 10.1 KB | 317 | Config-driven prompt assembly system documentation |
| `templates/prompts/BOOTSTRAP.md` | template | 1.2 KB | 43 | Bootstrap prompt: first-run initialization |
| `templates/prompts/HEARTBEAT.md` | template | 0.4 KB | 19 | Heartbeat prompt: periodic check-in behavior |
| `templates/prompts/IDENTITY.md` | template | 0.6 KB | 14 | Identity prompt: agent name and role variables |
| `templates/prompts/MEMORY.md` | template | 0.7 KB | 31 | Memory prompt: knowledge retention scaffold |
| `templates/prompts/SOUL.md` | template | 1.7 KB | 36 | Soul prompt: personality and values |
| `templates/prompts/TOOLS.md` | template | 6.0 KB | 166 | Tools prompt: available tool definitions |
| `templates/prompts/USER.md` | template | 1.3 KB | 42 | User prompt: human context and preferences |

### `templates/prompts/guru/` — Guru Role

| Path | Type | Size | Lines | Purpose |
|------|------|-----:|------:|---------|
| `templates/prompts/guru/AGENTS.md` | template | 7.3 KB | 257 | Guru agent behavior: technical specialist role |
| `templates/prompts/guru/IDENTITY.md` | template | 0.6 KB | 16 | Guru identity variables |
| `templates/prompts/guru/TOOLS.md` | template | 7.2 KB | 269 | Guru-specific tool definitions |

### `templates/prompts/helper/`

| Path | Type | Size | Lines | Purpose |
|------|------|-----:|------:|---------|
| `templates/prompts/helper/README.md` | readme | 1.7 KB | 47 | Ephemeral helper agent pattern documentation |

### `templates/prompts/manager/` — Manager Role

| Path | Type | Size | Lines | Purpose |
|------|------|-----:|------:|---------|
| `templates/prompts/manager/AGENTS.md` | template | 2.4 KB | 85 | Manager agent behavior: orchestration role |
| `templates/prompts/manager/HEARTBEAT.md` | template | 5.7 KB | 214 | Manager heartbeat: multi-agent coordination checks |
| `templates/prompts/manager/IDENTITY.md` | template | 1.8 KB | 53 | Manager identity variables |
| `templates/prompts/manager/SOUL.md` | template | 0.6 KB | 19 | Manager personality and values |
| `templates/prompts/manager/TOOLS.md` | template | 4.6 KB | 180 | Manager-specific tool definitions |

### `templates/prompts/sections/` — AGENTS.md Fragments

| Path | Type | Size | Lines | Purpose |
|------|------|-----:|------:|---------|
| `templates/prompts/sections/external-internal.md` | template-section | 0.3 KB | 11 | External vs internal communication rules |
| `templates/prompts/sections/first-run.md` | template-section | 0.1 KB | 3 | First-run initialization stub |
| `templates/prompts/sections/header.md` | template-section | 0.1 KB | 3 | AGENTS.md header with agent name variable |
| `templates/prompts/sections/make-it-yours.md` | template-section | 0.1 KB | 3 | Encouragement to personalize behavior |
| `templates/prompts/sections/safety.md` | template-section | 0.2 KB | 6 | Safety and boundary rules |
| `templates/prompts/sections/tools.md` | template-section | 0.2 KB | 3 | Tool usage introduction |

### `templates/prompts/web/` — Web Role

| Path | Type | Size | Lines | Purpose |
|------|------|-----:|------:|---------|
| `templates/prompts/web/AGENTS.md` | template | 2.3 KB | 81 | Web agent behavior: browser-based interactions |

### `tests/` — Test Suite

| Path | Type | Size | Lines | Purpose |
|------|------|-----:|------:|---------|
| `tests/README.md` | readme | 21.2 KB | 501 | Test suite documentation: distill pipeline tests |
| `tests/prompt-assembly-tests.md` | test-doc | 4.4 KB | 201 | Manual verification steps for prompt assembly |
| `tests/fixtures/FIXTURES.md` | test-fixture | 4.5 KB | 161 | Fixture index: what each test case covers |
| `tests/fixtures/001-ui-artifacts/input.md` | test-fixture | 2.6 KB | 106 | Test: UI artifact removal |
| `tests/fixtures/002-section-removal/input.md` | test-fixture | 3.5 KB | 109 | Test: section removal processing |
| `tests/fixtures/003-transcription-corrections/input.md` | test-fixture | 4.5 KB | 116 | Test: transcription correction handling |
| `tests/fixtures/004-code-blocks/input.md` | test-fixture | 3.3 KB | 133 | Test: code block preservation |
| `tests/fixtures/005-full-export/input.md` | test-fixture | 5.5 KB | 213 | Test: full export pipeline |
| `tests/fixtures/006-v1-migration/input.md` | test-fixture | 2.4 KB | 100 | Test: v1 format migration |
| `tests/fixtures/007-paste-and-export/input.md` | test-fixture | 4.6 KB | 119 | Test: paste-and-export workflow |
| `tests/fixtures/008-filter-test/canonical-with-sensitivity.md` | test-fixture | 0.8 KB | 38 | Test: sensitivity-based filtering |
| `tests/fixtures/009-e2e-pipeline/input.md` | test-fixture | 0.8 KB | 57 | Test: end-to-end pipeline |

---

## Observations

Notes for a future consolidation pass. Nothing was changed.

1. **Directories without README:** `tools/`, `templates/` (top-level), `.claude/commands/`, `templates/prompts/sections/`, all `tests/fixtures/0*` subdirs
2. ~~**Naming inconsistency:** fixed — renamed to `docs/bruba-web-docker-migration.md`~~
3. ~~**Orphaned backup:** `components/distill/lib.bak/` removed (7 Python files)~~
4. **Massive files:** `architecture-masterdoc.md` (90 KB, 2187 lines) and `filesystem-guide.md` (54 KB, 1235 lines) are each larger than many full projects' entire docs — potential split candidates
5. **Ghost references:** `docs/INDEX.md` links to `cc_logs/` directory and `cc_logs/INDEX.md`, but no tracked files exist there (gitignored)
6. **WIP convention:** 3 `_`-prefixed files in `docs/` (~64 KB total) — convention documented in INDEX.md but no clear lifecycle policy (when do they graduate or get archived?)
7. **Stale index:** `docs/INDEX.md` last updated 2026-02-03, doesn't list `per-agent-pipeline.md` or `bruba-web-docker-migration.md` (now renamed)
8. **No per-fixture docs:** `tests/fixtures/` has a top-level `FIXTURES.md` but individual fixture dirs (001–009) have only input files and no README
9. **Overlapping entry points:** `docs/README.md` and `docs/INDEX.md` both serve as navigation for `docs/` — README has task-based quick links + prose, INDEX has categorized table + naming conventions
