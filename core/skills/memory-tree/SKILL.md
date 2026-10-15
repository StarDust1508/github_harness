---
name: memory-tree
description: "Иерархическая память на SQLite с полнотекстовым поиском, оценкой релевантности и автосжатием. Используй, когда нужно структурированное долговременное хранение знаний вместо плоского файла заметок."
version: 1.0.0
metadata:
  hermes:
    tags: [Memory, Knowledge, Personal, Infrastructure]
---

# Memory Tree

Structured long-term memory for Hermes. Stores knowledge as scored Markdown
chunks in a SQLite database with FTS5 full-text search and hierarchical categories.

## Database location

`~/.hermes/state/memory_tree.db`

## CLI usage

```bash
python3 ~/.hermes/skills/personal/memory-tree/scripts/memory_tree.py <command> [args]
```

### Commands

| Command | Description |
|---------|-------------|
| `store <category> <text>` | Store a memory chunk (max 3000 tokens) |
| `search <query>` | Full-text search across all memories |
| `recall <category>` | List all memories in a category |
| `hot [--budget N]` | Export top-scored memories as Markdown (default budget: 4000 tokens) |
| `score <id> [+N\|-N]` | Adjust importance of a memory |
| `compact <category>` | Summarize old low-score memories in a category |
| `stats` | Show counts per category, total size |
| `export-md` | Export all memories as Markdown |
| `import-md <file>` | Import from existing MEMORY.md format |
| `categories` | List all categories with descriptions |
| `delete <id>` | Soft-delete a memory (sets importance to 0) |
| `get <id>` | Get a single memory by ID |

### Categories (default)

- **personal** — facts about the user, habits, preferences
- **projects** — active projects, goals, progress
- **people** — contacts, relationships, communication preferences
- **tools** — tools, workflows, environment setup
- **decisions** — past decisions with context and rationale
- **insights** — patterns, lessons learned, observations
- **system** — Hermes operational notes, configuration facts

### Scoring

Each memory has a computed score:

```
score = importance * (1 + log(access_count + 1)) * exp(-days_since_access / 30)
```

- `importance` — explicit weight (default 1.0, adjustable via `score` command)
- `access_count` — bumped each time a memory is retrieved via search/recall/hot
- `recency_decay` — exponential decay with 30-day half-life

### Auto-compaction

When a category exceeds `max_chunks` (default 50), the `compact` command
summarizes the lowest-scored memories into a single digest chunk.

### Hot slice

The `hot` command selects top-scored memories up to a token budget and formats
them as Markdown suitable for injection into a Hermes system prompt.

### Triggers

This skill activates when Hermes needs to:
- Store a learned fact, preference, or decision
- Search its memory for relevant context
- Generate a hot memory slice for a new session
- Compact or maintain memory storage
- Migrate data from flat MEMORY.md/USER.md files
