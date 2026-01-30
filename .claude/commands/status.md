# /status - Bot Status

Show the current state of the bot daemon and local files.

## Instructions

### 1. Clawdbot Status
```bash
./tools/bot clawdbot status 2>/dev/null | head -40
```

Shows: daemon, gateway, agents, sessions, memory index, heartbeat.

### 2. Local Mirror Status
```bash
echo "Mirror files: $(find mirror -name '*.md' -o -name '*.sh' -o -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"
```

### 3. Pulled Sessions
```bash
echo "Pulled sessions: $(wc -l < sessions/.pulled 2>/dev/null || echo 0)"
```

## Arguments

$ARGUMENTS

## Example Output

```
=== Bot Status ===

Clawdbot:
  Gateway: running (pid 25866)
  Dashboard: http://127.0.0.1:18789/
  Agents: 1 (bruba-main)
  Sessions: 1 active
  Memory: 124 files, 1814 chunks

Local:
  Mirror: 23 files
  Pulled: 27 sessions
```

## Related Skills

**Daemon management:**
- `/launch` - Start the daemon
- `/stop` - Stop the daemon
- `/restart` - Restart the daemon

**File operations:**
- `/mirror` - Pull bot files locally
- `/pull` - Pull closed sessions
