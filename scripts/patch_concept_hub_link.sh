#!/bin/sh
# Patch SkoHub's concept page component so every term links back to its *dynamic*
# representation in the weADAPT Connectivity Hub.
#
# WHY. The static SkoHub site is a mirror of the vocabulary that lives upstream in
# the Connectivity Hub. Each term page here (e.g. .../terms/<uuid>.html) has a
# living counterpart in the hub's viewer, e.g. for "Early warning systems (EWS)":
#   https://connectivity-hub.weadapt.org/?resource=<encoded jsonld url>&teaser_resource=false
# Reviewers browsing the taxonomy asked to jump from a term straight to that live
# view. The link is fully deterministic from the concept's UUID, which is the last
# path segment of the concept id (http://connectivity-hub.com/terms/<uuid>), so we
# don't need any extra data in concepts.ttl — we build it at render time.
#
# Concept.jsx renders only a fixed set of SKOS properties (definition, notes,
# related, *Match, ...) and has no generic "see also"/external-link slot, so a plain
# triple in the data would not surface as a link. We therefore inject the link into
# the component itself, right under the concept URI.
#
# HOW. skohub/skohub-vocabs-docker builds the site with Gatsby at `docker run` time
# (CMD `npm run container-build`, source at /app), so this runs inside the container
# just before that build — see .github/workflows/pages.yml, chained after
# patch_search_tree.sh. It inserts one JSX block after a unique anchor line and
# hard-fails if that anchor is missing / not unique (i.e. upstream SkoHub changed and
# the patch needs a re-check) rather than silently shipping an un-patched site. It is
# idempotent: a second run detects the marker and exits 0.
set -eu

f=/app/src/components/Concept.jsx
# Anchor: the concept-URI element, rendered once per concept page.
needle='<ConceptURI id={concept.id} />'
marker='connectivity-hub-live-link'

# --- The API host that backs the Connectivity Hub viewer. -------------------------
# `api-uat` is the UAT/staging host used in the original request; the production host
# `api.connectivity-hub.com` serves the same JSON-LD. Change this one value to switch.
hub_api_host='api-uat.connectivity-hub.com'
# ----------------------------------------------------------------------------------

if [ ! -f "$f" ]; then
  echo "PATCH ERROR: $f not found — the skohub-vocabs image layout changed." >&2
  exit 1
fi

# Idempotent: if we've already injected the link, do nothing.
if grep -F "$marker" "$f" >/dev/null 2>&1; then
  echo "PATCH OK: Connectivity Hub link already present in $f — skipping."
  exit 0
fi

count=$(grep -F -c "$needle" "$f" || true)
if [ "$count" != "1" ]; then
  echo "PATCH ERROR: expected exactly 1 occurrence of '$needle' in $f, found ${count}." >&2
  echo "Upstream SkoHub changed; re-check scripts/patch_concept_hub_link.sh against the new source." >&2
  exit 1
fi

# The JSX block to insert after the anchor line. Single-quoted heredoc: backticks,
# ${...} and {} are written verbatim (no shell expansion). The href is computed from
# concept.id at render time: last path segment = the term UUID.
block_tmp=$(mktemp)
cat > "$block_tmp" <<'EOF'
      {/* connectivity-hub-live-link: jump to this term's live view in the weADAPT Connectivity Hub */}
      <p className="hubLink" style={{ margin: "0.5rem 0" }}>
        <a
          target="_blank"
          rel="noreferrer"
          href={`https://connectivity-hub.weadapt.org/?resource=${encodeURIComponent(
            `https://__HUB_API_HOST__/api/keyword/${concept.id
              .split("/")
              .filter(Boolean)
              .pop()}.jsonld`
          )}&teaser_resource=false`}
        >
          View in the Connectivity Hub ↗
        </a>
      </p>
EOF

# Substitute the configurable API host into the block.
sed "s|__HUB_API_HOST__|${hub_api_host}|g" "$block_tmp" > "$block_tmp.host" && mv "$block_tmp.host" "$block_tmp"

# Insert the block immediately after the (unique) anchor line.
awk -v needle="$needle" -v blockfile="$block_tmp" '
  { print }
  index($0, needle) > 0 {
    while ((getline line < blockfile) > 0) print line
    close(blockfile)
  }
' "$f" > "$f.patched" && mv "$f.patched" "$f"
rm -f "$block_tmp"

if ! grep -F "$marker" "$f" >/dev/null; then
  echo "PATCH ERROR: verification failed — Connectivity Hub link not present after edit." >&2
  exit 1
fi

echo "PATCH OK: Connectivity Hub live-link injected into $f (host: ${hub_api_host})."
