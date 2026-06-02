#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 [SOURCE_DIR] [MAIN_TEX]" >&2
  echo "   or: $0 [MAIN_TEX]" >&2
}

discover_main_tex() {
  local dir="$1"
  local candidate

  for candidate in article.tex paper.tex main.tex; do
    if [[ -f "$dir/$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  echo "Error: no main TeX file provided and none of article.tex, paper.tex, or main.tex were found in $dir" >&2
  return 1
}

find_bib_file() {
  local dir="$1"
  local main_tex="$2"
  local main_base="${main_tex%.tex}"
  local candidate
  local -a preferred=(
    "$main_base.bib"
    bibliography.bib
    references.bib
    refs.bib
    ref.bib
    bib.bib
  )

  for candidate in "${preferred[@]}"; do
    if [[ -f "$dir/$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  mapfile -t bib_files < <(find "$dir" -maxdepth 1 -type f -name '*.bib' -printf '%f\n' | sort)
  if [[ "${#bib_files[@]}" -eq 1 ]]; then
    printf '%s\n' "${bib_files[0]}"
    return 0
  fi

  return 1
}

copy_asset_dir() {
  local source_dir="$1"
  local submission_dir="$2"
  local candidate
  local copied=false

  for candidate in figures plots; do
    if [[ -d "$source_dir/$candidate" ]]; then
      cp -a "$source_dir/$candidate" "$submission_dir/"
      copied=true
    fi
  done

  if [[ "$copied" == false ]]; then
    echo "Warning: no figures/ or plots/ directory found in $source_dir" >&2
  fi
}

flatten_asset_dir_to_root() {
  local submission_dir="$1"
  local asset_dir_name="$2"
  local asset_dir="$submission_dir/$asset_dir_name"
  local duplicates=""
  local file
  local base

  [[ -d "$asset_dir" ]] || return 0

  duplicates="$(
    find "$asset_dir" -mindepth 2 -type f -printf '%f\n' | sort | uniq -d || true
  )"

  if [[ -n "$duplicates" ]]; then
    echo "Error: duplicate filenames found under $asset_dir; cannot flatten safely." >&2
    echo "$duplicates" | sed 's/^/  - /' >&2
    exit 1
  fi

  while IFS= read -r -d '' file; do
    base="$(basename "$file")"
    if [[ -e "$submission_dir/$base" && "$submission_dir/$base" != "$file" ]]; then
      echo "Error: flattening $asset_dir_name/ would overwrite existing file $base in submission root." >&2
      exit 1
    fi
    mv "$file" "$submission_dir/$base"
  done < <(find "$asset_dir" -mindepth 2 -type f -print0)

  while IFS= read -r -d '' file; do
    base="$(basename "$file")"
    if [[ -e "$submission_dir/$base" && "$submission_dir/$base" != "$file" ]]; then
      echo "Error: flattening $asset_dir_name/ would overwrite existing file $base in submission root." >&2
      exit 1
    fi
    mv "$file" "$submission_dir/$base"
  done < <(find "$asset_dir" -maxdepth 1 -type f -print0)

  rm -rf "$asset_dir"
}

rewrite_flattened_asset_paths() {
  local tex_file="$1"

  perl -0pi -e '
    s{(\\includegraphics(?:\s*\[[^\]]*\])?\s*\{)(figures|plots)/(?:[^{}\/]+/)*([^{}\/]+\})}{$1$3}g;
    s{\\graphicspath\s*\{(?:\{[^{}]*\})+\}}{}g;
  ' "$tex_file"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

require_command() {
  if ! command_exists "$1"; then
    echo "Error: required command not found: $1" >&2
    exit 1
  fi
}

case "$#" in
  0)
    SOURCE_DIR="$PWD"
    MAIN_TEX=""
    ;;
  1)
    if [[ -d "$1" ]]; then
      SOURCE_DIR="$1"
      MAIN_TEX=""
    else
      if [[ "$1" != *.tex ]]; then
        echo "Error: single argument must be an existing directory or a .tex file." >&2
        usage
        exit 1
      fi

      if [[ "$1" == */* ]]; then
        SOURCE_DIR="${1%/*}"
        MAIN_TEX="${1##*/}"
      else
        SOURCE_DIR="$PWD"
        MAIN_TEX="$1"
      fi
    fi
    ;;
  2)
    SOURCE_DIR="$1"
    MAIN_TEX="$2"
    ;;
  *)
    usage
    exit 1
    ;;
esac

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "Error: source directory does not exist: $SOURCE_DIR" >&2
  exit 1
fi

SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd)"

if [[ -z "${MAIN_TEX:-}" ]]; then
  MAIN_TEX="$(discover_main_tex "$SOURCE_DIR")"
