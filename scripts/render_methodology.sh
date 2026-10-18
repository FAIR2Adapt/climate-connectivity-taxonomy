#!/bin/sh
# Render the committed methodology snapshot as a page of the site:
#   OUTDIR/index.html        the methodology as a web page, styled like the site
#   OUTDIR/media/            its figures, at full resolution
#   OUTDIR/methodology.pdf   the same content as a PDF download
#
# The snapshot in SRC (methodology.docx/.pdf/exported_at) is taken from the
# connectivity-hub team's Google Doc by scripts/fetch_methodology.sh in the refresh
# workflow; this script never contacts Google, so the build is offline.
#
# SOURCE FORMAT. The page is converted from the Word (.docx) export. Google's
# Markdown export downsamples the figures (~600 px) and drops some altogether (the
# cover screenshot); the .docx export keeps every figure at full resolution.
#
# Usage: sh scripts/render_methodology.sh SRC OUTDIR      (needs pandoc, perl)
set -eu

# --- The methodology Google Doc, linked from the page as the working document. ---
doc_id='1uPh00X7Et_E4Wsp4tqeIurVzxPW4gsuEXY136ghXTzc'
# ----------------------------------------------------------------------------------
doc_url="https://docs.google.com/document/d/${doc_id}/view"

src=${1:?usage: render_methodology.sh SRC OUTDIR}
out=${2:?usage: render_methodology.sh SRC OUTDIR}
for f in methodology.docx methodology.pdf exported_at; do
  if [ ! -f "$src/$f" ]; then
    echo "RENDER ERROR: $src/$f missing (run scripts/fetch_methodology.sh $src)." >&2
    exit 1
  fi
done
src=$(cd "$src" && pwd)
mkdir -p "$out"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# DOCX -> HTML fragment, figures extracted to OUTDIR/media/ (pandoc names them
# media/imageN.*, relative to the working directory, so run it from OUTDIR).
rm -rf "$out/media"
(cd "$out" && pandoc -f docx -t html5 --wrap=none --extract-media=. "$src/methodology.docx" -o "$tmp/body.html")
if ! grep -q '<img' "$tmp/body.html"; then
  echo "RENDER ERROR: no figures found in the converted page." >&2
  exit 1
fi
# - drop the fixed sizes pandoc copies from Word (in inches), so CSS can scale
#   figures to the column, and link each figure to its full-size file;
# - let wide tables scroll inside their own box instead of widening the page.
perl -pi -e 's|<img src="([^"]*)"[^>]*/>|<a class="figure" href="$1"><img src="$1" alt="" loading="lazy"></a>|g;
             s/<table/<div class="table-wrap"><table/g; s|</table>|</table></div>|g' "$tmp/body.html"

exported=$(cat "$src/exported_at")
cp "$src/methodology.pdf" "$out/methodology.pdf"

# The page lives at <site>/methodology/, so site assets are one level up. Colours
# and font follow the SkoHub theme in config.yaml.
{
cat <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Methodology · Climate Connectivity Taxonomy</title>
<link rel="icon" href="../favicon-32x32.png" type="image/png">
<style>
/* One reading column under a site-style header; colours from config.yaml. */
:root {
  --dark: rgb(15, 85, 75);
  --middle: rgb(20, 150, 140);
  --action: rgb(230, 0, 125);
  --light-grey: rgb(235, 235, 235);
  --rule: rgb(200, 200, 200);
  --bg: rgb(255, 255, 255);
  --note-bg: rgb(240, 248, 246);
  --text: rgb(5, 30, 30);
  --font: Ubuntu, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
  color-scheme: light;
}
@font-face { font-family: Ubuntu; font-style: normal; font-weight: 400;
  src: url(../fonts/ubuntu-v20-latin-regular.woff2) format("woff2"); }
@font-face { font-family: Ubuntu; font-style: normal; font-weight: 700;
  src: url(../fonts/ubuntu-v20-latin-700.woff2) format("woff2"); }
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--text); font-family: var(--font);
  font-size: 16px; line-height: 1.6; -webkit-font-smoothing: antialiased; }
