#!/usr/bin/env bash
set -euo pipefail

# prepare_arxiv_submission.sh
#
# Prepare a LaTeX paper source tree for arXiv submission.
#
# Usage:
#   ./prepare_arxiv_submission.sh [SOURCE_DIR] [MAIN_TEX]
#
# Examples:
#   ./prepare_arxiv_submission.sh . main.tex
#   ./prepare_arxiv_submission.sh /path/to/paper paper.tex
#
# Output:
#   SOURCE_DIR/arxiv_submission/
#   SOURCE_DIR/ax.tar
#
# Notes:
#   - This script edits only the copied arxiv_submission/ directory.
#   - It flattens subdirectories into the submission root.
#   - It rewrites common LaTeX references so files are addressed from the root.
#   - It removes comments from .tex files.
#   - It compiles the document, keeps the generated .bbl, removes .bib and build files,
#     then creates ax.tar.

SOURCE_DIR="${1:-.}"
MAIN_TEX="${2:-main.tex}"

SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd)"
SUBMISSION_DIR="$SOURCE_DIR/arxiv_submission"
TAR_PATH="$SOURCE_DIR/ax.tar"

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "Error: source directory does not exist: $SOURCE_DIR" >&2
  exit 1
fi

if [[ ! -f "$SOURCE_DIR/$MAIN_TEX" ]]; then
  echo "Error: main TeX file not found: $SOURCE_DIR/$MAIN_TEX" >&2
  echo "Usage: $0 [SOURCE_DIR] [MAIN_TEX]" >&2
  exit 1
fi

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

require_command() {
  if ! command_exists "$1"; then
    echo "Error: required command not found: $1" >&2
    exit 1
  fi
}

require_command rsync
require_command perl
require_command find
require_command tar

echo "Preparing arXiv submission from:"
echo "  source: $SOURCE_DIR"
echo "  main:   $MAIN_TEX"
echo

rm -rf "$SUBMISSION_DIR"
rm -f "$TAR_PATH"
mkdir -p "$SUBMISSION_DIR"

echo "1. Copying source tree to arxiv_submission/ ..."
rsync -a \
  --exclude='arxiv_submission/' \
  --exclude='.git/' \
  --exclude='.svn/' \
  --exclude='.hg/' \
  --exclude='.DS_Store' \
  --exclude='__MACOSX/' \
  --exclude='ax.tar' \
  "$SOURCE_DIR/" "$SUBMISSION_DIR/"

cd "$SUBMISSION_DIR"

echo "2. Removing hidden files/directories and common private/editor artifacts ..."
find . -mindepth 1 -name '.*' -exec rm -rf {} + 2>/dev/null || true
find . -type f \( \
  -name '*~' -o \
  -name '*.bak' -o \
  -name '*.tmp' -o \
  -name '*.swp' -o \
  -name '*.swo' -o \
  -name '.#*' \
\) -delete

echo "3. Removing existing build artifacts and rendered PDFs ..."
find . -type f \( \
  -name '*.aux' -o \
  -name '*.log' -o \
  -name '*.out' -o \
  -name '*.toc' -o \
  -name '*.lof' -o \
  -name '*.lot' -o \
  -name '*.fls' -o \
  -name '*.fdb_latexmk' -o \
  -name '*.synctex.gz' -o \
  -name '*.blg' -o \
  -name '*.run.xml' -o \
  -name '*.bcf' -o \
  -name '*.nav' -o \
  -name '*.snm' -o \
  -name '*.vrb' -o \
  -name '*.pdf' \
\) -delete

# File types commonly needed for LaTeX/arXiv submissions.
# Everything else is considered non-source/non-asset and is removed before flattening.
echo "4. Removing files that are usually not needed for arXiv compilation ..."
find . -type f ! \( \
  -name '*.tex' -o \
  -name '*.sty' -o \
  -name '*.cls' -o \
  -name '*.bst' -o \
  -name '*.bib' -o \
  -name '*.bbl' -o \
  -name '*.bbx' -o \
  -name '*.cbx' -o \
  -name '*.cfg' -o \
  -name '*.def' -o \
  -name '*.clo' -o \
  -name '*.ldf' -o \
  -name '*.ist' -o \
  -name '*.eps' -o \
  -name '*.ps' -o \
  -name '*.pdf_tex' -o \
  -name '*.png' -o \
  -name '*.jpg' -o \
  -name '*.jpeg' -o \
  -name '*.pdf' -o \
  -name '*.svg' \
\) -delete

echo "5. Flattening subdirectories into arxiv_submission/ root ..."

# Detect duplicate basenames before flattening. arXiv wants a simple structure,
# but duplicate filenames cannot be flattened safely without semantic choices.
duplicates="$(
  find . -mindepth 2 -type f -printf '%f\n' | sort | uniq -d || true
)"

