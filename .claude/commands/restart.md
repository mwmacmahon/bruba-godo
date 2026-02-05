# /restart - Restart Bot Daemon

Restart the OpenClaw daemon. Use after config changes or if the bot is misbehaving.

## Instructions

### 1. Restart the Daemon
```bash
./tools/bot "openclaw daemon restart"
```

### 2. Verify Running
```bash
sleep 2
./tools/bot openclaw daemon status
```

### 3. Check Status
```bash
./tools/bot openclaw status 2>/dev/null | grep -E "Gateway service|Agents|Sessions|Memory" | head -5
```

## Arguments

$ARGUMENTS

## Example Output

```
=== Restart ===

Restarting daemon...

Daemon: running
  PID: 12346
  Uptime: 2s

Sessions:
  bruba-main: active

=== Ready ===
```

## When to Use

- After editing `openclaw.json` (config changes)
- After editing `exec-approvals.json` (new allowlist entries)
- If bot becomes unresponsive
- If sessions seem stuck

## Related Skills

- `/launch` - Start the daemon (if stopped)
- `/stop` - Stop the daemon
- `/status` - Full status check
