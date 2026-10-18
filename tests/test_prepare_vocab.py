"""Tests for scripts/prepare_vocab.py, the SkoHub normaliser."""

import subprocess
import sys

import pytest
from rdflib import Graph, Literal, URIRef
from rdflib.namespace import DCTERMS, RDF, SKOS

import prepare_vocab as pv
from conftest import ROOT

T = "http://connectivity-hub.com/terms/"
SCHEME = URIRef(T)
TOP, CHILD, GRANDCHILD, ORPHAN = (URIRef(T + n) for n in ("top", "child", "grandchild", "orphan"))

SAMPLE = f"""
@prefix skos: <http://www.w3.org/2004/02/skos/core#> .
@prefix dct: <http://purl.org/dc/terms/> .

<{T}> a skos:ConceptScheme ;
    dct:title "MAIA taxonomy"@en ;
    skos:hasTopConcept <{T}top>, <{T}child>, <{T}grandchild> .

<{T}top> a skos:Concept ; skos:inScheme <{T}> ; skos:topConceptOf <{T}> ;
    skos:prefLabel "Top"@en ;
    skos:narrower <{T}child> .

# child only says broader; grandchild is wrongly marked as a top concept
<{T}child> a skos:Concept ; skos:inScheme <{T}> ; skos:topConceptOf <{T}> ;
    skos:prefLabel "Child"@en, "Child, longer label"@en ;
    skos:broader <{T}top> .

<{T}grandchild> a skos:Concept ; skos:inScheme <{T}> ; skos:topConceptOf <{T}> ;
    skos:prefLabel "Grandchild" ;
    skos:broader <{T}child> .

# no broader and not registered as a top concept
<{T}orphan> a skos:Concept ; skos:inScheme <{T}> ;
    skos:prefLabel "Orphan"@en .
"""


def prepared(ttl: str = SAMPLE) -> Graph:
    g = Graph().parse(data=ttl, format="turtle")
    pv.rename_scheme(g)
    pv.add_license(g)
    pv.add_methodology(g)
    pv.normalise_hierarchy(g)
    pv.tag_untagged_text(g)
    pv.dedupe_language_maps(g)
    return g


def top_concepts(g: Graph) -> set:
    return set(g.objects(SCHEME, SKOS.hasTopConcept))


def test_top_concept_iff_no_broader():
    g = prepared()
    assert top_concepts(g) == {TOP, ORPHAN}
    assert set(g.subjects(SKOS.topConceptOf, SCHEME)) == {TOP, ORPHAN}


def test_broader_narrower_symmetric():
    g = prepared()
    assert (CHILD, SKOS.broader, TOP) in g
    assert (TOP, SKOS.narrower, CHILD) in g
    assert (CHILD, SKOS.narrower, GRANDCHILD) in g


def test_scheme_gets_licence_methodology_and_new_title():
    g = prepared()
    assert (SCHEME, DCTERMS.license, pv.DEFAULT_LICENSE) in g
    assert (SCHEME, DCTERMS.references, pv.METHODOLOGY_URL) in g
    assert list(g.objects(SCHEME, DCTERMS.title)) == [Literal(pv.NEW_TITLE, lang="en")]


def test_existing_licence_is_kept():
    other = "https://example.org/licence"
    g = prepared(SAMPLE + f"<{T}> <http://purl.org/dc/terms/license> <{other}> .")
    assert set(g.objects(SCHEME, DCTERMS.license)) == {URIRef(other)}


def test_untagged_label_tagged_english():
    g = prepared()
    assert list(g.objects(GRANDCHILD, SKOS.prefLabel)) == [Literal("Grandchild", lang="en")]


def test_one_label_per_language_keeps_longest():
    g = prepared()
    assert list(g.objects(CHILD, SKOS.prefLabel)) == [Literal("Child, longer label", lang="en")]


def test_idempotent():
    once = prepared()
    twice = prepared(once.serialize(format="turtle"))
    assert set(once) == set(twice)


@pytest.fixture(scope="module")
def committed_vocab(tmp_path_factory) -> Graph:
    """The committed concepts.ttl, run through the script's command line."""
    out = tmp_path_factory.mktemp("vocab") / "concepts.ttl"
    subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "prepare_vocab.py"), str(ROOT / "concepts.ttl"), str(out)],
        check=True, capture_output=True,
    )
    return Graph().parse(out, format="turtle")


def test_committed_vocabulary_is_complete(committed_vocab):
    # same floor fetch_vocab.py uses to reject a truncated hub fetch
    import fetch_vocab
    concepts = set(committed_vocab.subjects(RDF.type, SKOS.Concept))
    assert len(concepts) >= fetch_vocab.MIN_CONCEPTS


def test_committed_vocabulary_hierarchy(committed_vocab):
    g = committed_vocab
    tops = top_concepts(g)
    assert tops, "no top concepts"
    assert not {c for c in tops if (c, SKOS.broader, None) in g}, "a top concept has a broader"
    assert (SCHEME, DCTERMS.license, None) in g


def test_committed_vocabulary_has_english_labels(committed_vocab):
    g = committed_vocab
    missing = [c for c in g.subjects(RDF.type, SKOS.Concept)
               if not any(l.language == "en" for l in g.objects(c, SKOS.prefLabel))]
    assert not missing, f"{len(missing)} concept(s) without an English prefLabel, e.g. {missing[:3]}"