fi

if [[ ! -f "$SOURCE_DIR/$MAIN_TEX" ]]; then
  echo "Error: main TeX file not found: $SOURCE_DIR/$MAIN_TEX" >&2
  usage
  exit 1
fi

BIB_FILE=""
if BIB_FILE="$(find_bib_file "$SOURCE_DIR" "$MAIN_TEX")"; then
  :
else
  echo "Warning: no suitable .bib file found next to $MAIN_TEX" >&2
fi

SUBMISSION_DIR="$SOURCE_DIR/arxiv_submission"
TAR_PATH="$SUBMISSION_DIR/ax.tar"

require_command perl
require_command find
require_command tar

echo "Preparing arXiv submission from:"
echo "  source: $SOURCE_DIR"
echo "  main:   $MAIN_TEX"
if [[ -n "$BIB_FILE" ]]; then
  echo "  bib:    $BIB_FILE"
else
  echo "  bib:    none found"
fi
echo

rm -rf "$SUBMISSION_DIR"
mkdir -p "$SUBMISSION_DIR"

echo "1. Copying main TeX file ..."
cp -a "$SOURCE_DIR/$MAIN_TEX" "$SUBMISSION_DIR/"

if [[ -n "$BIB_FILE" ]]; then
  echo "2. Copying BibTeX file ..."
  cp -a "$SOURCE_DIR/$BIB_FILE" "$SUBMISSION_DIR/"
else
  echo "2. Skipping BibTeX copy ..."
fi

echo "3. Copying figures/plots directories if present ..."
copy_asset_dir "$SOURCE_DIR" "$SUBMISSION_DIR"

echo "4. Flattening copied figures/plots into submission root ..."
flatten_asset_dir_to_root "$SUBMISSION_DIR" figures
flatten_asset_dir_to_root "$SUBMISSION_DIR" plots
rewrite_flattened_asset_paths "$SUBMISSION_DIR/$MAIN_TEX"

echo "5. Removing comments and adding arXiv multi-pass trigger ..."
perl -pi -e 's/(?<!\\)%.*$//' "$SUBMISSION_DIR/$MAIN_TEX"
if ! grep -Fq 'get arXiv to do 4 passes' "$SUBMISSION_DIR/$MAIN_TEX"; then
  printf '\n\\typeout{get arXiv to do 4 passes: Label(s) may have changed. Rerun}\n' >> "$SUBMISSION_DIR/$MAIN_TEX"
fi

echo "6. Compiling submission copy ..."
(
  cd "$SUBMISSION_DIR"

  if command_exists latexmk; then
    latexmk -pdf -interaction=nonstopmode -halt-on-error "$MAIN_TEX"
  else
    require_command pdflatex
    pdflatex -interaction=nonstopmode -halt-on-error "$MAIN_TEX"

    jobname="${MAIN_TEX%.tex}"
    if [[ -n "$BIB_FILE" && -f "$jobname.aux" ]] && grep -q '\\bibdata{' "$jobname.aux"; then
      require_command bibtex
      bibtex "$jobname"
    fi

    pdflatex -interaction=nonstopmode -halt-on-error "$MAIN_TEX"
    pdflatex -interaction=nonstopmode -halt-on-error "$MAIN_TEX"
    pdflatex -interaction=nonstopmode -halt-on-error "$MAIN_TEX"
  fi
)

jobname="${MAIN_TEX%.tex}"
if [[ -n "$BIB_FILE" ]]; then
  if [[ ! -f "$SUBMISSION_DIR/$jobname.bbl" ]]; then
    echo "Warning: no .bbl file was generated." >&2
  fi
fi

echo "7. Cleaning generated files, keeping .bbl ..."
find "$SUBMISSION_DIR" -maxdepth 1 -type f \( \
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
  -name '*.vrb' \
\) -delete

rm -f "$SUBMISSION_DIR/$jobname.pdf"

if [[ -n "$BIB_FILE" ]]; then
  rm -f "$SUBMISSION_DIR/$(basename "$BIB_FILE")"
fi

echo "8. Final submission contents:"
find "$SUBMISSION_DIR" -mindepth 1 | sed "s#^$SOURCE_DIR/##" | sort

echo
echo "9. Creating tarball: $TAR_PATH"
(
  cd "$SUBMISSION_DIR"
  rm -f "$(basename "$TAR_PATH")"
  tar -cvvf "$TAR_PATH" --exclude="$(basename "$TAR_PATH")" * >/dev/null
)

echo
echo "Done."
echo "Prepared source directory:"
echo "  $SUBMISSION_DIR"
echo "Tarball to upload:"
echo "  $TAR_PATH"
