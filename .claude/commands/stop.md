# /stop - Stop Bot Daemon

Stop the Clawdbot daemon.

## Instructions

### 1. Check Current Status
```bash
./tools/bot clawdbot daemon status 2>/dev/null || echo "Cannot connect"
```

If already stopped, report and exit.

### 2. Stop the Daemon
```bash
ssh bruba "clawdbot daemon stop"
```

### 3. Verify Stopped
```bash
sleep 1
./tools/bot clawdbot daemon status 2>/dev/null || echo "Daemon stopped"
```

## Arguments

$ARGUMENTS

## Example Output

```
=== Stop ===

Daemon: running (PID 12345)
Stopping...

Daemon: stopped

=== Done ===
```

## Related Skills

- `/launch` - Start the daemon
- `/restart` - Restart the daemon
- `/status` - Full status check
