# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Repo `FAIR2Adapt/climate-connectivity-taxonomy` holds the **Climate Connectivity Taxonomy**
(CC Taxonomy; formerly "MAIA taxonomy") — a SKOS vocabulary — plus the tooling to preview it with
[Skosmos](https://github.com/NatLibFi/Skosmos). It is part of the FAIR2Adapt workspace and is
related to `weADAPT-connectivity-hub/`: the taxonomy lives upstream at the connectivity-hub and is
mirrored here for browsing/editing. (The local working directory may still be named `maia`.)

The repo has **two independent data paths**, and it is important not to confuse them:

- **Public site** (`.github/workflows/pages.yml` → GitHub Pages at
  `https://fair2adapt.github.io/climate-connectivity-taxonomy/`). This does **not** use the
  committed `concepts.ttl`.
  It fetches the *complete* vocabulary live from the hub, normalises it, and builds a static
  [SkoHub Vocabs](https://github.com/skohub-io/skohub-vocabs) site. See "Public site pipeline".
- **Internal preview** (the `.devcontainer/` Codespace). This *does* use the committed
  `concepts.ttl` snapshot and serves it with Skosmos for editing/review.

## Public site pipeline (`scripts/` + `.github/workflows/pages.yml`)

The published site is built by, in order:

1. **`scripts/fetch_vocab.py OUTPUT.ttl`** — crawls the hub starting from the scheme and follows
   `hasTopConcept`/`broader`/`narrower`/`related` until it has fetched **every** concept (~1326),
   not just the top concepts. This is the fix for the missing hierarchy: the plain export only
   contains top concepts, so all child concepts (and the tree) are otherwise lost.
2. **`scripts/prepare_vocab.py IN.ttl OUT.ttl`** — idempotent normaliser for SkoHub:
   - adds `dct:license` to the scheme if absent (value = `DEFAULT_LICENSE`, currently CC BY 4.0 —
     SkoHub's build *requires* a licence on the scheme);
   - makes `broader`/`narrower` symmetric and sets `topConceptOf` so that a concept is a top
     concept **iff** it has no `broader` (otherwise every concept is a top concept and the tree is
     flat);
   - de-duplicates same-language values for single-valued-per-language predicates
     (`prefLabel`/`definition`/`example`/`dct:title`/`dct:description`) so SkoHub doesn't drop them.
3. SkoHub builds the site via the **`skohub/skohub-vocabs-docker:latest`** image (Node 18; the
   local `npm` build fails on Node ≥ 20 because of Gatsby's bundled `lmdb`/`msgpackr`). The image
   is `linux/amd64`-only — fine on GitHub runners; add `--platform linux/amd64` to run it on Apple
   Silicon. `BASEURL` (derived from the repo name, e.g. `/climate-connectivity-taxonomy`) sets the
   Pages path prefix. `config.yaml` holds the SkoHub config (UI title = "Climate Connectivity
   Taxonomy"); `prepare_vocab.py` also rewrites the scheme title if it still says "MAIA".

Refresh the site after the taxonomy changes: re-run the workflow (Actions → Run workflow) or wait
for the weekly cron. It always pulls the live vocabulary.

After fetching, the workflow **commits the fetched complete vocabulary back to `concepts.ttl`**
(`[skip ci]`, so it does not re-trigger — `concepts.ttl` is not in the trigger paths). So
`concepts.ttl` is a static, versioned record of exactly what was last published, and it also feeds
the **internal Skosmos preview** below (which therefore now gets the complete vocabulary). This
needs `permissions: contents: write` on the workflow; if branch protection blocks the bot push,
the snapshot commit step will fail (the site still deploys).

## The two moving parts

1. **`concepts.ttl`** — the entire vocabulary in one Turtle file (~2.7 MB). It is the
   `skos:ConceptScheme` `<http://connectivity-hub.com/terms/>` (hub title currently "MAIA taxonomy",
   rewritten to "Climate Connectivity Taxonomy" by `prepare_vocab.py`) followed
   by every `skos:Concept`. Concept URIs are `http://connectivity-hub.com/terms/<uuid>`. This is
   the file loaded into the triplestore for preview, so editing the vocabulary = editing this file
   (or regenerating it, see below).

2. **`generate_ttl_from_url.sh`** — rebuilds `concepts.ttl` from the live connectivity-hub.
   It fetches the scheme from `http://connectivity-hub.com/terms/`, extracts every UUID concept
   URI, fetches each as Turtle, and concatenates scheme + all concepts into `concepts.ttl`.
   Run it to re-sync from upstream:
   ```bash
   bash generate_ttl_from_url.sh
   ```
   Note: it **appends** to any existing `concepts.ttl` rather than truncating — delete the file
   first (`rm -f concepts.ttl`) for a clean regenerate. **It is also incomplete**: it only fetches
   the scheme's top concepts, so child concepts and the hierarchy are missing. For the complete
   vocabulary use `scripts/fetch_vocab.py` (used by the public-site pipeline).

## Preview pipeline (`.devcontainer/`)

Previewing is designed to run in a **GitHub Codespace** (Docker-in-Docker), not on a local
checkout. The flow, driven by `devcontainer.json`:

- **`postCreate.sh`** (postCreateCommand) does the real work:
  - clones Skosmos into `skosmos-src/` (gitignored / untracked),
  - edits `skosmos-src/dockerfiles/config/config-docker-compose.ttl`: deletes the bundled
    `:unesco` / `:stw` demo vocab blocks, appends a `:CCTaxonomy` `skosmos:Vocabulary` block pointing at
    the Fuseki SPARQL endpoint and graph `http://example.org/graph/dev`, and rewrites
    `skosmos:baseHref` to the Codespace's public `-9090` URL,
  - waits for the Docker daemon, brings up `docker compose -f skosmos-src/docker-compose.yml`
    (with retries), waits for the SPARQL endpoint, then `PUT`s `concepts.ttl` into the graph,
  - touches `/workspaces/.postcreate_done` as a readiness signal.
- **`postAttach.sh`** (postAttachCommand) reads that signal and prints the Skosmos URL, or tells
  you to check/rebuild if setup didn't finish.

Ports: Skosmos web UI is **9090** (the public Codespace URL), Fuseki SPARQL is reached on
**9030** locally (`/skosmos/sparql`, `/skosmos/data`), and the config references the in-compose
host `fuseki:3030`.

## Working notes

- After changing `concepts.ttl`, the data must be reloaded into Fuseki. In a Codespace, the
  documented way (README) is **F1 → Codespaces: Rebuild Container**, which re-runs `postCreate.sh`
  and re-PUTs the data. There is no incremental reload script.
- `skosmos-src/` is created at runtime and is not part of this repo — don't commit it. The
  `config-docker-compose.ttl` edits are made in place each run; `postCreate.sh` restores that
  file from git on a rebuild so the sed edits stay idempotent.
- Editing `concepts.ttl` by hand is valid for small fixes, but the source of truth is the
  connectivity-hub; prefer regenerating with `generate_ttl_from_url.sh` for bulk updates.
