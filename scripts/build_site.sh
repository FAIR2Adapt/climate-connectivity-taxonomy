#!/usr/bin/env bash
# Build the static SkoHub Vocabs site from the committed concepts.ttl into public/.
# Used by .github/workflows/pages.yml and for local builds:
#
#   bash scripts/build_site.sh                 # site served from / (local preview)
#   BASEURL=/climate-connectivity-taxonomy bash scripts/build_site.sh   # GitHub Pages
#
# Requires Docker, Python 3 with rdflib, and pandoc. Nothing is fetched from the
# connectivity-hub or Google here: the site is built from the committed concepts.ttl
# and methodology/ snapshots.
set -euo pipefail

cd "$(dirname "$0")/.."
BASEURL="${BASEURL:-}"

# 1. Normalise the vocabulary (licence + hierarchy + de-dup).
mkdir -p data
python3 scripts/prepare_vocab.py concepts.ttl data/concepts.ttl

# 2. Build the site with SkoHub. The image builds with Gatsby at run time (CMD
# `npm run container-build`, source under /app). We override the entrypoint to
# first apply our build-time patches and then run that same build:
#   - patch_search_tree.sh      fixes SkoHub's search so a matched parent concept
#     shows its subtree;
#   - patch_concept_hub_link.sh adds a "View in the Connectivity Hub" link to every
#     term page (deterministic from the concept UUID);
#   - patch_scheme_links.sh adds "Methodology" and "Connectivity Hub" links below
#     "License" on the scheme page (terms/index.html).
# Each patch hard-fails if the upstream source moved, so a broken patch stops the
# build instead of silently shipping the old behaviour.
echo "BASEURL=${BASEURL}" > .env
rm -rf public
mkdir -p public && chmod 777 public
docker run --rm --platform linux/amd64 \
  --entrypoint /bin/sh \
  -v "$PWD/public:/app/public" \
  -v "$PWD/data:/app/data" \
  -v "$PWD/.env:/app/.env" \
  -v "$PWD/config.yaml:/app/config.yaml" \
  -v "$PWD/scripts/patch_search_tree.sh:/tmp/patch_search_tree.sh:ro" \
  -v "$PWD/scripts/patch_concept_hub_link.sh:/tmp/patch_concept_hub_link.sh:ro" \
  -v "$PWD/scripts/patch_scheme_links.sh:/tmp/patch_scheme_links.sh:ro" \
  skohub/skohub-vocabs-docker:latest \
  -c "sh /tmp/patch_search_tree.sh && sh /tmp/patch_concept_hub_link.sh && sh /tmp/patch_scheme_links.sh && npm run container-build"

# The build writes public/ as the image's user, which the post-processing below
# can't overwrite. Hand it back to the calling user from a throwaway root container
# (no sudo needed on the host).
docker run --rm --platform linux/amd64 --user 0 --entrypoint chown \
  -v "$PWD/public:/app/public" \
  skohub/skohub-vocabs-docker:latest -R "$(id -u):$(id -g)" /app/public

# 3. Post-process the built site: SkoHub renders the nav tree in raw data order and
# indents parent rows past their leaf siblings.
python3 scripts/sort_tree.py public
python3 scripts/fix_tree_indent.py public

# 4. Render the methodology page from the committed snapshot of the Google Doc.
sh scripts/render_methodology.sh methodology public/methodology

echo "Site built in public/ (BASEURL='${BASEURL}')."
