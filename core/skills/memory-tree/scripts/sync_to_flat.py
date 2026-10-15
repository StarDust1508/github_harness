#!/usr/bin/env python3
"""
sync_to_flat.py — Sync Memory Tree → MEMORY.md

Generates a flat MEMORY.md file from the Memory Tree SQLite database,
using the Hermes §-delimiter format. This allows Hermes to load
the best memories into its system prompt automatically.

Run this:
  - On gateway start (via hook or cron)
  - After bulk memory operations
  - Periodically (every few hours)

Usage:
    python3 sync_to_flat.py [--budget CHARS] [--dry-run]
"""

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

MEMORY_TREE_SCRIPT = os.path.expanduser(
    "~/.hermes/skills/personal/memory-tree/scripts/memory_tree.py"
)
MEMORY_MD_PATH = os.path.expanduser("~/.hermes/memories/MEMORY.md")
DEFAULT_CHAR_BUDGET = 2200  # matches Hermes memory_char_limit


def get_hot_memories(token_budget: int) -> list[str]:
    """Get top-scored memories from Memory Tree."""
    result = subprocess.run(
        ["python3", MEMORY_TREE_SCRIPT, "--json", "hot", "--budget", str(token_budget)],
        capture_output=True, text=True, timeout=10,
    )
    if result.returncode != 0:
        print(f"ERROR: memory_tree.py hot failed: {result.stderr}", file=sys.stderr)
        return []

    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError:
        print(f"ERROR: invalid JSON from memory_tree.py", file=sys.stderr)
        return []

    if not data.get("ok"):
        print(f"ERROR: {data.get('error', 'unknown')}", file=sys.stderr)
        return []

    # Extract individual memory lines from the markdown
    markdown = data.get("markdown", "")
    entries = []
    for line in markdown.splitlines():
        line = line.strip()
        # Skip headers and empty lines
        if not line or line.startswith("#"):
            continue
        # Remove leading bullet
        if line.startswith("- "):
            line = line[2:]
        # Skip score annotations from hot output
        if line.startswith("[") and "score=" in line:
            # It's a multi-line entry header, skip
            continue
        if line:
            entries.append(line)

    return entries


def sync(char_budget: int, dry_run: bool = False) -> dict:
    """Sync Memory Tree to MEMORY.md."""
    # Convert char budget to rough token budget (4 chars per token)
    token_budget = char_budget // 4

    entries = get_hot_memories(token_budget)

    if not entries:
        return {"ok": False, "error": "No memories to sync"}

    # Build §-delimited content, respecting char budget
    selected = []
    total_chars = 0
    for entry in entries:
        entry_chars = len(entry)
        # Account for delimiter
        if total_chars + entry_chars + 3 > char_budget:
            break
        selected.append(entry)
        total_chars += entry_chars + 3  # +3 for \n§\n

    content = "\n§\n".join(selected)

    if dry_run:
        return {
            "ok": True,
            "action": "dry_run",
            "entries": len(selected),
            "chars": len(content),
            "budget": char_budget,
            "preview": content[:500],
        }

    # Backup existing MEMORY.md
    mem_path = Path(MEMORY_MD_PATH)
    if mem_path.exists():
        backup = mem_path.with_suffix(".md.bak")
        backup.write_text(mem_path.read_text(encoding="utf-8"), encoding="utf-8")

    # Write new MEMORY.md
    mem_path.parent.mkdir(parents=True, exist_ok=True)
    mem_path.write_text(content, encoding="utf-8")

    return {
        "ok": True,
        "action": "synced",
        "entries": len(selected),
        "chars": len(content),
        "budget": char_budget,
        "backup": str(mem_path.with_suffix(".md.bak")),
    }


def main():
    parser = argparse.ArgumentParser(description="Sync Memory Tree → MEMORY.md")
    parser.add_argument("--budget", type=int, default=DEFAULT_CHAR_BUDGET,
                        help=f"Max chars for MEMORY.md (default {DEFAULT_CHAR_BUDGET})")
    parser.add_argument("--dry-run", action="store_true",
                        help="Show what would be written without changing files")
    args = parser.parse_args()

    result = sync(args.budget, dry_run=args.dry_run)
    print(json.dumps(result, ensure_ascii=False))
    sys.exit(0 if result.get("ok") else 1)


if __name__ == "__main__":
    main()
