# Vault Strategy

How private content is managed alongside the public operator repo.

## TL;DR

bruba-godo is a public repo on GitHub — it holds tools, templates, components, and docs. But most of the *content* it works with (sessions, intake files, reference docs, exports, config with secrets) is private and gitignored. Previously this content lived in real directories inside godo, backed up to a separate vault repo via periodic rsync, with a `private` git branch for staging promotions. That was three moving parts doing one job.

**Vault mode replaces all of that with symlinks.** When enabled, every gitignored content directory becomes a symlink pointing into the vault repo. `agents/` isn't a real directory anymore — it's a symlink to `bruba-vault/agents/`. All existing tools (pull, push, export, intake, mirror) work exactly the same because they follow symlinks transparently. Content is *always* in the vault, so there's no sync step. Committing vault changes is just `git add -A && commit` in the vault repo (or `/vault-sync`). Promoting content to the public repo is a direct vault-to-PR flow filtered through `vault.deny`.

One command to set up (`vault-setup.sh enable`), one command to reverse (`vault-setup.sh disable`), fully config-driven via the `vault:` section in config.yaml.

---

## Two-Layer Model

The system uses two git repositories:

| Repo | Purpose | Visibility |
|------|---------|------------|
| **godo** (operator repo) | Tools, templates, components, docs | Public / GitHub |
| **vault** (content repo) | Agents (sessions, intake, exports, mirror), reference, config | Private / local-only |

With **vault mode** enabled, gitignored directories in godo become symlinks into the vault. All tools continue to work unchanged — they follow symlinks transparently.

## How Vault Mode Works

### Symlinks

When vault mode is enabled (`vault-setup.sh enable`), each configured directory is replaced with a symlink:

```
bruba-godo/agents/    →  vault-repo/agents/
bruba-godo/reference/ →  vault-repo/reference/
...
```

Individual files can also be symlinked (e.g., `config.yaml`).

### Transparent Operation

Because symlinks are transparent to the filesystem:
- `./tools/pull.sh` writes to `agents/{agent}/sessions/` → actually writes to `vault/agents/{agent}/sessions/`
- `./tools/export.sh` reads from `reference/` → actually reads from `vault/reference/`
- All paths in scripts, tools, and config remain unchanged

### No Sync Required

Content IS in the vault. There's no periodic sync step. The old model of "rsync godo → vault" is eliminated.

## Configuration

### `config.yaml`

```yaml
vault:
  enabled: true
  path: ~/source/<vault-name>     # Path to vault repo
  dirs:                            # Directories to symlink
    - agents
    - reference
    - logs
    - docs/cc_logs
    - docs/meta
    - docs/packets
  files:                           # Individual files to symlink
    - config.yaml
```

### `vault.deny`

Lives in the vault repo. Controls which vault content is eligible for promotion to the public repo via `vault-propose.sh`. Files matching deny patterns will never appear in promotion PRs.

Format: one pattern per line, `#` comments, blank lines ignored.

```
# Example vault.deny
config.yaml
agents/*/sessions/
agents/*/mirror/
*.env
```

## Setup

### Prerequisites

1. A vault repo exists with `.git/` initialized
2. `vault:` section configured in `config.yaml`

### Enable Vault Mode

```bash
./tools/vault-setup.sh enable
```

This will:
1. Create directories in the vault if needed
2. Rsync any existing content from godo → vault (godo wins conflicts)
3. Replace real dirs with symlinks to the vault
4. Update `.gitignore` (simplified patterns, no `.gitkeep` needed)
5. Remove `.gitkeep` files from git tracking

### Disable Vault Mode

```bash
./tools/vault-setup.sh disable
```

Reverses the process: removes symlinks, copies content back from vault to real directories, restores `.gitignore` from backup, recreates `.gitkeep` files.

### Check Status

```bash
./tools/vault-setup.sh status
```

Shows which directories are symlinked vs real, and whether symlink targets exist.

## Daily Workflow

### Normal Operations

Work exactly as before. All tools (pull, push, export, intake, etc.) work unchanged through symlinks.

### Committing Vault Changes

```bash
./tools/vault-sync.sh    # Direct script
/vault-sync              # Claude Code skill
```

This simply runs `git add -A && git commit` in the vault repo. Since content lives there directly via symlinks, there's nothing to copy.

The `/sync` skill automatically includes a vault commit as its final step, so standalone `/vault-sync` is mainly useful for quick commits between full pipeline runs.

### Promoting Content

To move vault content into the public repo (e.g., docs you want to share):

```bash
./tools/vault-propose.sh         # Interactive: select files, create PR
./tools/vault-propose.sh --list  # Just list what's promotable
```

This scans the vault for files not blocked by `vault.deny`, shows them, and creates a PR branch in godo with real copies of selected files.

## .gitignore Changes

Vault mode simplifies `.gitignore`. The complex patterns with `.gitkeep` exceptions:

```gitignore
# Before (without vault mode)
agents/*
!agents/.gitkeep
...
```

Become simple directory entries:

```gitignore
# After (with vault mode)
agents
...
```

This works because symlinks are single filesystem entries (not directories), so git just ignores the symlink name.

The transformation is automatic during `vault-setup.sh enable` and reversed during `vault-setup.sh disable` (restores from `.gitignore.pre-vault` backup).

## Security Considerations

- **Vault access:** The vault repo is local-only. It is not pushed to GitHub or any remote.
- **iCloud/cloud backup:** If the vault is in an iCloud-synced directory, content is backed up to Apple's cloud. Consider whether this is acceptable for your threat model.
- **Symlink visibility:** `ls -la` in godo will show symlink targets, revealing the vault path. This is informational, not a security issue.
- **config.yaml:** Contains secrets (API keys, phone numbers, UUIDs). When symlinked, it lives in the vault. The vault.deny file should include `config.yaml` to prevent accidental promotion.

## Relationship to Legacy Scripts

| Script | With Vault Mode | Without Vault Mode |
|--------|----------------|-------------------|
| `vault-sync.sh` | Commits vault repo | Not applicable |
| `vault-propose.sh` | Scans vault, creates PR | Not applicable |
| `vault/sync-from-godo.sh` | Not needed (legacy) | Rsyncs godo → vault |

The vault repo's `sync-from-godo.sh` is preserved for standalone/backup use but is unnecessary when vault mode is active.
