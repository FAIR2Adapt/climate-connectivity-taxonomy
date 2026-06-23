#!/usr/bin/env python3
"""Fetch the *complete* Climate Connectivity Taxonomy from the connectivity-hub.

The previous exporter only downloaded the concepts listed in the scheme's
skos:hasTopConcept, which drops every child concept (anything reachable only via
skos:broader / skos:narrower). This crawler instead starts from the scheme and
follows hierarchy/relation links until it has fetched every referenced concept,
so the resulting file contains the full tree.

Usage:
    python scripts/fetch_vocab.py OUTPUT.ttl [SCHEME_URL]
"""

import sys
import time
import urllib.request

from rdflib import Graph, URIRef
from rdflib.namespace import SKOS

DEFAULT_SCHEME = "http://connectivity-hub.com/terms/"
TURTLE = {"Accept": "text/turtle"}
# follow these predicates to discover more concepts to fetch
LINK_PREDICATES = [
    SKOS.hasTopConcept, SKOS.narrower, SKOS.broader,
    SKOS.narrowerTransitive, SKOS.broaderTransitive, SKOS.related,
]
MAX_CONCEPTS = 5000  # safety cap

# Completeness guards. The hub is intermittently flaky; a fetch that quietly
# drops concepts must NOT be deployed/committed (it would shrink the published
# vocabulary). Retry each request, then refuse to write the file if too many
# requests still failed or the result is suspiciously small.
RETRIES = 4              # attempts per URL before giving up
BACKOFF = 1.5           # seconds, multiplied by attempt number
ABORT_AFTER = 50        # bail out early once this many URLs have failed for good
MIN_CONCEPTS = 1000     # floor below which the vocabulary is assumed truncated
FAIL_RATE = 0.01        # tolerated fraction of failed fetches (≈1%)


def fetch(url: str) -> Graph:
    last_exc = None
    for attempt in range(RETRIES):
        try:
            req = urllib.request.Request(url, headers=TURTLE)
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = resp.read()
            g = Graph()
            g.parse(data=data, format="turtle")
            return g
        except Exception as exc:  # transient hub error/slowness — retry
            last_exc = exc
            if attempt < RETRIES - 1:
                time.sleep(BACKOFF * (attempt + 1))
    raise last_exc


def main() -> None:
    if not 2 <= len(sys.argv) <= 3:
        sys.exit(f"usage: {sys.argv[0]} OUTPUT.ttl [SCHEME_URL]")
    out = sys.argv[1]
    scheme_url = sys.argv[2] if len(sys.argv) == 3 else DEFAULT_SCHEME
    base = scheme_url  # term URIs share the scheme's namespace prefix

    merged = Graph()
    scheme = fetch(scheme_url)
    merged += scheme

    # seed the frontier with every term URI referenced by the scheme
    seen: set = {scheme_url}
    frontier = set()
    for p in LINK_PREDICATES:
        for o in scheme.objects(None, p):
            if isinstance(o, URIRef) and str(o).startswith(base):
                frontier.add(str(o))

    fetched = 0
    failed: list = []
    while frontier and fetched < MAX_CONCEPTS:
        url = frontier.pop()
        if url in seen:
            continue
        seen.add(url)
        try:
            g = fetch(url)
        except Exception as exc:  # gave up after retries; record it
            failed.append(url)
            print(f"  WARN could not fetch {url}: {exc}", file=sys.stderr)
            if len(failed) > ABORT_AFTER:
                sys.exit(f"ERROR: {len(failed)} fetches failed after retries — "
                         f"the connectivity-hub is unhealthy. Aborting before "
                         f"writing a truncated vocabulary; re-run when it recovers.")
            continue
        merged += g
        fetched += 1
        # discover new concepts referenced by this one
        for p in LINK_PREDICATES:
            for o in g.objects(URIRef(url), p):
                if isinstance(o, URIRef) and str(o).startswith(base) and str(o) not in seen:
                    frontier.add(str(o))
        if fetched % 100 == 0:
            print(f"  fetched {fetched} concepts, {len(frontier)} queued…")
        time.sleep(0.05)  # be gentle on the server

    # Completeness guards — refuse to write a truncated vocabulary, so the build
    # fails instead of deploying/committing fewer concepts than the hub holds.
    attempted = fetched + len(failed)
    tolerated = max(5, int(attempted * FAIL_RATE))
    if len(failed) > tolerated:
        sys.exit(f"ERROR: {len(failed)}/{attempted} concept fetches failed "
                 f"(tolerated {tolerated}). The hub was unhealthy; refusing to "
                 f"write an incomplete vocabulary.")
    if fetched < MIN_CONCEPTS:
        sys.exit(f"ERROR: only fetched {fetched} concepts (< {MIN_CONCEPTS}). "
                 f"Result looks truncated; refusing to write it.")

    merged.serialize(destination=out, format="turtle")
    n_concepts = len(set(merged.subjects(None, None)) &
                     set(merged.subjects(SKOS.prefLabel, None)))
    print(f"fetched {fetched} concepts ({len(failed)} failed); wrote {len(merged)} "
          f"triples ({n_concepts} labelled subjects) to {out}")


if __name__ == "__main__":
    main()
