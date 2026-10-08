#!/bin/sh
# Export the methodology Google Doc and publish it as part of the site:
#   OUTDIR/index.html        the methodology as a web page, styled like the site
#   OUTDIR/media/            its figures, at full resolution
#   OUTDIR/methodology.pdf   the same content as a PDF download
#
# WHY. The methodology is written in a Google Doc owned by the connectivity-hub
# team, which stays the source of truth (they keep editing it there). Linking the
# Google Doc directly makes the site depend on its sharing settings and ownership,
# and a Google Doc reads poorly on phones and isn't indexed with the site. So every
# site build (pages.yml) re-exports the doc — whether or not it changed — and the
# site links to its own copy at /methodology/.
#
# SOURCE FORMAT. The page is converted from the Word (.docx) export. Google's
# Markdown export downsamples the figures (~600 px) and drops some altogether (the
# cover screenshot); the .docx export keeps every figure at full resolution.
#
# CONSISTENCY. Google produces each format in a separate download, so an edit could
# land in between. We export Markdown -> DOCX -> PDF -> Markdown and only accept the
# export when both Markdown copies are identical (retrying a few times), so the page
# and the PDF always show the same content. (The Markdown is used only for this
# check: unlike the .docx, it has no embedded timestamps, so it is byte-stable.)
#
# SAFETY. Like fetch_vocab.py, this aborts non-zero rather than publish garbage: if
# Google returns an error, a login page or a suspiciously small file, the deploy
# fails and GitHub Pages keeps serving the previous site.
#
# Usage: sh scripts/export_methodology.sh OUTDIR      (needs curl, perl, pandoc)
set -eu

# --- The methodology Google Doc (must be viewable by anyone with the link). -------
doc_id='1uPh00X7Et_E4Wsp4tqeIurVzxPW4gsuEXY136ghXTzc'
# ----------------------------------------------------------------------------------
doc_url="https://docs.google.com/document/d/${doc_id}/view"
export_url="https://docs.google.com/document/d/${doc_id}/export?format="
# Sanity checks on the export: minimum sizes and a phrase the doc must contain.
min_md_bytes=20000
min_pdf_bytes=50000
must_contain='Climate Connectivity Taxonomy'
attempts=3

out=${1:?usage: export_methodology.sh OUTDIR}
mkdir -p "$out"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fetch() { # fetch FORMAT DEST
  curl -fsSL --retry 3 --retry-delay 5 -o "$2" "${export_url}$1"
}

ok=''
i=1
while [ "$i" -le "$attempts" ]; do
  if fetch md "$tmp/a.md" && fetch docx "$tmp/doc.docx" && fetch pdf "$tmp/doc.pdf" \
     && fetch md "$tmp/b.md"; then
    if cmp -s "$tmp/a.md" "$tmp/b.md"; then ok=1; break; fi
    echo "Methodology doc changed during export (attempt $i/$attempts); retrying." >&2
  else
    echo "Methodology export failed (attempt $i/$attempts); retrying." >&2
  fi
  i=$((i + 1))
  sleep 10
done
if [ -z "$ok" ]; then
  echo "EXPORT ERROR: no consistent export of the methodology doc after $attempts attempts." >&2
  exit 1
fi

md_bytes=$(wc -c < "$tmp/a.md")
pdf_bytes=$(wc -c < "$tmp/doc.pdf")
if [ "$md_bytes" -lt "$min_md_bytes" ] || ! grep -qF "$must_contain" "$tmp/a.md"; then
  echo "EXPORT ERROR: Markdown export looks wrong (${md_bytes} bytes, or missing '$must_contain')." >&2
  echo "Is the Google Doc still shared as 'anyone with the link can view'?" >&2
  exit 1
fi
if [ "$pdf_bytes" -lt "$min_pdf_bytes" ] || [ "$(head -c 4 "$tmp/doc.pdf")" != "%PDF" ]; then
  echo "EXPORT ERROR: PDF export looks wrong (${pdf_bytes} bytes or not a PDF)." >&2
  exit 1
fi

# DOCX -> HTML fragment, figures extracted to OUTDIR/media/ (pandoc names them
# media/imageN.*, relative to the working directory, so run it from OUTDIR).
rm -rf "$out/media"
(cd "$out" && pandoc -f docx -t html5 --wrap=none --extract-media=. "$tmp/doc.docx" -o "$tmp/body.html")
if ! grep -q '<img' "$tmp/body.html"; then
  echo "EXPORT ERROR: no figures found in the converted page." >&2
  exit 1
fi
# - drop the fixed sizes pandoc copies from Word (in inches), so CSS can scale
#   figures to the column, and link each figure to its full-size file;
# - let wide tables scroll inside their own box instead of widening the page.
perl -pi -e 's|<img src="([^"]*)"[^>]*/>|<a class="figure" href="$1"><img src="$1" alt="" loading="lazy"></a>|g;
             s/<table/<div class="table-wrap"><table/g; s|</table>|</table></div>|g' "$tmp/body.html"

exported=$(date -u '+%Y-%m-%d %H:%M UTC')
cp "$tmp/doc.pdf" "$out/methodology.pdf"

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

echo "EXPORT OK: methodology page, $(ls "$out/media" | wc -l) figure(s) and PDF written to $out (pdf ${pdf_bytes} B, exported ${exported})."