if [[ -n "$duplicates" ]]; then
  echo "Error: duplicate filenames found in subdirectories; cannot flatten safely." >&2
  echo "$duplicates" | sed 's/^/  - /' >&2
  echo >&2
  echo "Rename these files in the source tree or handle them manually, then rerun." >&2
  exit 1
fi

# Move every file from subdirectories to the root.
while IFS= read -r -d '' file; do
  base="$(basename "$file")"
  mv "$file" "./$base"
done < <(find . -mindepth 2 -type f -print0)

# Remove now-empty directories.
find . -mindepth 1 -type d -empty -delete

echo "6. Rewriting common LaTeX paths to flattened basenames ..."

# This covers common LaTeX commands whose arguments point to files.
# Examples:
#   \input{sections/intro}         -> \input{intro}
#   \includegraphics[...]{figs/a}  -> \includegraphics[...]{a}
#   \bibliography{bib/references}  -> \bibliography{references}
#
# It intentionally does not rewrite arbitrary text.
for f in *.tex *.sty *.cls 2>/dev/null; do
  [[ -f "$f" ]] || continue
  perl -0pi -e '
    s{\\(input|include|subfile|bibliography|addbibresource|includegraphics)(\s*(?:\[[^\]]*\]\s*)?\{)([^{}]*\/)([^{}\/]+)(\})}{\\$1$2$4$5}g;
    s{\\graphicspath\s*\{(?:\{[^{}]*\})+\}}{}g;
  ' "$f"
done

echo "7. Removing LaTeX comments from .tex files ..."

# Remove comments that start with an unescaped percent sign.
# This is a pragmatic LaTeX comment stripper. It preserves escaped \%.
# Caveat: as with most simple strippers, unusual verbatim/minted/comment-heavy
# constructs should be inspected manually afterwards.
for f in *.tex 2>/dev/null; do
  [[ -f "$f" ]] || continue
  perl -pi -e 's/(?<!\\)%.*$//' "$f"
done

echo "8. Adding arXiv multi-pass trigger after \\end{document}, if missing ..."
if ! grep -Fq 'get arXiv to do 4 passes' "$MAIN_TEX"; then
  printf '\n\\typeout{get arXiv to do 4 passes: Label(s) may have changed. Rerun}\n' >> "$MAIN_TEX"
fi

echo "9. Compiling to generate/check PDF and .bbl ..."

compile_with_latexmk=false
if command_exists latexmk; then
  compile_with_latexmk=true
fi

if "$compile_with_latexmk"; then
  latexmk -pdf -interaction=nonstopmode -halt-on-error "$MAIN_TEX"
else
  require_command pdflatex
  pdflatex -interaction=nonstopmode -halt-on-error "$MAIN_TEX"

  # Try common bibliography workflows.
  jobname="${MAIN_TEX%.tex}"
  if [[ -f "$jobname.aux" ]]; then
    if grep -q '\\bibdata{' "$jobname.aux" && command_exists bibtex; then
      bibtex "$jobname" || true
    fi
  fi

  pdflatex -interaction=nonstopmode -halt-on-error "$MAIN_TEX"
  pdflatex -interaction=nonstopmode -halt-on-error "$MAIN_TEX"
  pdflatex -interaction=nonstopmode -halt-on-error "$MAIN_TEX"
fi

jobname="${MAIN_TEX%.tex}"

if [[ ! -f "$jobname.bbl" ]]; then
  echo "Warning: no .bbl file was produced." >&2
  echo "If your paper uses BibTeX, inspect the compile log before submitting." >&2
fi

echo "10. Removing .bib and post-compile generated files, keeping .bbl ..."
find . -type f -name '*.bib' -delete

find . -type f \( \
  -name '*.aux' -o \
  -name '*.log' -o \
  -name '*.out' -o \
  -name '*.toc' -o \
  -name '*.lof' -o \
  -name '*.lot' -o \
  -name '*.fls' -o \
  -name '*.fdb_latexmk' -o \
  -name '*.synctex.gz' -o \
  -name '*.blg' -o \
  -name '*.run.xml' -o \
  -name '*.bcf' -o \
  -name '*.nav' -o \
  -name '*.snm' -o \
  -name '*.vrb' -o \
  -name '*.pdf' \
\) -delete

echo "11. Final public-file sanity listing:"
find . -maxdepth 1 -type f | sed 's#^\./##' | sort

echo
echo "12. Creating tarball: $TAR_PATH"
tar -cvvf "$TAR_PATH" ./* >/dev/null

echo
echo "Done."
echo "Prepared source directory:"
echo "  $SUBMISSION_DIR"
echo "Tarball to upload:"
echo "  $TAR_PATH"
echo
echo "Important: inspect arxiv_submission/ before uploading. Everything in ax.tar will be public."
