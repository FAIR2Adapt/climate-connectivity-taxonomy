#!/bin/sh
# Fetch the methodology Google Doc into the repo (run by refresh-vocab.yml):
#   DIR/methodology.md     Markdown export: the change test, and readable diffs
#   DIR/methodology.docx   Word export: the source of the web page (keeps figures)
#   DIR/methodology.pdf    PDF export: offered as a download on the page
#   DIR/exported_at        when this copy was taken from the doc (UTC)
#
# WHY. The methodology is written in a Google Doc owned by the connectivity-hub
# team, which stays the source of truth (they keep editing it there). Like
# concepts.ttl, it is snapshotted into the repo by the refresh workflow, and the
# site build (scripts/render_methodology.sh) only renders the committed copy — so
# a deploy never depends on Google, and `git log -- methodology/` is its history.
#
# CHANGE TEST. Google's .docx and .pdf exports embed timestamps, so they differ on
# every download. DIR is only rewritten when the Markdown export (byte-stable)
# differs from the committed one; otherwise nothing is touched and nothing is
# committed.
#
# CONSISTENCY. Google produces each format in a separate download, so an edit could
# land in between. We export Markdown -> DOCX -> PDF -> Markdown and only accept the
# export when both Markdown copies are identical (retrying a few times), so the page
# and the PDF always show the same content.
#
# SAFETY. Like fetch_vocab.py, this aborts non-zero rather than commit garbage: if
# Google returns an error, a login page or a suspiciously small file, DIR is left
# as it was.
#
# Usage: sh scripts/fetch_methodology.sh DIR      (needs curl)
set -eu
# --- The methodology Google Doc (must be viewable by anyone with the link). -------
doc_id='1uPh00X7Et_E4Wsp4tqeIurVzxPW4gsuEXY136ghXTzc'
# ----------------------------------------------------------------------------------
export_url="https://docs.google.com/document/d/${doc_id}/export?format="
# Sanity checks on the export: minimum sizes and a phrase the doc must contain.
min_md_bytes=20000
min_pdf_bytes=50000
must_contain='Climate Connectivity Taxonomy'
attempts=3

out=${1:?usage: fetch_methodology.sh DIR}
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
if [ "$(head -c 2 "$tmp/doc.docx")" != "PK" ]; then
  echo "EXPORT ERROR: Word export looks wrong (not a .docx)." >&2
  exit 1
fi

if [ -f "$out/methodology.md" ] && cmp -s "$tmp/a.md" "$out/methodology.md"; then
  echo "Methodology unchanged — nothing to update."
  exit 0
fi
cp "$tmp/a.md" "$out/methodology.md"
cp "$tmp/doc.docx" "$out/methodology.docx"
cp "$tmp/doc.pdf" "$out/methodology.pdf"
date -u '+%Y-%m-%d %H:%M UTC' > "$out/exported_at"
echo "Methodology updated in $out (md ${md_bytes} B, pdf ${pdf_bytes} B)."
