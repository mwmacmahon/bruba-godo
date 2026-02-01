#!/bin/bash
# Ensure web-reader sandbox is running
# Can be run at login or as a health check
#
# The web-reader agent runs in a Docker sandbox that stops when idle.
# This script starts the container by invoking the agent with a ping.

READER_STATUS=$(clawdbot sandbox list 2>&1 | grep -A3 "web-reader")

if echo "$READER_STATUS" | grep -q "running"; then
    echo "web-reader: already running"
    exit 0
fi

echo "web-reader: starting..."
# Invoke reader with a simple ping to trigger container creation
RESULT=$(clawdbot agent --agent web-reader -m "ping" --local --json 2>&1)

if echo "$RESULT" | grep -q "payloads"; then
    echo "web-reader: started successfully"
    exit 0
else
    echo "web-reader: failed to start"
    echo "$RESULT"
    exit 1
fi
