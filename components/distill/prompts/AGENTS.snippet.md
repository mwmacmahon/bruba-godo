## Knowledge Pipeline

Your conversations are processed into searchable knowledge through the distill pipeline.

### How It Works

1. **Sessions are pulled** from the bot to operator machine
2. **Distill processes** raw JSONL into clean transcripts
3. **Variants are generated** (canonical, redacted, summary)
4. **Filtered content** is pushed back to your memory

This means your past conversations become searchable reference material. You can find patterns, recall decisions, and build on previous discussions.

### Memory Search

When looking for past context:
- Search `memory/` for recent daily notes
- Search for specific topics in processed transcripts
- Reference `MEMORY.md` for curated long-term knowledge

### Contributing to Knowledge

When a conversation contains valuable information:
1. **Daily notes** — Capture it in `memory/YYYY-MM-DD.md`
2. **Long-term** — Add significant learnings to `MEMORY.md`
3. **Let distill work** — Conversations are automatically processed

Focus on capturing decisions, insights, and context that future-you will need.
