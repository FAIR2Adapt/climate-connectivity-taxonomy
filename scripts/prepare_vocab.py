#!/usr/bin/env python3
"""Normalise the raw Climate Connectivity Taxonomy export so SkoHub Vocabs can build a good site.

The vocabulary is exported from the connectivity-hub as-is ("dirty"): it has no
licence, every concept is flagged as a top concept (so no hierarchy shows), and a
few concepts carry several same-language definitions/labels. This script rewrites
that export into a clean SKOS file that SkoHub can turn into a browsable site.

It is **idempotent**: running it on an already-clean file changes nothing, so a
fresh export from the hub can be dropped in and re-processed at build time.

Usage:
    python scripts/prepare_vocab.py INPUT.ttl OUTPUT.ttl
"""

import sys

from rdflib import Graph, Literal, URIRef
from rdflib.namespace import DCTERMS, RDF, SKOS, XSD

# Licence applied to the concept scheme when it has none. Change here (or pass a
# third CLI arg) if the official licence differs.
DEFAULT_LICENSE = URIRef("https://creativecommons.org/licenses/by/4.0/")

# Language assumed for literals that the hub exports without a language tag.
# SkoHub renders these fields through a per-language LanguageMap (i18n), so an
# untagged literal never matches the UI language ("en") and is silently dropped
# — most visibly skos:editorialNote, which the hub exports entirely untagged
# (e.g. "source:IPCC Glossary AR6"). Tagging them as English makes them render.
DEFAULT_LANG = "en"

# Text predicates SkoHub renders via i18n(language)(...). Any untagged plain
# literal on these is retagged with DEFAULT_LANG so the field shows up.
LOCALISED_TEXT = [
    SKOS.prefLabel,
    SKOS.altLabel,
    SKOS.hiddenLabel,
    SKOS.definition,
    SKOS.scopeNote,
    SKOS.editorialNote,
    SKOS.historyNote,
    SKOS.changeNote,
    SKOS.note,
    SKOS.example,
]

# The vocabulary was renamed from "MAIA taxonomy" to "Climate Connectivity
# Taxonomy". Until the hub itself is updated, rewrite any scheme title still
# carrying the old name. This is a no-op once the hub serves the new name.
OLD_TITLE_MARKER = "MAIA"
NEW_TITLE = "Climate Connectivity Taxonomy"

# Predicates that SkoHub treats as one value per language (a LanguageMap). If the
# export carries several values in the same language, we must collapse them to a
# single value or SkoHub drops the whole field as a type conflict. There are two
# ways to collapse, depending on what the predicate means:
#
#   MERGE   — content fields where every value is real text a reader should see
#             (e.g. a concept with an IPCC and a UNDRR-HIPS definition). We join
#             the same-language values into one literal so none is lost.
#   KEEP    — identity/label fields that are meant to hold a single value per
#             language (a concept has one prefLabel); if the export carries
#             several we keep the longest and drop the rest.
MERGE_PER_LANG = [
    SKOS.definition,
    SKOS.example,
    DCTERMS.description,
]
KEEP_LONGEST_PER_LANG = [
    SKOS.prefLabel,
    DCTERMS.title,
]

# Separator inserted between merged same-language values. The hub exports these
# fields as HTML (definitions already contain <br /> / <p> tags), so a paragraph
# break keeps the merged values visually distinct on the built page.
MERGE_SEPARATOR = "<br /><br />"


def rename_scheme(g: Graph) -> int:
    """Replace any scheme title still containing the old name with NEW_TITLE."""
    renamed = 0
    for scheme in g.subjects(RDF.type, SKOS.ConceptScheme):
        for predicate in (DCTERMS.title, SKOS.prefLabel):
            for obj in list(g.objects(scheme, predicate)):
                if isinstance(obj, Literal) and OLD_TITLE_MARKER in str(obj):
                    g.remove((scheme, predicate, obj))
                    g.add((scheme, predicate, Literal(NEW_TITLE, lang=obj.language or "en")))
                    renamed += 1
    return renamed


def add_license(g: Graph) -> int:
    """Give every concept scheme a dct:license if it lacks one."""
    added = 0
    for scheme in g.subjects(RDF.type, SKOS.ConceptScheme):
        if (scheme, DCTERMS.license, None) not in g:
            g.add((scheme, DCTERMS.license, DEFAULT_LICENSE))
            added += 1
    return added


