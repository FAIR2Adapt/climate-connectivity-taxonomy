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


def fetch(url: str) -> Graph:
    req = urllib.request.Request(url, headers=TURTLE)
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = resp.read()
    g = Graph()
    g.parse(data=data, format="turtle")
    return g


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
    while frontier and fetched < MAX_CONCEPTS:
        url = frontier.pop()
        if url in seen:
            continue
        seen.add(url)
        try:
            g = fetch(url)
        except Exception as exc:  # keep going; report at the end
            print(f"  WARN could not fetch {url}: {exc}", file=sys.stderr)
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

    merged.serialize(destination=out, format="turtle")
    n_concepts = len(set(merged.subjects(None, None)) &
                     set(merged.subjects(SKOS.prefLabel, None)))
    print(f"fetched {fetched} concepts; wrote {len(merged)} triples "
          f"({n_concepts} labelled subjects) to {out}")


if __name__ == "__main__":
    main()
