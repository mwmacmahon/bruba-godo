#!/bin/bash
# Constrained wrapper for web-reader agent invocation
# Only allows invoking web-reader with a message query
#
# This wrapper is added to the main agent's exec-approvals allowlist,
# providing a controlled interface to web search without giving the
# main agent direct web_fetch/web_search tool access.

if [ -z "$1" ]; then
  echo "Usage: web-search.sh <query>" >&2
  exit 1
fi

exec /Users/bruba/.npm-global/bin/clawdbot agent \
  --agent web-reader \
  --message "$1" \
  --local \
  --json \
  --timeout 120