a { color: var(--dark); text-decoration: underline; text-underline-offset: 2px; }
a:hover { color: var(--action); }
a:focus-visible { outline: 2px solid var(--action); outline-offset: 2px; }
.site-header { border-bottom: 1px solid var(--light-grey); padding: 20px 16px; }
.site-header a { color: var(--dark); font-size: 24px; font-weight: 700; text-decoration: none; }
main { max-width: 46rem; margin: 0 auto; padding: 32px 16px 48px; }
.notice { background: var(--note-bg); border: 1px solid var(--rule); border-radius: 6px;
  padding: 14px 16px; margin-bottom: 32px; font-size: 14px; line-height: 1.5; }
.notice p { margin: 0; }
.notice .links { display: flex; flex-wrap: wrap; gap: 6px 18px; margin-top: 8px; font-weight: 700; }
.doc h1, .doc h2, .doc h3, .doc h4, .doc h5 { color: var(--dark); line-height: 1.25;
  text-wrap: balance; margin: 2em 0 0.6em; }
.doc h3 { font-size: 1.5rem; }
.doc h4 { font-size: 1.25rem; }
.doc h5 { font-size: 1.05rem; }
/* The doc's title is its first two paragraphs. */
.doc > p:nth-child(-n+2) { font-size: 1.6rem; font-weight: 700; line-height: 1.25; color: var(--dark); margin: 0 0 0.3em; }
.doc > p:nth-child(-n+2) u { text-decoration: none; }
.doc img { display: block; max-width: 100%; height: auto; margin: 1em auto; border: 1px solid var(--light-grey); }
.doc a.figure { display: block; }
.figure-hint { font-size: 14px; }
.table-wrap { overflow-x: auto; margin: 1.2em 0; }
.doc table { border-collapse: collapse; font-size: 14px; line-height: 1.45; min-width: 36rem; }
.doc th, .doc td { border-top: 1px solid var(--rule); padding: 8px 10px; vertical-align: top; text-align: left; }
.doc th { background: var(--light-grey); }
.doc .footnotes { font-size: 14px; border-top: 1px solid var(--rule); margin-top: 3em; }
.doc .footnotes hr { display: none; }
.site-footer { border-top: 1px solid var(--light-grey); padding: 16px; font-size: 14px; }
.site-footer nav { display: flex; flex-wrap: wrap; gap: 6px 18px; justify-content: center; }
</style>
</head>
<body>
<header class="site-header"><a href="../connectivity-hub.com/terms/index.html">Climate Connectivity Taxonomy</a></header>
<main>
<div class="notice">
EOF
printf '  <p>The methodology is maintained as a working document by the Climate Connectivity Hub team. This page is a copy, last updated from it on %s.</p>\n' "$exported"
printf '  <p class="figure-hint">Select a figure to open it at full size.</p>
  <div class="links"><a href="methodology.pdf">Download PDF</a><a href="%s" target="_blank" rel="noopener noreferrer">Working document (Google Doc)</a></div>\n' "$doc_url"
cat <<'EOF'
</div>
<article class="doc">
EOF
cat "$tmp/body.html"
cat <<'EOF'
</article>
</main>
<footer class="site-footer"><nav>
  <a href="../connectivity-hub.com/terms/index.html">Taxonomy</a>
  <a href="https://creativecommons.org/licenses/by/4.0/" target="_blank" rel="noopener noreferrer">Licence: CC BY 4.0</a>
  <a href="https://connectivity-hub.weadapt.org/" target="_blank" rel="noopener noreferrer">Connectivity Hub</a>
  <a href="https://github.com/FAIR2Adapt/climate-connectivity-taxonomy" target="_blank" rel="noopener noreferrer">Source on GitHub</a>
</nav></footer>
</body>
</html>
EOF
} > "$out/index.html"

echo "Methodology page, $(ls "$out/media" | wc -l) figure(s) and PDF written to $out (exported ${exported})."
