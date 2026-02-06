#!/bin/bash
#
# session-compact.sh - Force session compaction via gateway call
#
# Usage:
#   session-compact.sh <agent-id>      # Compact single agent
#
# Uses openclaw gateway call sessions.compact — confirmed working.
# Note: memoryFlush does NOT fire on manual compaction.
#
# Version: 1.0.0
# Updated: 2026-02-06

set -e

VALID_AGENTS="bruba-main bruba-manager bruba-guru bruba-rex bruba-web"

usage() {
    echo "Usage: session-compact.sh <agent-id>"
    echo ""
    echo "Force session compaction via gateway call."
    echo "Note: memoryFlush does NOT fire on manual compaction."
    echo ""
    echo "Valid agents: $VALID_AGENTS"
    exit 1
}

TARGET="${1:?$(usage)}"

if [[ ! " $VALID_AGENTS " =~ " $TARGET " ]]; then
    echo "Error: Invalid agent '$TARGET'"
    echo "Valid agents: $VALID_AGENTS"
    exit 1
fi

echo "Compacting $TARGET..."
result=$(openclaw gateway call sessions.compact --params "{\"key\":\"agent:${TARGET}:main\"}" 2>&1)
if [[ $? -eq 0 ]]; then
    echo "OK: $TARGET compacted"
else
    echo "FAIL: $TARGET — $result"
    exit 1
fi
