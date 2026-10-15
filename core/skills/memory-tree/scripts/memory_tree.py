#!/usr/bin/env python3
"""
memory_tree.py — Hierarchical SQLite-backed memory system for Hermes.

Stores knowledge as scored Markdown chunks with FTS5 full-text search,
hierarchical categories, recency-weighted scoring, and hot-slice export.

Database: ~/.hermes/state/memory_tree.db

Usage:
    python3 memory_tree.py store <category> <text>
    python3 memory_tree.py search <query> [--limit N]
    python3 memory_tree.py recall <category> [--limit N]
    python3 memory_tree.py hot [--budget N]
    python3 memory_tree.py score <id> <delta>
    python3 memory_tree.py compact <category>
    python3 memory_tree.py stats
    python3 memory_tree.py export-md
    python3 memory_tree.py import-md <file>
    python3 memory_tree.py categories
    python3 memory_tree.py get <id>
    python3 memory_tree.py delete <id>
"""

from __future__ import annotations

import argparse
import datetime
import json
import math
import os
import re
import sqlite3
import sys
from pathlib import Path
from typing import Any

# --- Constants ---

DB_DIR = os.path.expanduser("~/.hermes/state")
DB_PATH = os.path.join(DB_DIR, "memory_tree.db")
MAX_CHUNK_TOKENS = 3000  # approx, using 4 chars per token heuristic
RECENCY_HALF_LIFE_DAYS = 30.0
DEFAULT_HOT_BUDGET = 4000  # tokens
CHARS_PER_TOKEN = 4  # rough estimate

DEFAULT_CATEGORIES = {
    "personal": ("Facts about the user — habits, preferences, style", 50, 3000),
    "projects": ("Active projects, goals, progress updates", 50, 3000),
    "people": ("Contacts, relationships, communication preferences", 30, 2000),
    "tools": ("Tools, workflows, environment, configuration", 40, 3000),
    "decisions": ("Past decisions with context and rationale", 30, 2000),
    "insights": ("Patterns, lessons learned, observations", 40, 3000),
    "system": ("Hermes operational notes, bugs, config facts", 30, 2000),
}


# --- Database ---

def get_db() -> sqlite3.Connection:
    """Get or create the database connection."""
    os.makedirs(DB_DIR, exist_ok=True)
    db = sqlite3.connect(DB_PATH)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("PRAGMA foreign_keys=ON")
    _init_schema(db)
    return db


def _init_schema(db: sqlite3.Connection):
    """Create tables if they don't exist."""
    db.executescript("""
        CREATE TABLE IF NOT EXISTS memories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            category TEXT NOT NULL,
            content TEXT NOT NULL,
            source TEXT DEFAULT 'agent',
            importance REAL DEFAULT 1.0,
            access_count INTEGER DEFAULT 0,
            last_accessed TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS categories (
            name TEXT PRIMARY KEY,
            description TEXT,
            max_chunks INTEGER DEFAULT 50,
            token_budget INTEGER DEFAULT 3000
        );

        CREATE INDEX IF NOT EXISTS idx_memories_category
            ON memories(category);
        CREATE INDEX IF NOT EXISTS idx_memories_importance
            ON memories(importance DESC);
    """)

    # FTS5 virtual table — create only if not exists
    try:
        db.execute("SELECT 1 FROM memories_fts LIMIT 1")
    except sqlite3.OperationalError:
        db.execute("""
            CREATE VIRTUAL TABLE memories_fts
            USING fts5(content, category, tokenize='unicode61')
        """)
        # Populate FTS from existing memories (for migration)
        db.execute("""
            INSERT INTO memories_fts(rowid, content, category)
            SELECT id, content, category FROM memories
        """)

    # Seed default categories
    for name, (desc, max_chunks, budget) in DEFAULT_CATEGORIES.items():
        db.execute(
            "INSERT OR IGNORE INTO categories (name, description, max_chunks, token_budget) "
            "VALUES (?, ?, ?, ?)",
            (name, desc, max_chunks, budget),
        )
    db.commit()


# --- Scoring ---

