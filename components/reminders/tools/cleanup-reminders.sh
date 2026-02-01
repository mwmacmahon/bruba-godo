#!/bin/bash
# Wrapper for cleanup-reminders.py
# Usage: cleanup-reminders.sh [--execute]
# Default is dry-run mode (safe preview)
#
# Retention periods:
#   - Groceries: 7 days (aggressive - it's just shopping history)
#   - All others: 365 days
#
# Backups: ~/clawd/output/reminders_archive/<list_name>/<timestamp>.json

/usr/bin/python3 ~/clawd/tools/helpers/cleanup-reminders.py "$@"
