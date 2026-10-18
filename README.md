# Climate Connectivity Taxonomy

**A SKOS vocabulary connecting dispersed climate change adaptation and disaster risk knowledge.**
The Climate Connectivity Taxonomy (CC Taxonomy, formerly "MAIA taxonomy") drives the data
connections in the [Climate Connectivity Hub](https://connectivity-hub.weadapt.org/). It is developed
by SEI Oxford through the PLACARD, MAIA, DIRECTED and FAIR2Adapt projects. It builds on the IPCC AR6
Glossary and the UNDRR-ISC Hazard Information Profiles, extended with expert-reviewed terms from
platforms such as weADAPT, Climate-ADAPT, CORDIS, PreventionWeb and the Resilience Platform.
The current version is **1.1** (27 August 2026), with ~1,400 concepts.

This repository mirrors the taxonomy from the hub as a versioned Turtle file and holds the tooling
that publishes it as a searchable website and previews it, so that the vocabulary is findable,
citable and reusable outside the hub. It is meant for researchers who need consistent terminology,
data managers and web developers integrating climate vocabularies, and tool developers.

- **Browse online:** <https://fair2adapt.github.io/climate-connectivity-taxonomy/>
- **Download:** [`concepts.ttl`](concepts.ttl) (SKOS, Turtle)
- **Paper:** Bharwani, Williamson & Wangrat (2026), [doi:10.1007/s10584-026-04139-y](https://doi.org/10.1007/s10584-026-04139-y)
- **Concept URIs:** `http://connectivity-hub.com/terms/<uuid>` in the scheme `http://connectivity-hub.com/terms/`
- **Methodology:** [development, methodology and next steps](https://fair2adapt.github.io/climate-connectivity-taxonomy/methodology/) (also as PDF)

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
- [pandoc](https://pandoc.org/installing.html), for the methodology page of the site (option A only)

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

This builds exactly what is published on GitHub Pages, from the committed `concepts.ttl` and
`methodology/`. Nothing is fetched from the hub or Google.

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

Refreshing the **data** and deploying the **site** are separate steps, so a flaky hub (or Google)
can never publish a truncated vocabulary or a broken page:

1. [`refresh-vocab.yml`](.github/workflows/refresh-vocab.yml) runs every Monday, or by hand via
   *Actions → Run workflow*. Two independent jobs:
   - `scripts/fetch_vocab.py` crawls the hub through `hasTopConcept`/`broader`/`narrower`/`related`
     until it has every concept, retrying failures. The job commits `concepts.ttl` **only if the
     fetch is complete**.
   - `scripts/fetch_methodology.sh` takes a copy of the methodology Google Doc (which the hub team
     keeps editing) into `methodology/`, and commits it **only if the content changed**.

   If either job committed, the workflow then starts the deploy.
2. [`pages.yml`](.github/workflows/pages.yml) runs `scripts/build_site.sh` on the committed files
   and deploys the result to GitHub Pages. It never contacts the hub or Google. Run it by hand to
   rebuild the site without new data. Pull requests run the build without deploying and attach the
   built site as a `site-preview` artifact.

`build_site.sh` normalises the vocabulary for SkoHub (`prepare_vocab.py`: licence, symmetric
`broader`/`narrower`, same-language de-duplication), builds the site with the
`skohub/skohub-vocabs-docker` image plus small patches (`scripts/patch_*.sh`), then sorts and
re-indents the navigation tree (`sort_tree.py`, `fix_tree_indent.py`), and renders the methodology
page from `methodology/` with pandoc (`render_methodology.sh`).

So `concepts.ttl` is always the last complete published vocabulary, and
`git log -- concepts.ttl` and `git log -- methodology/` show how the taxonomy and its methodology
changed over time. Don't edit `methodology/` by hand: edit the Google Doc.

To fetch the current vocabulary from the hub yourself:

```bash
python3 scripts/fetch_vocab.py concepts.ttl
```

---

## Contributing

**To the taxonomy.** The source of truth is the Climate Connectivity Hub, curated by SEI. Can't find a
term, or have a different definition or a perspective from your field? Contact
[sukaina.bharwani@sei.org](mailto:sukaina.bharwani@sei.org) to suggest a concept or give feedback;
it feeds into versions 1.x and 2. Please read the scope in the
[methodology](https://fair2adapt.github.io/climate-connectivity-taxonomy/methodology/)
first. Accepted changes reach this repository with the weekly refresh. Don't edit `concepts.ttl`
here for content changes: the next refresh from the hub overwrites them.

**To the website and tooling.** Open an issue or a pull request. Please build the site locally
(`bash scripts/build_site.sh`) before submitting changes to `scripts/` or `config.yaml`; pull
requests touching them are also build-tested by CI.

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
Agreement No. 101188256 ([FAIR2Adapt](https://github.com/FAIR2Adapt)). The taxonomy itself was
developed through the PLACARD, MAIA, DIRECTED and FAIR2Adapt projects.

The site is built with [SkoHub Vocabs](https://github.com/skohub-io/skohub-vocabs) and previewed
with [Skosmos](https://github.com/NatLibFi/Skosmos).

---

## Citation

To cite the taxonomy, please cite the paper describing it:

> Bharwani, S., Williamson, K., & Wangrat, A. (2026). Scaling knowledge interoperability for
> accelerated climate action through the Climate Connectivity Hub and Taxonomy. *Climatic Change*,
> 179, 48. https://doi.org/10.1007/s10584-026-04139-y

```bibtex
@article{bharwani2026,
  author  = {Bharwani, Sukaina and Williamson, Kate and Wangrat, Adam},
  title   = {Scaling knowledge interoperability for accelerated climate action through the
             Climate Connectivity Hub and Taxonomy},
  journal = {Climatic Change},
  volume  = {179},
  pages   = {48},
  year    = {2026},
  doi     = {10.1007/s10584-026-04139-y}
}
```

To cite this repository (the published vocabulary snapshot and its tooling), use
[`CITATION.cff`](CITATION.cff) (GitHub's **Cite this repository** button).
