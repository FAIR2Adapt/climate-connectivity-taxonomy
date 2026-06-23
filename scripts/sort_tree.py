#!/usr/bin/env python3
"""Sort the SkoHub tree alphabetically after the site is built.

SkoHub renders the left-hand navigation tree straight from the order of the
`hasTopConcept` / `narrower` arrays in the generated JSON, with no sorting of its
own (see src/templates/App.jsx + src/components/nestedList.jsx upstream). The
arrays come out in Gatsby's node-processing order, which is effectively arbitrary,
so ~1000 top concepts and their children appear unordered and structured branches
are hard to find by browsing.

This walks the built `public/` directory and sorts every `hasTopConcept` and
`narrower` array by prefLabel (case-insensitively, by the chosen UI language with a
fallback to any available label), recursively. It touches the fetched tree file
(`<scheme>/index.json`) *and* the baked Gatsby `page-data.json` files, so the tree
is sorted both on the concept-scheme landing page and once a concept is opened.

Usage:
    python scripts/sort_tree.py public [LANG]   # LANG defaults to "en"
"""

import json
import sys
from pathlib import Path

SORT_KEYS = ("hasTopConcept", "narrower")


def label(node: dict, lang: str) -> str:
    """Best-effort prefLabel for sorting: chosen language, else any, else id."""
    pl = node.get("prefLabel")
    if isinstance(pl, dict) and pl:
        val = pl.get(lang) or next(iter(pl.values()))
        if isinstance(val, str):
            return val.casefold()
    if isinstance(pl, str):
        return pl.casefold()
    return str(node.get("id", "")).casefold()


def sort_node(node, lang: str) -> int:
    """Recursively sort tree arrays in-place. Returns how many arrays it sorted."""
    sorted_count = 0
    if isinstance(node, list):
        for item in node:
            sorted_count += sort_node(item, lang)
    elif isinstance(node, dict):
        for key, value in node.items():
            if key in SORT_KEYS and isinstance(value, list):
                value.sort(key=lambda n: label(n, lang) if isinstance(n, dict) else "")
                sorted_count += 1
            sorted_count += sort_node(value, lang)
    return sorted_count


def main() -> None:
    if not 2 <= len(sys.argv) <= 3:
        sys.exit(f"usage: {sys.argv[0]} PUBLIC_DIR [LANG]")
    root = Path(sys.argv[1])
    lang = sys.argv[2] if len(sys.argv) == 3 else "en"

    files = changed = arrays = 0
    for path in root.rglob("*.json"):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError):
            continue
        files += 1
        n = sort_node(data, lang)
        if n:
            path.write_text(
                json.dumps(data, ensure_ascii=False, separators=(",", ":")),
                encoding="utf-8",
            )
            changed += 1
            arrays += n
    print(f"scanned {files} JSON file(s); sorted {arrays} tree array(s) "
          f"in {changed} file(s) by prefLabel[{lang}]")


if __name__ == "__main__":
    main()
