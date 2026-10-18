"""Tests for the built-site post-processors scripts/sort_tree.py and fix_tree_indent.py."""

import json
import subprocess
import sys

import fix_tree_indent
import sort_tree
from conftest import ROOT


def node(label, *children):
    n = {"id": label, "prefLabel": {"en": label}}
    if children:
        n["narrower"] = list(children)
    return n


def labels(nodes):
    return [n["prefLabel"]["en"] for n in nodes]


def test_sort_node_sorts_recursively_and_case_insensitively():
    tree = {"hasTopConcept": [node("beta", node("Zeta"), node("alpha")), node("Alpha")]}
    assert sort_tree.sort_node(tree, "en") == 2
    assert labels(tree["hasTopConcept"]) == ["Alpha", "beta"]
    assert labels(tree["hasTopConcept"][1]["narrower"]) == ["alpha", "Zeta"]


def test_label_falls_back_to_other_language_then_id():
    assert sort_tree.label({"prefLabel": {"de": "Wasser"}}, "en") == "wasser"
    assert sort_tree.label({"id": "X1"}, "en") == "x1"


def run(script, *args):
    subprocess.run([sys.executable, str(ROOT / "scripts" / script), *map(str, args)],
                   check=True, capture_output=True)


def test_sort_tree_rewrites_built_json(tmp_path):
    f = tmp_path / "terms" / "index.json"
    f.parent.mkdir()
    f.write_text(json.dumps({"hasTopConcept": [node("b"), node("a")]}))
    run("sort_tree.py", tmp_path)
    assert labels(json.loads(f.read_text())["hasTopConcept"]) == ["a", "b"]


def test_fix_tree_indent_injects_css_once(tmp_path):
    page = tmp_path / "index.html"
    page.write_text("<html><head><title>t</title></head><body></body></html>")
    (tmp_path / "404.html").mkdir()  # Gatsby creates directories named like pages
    run("fix_tree_indent.py", tmp_path)
    run("fix_tree_indent.py", tmp_path)
    assert page.read_text().count(fix_tree_indent.MARKER) == 1
