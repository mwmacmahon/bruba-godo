#!/usr/bin/env bash
set -euo pipefail

# vault-setup.sh — Enable/disable/check vault symlink mode
#
# Usage:
#   vault-setup.sh enable   — Migrate gitignored dirs to vault via symlinks
#   vault-setup.sh disable  — Reverse symlinks back to real dirs
#   vault-setup.sh status   — Show which dirs are symlinked vs real

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

COMMAND="${1:-status}"

# ── Helpers ──────────────────────────────────────────────────────

# Read vault config from config.yaml (before any symlink changes)
# We inline parsing here because config.yaml itself may be in the vault list
read_vault_config() {
    local config_file="$ROOT_DIR/config.yaml"

    # If config.yaml is a symlink, it already points into vault — read through it
    if [[ ! -f "$config_file" ]]; then
        echo "ERROR: config.yaml not found at $config_file" >&2
        return 1
    fi

    VAULT_ENABLED=$(python3 -c "
import yaml
with open('$config_file') as f:
    c = yaml.safe_load(f)
v = c.get('vault', {})
print('true' if v.get('enabled') else 'false')
" 2>/dev/null || echo "false")

    VAULT_PATH=$(python3 -c "
import yaml, os
with open('$config_file') as f:
    c = yaml.safe_load(f)
v = c.get('vault', {})
print(os.path.expanduser(v.get('path', '')))
" 2>/dev/null)

    VAULT_DIRS=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && VAULT_DIRS+=("$line")
    done < <(python3 -c "
import yaml
with open('$config_file') as f:
    c = yaml.safe_load(f)
for d in c.get('vault',{}).get('dirs',[]):
    print(d)
" 2>/dev/null)

    VAULT_FILES=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && VAULT_FILES+=("$line")
    done < <(python3 -c "
import yaml
with open('$config_file') as f:
    c = yaml.safe_load(f)
for f2 in c.get('vault',{}).get('files',[]):
    print(f2)
" 2>/dev/null)
}

# ── Status ───────────────────────────────────────────────────────

do_status() {
    read_vault_config

    echo "=== Vault Status ==="
    echo "Enabled in config: $VAULT_ENABLED"
    echo "Vault path: ${VAULT_PATH:-<not set>}"
    echo ""

    if [[ -n "$VAULT_PATH" && -d "$VAULT_PATH/.git" ]]; then
        echo "Vault repo: found"
    elif [[ -n "$VAULT_PATH" ]]; then
        echo "Vault repo: NOT FOUND at $VAULT_PATH"
    fi
    echo ""

    echo "Directories:"
    for dir in "${VAULT_DIRS[@]}"; do
        local full="$ROOT_DIR/$dir"
        if [[ -L "$full" ]]; then
            local target
            target=$(readlink "$full")
            if [[ -d "$target" ]]; then
                echo "  $dir → $target (symlink, target exists)"
            else
                echo "  $dir → $target (symlink, TARGET MISSING)"
            fi
        elif [[ -d "$full" ]]; then
            echo "  $dir (real directory)"
        else
            echo "  $dir (does not exist)"
        fi
    done

    echo ""
    echo "Files:"
    for file in "${VAULT_FILES[@]}"; do
        local full="$ROOT_DIR/$file"
        if [[ -L "$full" ]]; then
            local target
            target=$(readlink "$full")
            if [[ -f "$target" ]]; then
                echo "  $file → $target (symlink, target exists)"
            else
                echo "  $file → $target (symlink, TARGET MISSING)"
            fi
        elif [[ -f "$full" ]]; then
            echo "  $file (real file)"
        else
            echo "  $file (does not exist)"
        fi
    done
}

# ── Enable ───────────────────────────────────────────────────────

do_enable() {
    read_vault_config

    if [[ "$VAULT_ENABLED" != "true" ]]; then
        echo "ERROR: vault.enabled is not true in config.yaml"
        echo "Set vault.enabled: true and vault.path before running enable."
        exit 1
    fi

    if [[ -z "$VAULT_PATH" || ! -d "$VAULT_PATH/.git" ]]; then
        echo "ERROR: Vault repo not found at ${VAULT_PATH:-<not set>}"
        echo "Create the vault repo first: git init $VAULT_PATH"
        exit 1
    fi

    echo "=== Vault Setup: Enable ==="
    echo "Godo:  $ROOT_DIR"
    echo "Vault: $VAULT_PATH"
    echo ""

    local migrated_dirs=0
    local migrated_files=0
    local skipped=0

    # ── Migrate directories ──
    for dir in "${VAULT_DIRS[@]}"; do
        local godo_path="$ROOT_DIR/$dir"
        local vault_path="$VAULT_PATH/$dir"

        if [[ -L "$godo_path" ]]; then
            echo "  SKIP $dir (already a symlink)"
            ((skipped++))
            continue
        fi

        # Ensure vault target dir exists
        mkdir -p "$vault_path"

        # If godo has a real dir with content, merge into vault (godo wins conflicts)
        if [[ -d "$godo_path" ]]; then
            # Count non-.gitkeep files
            local file_count
            file_count=$(find "$godo_path" -not -name '.gitkeep' -not -type d | wc -l | tr -d ' ')
            if [[ "$file_count" -gt 0 ]]; then
                echo "  SYNC $dir → vault ($file_count files)"
                rsync -a --ignore-existing "$godo_path/" "$vault_path/"
            fi
            rm -rf "$godo_path"
        fi

        # Create symlink
        ln -s "$vault_path" "$godo_path"
        echo "  LINK $dir → $vault_path"
        ((migrated_dirs++))
    done

    echo ""

    # ── Migrate individual files ──
    for file in "${VAULT_FILES[@]}"; do
        local godo_path="$ROOT_DIR/$file"
        local vault_path="$VAULT_PATH/$file"

        if [[ -L "$godo_path" ]]; then
            echo "  SKIP $file (already a symlink)"
            ((skipped++))
            continue
        fi

        # Ensure vault target parent dir exists
        mkdir -p "$(dirname "$vault_path")"

        # Copy to vault if godo has a real file and vault doesn't, or godo is newer
        if [[ -f "$godo_path" ]]; then
            if [[ ! -f "$vault_path" ]] || [[ "$godo_path" -nt "$vault_path" ]]; then
                echo "  COPY $file → vault"
                cp "$godo_path" "$vault_path"
            fi
            rm "$godo_path"
        fi

        # Create symlink
        ln -s "$vault_path" "$godo_path"
        echo "  LINK $file → $vault_path"
        ((migrated_files++))
    done

    echo ""

    # ── Update .gitignore ──
    local gitignore="$ROOT_DIR/.gitignore"
    if [[ -f "$gitignore" ]]; then
        echo "Updating .gitignore..."
        cp "$gitignore" "${gitignore}.pre-vault"
        echo "  Backed up to .gitignore.pre-vault"

        # Build new gitignore: keep non-vault lines, replace vault patterns
        python3 -c "
import re, sys

vault_dirs = $(python3 -c "
import yaml, json
with open('$ROOT_DIR/config.yaml') as f:
    c = yaml.safe_load(f)
print(json.dumps(c.get('vault',{}).get('dirs',[])))
")

# Patterns that the vault dirs generate in the old gitignore
# e.g., sessions/*, !sessions/.gitkeep, etc.
vault_base_names = set()
for d in vault_dirs:
    # 'docs/cc_logs' -> also match 'docs/cc_logs/'
    vault_base_names.add(d)
    vault_base_names.add(d + '/')

with open('$gitignore') as f:
    lines = f.readlines()

# Find the vault-related block and replace it
new_lines = []
skip_block = False
vault_section_added = False

for line in lines:
    stripped = line.strip()

    # Detect if this line is part of a vault-managed pattern
    is_vault_line = False
    for d in vault_dirs:
        base = d.split('/')[-1] if '/' in d else d
        full = d
        # Match patterns like: dir/*, !dir/.gitkeep, dir, dir/subdir/*, etc.
        if (stripped.startswith(full + '/') or
            stripped.startswith('!' + full + '/') or
            stripped == full or
            stripped == full + '/' or
            # Handle sub-patterns like reference/transcripts/*
            any(stripped.startswith(p) for p in [
                full + '/*', '!' + full + '/', full + '/'
            ])):
            is_vault_line = True
            break

    if is_vault_line:
        if not vault_section_added:
            # Insert the clean vault section
            new_lines.append('# Vault-managed directories (symlinked when vault mode enabled)\n')
            for d in vault_dirs:
                new_lines.append(d + '\n')
            new_lines.append('\n')
            vault_section_added = True
        # Skip old vault-related lines
        continue

    # Also skip comment lines that preceded vault blocks
    if stripped in [
        '# Local state and output (keep directory structure via .gitkeep)',
        '# Assembled outputs (generated from templates + components + user)',
        '# Planning docs (internal only)',
        '# Phase packets (internal planning, not committed)',
        '# Claude Code work logs (local only, exported to bot)',
    ]:
        continue

    new_lines.append(line)

with open('$gitignore', 'w') as f:
    f.writelines(new_lines)
" 2>/dev/null

        echo "  Updated .gitignore (simple dir entries, no .gitkeep patterns)"
    fi

    # ── Remove .gitkeep files from git tracking ──
    echo ""
    echo "Cleaning up .gitkeep files from git tracking..."
    cd "$ROOT_DIR"
    local gitkeep_count=0
    for dir in "${VAULT_DIRS[@]}"; do
        # Find tracked .gitkeep files in vaulted dirs
        local gitkeeps
        gitkeeps=$(git ls-files "$dir/**/.gitkeep" "$dir/.gitkeep" 2>/dev/null || true)
        if [[ -n "$gitkeeps" ]]; then
            while IFS= read -r gk; do
                git rm --cached "$gk" 2>/dev/null && ((gitkeep_count++)) || true
            done <<< "$gitkeeps"
        fi
    done
    if [[ $gitkeep_count -gt 0 ]]; then
        echo "  Removed $gitkeep_count .gitkeep file(s) from git tracking"
    else
        echo "  No .gitkeep files to clean up"
    fi

    # ── Summary ──
    echo ""
    echo "=== Summary ==="
    echo "  Directories migrated: $migrated_dirs"
    echo "  Files migrated: $migrated_files"
    echo "  Already symlinked: $skipped"
    echo ""
    echo "Vault mode is now active. Run 'vault-setup.sh status' to verify."
    echo "Remember to commit the .gitignore changes in bruba-godo."
}

# ── Disable ──────────────────────────────────────────────────────

do_disable() {
    read_vault_config

    echo "=== Vault Setup: Disable ==="
    echo "Reversing symlinks back to real directories..."
    echo ""

    local restored_dirs=0
    local restored_files=0

    # ── Restore directories ──
    for dir in "${VAULT_DIRS[@]}"; do
        local godo_path="$ROOT_DIR/$dir"
        local vault_path="$VAULT_PATH/$dir"

        if [[ ! -L "$godo_path" ]]; then
            echo "  SKIP $dir (not a symlink)"
            continue
        fi

        # Remove symlink
        rm "$godo_path"

        # Copy content from vault to real dir
        mkdir -p "$godo_path"
        if [[ -d "$vault_path" ]]; then
            rsync -a "$vault_path/" "$godo_path/"
            echo "  RESTORE $dir (copied from vault)"
        else
            echo "  RESTORE $dir (empty — vault dir not found)"
        fi
        ((restored_dirs++))
    done

    echo ""

    # ── Restore individual files ──
    for file in "${VAULT_FILES[@]}"; do
        local godo_path="$ROOT_DIR/$file"
        local vault_path="$VAULT_PATH/$file"

        if [[ ! -L "$godo_path" ]]; then
            echo "  SKIP $file (not a symlink)"
            continue
        fi

        # Remove symlink
        rm "$godo_path"

        # Copy from vault
        if [[ -f "$vault_path" ]]; then
            cp "$vault_path" "$godo_path"
            echo "  RESTORE $file (copied from vault)"
        else
            echo "  RESTORE $file (not found in vault)"
        fi
        ((restored_files++))
    done

    echo ""

    # ── Restore .gitignore ──
    local gitignore="$ROOT_DIR/.gitignore"
    local backup="${gitignore}.pre-vault"
    if [[ -f "$backup" ]]; then
        echo "Restoring .gitignore from pre-vault backup..."
        cp "$backup" "$gitignore"
        echo "  Restored from .gitignore.pre-vault"
    else
        echo "WARNING: No .gitignore.pre-vault backup found."
        echo "  You may need to manually restore .gitkeep patterns."
    fi

    # ── Recreate .gitkeep files ──
    echo ""
    echo "Recreating .gitkeep files..."
    cd "$ROOT_DIR"
    local gitkeep_count=0
    for dir in "${VAULT_DIRS[@]}"; do
        local godo_path="$ROOT_DIR/$dir"
        if [[ -d "$godo_path" ]]; then
            touch "$godo_path/.gitkeep"
            git add "$godo_path/.gitkeep" 2>/dev/null || true
            ((gitkeep_count++))
        fi
        # Handle known subdirs (intake/processed, reference/transcripts, etc.)
        for subdir in "$godo_path"/*/; do
            if [[ -d "$subdir" ]]; then
                touch "$subdir/.gitkeep"
                git add "$subdir/.gitkeep" 2>/dev/null || true
                ((gitkeep_count++))
            fi
        done
    done
    echo "  Recreated $gitkeep_count .gitkeep file(s)"

    # ── Summary ──
    echo ""
    echo "=== Summary ==="
    echo "  Directories restored: $restored_dirs"
    echo "  Files restored: $restored_files"
    echo ""
    echo "Vault mode disabled. Symlinks replaced with real directories."
    echo "Remember to set vault.enabled: false in config.yaml and commit .gitignore."
}

# ── Main ─────────────────────────────────────────────────────────

case "$COMMAND" in
    enable)
        do_enable
        ;;
    disable)
        do_disable
        ;;
    status)
        do_status
        ;;
    -h|--help)
        echo "Usage: vault-setup.sh <enable|disable|status>"
        echo ""
        echo "Commands:"
        echo "  enable   Migrate gitignored dirs to vault via symlinks"
        echo "  disable  Reverse symlinks back to real dirs"
        echo "  status   Show which dirs are symlinked vs real"
        ;;
    *)
        echo "Unknown command: $COMMAND"
        echo "Usage: vault-setup.sh <enable|disable|status>"
        exit 1
        ;;
esac
