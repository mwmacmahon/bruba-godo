# /vault-sync - Commit Vault Changes

Commit all pending changes in the vault repo. When vault mode is enabled, content dirs (sessions, intake, reference, etc.) are symlinked into the vault — this skill commits those changes.

## Instructions

### 1. Check Vault Mode

```bash
./tools/vault-setup.sh status
```

If vault mode is not enabled (all dirs show "real directory"), inform the user:
- "Vault mode is not enabled. Run `./tools/vault-setup.sh enable` to migrate, or set `vault.enabled: true` in config.yaml."
- Stop here.

### 2. Show Pending Changes

```bash
./tools/vault-sync.sh --dry-run
```

Report the summary to the user: how many files changed, added, deleted.

If no changes, report "Vault is clean, nothing to commit" and stop.

### 3. Commit

```bash
./tools/vault-sync.sh
```

Report the commit result.

## Arguments

$ARGUMENTS

Options:
- `--dry-run` — Show what would be committed without committing
- `--status` — Just show vault-setup status, don't commit

## Example

```
User: /vault-sync

Claude: Checking vault status...
Vault mode: enabled
Vault: /Users/dadbook/source/bruba-vault

Pending changes:
 M agents/bruba-main/sessions/abc123.jsonl
 A agents/bruba-main/intake/def456.md
 M config.yaml

3 files changed. Committing...

Vault committed: "vault sync 2026-02-05-1730"
```

## Related Skills

- `/sync` - Full pipeline sync (includes vault sync at the end)
- `/push` - Push content to bot memory
- `/pull` - Pull sessions from bot
