# /morning-check - Verify Post-Reset Wake

Check that all agents woke up properly after the 4am reset.

## Instructions

### 1. Check Last Wake Log
```bash
./tools/bot cat /Users/bruba/agents/bruba-manager/workspace/logs/wake-$(date +%Y-%m-%d).log 2>/dev/null || echo "No wake log for today"
```

### 2. Check Agent Sessions
```bash
./tools/bot openclaw sessions --active 60
```

Shows sessions active in the last hour. After 4am reset, all agents should show fresh sessions if wake job ran.

### 3. Verify Each Agent Responds
```bash
./tools/bot 'openclaw agent --agent bruba-main -m "ping"'
./tools/bot 'openclaw agent --agent bruba-guru -m "ping"'
./tools/bot 'openclaw agent --agent bruba-web -m "ping"'
./tools/bot 'openclaw agent --agent bruba-manager -m "ping"'
```

## Expected Output

```
Wake log (2026-02-04):
  bruba-main: initialized
  bruba-guru: initialized
  bruba-web: initialized

Active sessions (last 60 min): 4

Ping responses:
  bruba-main: Pong
  bruba-guru: Pong
  bruba-web: pong
  bruba-manager: Pong
```

## Related Skills

- `/wake` - Manually wake all agents
- `/status` - Check daemon status
