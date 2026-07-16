#!/bin/sh
# Patch SkoHub's navigation-tree component so that a concept which *itself* matches
# the search query shows its full subtree, instead of having its (non-matching)
# children pruned away.
#
# WHY. SkoHub renders the left nav tree from src/components/nestedList.jsx. When a
# search is active it filters the tree to only the branches that contain a match and
# passes that same filter down into every child list. A parent concept whose own
# prefLabel matches (e.g. "Barriers and enablers") is therefore shown, but each of
# its children is filtered out unless the child *also* matches the query — so the
# node renders in its "expanded" state with nothing beneath it. To the user the hit
# looks un-expandable / dead, even though its name still links to the concept page.
# See the reported issue: searching "Barriers and enablers" shows the term with no
# children and no working expand toggle.
#
# FIX. In the child recursion, if the current item is itself a direct search match
# (its id is in the flattened FlexSearch result set) render its children WITHOUT the
# filter, so the whole subtree shows and stays browsable. Branches that are only in
# the tree because a *descendant* matched keep the filter, so an unrelated deep match
# still narrows the tree as before.
#
# HOW. skohub/skohub-vocabs-docker builds the site with Gatsby at `docker run` time
# (CMD `npm run container-build`, source at /app), so this runs inside the container
# just before that build — see .github/workflows/pages.yml. It rewrites exactly one
# line and is version-robust: it recomputes the match set inline from the `queryFilter`
# prop rather than depending on the `filteredIds` local, and it hard-fails if the
# target line is missing or not unique (i.e. upstream changed and the patch needs a
# re-check) rather than silently shipping an unpatched site.
set -eu

f=/app/src/components/nestedList.jsx
needle='queryFilter={queryFilter}'
# A concept is a direct match iff its id is in any field's result list.
replacement='queryFilter={queryFilter && queryFilter.flatMap((f) => f.result).includes(item.id) ? null : queryFilter}'

if [ ! -f "$f" ]; then
  echo "PATCH ERROR: $f not found — the skohub-vocabs image layout changed." >&2
  exit 1
fi

count=$(grep -F -c "$needle" "$f" || true)
if [ "$count" != "1" ]; then
  echo "PATCH ERROR: expected exactly 1 occurrence of '$needle' in $f, found ${count}." >&2
  echo "Upstream SkoHub changed; re-check scripts/patch_search_tree.sh against the new source." >&2
  exit 1
fi

# Literal (non-regex) single-line replace via awk, to avoid escaping the { } & in sed.
awk -v needle="$needle" -v repl="$replacement" '
  {
    idx = index($0, needle)
    if (idx > 0) {
      $0 = substr($0, 1, idx - 1) repl substr($0, idx + length(needle))
    }
    print
  }
' "$f" > "$f.patched" && mv "$f.patched" "$f"

if ! grep -F "flatMap((f) => f.result).includes(item.id)" "$f" >/dev/null; then
  echo "PATCH ERROR: verification failed — replacement not present after edit." >&2
  exit 1
fi

echo "PATCH OK: matched-parent subtree fix applied to $f"
