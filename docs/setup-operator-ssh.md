---
type: doc
scope: reference
title: "Setting Up Operator SSH Access"
description: "Configure SSH from operator to bot machine"
---

# Setting Up Operator SSH Access

This guide covers configuring your local machine (the operator) to connect to the bot machine via SSH.

## Overview

You'll generate an SSH key pair, copy the public key to the bot machine, and configure your SSH client for easy access.

---

## 1. Generate SSH Key

If you don't already have an SSH key (check `~/.ssh/id_ed25519` or `~/.ssh/id_rsa`):

```bash
# Generate ed25519 key (recommended)
ssh-keygen -t ed25519 -C "your-email@example.com"

# Or RSA if ed25519 isn't supported
ssh-keygen -t rsa -b 4096 -C "your-email@example.com"
```

Accept the default path (`~/.ssh/id_ed25519`) and optionally set a passphrase.

---

## 2. Copy Key to Remote Machine

### Option A: Using ssh-copy-id (easiest)

```bash
ssh-copy-id bruba@<remote-ip-or-hostname>
```

This adds your public key to `~/.ssh/authorized_keys` on the remote.

### Option B: Manual copy

If `ssh-copy-id` isn't available:

```bash
# On your local machine
cat ~/.ssh/id_ed25519.pub

# Copy the output, then on the remote machine:
mkdir -p ~/.ssh
chmod 700 ~/.ssh
echo "paste-the-public-key-here" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

---

## 3. Configure SSH Client

Add an entry to `~/.ssh/config` for easy access:

```
Host bruba
    HostName 192.168.1.100    # Replace with actual IP or hostname
    User bruba                 # Bot user account
    Port 22                    # Default SSH port
    IdentityFile ~/.ssh/id_ed25519
```

**Common configurations:**

```
# Local machine on same network
Host bruba
    HostName 192.168.1.100
    User bruba

# Machine behind router (port forwarded)
Host bruba
    HostName your-domain.com
    User bruba
    Port 2222

# Via jump host / bastion
Host bruba
    HostName 10.0.0.50
    User bruba
    ProxyJump bastion.example.com

# Tailscale / ZeroTier (use Tailscale IP)
Host bruba
    HostName 100.x.y.z
    User bruba
```

---

## 4. Test the Connection

```bash
# Simple test
ssh bruba echo "Connection successful"

# Check clawdbot
ssh bruba clawdbot --version

# Test the tools/bot wrapper (from bruba-godo directory)
./tools/bot echo ok
```

Expected output:

```
Connection successful
x.y.z   (clawdbot version)
ok
```

---

## Troubleshooting

### "Permission denied (publickey)"

Your key isn't authorized on the remote:

```bash
# Check remote authorized_keys
ssh bruba@<ip> -o PreferredAuthentications=password
cat ~/.ssh/authorized_keys
```

Ensure your public key is listed and file permissions are correct (700 for `.ssh/`, 600 for `authorized_keys`).

### "Connection refused"

SSH server isn't running or port is wrong:

```bash
# Check from remote machine
sudo systemctl status sshd  # Linux
sudo systemsetup -getremotelogin  # macOS

# Check firewall
sudo ufw status  # Ubuntu
```

### "Connection timed out"

Network issue — wrong IP, firewall blocking, or machine is off:

```bash
# Check connectivity
ping <remote-ip>

# Check if SSH port is open
nc -zv <remote-ip> 22
```

### "Host key verification failed"

Remote machine's host key changed (reinstall, different machine):

```bash
# Remove old key (only if you know why it changed!)
ssh-keygen -R <remote-ip>
```

### Slow connection

Add to your SSH config:

```
Host bruba
    # ... other settings ...
    Compression yes
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

---

## Security Best Practices

### Disable Password Authentication

After confirming key auth works, disable passwords on the remote:

Edit `/etc/ssh/sshd_config`:

```
PasswordAuthentication no
ChallengeResponseAuthentication no
```

Reload: `sudo systemctl reload sshd`

### Use a Passphrase

Protect your private key with a passphrase. Use `ssh-agent` to avoid retyping:

```bash
# Start agent
eval "$(ssh-agent -s)"

# Add key (will prompt for passphrase once)
ssh-add ~/.ssh/id_ed25519

# macOS: store in Keychain
ssh-add --apple-use-keychain ~/.ssh/id_ed25519
```

Add to `~/.ssh/config`:

```
Host *
    AddKeysToAgent yes
    UseKeychain yes  # macOS only
```

### Limit SSH Access

On the remote, restrict to specific users in `/etc/ssh/sshd_config`:

```
AllowUsers bruba your-admin-user
```

---

## Quick Reference

| Task | Command |
|------|---------|
| Generate key | `ssh-keygen -t ed25519` |
| Copy key | `ssh-copy-id bruba@<ip>` |
| Test connection | `ssh bruba echo ok` |
| Check config | `ssh -G bruba` (shows resolved config) |
| Verbose debug | `ssh -vvv bruba` |

---

## Next Steps

1. Clone bruba-godo and update `config.yaml` with your SSH host
2. Run `./tools/bot clawdbot status` to verify
3. Run `./tools/provision-bot.sh` to set up an agent
