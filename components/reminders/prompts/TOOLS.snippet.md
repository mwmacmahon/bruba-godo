### Reminders

**Binary:** /opt/homebrew/bin/remindctl

**⚠️ CRITICAL: Never use display indices `[1]`, `[2]`, etc. — they are BROKEN.**
Display indices don't match internal IDs. Using `remindctl edit 8` will edit the WRONG reminder (possibly from a different list, possibly years old).

**Always use UUIDs:**
1. Get the UUID: `remindctl list Planning --json | grep -B5 "title text"`
2. Use UUID or prefix: `remindctl edit 4DF7 --title "New title"`

**Behavior when asked about reminders:**
- **Default to uncompleted** — "how many reminders" means uncompleted
- **Skip completed unless asked** — saves tokens, completed are rarely relevant
- **Exceptions:**
  - "Did I already do X?" → check recent completed
  - "What did I finish this week?" → check completed
  - Last ~7 days → can include both completed and uncompleted
- Use `--quiet` for counts, avoid loading full lists unless needed

### Example: Calendar
```
**Binary:** /opt/homebrew/bin/icalBuddy (if installed)
```

### Voice Tools

**Location:** `/Users/bruba/tools/`

**Transcription:** Always use the script, not raw whisper-cpp:
```bash
/Users/bruba/tools/whisper-clean.sh "/path/to/audio"
```

**⚠️ Check tools/ first** before running raw exec commands — there's usually a wrapper script that handles the details.
