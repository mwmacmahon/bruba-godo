## Web Search

Main does not have direct web tools. For web research:

**Option 1: Forward to Manager**
Use `sessions_send` to bruba-manager with the research request. Manager spawns an ephemeral helper with web_search + web_fetch.

**Option 2: Ask the user**
For urgent needs, ask the user to search and paste results.

**Why no direct web access:**
- Security isolation (web content is untrusted)
- Manager coordinates helpers with automatic cleanup
- Helpers have limited tools (no exec, no memory access)
