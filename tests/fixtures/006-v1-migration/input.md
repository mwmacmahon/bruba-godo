=== MESSAGE 0 | USER ===
Can you explain git rebase vs merge? I always get confused about when to use which.
11:00 AM

=== MESSAGE 1 | ASSISTANT ===
Great question! Here's a quick comparison:

**Merge:**
- Creates a new merge commit
- Preserves complete history
- Shows when branches diverged and rejoined

**Rebase:**
- Moves your commits to the tip of the target branch
- Creates a linear history
- Makes it look like you started from the latest code

Here's the visual difference:

```
# Before merge
main:    A---B---C
feature:      \---D---E

# After merge
main:    A---B---C-------M
feature:      \---D---E-/

# After rebase
main:    A---B---C---D'---E'
```

The golden rule: never rebase commits that others have pulled. That breaks their history.

Want me to show you how to do an interactive rebase?
11:05 AM

=== MESSAGE 2 | USER ===
That's super clear, thanks! I think I finally get it now. Done, export.
11:07 AM

=== MESSAGE 3 | ASSISTANT ===
**Transcription scan:** No voice content found.

Before I produce the export:
- Outputs: keep finished only (default) ✓
- Skip any sections? (default: no) ✓

Proceeding with export.

---

```yaml
=== EXPORT CONFIG ===
filename_base: 2026-01-24-git-rebase
project: planning

outputs: finished_only

sections_to_remove:
  - start_anchor: "Want me to show you how to do"
    end_anchor: "interactive rebase?"
    reason: "unanswered offer"

outputs_to_remove: []

transcription_replacements: []

transcription_errors_noted: none

continuation_packet: no
=== END CONFIG ===
```

---

## Summary

Explained the difference between git merge and rebase. Merge preserves complete branch history with merge commits, while rebase creates a linear history by moving commits to the tip of the target branch.

## What Was Discussed

Compared merge vs rebase strategies with visual diagrams. Key distinction: merge shows full history including branch points, rebase creates cleaner linear history. Emphasized the "golden rule" to never rebase commits others have pulled.

## Decisions Made

- **Understand before using** — Rebase is powerful but can cause issues if misused

## Outputs

- Visual comparison of merge vs rebase histories

---
```
brief_description: Git merge vs rebase explained - when to use each and the golden rule of rebasing.
```

---

Export complete. Use your bookmarklet to copy the conversation, then paste into your intake folder.
