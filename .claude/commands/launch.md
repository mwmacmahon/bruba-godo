# /launch - Start Bot Daemon

Start the OpenClaw daemon after a reboot or if it's stopped.

## Instructions

### 1. Check if Already Running
```bash
./tools/bot openclaw daemon status 2>/dev/null || echo "Cannot connect"
```

If already running, report status and exit.

### 2. Start the Daemon
```bash
ssh bruba "openclaw daemon start"
```

### 3. Verify Startup
```bash
sleep 2
./tools/bot openclaw daemon status
```

### 4. Check Status
```bash
./tools/bot openclaw status 2>/dev/null | grep -E "Gateway service|Agents|Sessions|Memory" | head -5
```

## Arguments

$ARGUMENTS

## Example Output

```
=== Launch ===

Daemon: stopped
Starting...

Daemon: running
  PID: 12345
  Uptime: 2s

Sessions:
  bruba-main: active

=== Ready ===
```

## Related Skills

- `/stop` - Stop the daemon
- `/restart` - Restart the daemon
- `/status` - Full status check
