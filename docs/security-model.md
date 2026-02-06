---
type: doc
scope: reference
title: "Security Model"
description: "Threat model, permissions, and security practices"
---

# Security Model

Security reference for bot instances running OpenClaw. Covers threat model, permission boundaries, known gaps, and operational security practices.

> **Related docs:**
> - [Setup Guide](setup.md) — Configuration procedures
> - [Operations Guide](operations-guide.md) — Day-to-day usage

---

## Table of Contents

1. [Security Philosophy](#security-philosophy)
2. [Threat Model](#threat-model)
3. [Permission Architecture](#permission-architecture)
4. [Agent Isolation](#agent-isolation)
5. [Docker Sandbox](#docker-sandbox)
6. [Defense Layers](#defense-layers)
7. [Known Gaps](#known-gaps)
8. [Operational Security](#operational-security)
9. [Incident Response](#incident-response)
10. [Security Checklist](#security-checklist)

---

## Active Security Issues

Tracked issues requiring attention.

### Issue 1: Exec Command Scoping

**Status:** Blocked — Approval UX broken

**Current state:** Filesystem commands (wc, ls, head, tail, grep, du) have full disk access within bot account. Security relies on account isolation only.

**Target state:** Commands scoped to workspace via exec-approvals.json patterns, with approval required for access outside that scope.

**Blockers:**
- Signal: Approval requests don't appear
- Dashboard: Only one approval popup for multiple pending approvals
- No way to list/view/manage pending approvals programmatically

### Issue 2: Config File Protection (Agent Self-Escalation)

**Status:** Partially Fixed

**Issue:** Agent can edit `~/.openclaw/exec-approvals.json` directly using edit/write tools.

**Root cause:** The file serves dual purposes:
1. Allowlist patterns (should be lockable)
2. Usage metadata — `lastUsedAt` timestamps (daemon needs to write)

**Partial fix applied:**
- `openclaw.json` locked (root:staff) — protects `tools.deny` list
- `exec-approvals.json` cannot be locked — daemon writes timestamps

**Remaining risk:** Agent can self-escalate by adding binaries to allowlist.

**Proper solution:** OpenClaw feature request — separate allowlist from metadata.

---

## Security Philosophy

### Core Principles

**1. Defense in Depth**
No single control is trusted completely. Security relies on multiple overlapping layers:
- Account isolation (OS user boundary)
- Tool deny lists (capability restrictions)
- Exec allowlists (binary whitelisting)
- Agent isolation (sandboxed subagents)
- Human-in-the-loop (permission for external actions)

**2. Least Privilege**
Agents receive minimum permissions needed for their role:
- Main agent: filesystem + exec (allowlisted) — no web
- Reader agent: web search/fetch — no exec, write, or memory

**3. Assume Compromise**
Design assumes the AI model may attempt unauthorized actions:
- Cannot trust model to self-police
- Security enforced at infrastructure level
- Model-level guardrails are supplementary, not primary

**4. Local-First Privacy**
Sensitive data stays local:
- Local embeddings (no cloud embedding APIs)
- E2EE channels (Signal)
- Sensitive content routing decisions explicit

**5. Contain Before Detect**
Focus on limiting blast radius over detecting misbehavior:
- Account isolation limits damage scope
- Sandboxed agents cannot escalate
- External actions require explicit approval

### Industry Context

This security model aligns with emerging frameworks:
- **OWASP Top 10 for Agentic Applications** — Addresses risks from autonomous action
- **NIST AI RMF** — Risk management for AI systems

Key insight: "You cannot secure an autonomous system by asking the model to protect itself. You secure it by shaping the environment it operates in."

---

## Threat Model

### What We're Protecting Against

| Threat | Description | Severity |
|--------|-------------|----------|
| **Cloud exposure** | Sensitive content hitting external APIs | High |
| **Prompt injection** | Malicious messages manipulating agent behavior | High |
| **Over-privileged access** | Agent able to do things it shouldn't | Medium |
| **Data exfiltration** | Compromised AI sending data externally | High |
| **Self-escalation** | Agent modifying its own permissions | Medium |

### Attack Vectors

**Direct Prompt Injection**
Attacker sends messages designed to override agent instructions.
- *Mitigation:* Single-user channel lockdown, no external message sources

**Indirect Prompt Injection**
Malicious instructions hidden in fetched web content.
- *Mitigation:* Reader agent isolation, injection detection in prompts

**Config File Manipulation**
Agent uses write/edit tools to modify security config.
- *Mitigation:* Config file protection (see setup guide)

**Tool Abuse**
Agent misuses allowed tools for unintended purposes.
- *Mitigation:* Tight exec allowlist, human-in-the-loop for externals

### Trust Boundaries

```
Most Trusted                                    Least Trusted
    ←─────────────────────────────────────────────────→
Your Code      OpenClaw       Docker Sandbox     AI Model
(scripts)      Gateway        (reader agent)     (Claude)
```

**Trust gradient implications:**
- Scripts and wrappers: Can enforce invariants
- OpenClaw: Trusted to enforce config
- Sandbox: Untrusted code containment
- AI Model: Assume may attempt unauthorized actions

---

## Permission Architecture

### Multi-Agent Design

Five agents with role-based permissions:

| Agent | Sandbox | Network | Key Tools | Denied |
|-------|---------|---------|-----------|--------|
| **bruba-main** | Off (host) | None | read, write, edit, exec, memory_*, sessions_send, message | web_*, browser, cron, gateway |
| **bruba-rex** | Off (host) | None | Same as main + cron, image | web_*, browser, gateway |
| **bruba-guru** | Off (host) | None | read, write, edit, exec, memory_*, sessions_send, message | web_*, browser, cron, gateway |
| **bruba-manager** | Off (host) | None | read, write, exec, sessions_send, memory_* | edit, web_*, browser, cron, gateway |
| **bruba-web** | **Docker** | **bridge** | web_search, web_fetch, read, write | exec, edit, memory_*, sessions_* |

### File Tools vs Exec

| Operation | Tool | Example |
|-----------|------|---------|
| **Read file** | `read` | `read /Users/bruba/agents/bruba-main/memory/docs/Doc - setup.md` |
| **Write file** | `write` | `write /Users/bruba/agents/bruba-main/workspace/output/result.md` |
| **Edit file** | `edit` | `edit /Users/bruba/agents/bruba-main/workspace/drafts/draft.md` |
| **List files** | `exec` | `exec /bin/ls /Users/bruba/agents/bruba-main/memory/` |
| **Find files** | `exec` | `exec /usr/bin/find /Users/bruba/agents/bruba-main/memory/ -name "*.md"` |
| **Search content** | `exec` | `exec /usr/bin/grep -r "pattern" /Users/bruba/agents/bruba-main/` |
| **Run script** | `exec` | `exec /Users/bruba/agents/bruba-main/tools/tts.sh "hello" /tmp/out.wav` |
| **Memory search** | `memory_search` | `memory_search "topic"` (indexed content) |

### Exec Allowlist

All entries in `exec-approvals.json` under `agents.<agent-id>.allowlist`:

| Category | Commands |
|----------|----------|
| File listing | `/bin/ls` |
| File viewing | `/bin/cat`, `/usr/bin/head`, `/usr/bin/tail` |
| Searching | `/usr/bin/grep`, `/usr/bin/find` |
| Info | `/usr/bin/wc`, `/usr/bin/du`, `/usr/bin/uname`, `/usr/bin/whoami` |
| Custom tools | `/Users/bruba/agents/bruba-main/tools/*.sh` |
| System utils | `/opt/homebrew/bin/remindctl`, `/opt/homebrew/bin/icalBuddy` |

All commands have full account access — security relies on account isolation.

---

## Agent Isolation

### Web Content Isolation (bruba-web)

bruba-web is a **separate peer agent** (not a subagent) that handles all web access. This is required by OpenClaw's tool inheritance model — subagents cannot have tools their parent lacks.

**Key properties:**
- bruba-web runs in a Docker container with `network: bridge`
- Has NO memory persistence (`memorySearch.enabled: false`)
- Cannot use `sessions_send` (can't initiate contact with other agents)
- Cannot modify other agents' files
- Web content stays in bruba-web's context; only structured summaries cross to other agents

**Prompt injection defense:** If fetched web content contains "ignore previous instructions," it's processed in bruba-web's isolated context. bruba-web has no tools to affect other agents or the host.

### Cross-Agent Communication

Agents communicate via `sessions_send` (peer-to-peer messaging), not `sessions_spawn` (parent-child). This ensures each agent retains independent tool configurations.

| From | To | Purpose |
|------|----|---------|
| bruba-main | bruba-web | Web search requests |
| bruba-main | bruba-guru | Technical deep-dives |
| bruba-manager | bruba-main | Alerts, delegation |
| bruba-manager | bruba-web | Background research |

---

## Docker Sandbox

**Current state (as of 2026-02-04):**
- **bruba-web:** Docker sandbox enabled (`mode: "all"`, `network: "bridge"`)
- **Other agents:** Running directly on host (`sandbox.mode: "off"` globally)

bruba-web handles untrusted web content — highest prompt injection risk. Other agents don't need network access, so tool-level restrictions suffice.

### Sandbox Configuration

**Global defaults** (`agents.defaults.sandbox` in openclaw.json):

```json
{
  "mode": "all",
  "scope": "agent",
  "workspaceAccess": "rw",
  "docker": {
    "readOnlyRoot": true,
    "network": "none",
    "memory": "512m",
    "binds": [
      "/Users/bruba/agents/bruba-shared/packets:/workspaces/shared/packets:rw",
      "/Users/bruba/agents/bruba-shared/context:/workspaces/shared/context:rw",
      "/Users/bruba/agents/bruba-shared/repo:/workspaces/shared/repo:ro"
    ]
  }
}
```

**Per-agent overrides:**

| Agent | Override | Reason |
|-------|----------|--------|
| bruba-main | `workspaceRoot` | File tool validation |
| bruba-guru | `workspaceRoot` | File tool validation |
| bruba-manager | `workspaceRoot` | File tool validation |
| bruba-web | `workspaceRoot` + `network: "bridge"` | Needs internet for web_search |

### Sandbox Tool Policy

There's a **sandbox-level tool ceiling** in addition to global and agent-level tool policies:

**Tool availability hierarchy (all must allow):**
1. Global `tools.allow` → ceiling for all agents
2. Agent `tools.allow` → ceiling for specific agent
3. **Sandbox `tools.sandbox.tools.allow`** → ceiling for containerized agents

**Gotcha:** If a tool is allowed at global and agent level but NOT in `tools.sandbox.tools.allow`, containerized agents won't have it. This caused the `message` tool to disappear after sandbox migration.

### Container Path Mapping

| Host Path | Container Path | Notes |
|-----------|----------------|-------|
| `/Users/bruba/agents/{agent}/` | `/workspace/` | Agent's container |
| `/Users/bruba/agents/bruba-shared/packets/` | `/workspaces/shared/packets/` | All containers |
| `/Users/bruba/agents/bruba-shared/context/` | `/workspaces/shared/context/` | All containers |
| `/Users/bruba/agents/bruba-shared/repo/` | `/workspaces/shared/repo/` | All containers (ro) |

### Network Isolation

| Agent | Network | Can Reach |
|-------|---------|-----------|
| bruba-main | none | Only gateway (internal) |
| bruba-guru | none | Only gateway (internal) |
| bruba-manager | none | Only gateway (internal) |
| bruba-web | bridge | Internet + gateway |

Even if an agent were compromised, it cannot make outbound network connections (except bruba-web, which is already the web-facing agent).

### What Containers Cannot Access

| Resource | Why Protected |
|----------|---------------|
| `~/.openclaw/exec-approvals.json` | Prevents privilege self-escalation |
| `~/.openclaw/openclaw.json` | Config shouldn't be agent-writable |
| `~/.clawdbot/agents/*/auth-profiles.json` | API keys stay on host |
| `/Users/bruba/` (general) | No arbitrary host filesystem access |
| Other agents' workspaces | Cross-agent isolation |

### Security Implications

**Privilege escalation prevention:** `exec-approvals.json` not mounted → agent cannot read or modify allowlist. Node host reads allowlist from HOST filesystem, outside container.

**Tool script integrity:** ALL agents have `tools/` mounted read-only. Write attempts fail with "Read-only file system." Original scripts on host remain unchanged.

### Container Lifecycle

- Gateway creates containers on-demand when agents are first used
- Containers persist while gateway runs (survive session resets)
- `openclaw gateway stop` gracefully stops containers
- Containers auto-prune after 24h idle (configurable)
- Auto-warm: `~/bin/bruba-start` + LaunchAgent warms bruba-web on login

### Debugging Sandbox

```bash
openclaw sandbox explain          # Check configuration
openclaw sandbox list             # List running containers
openclaw sandbox recreate --all   # Recreate after config change

# Verify isolation (should fail)
docker exec openclaw-sandbox-bruba-main cat /root/.openclaw/exec-approvals.json
docker exec openclaw-sandbox-bruba-main ls /Users/bruba/

# Verify tools/:ro (should fail)
docker exec openclaw-sandbox-bruba-main touch /workspace/tools/test.txt
```

See also: [Docker Migration](bruba-web-docker-migration.md) for setup details and rollback procedures.

---

## Defense Layers

### The 7-Layer Security Model

```
Layer 1: Account Isolation
    └── Bot runs as separate OS user
    └── Cannot access your files
    └── Primary security boundary

Layer 2: Docker Sandbox (per-agent containers)
    └── bruba-web: Docker with bridge network
    └── Others: host (off) — tool restrictions suffice
    └── Filesystem isolation, read-only tools/

Layer 3: Network Isolation
    └── bruba-web: bridge (internet access)
    └── Others: none (gateway only)

Layer 4: Tool Deny List (tools.deny)
    └── Per-agent capability restrictions

Layer 5: Tool Allow List (tools.allow)
    └── Explicit allowlist per agent
    └── Global ceiling effect applies

Layer 6: Exec Allowlist (exec-approvals.json)
    └── Per-agent binary whitelists
    └── Must use full paths

Layer 7: OS Permissions (macOS TCC)
    └── Calendar, Reminders access via system permissions
    └── Granted to specific binary (Node.js)
```

### Layer Enforcement

| Layer | Enforced By | Bypassable? |
|-------|-------------|-------------|
| Account isolation | OS | No* |
| Docker sandbox | OpenClaw gateway | No |
| Network isolation | Docker networking | No |
| Tool deny list | OpenClaw gateway | Only via config edit |
| Tool allow list | OpenClaw gateway | Only via config edit |
| Exec allowlist | OpenClaw gateway | Via exec-approvals.json edit |
| OS permissions | OS | Via GUI only |

*Unless bot account compromised

### Config File Protection

**Two ownership models exist:**

| Model | Ownership | Permissions | Protection Level |
|-------|-----------|-------------|------------------|
| **Bot-owned** | bot:wheel | 600 | Medium — agent could modify |
| **Root-owned** | root:staff | 644 | High — agent cannot modify |

| File | Can Lock? | Notes |
|------|-----------|-------|
| `openclaw.json` | ✅ Yes | Root-owned: agent cannot modify tools.deny |
| `exec-approvals.json` | ❌ No | Daemon writes timestamps; root ownership breaks exec |

**Why exec-approvals.json can't be locked:**
- OpenClaw daemon writes `lastUsedAt` timestamps on every command
- Root ownership breaks exec functionality entirely
- This is a known self-escalation gap

---

## Known Gaps

See also: [Known Issues](known-issues.md) for active bugs and workarounds.

### Gap 1: Exec Allowlist Self-Escalation

**Issue:** Agent can use write/edit tools to add entries to exec-approvals.json.

**Impact:** Agent could grant itself arbitrary exec permissions.

**Current mitigation:** None (documented risk)

**Future solutions:**
- OpenClaw feature: Separate read-only allowlist from writable metadata
- Wrapper approach: Root-owned allowlist file

### Gap 2: Broad Filesystem Access

**Issue:** Allowlisted commands (ls, cat, grep, etc.) have full account access.

**Impact:** Agent can read any file the bot user can access.

**Current mitigation:** Account isolation (bot user has limited files)

### Gap 3: No Automated Containment

**Issue:** Can monitor agent behavior but cannot auto-stop misbehavior.

**Impact:** Governance-containment gap (industry-wide issue)

**Current mitigation:** Human oversight, regular log review

---

## Operational Security

### Channel Security

| Channel | Security | Recommendation |
|---------|----------|----------------|
| Signal | E2EE, single-user allowlist | ✅ Recommended |
| Gateway Dashboard | HTTPS via Tailscale, token auth | ✅ Admin fallback |
| Telegram | No E2EE | ⚠️ Consider alternatives |

**Signal lockdown config:**
```json
{
  "channels": {
    "signal": {
      "dmPolicy": "allowlist",
      "allowFrom": ["+1XXXXXXXXXX"]
    }
  }
}
```

### Memory Isolation

**Main sessions only:**
- `MEMORY.md` (long-term curated memory) only loaded in main DM sessions
- NOT loaded in group chats or shared contexts
- Prevents sensitive context leakage

### External Action Approval

| Action Type | Permission Required |
|-------------|---------------------|
| Read files | ✅ Free |
| Search memory | ✅ Free |
| Web search | ⚠️ Ask first |
| Send emails | ❌ Explicit approval |
| Post to social media | ❌ Explicit approval |
| Anything leaving the machine | ❌ Explicit approval |

---

## Incident Response

### Suspected Compromise

**Indicators:**
- Unexpected exec commands in logs
- Attempts to access denied tools
- Unusual memory search patterns
- Changes to config files

**Response steps:**

1. **Isolate immediately**
   ```bash
   ssh bruba 'openclaw daemon stop'
   ```

2. **Preserve evidence**
   ```bash
   scp -r bruba:~/.openclaw/logs/ /tmp/incident-$(date +%Y%m%d)/
   scp bruba:~/.openclaw/*.json /tmp/incident-$(date +%Y%m%d)/
   ```

3. **Review changes**
   ```bash
   diff /backup/openclaw.json /Users/bruba/.openclaw/openclaw.json
   diff /backup/exec-approvals.json /Users/bruba/.openclaw/exec-approvals.json
   ```

4. **Assess scope**
   - What data was accessed?
   - What actions were taken?
   - Was anything exfiltrated?

5. **Restore and harden**
   - Restore configs from backup
   - Review and tighten permissions
   - Update documentation with learnings

### Regular Security Tasks

| Frequency | Task |
|-----------|------|
| Daily | Review session logs for anomalies |
| Weekly | Check exec-approvals.json unchanged |
| Monthly | Full permission audit |

---

## Security Checklist

### Initial Setup

- [ ] Bot runs as separate OS user
- [ ] `tools.exec.host: "gateway"` set
- [ ] `tools.exec.security: "allowlist"` set
- [ ] Channel dmPolicy set appropriately
- [ ] Local embeddings configured (no cloud APIs)

### Config Protection (Choose One)

**Option A: Bot-owned**
- [ ] `openclaw.json` has 600 permissions
- [ ] `exec-approvals.json` has 600 permissions

**Option B: Root-owned (recommended)**
- [ ] `openclaw.json` owned by root:staff
- [ ] `exec-approvals.json` has 600 permissions (bot-owned by necessity)

### Ongoing Verification

- [ ] Config file ownership unchanged
- [ ] Exec allowlist unchanged: `cat ~/.openclaw/exec-approvals.json | md5`
- [ ] No unexpected tools enabled: `openclaw config get tools`
- [ ] Channel config still locked

### After Config Changes

- [ ] Re-lock openclaw.json (if using root-owned)
- [ ] Restart daemon
- [ ] Reset session
- [ ] Verify new config active

---

## References

### External Resources

- [OWASP Top 10 for Agentic Applications](https://www.practical-devsecops.com/owasp-top-10-agentic-applications/)
- [OWASP Gen AI Security Project](https://genai.owasp.org/)
- [Anthropic Prompt Injection Research](https://www.anthropic.com/research/prompt-injection-defenses)
- [NIST AI Risk Management Framework](https://www.nist.gov/itl/ai-risk-management-framework)

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 2.0.0 | 2026-02-06 | Merged Docker sandbox from masterdoc: sandbox config, container paths, network isolation, access matrices, debugging. Updated to 5-agent model, 7-layer defense. |
| 1.0.0 | 2026-01-30 | Initial version |
