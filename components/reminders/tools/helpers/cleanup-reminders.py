#!/usr/bin/env python3
"""
Cleanup old completed reminders from all lists.
- Groceries: completed more than 1 week ago (aggressive)
- All others: completed more than 1 year ago

Saves backups to ~/clawd/output/reminders_archive/<list_name>/
"""
import subprocess
import json
import sys
from datetime import datetime, timedelta
from pathlib import Path

OUTPUT_DIR = Path.home() / "clawd/output/reminders_archive"
REMINDCTL = "/opt/homebrew/bin/remindctl"

# Lists with custom retention periods (in days)
RETENTION_DAYS = {
    "Groceries": 7,  # 1 week
}
DEFAULT_RETENTION_DAYS = 365  # 1 year

def get_cutoff_date(list_name):
    """Returns cutoff date based on list-specific retention."""
    days = RETENTION_DAYS.get(list_name, DEFAULT_RETENTION_DAYS)
    return datetime.now() - timedelta(days=days), days

def get_all_lists():
    """Get all reminder list names."""
    result = subprocess.run(
        [REMINDCTL, "lists", "--json"],
        capture_output=True, text=True
    )
    lists = json.loads(result.stdout)
    return [lst["title"] for lst in lists]

def get_reminders(list_name):
    """Get all reminders from a specific list."""
    result = subprocess.run(
        [REMINDCTL, "list", list_name, "--json"],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        return []
    return json.loads(result.stdout)

def filter_old_completed(reminders, cutoff):
    """Filter to only completed reminders older than cutoff."""
    old = []
    for r in reminders:
        if r.get("isCompleted") and r.get("completionDate"):
            try:
                completed = datetime.fromisoformat(r["completionDate"].replace("Z", "+00:00"))
                if completed.replace(tzinfo=None) < cutoff:
                    old.append(r)
            except:
                pass
    return old

def save_backup(reminders, list_name):
    """Save backup JSON to list-specific archive directory."""
    safe_name = list_name.replace(" ", "_").lower()
    list_dir = OUTPUT_DIR / safe_name
    list_dir.mkdir(parents=True, exist_ok=True)

    timestamp = datetime.now().strftime("%Y-%m-%d-%H%M%S")
    filename = f"{timestamp}.json"
    path = list_dir / filename

    with open(path, "w") as f:
        json.dump(reminders, f, indent=2)
    return path

def delete_reminders(reminders, dry_run=True):
    """Delete reminders, returns count deleted."""
    deleted = 0
    for r in reminders:
        uuid = r["id"]
        title = r.get("title", "untitled")[:50]
        comp_date = r.get("completionDate", "unknown")[:10]

        if dry_run:
            print(f"  [DRY RUN] Would delete: {title} (completed {comp_date})")
        else:
            result = subprocess.run(
                [REMINDCTL, "delete", uuid, "--force"],
                capture_output=True, text=True
            )
            if result.returncode == 0:
                deleted += 1
                print(f"  Deleted: {title}")
            else:
                print(f"  Failed to delete {uuid}: {result.stderr}", file=sys.stderr)
    return deleted

def main():
    dry_run = "--execute" not in sys.argv

    print("Cleanup settings:")
    print(f"  Default retention: {DEFAULT_RETENTION_DAYS} days")
    for list_name, days in RETENTION_DAYS.items():
        print(f"  {list_name}: {days} days")
    print(f"Output directory: {OUTPUT_DIR}")

    if dry_run:
        print("\n[DRY RUN MODE - add --execute to actually delete]\n")
    else:
        print()

    lists = get_all_lists()
    total_found = 0
    total_deleted = 0

    for list_name in lists:
        cutoff, days = get_cutoff_date(list_name)
        reminders = get_reminders(list_name)
        old_completed = filter_old_completed(reminders, cutoff)

        if not old_completed:
            continue

        total_found += len(old_completed)
        print(f"\n{list_name}: {len(old_completed)} completed reminders (>{days} days old)")

        # Save backup before any deletion
        backup_path = save_backup(old_completed, list_name)
        print(f"  Backup: {backup_path}")

        if dry_run:
            # Show first 5 as preview
            for r in old_completed[:5]:
                title = r.get("title", "untitled")[:50]
                comp_date = r.get("completionDate", "?")[:10]
                print(f"  [DRY RUN] Would delete: {title} (completed {comp_date})")
            if len(old_completed) > 5:
                print(f"  ... and {len(old_completed) - 5} more")
        else:
            deleted = delete_reminders(old_completed, dry_run=False)
            total_deleted += deleted

    print(f"\n{'='*50}")
    print(f"Total found: {total_found} old completed reminders")
    if not dry_run:
        print(f"Total deleted: {total_deleted}")
    else:
        print("Run with --execute to delete")

if __name__ == "__main__":
    main()
