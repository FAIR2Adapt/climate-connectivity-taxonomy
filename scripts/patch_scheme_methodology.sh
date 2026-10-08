#!/bin/sh
# Patch SkoHub's concept-scheme page component so the scheme page
# (.../terms/index.html) shows a "Methodology" section right below "License".
#
# WHY. The connectivity-hub team asked for the methodology document to be linked
# from the scheme page, not only from the site footer. The scheme already carries
# it as dct:references (scripts/prepare_vocab.py), but ConceptScheme.jsx renders
# only a fixed set of fields (title, description, publisher, issued, license,
# preferred namespace) and has no slot for dct:references. Putting the link in
# dct:description would show it, but above the licence; they want it below.
#
# HOW. Same mechanism as patch_concept_hub_link.sh: runs inside the
# skohub/skohub-vocabs-docker container just before `npm run container-build`
# (see .github/workflows/pages.yml). It inserts one JSX block, styled like the
# License block, before the unique "preferred namespace URI" anchor line — i.e.
# straight after the License block. It hard-fails if the anchor is missing or not
# unique (upstream SkoHub changed) and is idempotent (a second run exits 0).
set -eu

f=/app/src/components/ConceptScheme.jsx
# Anchor: the first block after License in ConceptScheme.jsx.
needle='{conceptScheme.preferredNamespaceUri && ('
marker='cct-methodology-link'

# --- How the taxonomy was built. Keep in sync with METHODOLOGY_URL in ------------
# scripts/prepare_vocab.py and the footer link in config.yaml.
methodology_url='https://docs.google.com/document/d/1uPh00X7Et_E4Wsp4tqeIurVzxPW4gsuEXY136ghXTzc/view'
# ----------------------------------------------------------------------------------

if [ ! -f "$f" ]; then
  echo "PATCH ERROR: $f not found — the skohub-vocabs image layout changed." >&2
  exit 1
fi

# Idempotent: if we've already injected the section, do nothing.
if grep -F "$marker" "$f" >/dev/null 2>&1; then
  echo "PATCH OK: methodology section already present in $f — skipping."
  exit 0
fi

count=$(grep -F -c "$needle" "$f" || true)
if [ "$count" != "1" ]; then
  echo "PATCH ERROR: expected exactly 1 occurrence of '$needle' in $f, found ${count}." >&2
  echo "Upstream SkoHub changed; re-check scripts/patch_scheme_methodology.sh against the new source." >&2
  exit 1
fi

# The JSX block to insert before the anchor line (same markup as the License block).
block_tmp=$(mktemp)
cat > "$block_tmp" <<'EOF'
          {/* cct-methodology-link: how the taxonomy was built */}
          <div>
            <h3>Methodology</h3>
            <a href="__METHODOLOGY_URL__" target="_blank" rel="noopener noreferrer">
              __METHODOLOGY_URL__
            </a>
          </div>
EOF

sed "s|__METHODOLOGY_URL__|${methodology_url}|g" "$block_tmp" > "$block_tmp.url" && mv "$block_tmp.url" "$block_tmp"

# Insert the block immediately before the (unique) anchor line.
awk -v needle="$needle" -v blockfile="$block_tmp" '
  index($0, needle) > 0 {
    while ((getline line < blockfile) > 0) print line
    close(blockfile)
  }
  { print }
' "$f" > "$f.patched" && mv "$f.patched" "$f"
rm -f "$block_tmp"

if ! grep -F "$marker" "$f" >/dev/null; then
  echo "PATCH ERROR: verification failed — methodology section not present after edit." >&2
  exit 1
fi

echo "PATCH OK: methodology section injected into $f."
