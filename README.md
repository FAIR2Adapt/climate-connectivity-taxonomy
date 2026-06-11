# Climate Connectivity Taxonomy

## Browse the taxonomy online

The Climate Connectivity Taxonomy (CC Taxonomy) is published as a static,
browsable website on GitHub Pages:

**https://fair2adapt.github.io/climate-connectivity-taxonomy/**

The site is built automatically by [`.github/workflows/pages.yml`](.github/workflows/pages.yml):

1. `scripts/fetch_vocab.py` fetches the **complete** vocabulary from the
   connectivity-hub (top concepts *and* their children, by crawling the
   hierarchy — the plain export in `concepts.ttl` only contains top concepts).
2. `scripts/prepare_vocab.py` normalises it for [SkoHub Vocabs](https://github.com/skohub-io/skohub-vocabs):
   adds a licence, makes `broader`/`narrower` consistent so the hierarchy shows,
   and de-duplicates same-language labels. It is idempotent.
3. SkoHub builds the static site and it is deployed to GitHub Pages.

**To refresh the published site after the taxonomy changes in the hub:** just
re-run the workflow — *Actions → "Build and deploy Climate Connectivity
Taxonomy to GitHub Pages" → Run workflow*. It also refreshes automatically every Monday. The
pipeline always pulls the live vocabulary; you don't need to edit anything.

After each run the workflow commits the exact vocabulary it fetched back to
`concepts.ttl`, so the repo always holds a static, versioned snapshot of what was
published (and `git log -- concepts.ttl` shows how the taxonomy changed over time).

The licence applied to the published vocabulary is set once in
`scripts/prepare_vocab.py` (`DEFAULT_LICENSE`).

# Previewing Vocabulary in GitHub Codespaces

The Codespace/Skosmos setup below is the internal tool for previewing and
reviewing the vocabulary (it reads the `concepts.ttl` snapshot in this repo).

1. In the GitHub repo, go to **Code → Codespaces → Create codespace on main**. This starts a VS Code environment and brings up Skosmos in Docker for preview.

   ![Create codespace](images/create_codespace.png)

2. Wait a few minutes for containers to start. Once it is ready you can find the links to Skosmos in terminal.

   ![Open Skosmos](images/containers_ready.png)

3. Open the link in a browser, then click on **English** to view the taxonomy.
4. If you make changes to the vocabulary, press **F1** and run **Codespaces: Rebuild Container** to restart services with the new changes.
5. If the container doesn’t start, press **F1** and run **Codespaces: View creation log** to see startup logs.
6. When you’re done, delete the Codespace (free plan includes ~60 hours/month).
