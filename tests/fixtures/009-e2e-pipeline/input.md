=== MESSAGE 0 | USER ===
This is a test conversation for e2e pipeline testing.

=== MESSAGE 1 | ASSISTANT ===
Understood. This file will flow through the full pipeline:
1. intake/ → canonicalize → reference/transcripts/
2. reference/ → export → agents/{agent}/exports/

This validates the complete content flow.

=== MESSAGE 2 | USER ===
Done, export please.

=== MESSAGE 3 | ASSISTANT ===
Here's the export configuration:

---

```yaml
=== EXPORT CONFIG ===
title: E2E Pipeline Test
slug: e2e-test-conversation
date: 2026-01-31
source: test
scope: meta
tags: [testing, e2e]
=== END CONFIG ===
```

---

## Summary

Test conversation for e2e pipeline validation. Used by `tests/test-e2e-pipeline.sh`.

## Continuation Context

None - this is a test fixture.
