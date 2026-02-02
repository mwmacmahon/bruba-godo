## Web Search

Web search uses a **sandboxed sub-agent** for security. You don't have direct web tools - instead:

**To search the web:**
```bash
/Users/bruba/agents/bruba-main/tools/web-search.sh "your search query"
```

**How it works:**
1. Script invokes `web-reader` agent (runs in Docker sandbox)
2. Reader has web_fetch + web_search only (no exec/write/edit)
3. Returns JSON with search results

**When to use:**
- Current events, recent information
- Documentation lookups
- Fact-checking when memory doesn't have it
- Research for <REDACTED-NAME>'s questions

**Note:** First search may be slow if Docker container is starting.
