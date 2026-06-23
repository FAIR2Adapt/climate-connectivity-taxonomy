#!/usr/bin/env python3
"""Fix the SkoHub navigation-tree indentation in the built site.

SkoHub renders each tree row as a flexbox `<li>` where the expand/collapse toggle
button only exists on concepts that *have* children (see nestedList.jsx upstream).
Because the button is an in-row flex child (~25px wide), a parent concept's label is
pushed ~25px to the right of its leaf siblings, so an expanded parent (e.g.
"Uncertainty") looks like it is nested *under* the leaf directly above it (e.g.
"Adaptation revenues") even though they are siblings. See the Climate Connectivity
Taxonomy issue where Uncertainty appeared under Adaptation revenues.

We can't patch the (prebuilt) SkoHub image, so we inject a small CSS rule into every
built HTML page that gives leaf rows the same left offset as the toggle, lining all
siblings up. Uses :has() (widely supported) to target rows that lack a toggle button.

Idempotent: pages already carrying the marker are skipped.

Usage:
    python scripts/fix_tree_indent.py public
"""

import sys
from pathlib import Path

MARKER = "cct-tree-indent-fix"
# 25px = toggle button width (20px) + its margin-right (5px), from nestedList.jsx.
STYLE = (
    f'<style id="{MARKER}">'
    ".concepts li:not(:has(> button.treeItemIcon)) > div{margin-left:25px}"
    "</style>"
)


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(f"usage: {sys.argv[0]} PUBLIC_DIR")
    root = Path(sys.argv[1])

    seen = patched = 0
    for path in root.rglob("*.html"):
        if not path.is_file():  # Gatsby creates dirs literally named "404.html"
            continue
        html = path.read_text(encoding="utf-8")
        seen += 1
        if MARKER in html or "</head>" not in html:
            continue
        path.write_text(html.replace("</head>", STYLE + "</head>", 1),
                        encoding="utf-8")
        patched += 1
    print(f"scanned {seen} HTML file(s); injected tree-indent CSS into {patched}")


if __name__ == "__main__":
    main()
