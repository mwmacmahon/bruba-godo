# /wake - Wake All Agents

Send a ping to all agents to ensure their containers are running.

## Instructions

### 1. Ping All Agents

Run these commands sequentially (each spawns a container if needed):

```bash
./tools/bot 'openclaw agent --agent bruba-main -m "ping"'
```

```bash
./tools/bot 'openclaw agent --agent bruba-guru -m "ping"'
```

```bash
./tools/bot 'openclaw agent --agent bruba-web -m "ping"'
```

```bash
./tools/bot 'openclaw agent --agent bruba-manager -m "ping"'
```

### 2. Report Results

Show which agents responded and their status.

## Arguments

$ARGUMENTS

- No arguments: ping all 4 agents
- Agent name (e.g., `guru`): ping only that agent

## Example Output

```
Waking agents...
  bruba-main: Pong
  bruba-guru: Pong - Guru online
  bruba-web: pong
  bruba-manager: Pong

All 4 agents awake.
```

## Notes

- Containers are configured with `prune.idleHours: 0` (always on)
- First wake after restart may take 1-2 min for cold start
- Uses SSH directly due to complex quoting requirements

## Related Skills

- `/status` - Check daemon and agent status
- `/restart` - Restart the gateway