def compute_score(row: sqlite3.Row) -> float:
    """Compute memory score: importance * log_access * recency_decay."""
    importance = row["importance"]
    access_count = row["access_count"]
    last_accessed = row["last_accessed"] or row["created_at"]

    try:
        last_dt = datetime.datetime.fromisoformat(last_accessed)
    except (ValueError, TypeError):
        last_dt = datetime.datetime.now()

    days_ago = (datetime.datetime.now() - last_dt).total_seconds() / 86400.0
    recency_decay = math.exp(-days_ago / RECENCY_HALF_LIFE_DAYS)
    log_access = 1.0 + math.log(access_count + 1)

    return importance * log_access * recency_decay


def estimate_tokens(text: str) -> int:
    """Rough token estimate."""
    return max(1, len(text) // CHARS_PER_TOKEN)


def _bump_access(db: sqlite3.Connection, memory_id: int):
    """Increment access count and update last_accessed."""
    now = datetime.datetime.now().isoformat()
    db.execute(
        "UPDATE memories SET access_count = access_count + 1, "
        "last_accessed = ? WHERE id = ?",
        (now, memory_id),
    )


# --- Commands ---

def cmd_store(db: sqlite3.Connection, category: str, text: str,
              source: str = "agent", importance: float = 1.0) -> dict:
    """Store a memory chunk."""
    # Validate category exists or create it
    cat = db.execute("SELECT 1 FROM categories WHERE name = ?", (category,)).fetchone()
    if not cat:
        db.execute(
            "INSERT INTO categories (name, description, max_chunks, token_budget) "
            "VALUES (?, ?, 50, 3000)",
            (category, f"Auto-created category: {category}"),
        )

    tokens = estimate_tokens(text)
    if tokens > MAX_CHUNK_TOKENS:
        return {"ok": False, "error": f"Text too long ({tokens} tokens, max {MAX_CHUNK_TOKENS})"}

    now = datetime.datetime.now().isoformat()
    cursor = db.execute(
        "INSERT INTO memories (category, content, source, importance, "
        "access_count, last_accessed, created_at, updated_at) "
        "VALUES (?, ?, ?, ?, 0, ?, ?, ?)",
        (category, text, source, importance, now, now, now),
    )
    memory_id = cursor.lastrowid

    # Update FTS index
    db.execute(
        "INSERT INTO memories_fts(rowid, content, category) VALUES (?, ?, ?)",
        (memory_id, text, category),
    )
    db.commit()

    return {
        "ok": True,
        "id": memory_id,
        "category": category,
        "tokens": tokens,
    }


def cmd_search(db: sqlite3.Connection, query: str, limit: int = 10) -> dict:
    """Full-text search across all memories."""
    rows = db.execute(
        "SELECT m.* FROM memories m "
        "JOIN memories_fts f ON m.id = f.rowid "
        "WHERE memories_fts MATCH ? AND m.importance > 0 "
        "ORDER BY rank "
        "LIMIT ?",
        (query, limit),
    ).fetchall()

    results = []
    for row in rows:
        _bump_access(db, row["id"])
        results.append({
            "id": row["id"],
            "category": row["category"],
            "content": row["content"],
            "score": round(compute_score(row), 3),
            "created": row["created_at"][:10],
        })
    db.commit()

    return {"ok": True, "count": len(results), "results": results}


def cmd_recall(db: sqlite3.Connection, category: str, limit: int = 20) -> dict:
    """List memories in a category, sorted by score."""
    rows = db.execute(
        "SELECT * FROM memories WHERE category = ? AND importance > 0 "
        "ORDER BY importance DESC, updated_at DESC LIMIT ?",
        (category, limit),
    ).fetchall()

    results = []
    for row in rows:
        _bump_access(db, row["id"])
        results.append({
            "id": row["id"],
            "content": row["content"],
            "score": round(compute_score(row), 3),
            "source": row["source"],
            "created": row["created_at"][:10],
            "accesses": row["access_count"],
        })
    db.commit()

    # Sort by computed score
    results.sort(key=lambda x: x["score"], reverse=True)
    return {"ok": True, "category": category, "count": len(results), "results": results}


def cmd_hot(db: sqlite3.Connection, budget: int = DEFAULT_HOT_BUDGET) -> dict:
    """Export top-scored memories within a token budget as Markdown."""
    rows = db.execute(
        "SELECT * FROM memories WHERE importance > 0"
    ).fetchall()

    # Score and sort
    scored = []
    for row in rows:
        scored.append((compute_score(row), dict(row)))
    scored.sort(key=lambda x: x[0], reverse=True)

    # Pack within budget
    selected = []
    used_tokens = 0
    for score, mem in scored:
        tokens = estimate_tokens(mem["content"])
        if used_tokens + tokens > budget:
            continue
        selected.append((score, mem))
        used_tokens += tokens
        _bump_access(db, mem["id"])

    db.commit()

    # Format as Markdown
    lines = ["# Hot Memory\n"]
    current_cat = None
    # Group by category
    by_cat: dict[str, list] = {}
    for score, mem in selected:
        cat = mem["category"]
        if cat not in by_cat:
            by_cat[cat] = []
        by_cat[cat].append((score, mem))

    for cat in sorted(by_cat.keys()):
        lines.append(f"\n## {cat}\n")
        for score, mem in by_cat[cat]:
            content = mem["content"].strip()
            # Single-line entries as bullets, multi-line as blocks
            if "\n" in content:
                lines.append(f"- [{mem['created_at'][:10]}] (score={score:.2f})")
                lines.append(f"  {content}\n")
            else:
                lines.append(f"- {content}")

    markdown = "\n".join(lines)
    return {
        "ok": True,
        "memories_count": len(selected),
        "tokens_used": used_tokens,
        "budget": budget,
        "markdown": markdown,
    }


def cmd_score(db: sqlite3.Connection, memory_id: int, delta: float) -> dict:
    """Adjust importance of a memory."""
    row = db.execute("SELECT * FROM memories WHERE id = ?", (memory_id,)).fetchone()
    if not row:
        return {"ok": False, "error": f"Memory {memory_id} not found"}

    new_importance = max(0.0, row["importance"] + delta)
    now = datetime.datetime.now().isoformat()
    db.execute(
        "UPDATE memories SET importance = ?, updated_at = ? WHERE id = ?",
        (new_importance, now, memory_id),
    )
    db.commit()

    return {
        "ok": True,
        "id": memory_id,
        "old_importance": row["importance"],
        "new_importance": new_importance,
    }


def cmd_compact(db: sqlite3.Connection, category: str) -> dict:
    """Summarize old low-score memories in a category.

    Takes the lowest-scored 50% of memories (if count > max_chunks),
    concatenates them into a digest, and replaces them with a single summary.
    """
    cat_info = db.execute(
        "SELECT * FROM categories WHERE name = ?", (category,)
    ).fetchone()
    if not cat_info:
        return {"ok": False, "error": f"Category '{category}' not found"}

    max_chunks = cat_info["max_chunks"]
    rows = db.execute(
        "SELECT * FROM memories WHERE category = ? AND importance > 0",
        (category,),
    ).fetchall()

    if len(rows) <= max_chunks:
        return {
            "ok": True,
            "action": "none",
            "reason": f"Category has {len(rows)} chunks (max {max_chunks}), no compaction needed",
        }

    # Score all and find bottom half
    scored = [(compute_score(row), dict(row)) for row in rows]
    scored.sort(key=lambda x: x[0])

    to_compact = scored[:len(scored) // 2]
    if len(to_compact) < 2:
        return {"ok": True, "action": "none", "reason": "Too few memories to compact"}

    # Build digest
    digest_parts = []
    ids_to_remove = []
    for _, mem in to_compact:
        digest_parts.append(f"[{mem['created_at'][:10]}] {mem['content'].strip()}")
        ids_to_remove.append(mem["id"])

    digest = "COMPACTED DIGEST:\n" + "\n".join(digest_parts)

    # Truncate if too long
    if estimate_tokens(digest) > MAX_CHUNK_TOKENS:
        # Keep first N lines that fit
        lines = digest.split("\n")
        truncated = []
        tokens = 0
        for line in lines:
            lt = estimate_tokens(line)
            if tokens + lt > MAX_CHUNK_TOKENS - 50:
                break
            truncated.append(line)
            tokens += lt
        truncated.append(f"... ({len(lines) - len(truncated)} more entries compacted)")
        digest = "\n".join(truncated)

    # Soft-delete originals (set importance to 0)
    now = datetime.datetime.now().isoformat()
    for mid in ids_to_remove:
        db.execute(
            "UPDATE memories SET importance = 0, updated_at = ? WHERE id = ?",
            (now, mid),
        )

    # Store digest
    result = cmd_store(db, category, digest, source="compact", importance=0.8)
    db.commit()

    return {
        "ok": True,
        "action": "compacted",
        "removed_count": len(ids_to_remove),
        "digest_id": result.get("id"),
        "digest_tokens": estimate_tokens(digest),
    }


def cmd_stats(db: sqlite3.Connection) -> dict:
    """Show counts per category, total size."""
    rows = db.execute(
        "SELECT category, COUNT(*) as count, "
        "SUM(LENGTH(content)) as total_chars "
        "FROM memories WHERE importance > 0 "
        "GROUP BY category ORDER BY count DESC"
    ).fetchall()

    cats = []
    total_memories = 0
    total_chars = 0
    for row in rows:
        count = row["count"]
        chars = row["total_chars"] or 0
        cats.append({
            "category": row["category"],
            "count": count,
            "tokens": chars // CHARS_PER_TOKEN,
        })
        total_memories += count
        total_chars += chars

    db_size = os.path.getsize(DB_PATH) if os.path.exists(DB_PATH) else 0

    return {
        "ok": True,
        "total_memories": total_memories,
        "total_tokens": total_chars // CHARS_PER_TOKEN,
        "db_size_kb": db_size // 1024,
        "categories": cats,
    }


def cmd_export_md(db: sqlite3.Connection) -> dict:
    """Export all memories as Markdown."""
    rows = db.execute(
        "SELECT * FROM memories WHERE importance > 0 "
        "ORDER BY category, created_at"
    ).fetchall()

    lines = ["# Memory Tree Export\n"]
    lines.append(f"Exported: {datetime.datetime.now().isoformat()}\n")

    current_cat = None
    for row in rows:
        if row["category"] != current_cat:
            current_cat = row["category"]
            lines.append(f"\n## {current_cat}\n")
        content = row["content"].strip()
        meta = f"[id={row['id']} src={row['source']} imp={row['importance']}]"
        lines.append(f"- {meta} {content}\n")

    markdown = "\n".join(lines)
    return {"ok": True, "count": len(rows), "markdown": markdown}


def cmd_import_md(db: sqlite3.Connection, filepath: str) -> dict:
    """Import from existing MEMORY.md format.

    Expects paragraphs separated by '§' (Hermes MEMORY.md format)
    or lines starting with '-' or numbered items.
    """
    path = os.path.expanduser(filepath)
    if not os.path.exists(path):
        return {"ok": False, "error": f"File not found: {path}"}

    with open(path, "r") as f:
        raw = f.read()

    # Hermes MEMORY.md uses § as separator
    if "§" in raw:
        chunks = [c.strip() for c in raw.split("§") if c.strip()]
    else:
        # Try line-by-line, skip headers
        chunks = []
        for line in raw.splitlines():
            line = line.strip()
            if line and not line.startswith("#"):
                # Remove leading bullet/number
                line = re.sub(r"^[-*]\s*", "", line)
                line = re.sub(r"^\d+[.)]\s*", "", line)
                if line:
                    chunks.append(line)

    imported = 0
    for chunk in chunks:
        if not chunk or len(chunk) < 5:
            continue

        # Try to detect category from content
        category = _guess_category(chunk)
        result = cmd_store(db, category, chunk, source="import", importance=0.8)
        if result.get("ok"):
            imported += 1

    return {"ok": True, "imported": imported, "total_chunks": len(chunks)}


def _guess_category(text: str) -> str:
    """Guess the best category for a text chunk."""
    text_lower = text.lower()

    project_words = {"проект", "project", "деплой", "deploy", "репо", "repo",
                     "sprint", "релиз", "release", "wr1", "hunter"}
    tool_words = {"python", "node", "brew", "config", "terminal", "vscode",
                  "obsidian", "hermes", "claude", "opencode", "git", "npm"}
    people_words = {"встреча", "meeting", "коллега", "звонок", "call",
                    "пользователь", "user", "дмитрий", "dmitry"}
    system_words = {"баг", "bug", "ошибка", "error", "хук", "hook",
                    "лимит", "limit", "cron", "gateway"}
    insight_words = {"паттерн", "pattern", "урок", "lesson", "вывод",
                     "conclusion", "наблюдение", "observation"}

    for word in project_words:
        if word in text_lower:
            return "projects"
    for word in tool_words:
        if word in text_lower:
            return "tools"
    for word in people_words:
        if word in text_lower:
            return "people"
    for word in system_words:
        if word in text_lower:
            return "system"
    for word in insight_words:
        if word in text_lower:
            return "insights"

    return "personal"


def cmd_categories(db: sqlite3.Connection) -> dict:
    """List all categories with descriptions."""
    rows = db.execute(
        "SELECT c.*, "
        "(SELECT COUNT(*) FROM memories m WHERE m.category = c.name AND m.importance > 0) as count "
        "FROM categories c ORDER BY c.name"
    ).fetchall()

    cats = []
    for row in rows:
        cats.append({
            "name": row["name"],
            "description": row["description"],
            "max_chunks": row["max_chunks"],
            "count": row["count"],
        })
    return {"ok": True, "categories": cats}


def cmd_get(db: sqlite3.Connection, memory_id: int) -> dict:
    """Get a single memory by ID."""
    row = db.execute("SELECT * FROM memories WHERE id = ?", (memory_id,)).fetchone()
    if not row:
        return {"ok": False, "error": f"Memory {memory_id} not found"}

    _bump_access(db, memory_id)
    db.commit()

    return {
        "ok": True,
        "id": row["id"],
        "category": row["category"],
        "content": row["content"],
        "source": row["source"],
        "importance": row["importance"],
        "access_count": row["access_count"] + 1,
        "score": round(compute_score(row), 3),
        "created_at": row["created_at"],
        "updated_at": row["updated_at"],
    }


def cmd_delete(db: sqlite3.Connection, memory_id: int) -> dict:
    """Soft-delete a memory (set importance to 0)."""
    row = db.execute("SELECT * FROM memories WHERE id = ?", (memory_id,)).fetchone()
    if not row:
        return {"ok": False, "error": f"Memory {memory_id} not found"}

    now = datetime.datetime.now().isoformat()
    db.execute(
        "UPDATE memories SET importance = 0, updated_at = ? WHERE id = ?",
        (now, memory_id),
    )
    db.commit()
    return {"ok": True, "id": memory_id, "action": "soft-deleted"}


# --- Output ---

def output(data: dict, human: bool = False):
    """Output result as JSON or human-readable."""
    if human:
        if not data.get("ok", True):
            print(f"ERROR: {data.get('error', 'unknown')}", file=sys.stderr)
            return

        if "results" in data:
            for r in data["results"]:
                score_str = f" [score={r.get('score', '?')}]" if "score" in r else ""
                print(f"  #{r.get('id', '?')} [{r.get('category', '?')}]{score_str}")
                content = r.get("content", "")
                if len(content) > 120:
                    content = content[:117] + "..."
                print(f"    {content}")
                print()
        elif "markdown" in data:
            print(data["markdown"])
        elif "categories" in data:
            for c in data["categories"]:
                count = c.get("count", 0)
                print(f"  {c['name']:15s}  {count:3d} memories  {c.get('description', '')}")
        elif "id" in data:
            print(f"  OK: id={data['id']} {data.get('category', '')} "
                  f"{data.get('action', 'stored')}")
        elif "total_memories" in data:
            print(f"  Total: {data['total_memories']} memories, "
                  f"~{data['total_tokens']} tokens, "
                  f"{data['db_size_kb']} KB on disk")
            print()
            for c in data.get("categories", []):
                print(f"  {c['category']:15s}  {c['count']:3d} memories  ~{c['tokens']} tokens")
        elif "imported" in data:
            print(f"  Imported {data['imported']} / {data['total_chunks']} chunks")
        else:
            print(json.dumps(data, ensure_ascii=False, indent=2))
    else:
        print(json.dumps(data, ensure_ascii=False))


# --- CLI ---

def main():
    parser = argparse.ArgumentParser(
        description="Memory Tree — hierarchical memory for Hermes",
    )
    parser.add_argument("--json", action="store_true",
                        help="Output as JSON (default when piped)")
    sub = parser.add_subparsers(dest="command", required=True)

    # store
    p = sub.add_parser("store", help="Store a memory chunk")
    p.add_argument("category", help="Category name")
    p.add_argument("text", nargs="+", help="Memory content")
    p.add_argument("--source", default="agent")
    p.add_argument("--importance", type=float, default=1.0)

    # search
    p = sub.add_parser("search", help="Full-text search")
    p.add_argument("query", nargs="+", help="Search query")
    p.add_argument("--limit", type=int, default=10)

    # recall
    p = sub.add_parser("recall", help="List memories in category")
    p.add_argument("category", help="Category name")
    p.add_argument("--limit", type=int, default=20)

    # hot
    p = sub.add_parser("hot", help="Export top-scored memories")
    p.add_argument("--budget", type=int, default=DEFAULT_HOT_BUDGET)

    # score
    p = sub.add_parser("score", help="Adjust importance")
    p.add_argument("id", type=int, help="Memory ID")
    p.add_argument("delta", type=float, help="Importance change (+1, -0.5, etc)")

    # compact
    p = sub.add_parser("compact", help="Compact old memories")
    p.add_argument("category", help="Category to compact")

    # stats
    sub.add_parser("stats", help="Show statistics")

    # export-md
    sub.add_parser("export-md", help="Export all as Markdown")

    # import-md
    p = sub.add_parser("import-md", help="Import from MEMORY.md")
    p.add_argument("file", help="Path to MEMORY.md file")

    # categories
    sub.add_parser("categories", help="List categories")

    # get
    p = sub.add_parser("get", help="Get a memory by ID")
    p.add_argument("id", type=int)

    # delete
    p = sub.add_parser("delete", help="Soft-delete a memory")
    p.add_argument("id", type=int)

    args = parser.parse_args()

    # Detect if output should be human-readable
    human = sys.stdout.isatty() and not args.json

    db = get_db()

    try:
        if args.command == "store":
            text = " ".join(args.text)
            result = cmd_store(db, args.category, text,
                               source=args.source, importance=args.importance)

        elif args.command == "search":
            query = " ".join(args.query)
            result = cmd_search(db, query, limit=args.limit)

        elif args.command == "recall":
            result = cmd_recall(db, args.category, limit=args.limit)

        elif args.command == "hot":
            result = cmd_hot(db, budget=args.budget)

        elif args.command == "score":
            result = cmd_score(db, args.id, args.delta)

        elif args.command == "compact":
            result = cmd_compact(db, args.category)

        elif args.command == "stats":
            result = cmd_stats(db)

        elif args.command == "export-md":
            result = cmd_export_md(db)

        elif args.command == "import-md":
            result = cmd_import_md(db, args.file)

        elif args.command == "categories":
            result = cmd_categories(db)

        elif args.command == "get":
            result = cmd_get(db, args.id)

        elif args.command == "delete":
            result = cmd_delete(db, args.id)

        else:
            result = {"ok": False, "error": f"Unknown command: {args.command}"}

        output(result, human=human)
        sys.exit(0 if result.get("ok", False) else 1)

    finally:
        db.close()


if __name__ == "__main__":
    main()
