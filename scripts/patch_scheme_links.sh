#!/bin/sh
# Patch SkoHub's concept-scheme page component so the scheme page
# (.../terms/index.html) shows "Methodology" and "Connectivity Hub" sections right
# below "License".
#
# WHY. The scheme page is the landing page most visitors see first, so the
# connectivity-hub team asked for the methodology document and the hub to be
# linked there too, not only from the site footer (which keeps its links). The
# scheme already carries the methodology as dct:references
# (scripts/prepare_vocab.py), but ConceptScheme.jsx renders only a fixed set of
# fields (title, description, publisher, issued, license, preferred namespace) and
# has no slot for dct:references. Putting the links in dct:description would show
# them, but above the licence; they want them below.
#
# HOW. Same mechanism as patch_concept_hub_link.sh: runs inside the
# skohub/skohub-vocabs-docker container just before `npm run container-build`
# (see .github/workflows/pages.yml). It inserts JSX blocks, styled like the
# License block, before the unique "preferred namespace URI" anchor line — i.e.
# straight after the License block. It hard-fails if the anchor is missing or not
# unique (upstream SkoHub changed) and is idempotent (a second run exits 0).
set -eu

f=/app/src/components/ConceptScheme.jsx
# Anchor: the first block after License in ConceptScheme.jsx.
needle='{conceptScheme.preferredNamespaceUri && ('
marker='cct-scheme-links'

# --- Link targets. Keep in sync with the footer links in config.yaml, and the ----
# methodology URL with METHODOLOGY_URL in scripts/prepare_vocab.py.
methodology_url='https://docs.google.com/document/d/1uPh00X7Et_E4Wsp4tqeIurVzxPW4gsuEXY136ghXTzc/view'
hub_url='https://connectivity-hub.weadapt.org/'
# ----------------------------------------------------------------------------------

if [ ! -f "$f" ]; then
  echo "PATCH ERROR: $f not found — the skohub-vocabs image layout changed." >&2
  exit 1
fi

# Idempotent: if we've already injected the links, do nothing.
if grep -F "$marker" "$f" >/dev/null 2>&1; then
  echo "PATCH OK: scheme links already present in $f — skipping."
  exit 0
fi

count=$(grep -F -c "$needle" "$f" || true)
if [ "$count" != "1" ]; then
  echo "PATCH ERROR: expected exactly 1 occurrence of '$needle' in $f, found ${count}." >&2
  echo "Upstream SkoHub changed; re-check scripts/patch_scheme_links.sh against the new source." >&2
  exit 1
fi

# The JSX blocks to insert before the anchor line (same markup as the License block).
block_tmp=$(mktemp)
cat > "$block_tmp" <<'EOF'
          {/* cct-scheme-links: methodology document and upstream hub */}
          <div>
            <h3>Methodology</h3>
            <a href="__METHODOLOGY_URL__" target="_blank" rel="noopener noreferrer">
              __METHODOLOGY_URL__
            </a>
          </div>
          <div>
            <h3>Connectivity Hub</h3>
            <a href="__HUB_URL__" target="_blank" rel="noopener noreferrer">
              __HUB_URL__
            </a>
          </div>
EOF

sed -e "s|__METHODOLOGY_URL__|${methodology_url}|g" -e "s|__HUB_URL__|${hub_url}|g" \
  "$block_tmp" > "$block_tmp.url" && mv "$block_tmp.url" "$block_tmp"

# Insert the blocks immediately before the (unique) anchor line.
awk -v needle="$needle" -v blockfile="$block_tmp" '
  index($0, needle) > 0 {
    while ((getline line < blockfile) > 0) print line
    close(blockfile)
  }
  { print }
' "$f" > "$f.patched" && mv "$f.patched" "$f"
rm -f "$block_tmp"

if ! grep -F "$marker" "$f" >/dev/null; then
  echo "PATCH ERROR: verification failed — scheme links not present after edit." >&2
  exit 1
fi

echo "PATCH OK: methodology and Connectivity Hub links injected into $f."
