# Climate Connectivity Taxonomy

**A SKOS vocabulary of climate-adaptation concepts, published as a browsable website.**
The Climate Connectivity Taxonomy (CC Taxonomy, formerly "MAIA taxonomy") organises the ~1,400
concepts used to describe resources in the [weADAPT Connectivity Hub](https://connectivity-hub.weadapt.org/).
This repository mirrors the taxonomy from the hub as a versioned Turtle file and holds the tooling
that publishes and previews it, so that the vocabulary is findable, citable and reusable outside
the hub.

- **Browse online:** <https://fair2adapt.github.io/climate-connectivity-taxonomy/>
- **Download:** [`concepts.ttl`](concepts.ttl) (SKOS, Turtle)
- **Concept URIs:** `http://connectivity-hub.com/terms/<uuid>` in the scheme `http://connectivity-hub.com/terms/`
- **Methodology:** [how the taxonomy was built](https://docs.google.com/document/d/1uPh00X7Et_E4Wsp4tqeIurVzxPW4gsuEXY136ghXTzc/view)

---

## Table of Contents

1. [Requirements](#requirements)
2. [Installation](#installation)
3. [Configuration](#configuration)
4. [Usage](#usage)
5. [Contributing](#contributing)
6. [License](#license)
7. [Acknowledgements](#acknowledgements)
8. [Citation](#citation)

---

## Requirements

You need nothing to browse or download the taxonomy. To build the site or run the preview yourself:

- Linux, macOS or Windows with WSL2
- [Git](https://git-scm.com/)
- [Docker](https://docs.docker.com/get-docker/) with Docker Compose. The SkoHub image is
  `linux/amd64`-only; on Apple Silicon it runs under emulation (slower, but it works).
- Python 3 (the CI uses 3.12) with [rdflib](https://rdflib.readthedocs.io/): `pip install rdflib`

Alternatively, a GitHub account is enough to run the Skosmos preview in a
[GitHub Codespace](#option-c-skosmos-preview-in-a-github-codespace), with nothing installed locally.

---

## Installation

```bash
# Clone the repo
git clone https://github.com/FAIR2Adapt/climate-connectivity-taxonomy.git

# Enter directory
cd climate-connectivity-taxonomy

# Install the Python dependency
pip install rdflib
```

Then choose how you want to look at the vocabulary.

### Option A: build the public site locally (SkoHub Vocabs)

This builds exactly what is published on GitHub Pages, from the committed `concepts.ttl`.

```bash
# Normalise concepts.ttl, build the site with SkoHub and post-process it into public/
bash scripts/build_site.sh

# Serve it
python3 -m http.server -d public 8000
```

Open <http://localhost:8000/>. The first build pulls the SkoHub image and takes a few minutes.

### Option B: Skosmos preview locally

[Skosmos](https://github.com/NatLibFi/Skosmos) is the internal tool for reviewing the vocabulary.

```bash
# Clone Skosmos into skosmos-src/, configure it, start Skosmos + Fuseki and load concepts.ttl
bash .devcontainer/postCreate.sh
```

Open <http://localhost:9090/> and click **English**. Stop it with
`docker compose -f skosmos-src/docker-compose.yml down`.

### Option C: Skosmos preview in a GitHub Codespace

1. In the GitHub repo, go to **Code → Codespaces → Create codespace on main**. This starts a VS
   Code environment and brings up Skosmos in Docker.

   ![Create codespace](images/create_codespace.png)

2. Wait a few minutes for the containers to start. When they are ready, the terminal shows the
   Skosmos link.

   ![Open Skosmos](images/containers_ready.png)

3. Open the link in a browser, then click **English** to view the taxonomy.
4. If the container doesn't start, press **F1** and run **Codespaces: View creation log**.
5. When you're done, delete the Codespace (the free plan includes ~60 hours/month).

---

## Configuration

| What | Where |
|---|---|
| Site title, colours, search fields | [`config.yaml`](config.yaml) ([SkoHub config docs](https://skohub.io)) |
| Licence added to the published scheme | `DEFAULT_LICENSE` in [`scripts/prepare_vocab.py`](scripts/prepare_vocab.py) |
| Path prefix of the site | `BASEURL` environment variable of `scripts/build_site.sh` (empty locally, `/climate-connectivity-taxonomy` on GitHub Pages) |
| Completeness checks for a hub fetch | `MIN_CONCEPTS`, `FAIL_RATE`, `ABORT_AFTER` in [`scripts/fetch_vocab.py`](scripts/fetch_vocab.py) |

---

## Usage

### Reuse the vocabulary

`concepts.ttl` is plain SKOS in Turtle, so any RDF tool can read it:

```python
from rdflib import Graph
g = Graph().parse("concepts.ttl")
print(len(g), "triples")
```

Each concept also has a human-readable page on the public site and a link back to the
Connectivity Hub.

### How the public site is kept up to date

Refreshing the **data** and deploying the **site** are separate steps, so a flaky hub can never
publish a truncated vocabulary:

1. [`refresh-vocab.yml`](.github/workflows/refresh-vocab.yml) runs every Monday, or by hand via
   *Actions → Run workflow*. `scripts/fetch_vocab.py` crawls the hub through
   `hasTopConcept`/`broader`/`narrower`/`related` until it has every concept, retrying failures.
   The workflow commits `concepts.ttl` **only if the fetch is complete**.
2. That commit triggers [`pages.yml`](.github/workflows/pages.yml), which runs
   `scripts/build_site.sh` on the committed `concepts.ttl` and deploys the result to GitHub Pages.
   It never contacts the hub. Run it by hand to rebuild the site without new data.

`build_site.sh` normalises the vocabulary for SkoHub (`prepare_vocab.py`: licence, symmetric
`broader`/`narrower`, same-language de-duplication), builds the site with the
`skohub/skohub-vocabs-docker` image plus small patches (`scripts/patch_*.sh`), then sorts and
re-indents the navigation tree (`sort_tree.py`, `fix_tree_indent.py`).

So `concepts.ttl` is always the last complete published vocabulary, and
`git log -- concepts.ttl` shows how the taxonomy changed over time.

To fetch the current vocabulary from the hub yourself:

```bash
python3 scripts/fetch_vocab.py concepts.ttl
```

---

## Contributing

The source of truth for the taxonomy is the **weADAPT Connectivity Hub**: add or change concepts
there, and the weekly refresh brings them into this repository. Small fixes directly in
`concepts.ttl` are possible, but the next refresh from the hub overwrites them.

For the site and tooling, open an issue or a pull request. Please build the site locally
(`bash scripts/build_site.sh`) before submitting changes to `scripts/` or `config.yaml`.

---

## License

- **Taxonomy** (`concepts.ttl` and the content of the published website): © SEI Oxford,
  licensed under [Creative Commons Attribution 4.0 International (CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/),
  as agreed with the weADAPT Connectivity Hub team.
- **Code** (`scripts/`, `.github/`, `.devcontainer/`, `generate_ttl_from_url.sh`):
  [MIT](LICENSE), © The Climate Connectivity Taxonomy contributors.

---

## Acknowledgements

This work has been funded by the European Union's Horizon Europe Framework Programme under Grant
Agreement No. 101188256 ([FAIR2Adapt](https://github.com/FAIR2Adapt)).

The site is built with [SkoHub Vocabs](https://github.com/skohub-io/skohub-vocabs) and previewed
with [Skosmos](https://github.com/NatLibFi/Skosmos).

---

## Citation

If you use the Climate Connectivity Taxonomy, please cite it as described in
[`CITATION.cff`](CITATION.cff) (GitHub's **Cite this repository** button), for example:

```bibtex
@misc{cc_taxonomy,
  title        = {Climate Connectivity Taxonomy},
  author       = {{SEI Oxford} and Fouilloux, Anne and Filiz, Elifsu},
  year         = {2026},
  publisher    = {GitHub},
  howpublished = {\url{https://github.com/FAIR2Adapt/climate-connectivity-taxonomy}},
  note         = {SKOS vocabulary. Browsable at \url{https://fair2adapt.github.io/climate-connectivity-taxonomy/}}
}
```