def normalise_hierarchy(g: Graph) -> tuple[int, int]:
    """Surface the latent hierarchy.

    1. Make broader/narrower symmetric so SkoHub can walk the tree from the top
       down (it builds the tree from a parent's skos:narrower links).
    2. A concept is a *top* concept iff it has no broader. Rebuild
       skos:topConceptOf / skos:hasTopConcept accordingly so child concepts stop
       appearing at the root.
    """
    # 1. symmetric broader <-> narrower
    for child, _, parent in list(g.triples((None, SKOS.broader, None))):
        g.add((parent, SKOS.narrower, child))
    for parent, _, child in list(g.triples((None, SKOS.narrower, None))):
        g.add((child, SKOS.broader, parent))

    has_broader = {c for c, _, _ in g.triples((None, SKOS.broader, None))}

    # Map each concept to the scheme(s) it belongs to (via inScheme/topConceptOf).
    schemes_of: dict[URIRef, set] = {}
    for c, _, s in g.triples((None, SKOS.inScheme, None)):
        schemes_of.setdefault(c, set()).add(s)
    for c, _, s in g.triples((None, SKOS.topConceptOf, None)):
        schemes_of.setdefault(c, set()).add(s)

    demoted = promoted = 0
    for concept in set(g.subjects(RDF.type, SKOS.Concept)):
        schemes = schemes_of.get(concept, set())
        if concept in has_broader:
            # child concept: must not be a top concept
            for s in list(schemes):
                if (concept, SKOS.topConceptOf, s) in g:
                    g.remove((concept, SKOS.topConceptOf, s))
                    demoted += 1
                g.remove((s, SKOS.hasTopConcept, concept))
        else:
            # root concept: make sure it is registered as a top concept
            for s in schemes:
                if (concept, SKOS.topConceptOf, s) not in g:
                    g.add((concept, SKOS.topConceptOf, s))
                    g.add((s, SKOS.hasTopConcept, concept))
                    promoted += 1
    return demoted, promoted


def tag_untagged_text(g: Graph) -> int:
    """Add DEFAULT_LANG to untagged plain literals on localised-text predicates.

    SkoHub looks each value up by language; a literal with no language tag is
    invisible in the "en" UI. We only touch plain strings (no language, no
    datatype other than xsd:string) so typed values are left alone.
    """
    tagged = 0
    for predicate in LOCALISED_TEXT:
        for subject, _, obj in list(g.triples((None, predicate, None))):
            if (
                isinstance(obj, Literal)
                and not obj.language
                and obj.datatype in (None, XSD.string)
            ):
                g.remove((subject, predicate, obj))
                g.add((subject, predicate, Literal(str(obj), lang=DEFAULT_LANG)))
                tagged += 1
    return tagged


def _collapse(g: Graph, predicate, merge: bool) -> int:
    """Collapse several same-language values on `predicate` to one per language.

    If `merge`, the values are concatenated into a single literal (nothing is
    lost); otherwise the longest is kept and the rest dropped. The graph is a
    set with no value order, so values are ordered deterministically — longest
    first, then lexically — so the output is stable and idempotent.
    """
    changed = 0
    for subject in set(g.subjects(predicate, None)):
        by_lang: dict[str, list] = {}
        for obj in g.objects(subject, predicate):
            if isinstance(obj, Literal) and obj.language:
                by_lang.setdefault(obj.language, []).append(obj)
        for lang, values in by_lang.items():
            if len(values) <= 1:
                continue
            ordered = sorted(values, key=lambda lit: (-len(str(lit)), str(lit)))
            for obj in values:
                g.remove((subject, predicate, obj))
            if merge:
                merged = MERGE_SEPARATOR.join(str(lit) for lit in ordered)
                g.add((subject, predicate, Literal(merged, lang=lang)))
                changed += len(values) - 1
            else:
                g.add((subject, predicate, ordered[0]))
                changed += len(values) - 1
    return changed


def dedupe_language_maps(g: Graph) -> int:
    """Collapse multi-valued LanguageMap predicates to one value per language.

    Content predicates (definitions, examples) merge so no text is lost;
    identity predicates (prefLabel, title) keep the longest value.
    """
    changed = 0
    for predicate in MERGE_PER_LANG:
        changed += _collapse(g, predicate, merge=True)
    for predicate in KEEP_LONGEST_PER_LANG:
        changed += _collapse(g, predicate, merge=False)
    return changed


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(f"usage: {sys.argv[0]} INPUT.ttl OUTPUT.ttl")
    src, dst = sys.argv[1], sys.argv[2]

    g = Graph()
    g.parse(src, format="turtle")
    before = len(g)

    renamed = rename_scheme(g)
    licenses = add_license(g)
    demoted, promoted = normalise_hierarchy(g)
    tagged = tag_untagged_text(g)
    deduped = dedupe_language_maps(g)

    g.serialize(destination=dst, format="turtle")

    print(f"parsed {before} triples from {src}")
    print(f"  renamed {renamed} scheme title(s) to '{NEW_TITLE}'")
    print(f"  licence added to {licenses} scheme(s)")
    print(f"  hierarchy: demoted {demoted} child concept(s) from top level, "
          f"promoted {promoted} root(s)")
    print(f"  tagged {tagged} untagged literal(s) as '{DEFAULT_LANG}'")
    print(f"  de-duplicated {deduped} same-language value(s)")
    print(f"wrote {len(g)} triples to {dst}")


if __name__ == "__main__":
    main()
