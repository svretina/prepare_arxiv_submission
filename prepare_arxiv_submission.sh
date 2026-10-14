#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 [SOURCE_DIR] [MAIN_TEX]" >&2
  echo "   or: $0 [MAIN_TEX]" >&2
}

discover_main_tex() {
  local dir="$1"
  local candidate
  local provided_tex

  for candidate in article.tex paper.tex main.tex; do
    if [[ -f "$dir/$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  read -r -p "No article.tex, paper.tex, or main.tex found. Enter the main TeX filename: " provided_tex || {
    echo "Error: no main TeX filename provided." >&2
    return 1
  }

  if [[ -z "$provided_tex" ]]; then
    echo "Error: main TeX filename cannot be blank." >&2
    return 1
  fi

  if [[ "$provided_tex" != *.tex ]]; then
    provided_tex+=".tex"
  fi

  printf '%s\n' "$provided_tex"
}

ensure_tex_extension() {
  local tex_name="$1"

  if [[ "$tex_name" != *.tex ]]; then
    tex_name+=".tex"
  fi

  printf '%s\n' "$tex_name"
}

find_bib_files() {
  local dir="$1"
  local main_tex="$2"

  perl - "$dir" "$dir/$main_tex" <<'PERL'
use strict;
use warnings;

my ($source_dir, $tex_file) = @ARGV;
open my $tex_fh, '<', $tex_file or die "Error: cannot read $tex_file: $!\n";
local $/;
my $tex = <$tex_fh>;
close $tex_fh or die "Error: cannot close $tex_file: $!\n";

# Ignore commented-out bibliography declarations, just as LaTeX does.
$tex =~ s/^[ \t]*%[^\n]*\n//mg;
$tex =~ s/(?<!\\)%[^\n]*//g;

my (%seen, @bib_files, @missing, @unsafe);
while ($tex =~ m!\\(bibliography|addbibresource|addglobalbib|addsectionbib)
                  (?:\s*\[[^\]]*\])?\s*\{([^}]*)\}!gx) {
  my ($command, $arguments) = ($1, $2);

  # \bibliography accepts a comma-separated list.  Splitting the other
  # commands too is harmless and supports generated TeX that groups entries.
  for my $reference (split /,/, $arguments) {
    $reference =~ s/^\s+|\s+$//g;
    next unless length $reference;
    $reference .= '.bib' unless $reference =~ /\.bib\z/i;

    if ($reference =~ m!\A/|(?:\A|/)\.\.(?:/|\z)!) {
      push @unsafe, $reference;
      next;
    }

    if (!-f "$source_dir/$reference") {
      push @missing, $reference;
      next;
    }

    next if $seen{$reference}++;
    push @bib_files, $reference;
  }
}

if (@missing || @unsafe) {
  print STDERR "Error: bibliography file(s) referenced by $tex_file could not be used:\n";
  print STDERR "  - $_\n" for @missing;
  print STDERR "  - $_ (path outside the source directory)\n" for @unsafe;
  exit 2;
}

exit 1 unless @bib_files;
print "$_\n" for @bib_files;
PERL
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

preprocess_main_tex() {
  local tex_file="$1"

  perl -0pi -e '
    s/^[ \t]*%[^\n]*\n//mg;
    s/(?<!\\)%[^\n]*//g;

    1 while s{
      \\iffalse\b
      (?:
        (?!\\iffalse\b|\\fi\b).
        | (?0)
      )*
      \\fi\b
    }{}gsx;
  ' "$tex_file"
}

rename_figures_in_order() {
  local submission_dir="$1"
  local tex_file="$2"

  perl - "$submission_dir" "$tex_file" <<'PERL'
use strict;
use warnings;
use File::Basename qw(basename);

my ($submission_dir, $tex_file) = @ARGV;
open my $tex_fh, '<', $tex_file or die "Error: cannot read $tex_file: $!\n";
local $/;
my $tex = <$tex_fh>;
close $tex_fh or die "Error: cannot close $tex_file: $!\n";

opendir my $dir_fh, $submission_dir
  or die "Error: cannot read submission directory $submission_dir: $!\n";
my @files = grep {
  -f "$submission_dir/$_"
    && /\.(?:pdf|png|jpe?g|eps|ps|svg)\z/i
} readdir $dir_fh;
closedir $dir_fh;

my (%exact_file, %stem_files);
for my $file (@files) {
  $exact_file{$file} = $file;
  (my $stem = $file) =~ s/\.[^.]+\z//;
  push @{ $stem_files{$stem} }, $file;
}

sub resolve_reference {
  my ($reference) = @_;
  $reference =~ s{^\./}{};
  $reference = basename($reference);

  return $exact_file{$reference} if exists $exact_file{$reference};
  return undef if $reference =~ /\.[^.]+\z/;

  my $matches = $stem_files{$reference} // [];
  die "Error: ambiguous figure reference '$reference' in $tex_file; specify its extension.\n"
    if @$matches > 1;
  return $matches->[0];
}

sub letter_for {
  my ($number) = @_;
  my $letters = '';
  do {
    $number--;
    $letters = chr(ord('a') + $number % 26) . $letters;
    $number = int($number / 26);
  } while ($number > 0);
  return $letters;
}

my (%renamed, %target_owner, %subfigure_count, %direct_count);
my ($figure_number, $figure_depth, $subfigure_depth, $current_figure, $pending_subfigure) = (0, 0, 0, undef, 0);

while ($tex =~ m!
  \\begin\s*\{\s*(?:figure\*?|subfigure\*?)\s*\}
  | \\end\s*\{\s*(?:figure\*?|subfigure\*?)\s*\}
  | \\sub(?:float|figure)\b
  | \\includegraphics(?:\s*\[[^\]]*\])?\s*\{[^}]*\}
!gx) {
  my $token = $&;

  if ($token =~ /^\\begin\s*\{\s*(figure\*?)\s*\}/) {
    if ($figure_depth++ == 0) {
      $current_figure = ++$figure_number;
    }
    next;
  }

  if ($token =~ /^\\end\s*\{\s*(figure\*?)\s*\}/) {
    if (--$figure_depth <= 0) {
      $figure_depth = 0;
      $subfigure_depth = 0;
      $current_figure = undef;
      $pending_subfigure = 0;
    }
    next;
  }

  if ($token =~ /^\\begin\s*\{\s*subfigure\*?\s*\}/) {
    $subfigure_depth++ if $figure_depth;
    next;
  }

  if ($token =~ /^\\end\s*\{\s*subfigure\*?\s*\}/) {
    $subfigure_depth-- if $subfigure_depth;
    next;
  }

  if ($token =~ /^\\sub(?:float|figure)\b/) {
    $pending_subfigure = 1 if $figure_depth;
    next;
  }

  my ($reference) = $token =~ /\{([^}]*)\}\z/;
  my $source_file = resolve_reference($reference);
  next unless defined $source_file;
  next if exists $renamed{$source_file};

  my $number = $figure_depth ? $current_figure : ++$figure_number;
  my $suffix = '';
  if ($subfigure_depth || $pending_subfigure) {
    $suffix = letter_for(++$subfigure_count{$number});
  } elsif (++$direct_count{$number} > 1) {
    # Multiple graphics in one figure need distinct filenames even when the
    # source does not wrap them in subfigure environments.
    $suffix = letter_for(++$subfigure_count{$number});
  }
  $pending_subfigure = 0;

  my ($extension) = $source_file =~ /(\.[^.]+)\z/;
  my $target_file = "fig${number}${suffix}${extension}";
  die "Error: two figures would be renamed to $target_file.\n"
    if exists $target_owner{$target_file} && $target_owner{$target_file} ne $source_file;

  $renamed{$source_file} = $target_file;
  $target_owner{$target_file} = $source_file;
}

exit 0 unless %renamed;

for my $target_file (keys %target_owner) {
  my $source_file = $target_owner{$target_file};
  next if $source_file eq $target_file;
  next unless -e "$submission_dir/$target_file";
  die "Error: cannot rename figures because $target_file already exists in the submission root.\n"
    unless exists $renamed{$target_file};
}

my %temporary;
my $index = 0;
for my $source_file (sort keys %renamed) {
  my $target_file = $renamed{$source_file};
  next if $source_file eq $target_file;
  my $temporary = ".arxiv-figure-rename-$$-" . ++$index;
  die "Error: temporary filename collision for $temporary.\n"
    if -e "$submission_dir/$temporary";
  rename "$submission_dir/$source_file", "$submission_dir/$temporary"
    or die "Error: cannot rename $source_file temporarily: $!\n";
  $temporary{$source_file} = $temporary;
}

for my $source_file (sort keys %renamed) {
  my $target_file = $renamed{$source_file};
  next if $source_file eq $target_file;
  rename "$submission_dir/$temporary{$source_file}", "$submission_dir/$target_file"
    or die "Error: cannot rename $source_file to $target_file: $!\n";
}

$tex =~ s!
  (\\includegraphics(?:\s*\[[^\]]*\])?\s*\{)
  ([^}]*)
  (\})
!{
  my ($start, $reference, $end) = ($1, $2, $3);
  my $source_file = resolve_reference($reference);
  $start . (defined $source_file && exists $renamed{$source_file} ? $renamed{$source_file} : $reference) . $end;
}!gex;

open my $out_fh, '>', $tex_file or die "Error: cannot write $tex_file: $!\n";
print {$out_fh} $tex;
close $out_fh or die "Error: cannot close $tex_file: $!\n";

for my $source_file (sort keys %renamed) {
  print "  $source_file -> $renamed{$source_file}\n";
}
PERL
}

prune_unused_figures() {
  local submission_dir="$1"
  local tex_file="$2"
  local figure
  local stem
  local ext
  local ref
  local used=false
  local -a used_refs=()

  mapfile -t used_refs < <(
    perl -ne '
      while (/\\includegraphics(?:\s*\[[^\]]*\])?\s*\{([^}]+)\}/g) {
        print "$1\n";
      }
    ' "$tex_file" | sort -u
  )

  while IFS= read -r -d '' figure; do
    stem="$(basename "$figure")"
    ext="${stem##*.}"
    stem="${stem%.*}"
    used=false

    for ref in "${used_refs[@]}"; do
      ref="${ref#./}"
      if [[ "$ref" == "$stem" || "$ref" == "$stem.$ext" ]]; then
        used=true
        break
      fi
    done

    if [[ "$used" == false ]]; then
      rm -f "$figure"
    fi
  done < <(
    find "$submission_dir" -maxdepth 1 -type f \( \
      -iname '*.pdf' -o \
      -iname '*.png' -o \
      -iname '*.jpg' -o \
      -iname '*.jpeg' -o \
      -iname '*.eps' -o \
      -iname '*.ps' -o \
      -iname '*.svg' \
    \) ! -name "${MAIN_TEX%.tex}.pdf" -print0
  )
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

OUTPUT_DIR="$(pwd)"

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "Error: source directory does not exist: $SOURCE_DIR" >&2
  exit 1
fi

SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd)"

if [[ -z "${MAIN_TEX:-}" ]]; then
  MAIN_TEX="$(discover_main_tex "$SOURCE_DIR")"
else
  MAIN_TEX="$(ensure_tex_extension "$MAIN_TEX")"
fi

if [[ "$MAIN_TEX" == */* ]]; then
  if [[ "$MAIN_TEX" == /* ]]; then
    SOURCE_DIR="${MAIN_TEX%/*}"
  else
    SOURCE_DIR="$SOURCE_DIR/${MAIN_TEX%/*}"
  fi
  MAIN_TEX="${MAIN_TEX##*/}"

  if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "Error: source directory does not exist: $SOURCE_DIR" >&2
    exit 1
  fi
  SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd)"
fi

if [[ ! -f "$SOURCE_DIR/$MAIN_TEX" ]]; then
  echo "Error: main TeX file not found: $SOURCE_DIR/$MAIN_TEX" >&2
  usage
  exit 1
fi

declare -a BIB_FILES=()
if bib_output="$(find_bib_files "$SOURCE_DIR" "$MAIN_TEX")"; then
  mapfile -t BIB_FILES <<< "$bib_output"
else
  bib_status=$?
  if [[ "$bib_status" -eq 2 ]]; then
    exit 1
  fi
  echo "Warning: no bibliography file is referenced by $MAIN_TEX" >&2
fi

SUBMISSION_DIR="$OUTPUT_DIR/arxiv_submission"
TAR_PATH="$SUBMISSION_DIR/ax.tar"

require_command perl
require_command find
require_command tar

echo "Preparing arXiv submission from:"
echo "  source: $SOURCE_DIR"
echo "  main:   $MAIN_TEX"
echo "  output: $SUBMISSION_DIR"
if [[ "${#BIB_FILES[@]}" -gt 0 ]]; then
  echo "  bib:"
  for bib_file in "${BIB_FILES[@]}"; do
    echo "    $bib_file"
  done
else
  echo "  bib:    none referenced"
fi
echo

rm -rf "$SUBMISSION_DIR"
mkdir -p "$SUBMISSION_DIR"

echo "1. Copying main TeX file ..."
cp -a "$SOURCE_DIR/$MAIN_TEX" "$SUBMISSION_DIR/"

if [[ "${#BIB_FILES[@]}" -gt 0 ]]; then
  echo "2. Copying referenced bibliography file(s) ..."
  for bib_file in "${BIB_FILES[@]}"; do
    mkdir -p "$SUBMISSION_DIR/$(dirname "$bib_file")"
    cp -a "$SOURCE_DIR/$bib_file" "$SUBMISSION_DIR/$bib_file"
  done
else
  echo "2. Skipping bibliography copy ..."
fi

echo "3. Copying figures/plots directories if present ..."
copy_asset_dir "$SOURCE_DIR" "$SUBMISSION_DIR"

echo "4. Flattening copied figures/plots into submission root ..."
flatten_asset_dir_to_root "$SUBMISSION_DIR" figures
flatten_asset_dir_to_root "$SUBMISSION_DIR" plots
rewrite_flattened_asset_paths "$SUBMISSION_DIR/$MAIN_TEX"

echo "5. Removing comments, stripping \iffalse blocks, and adding arXiv multi-pass trigger ..."
preprocess_main_tex "$SUBMISSION_DIR/$MAIN_TEX"
if ! grep -Fq 'get arXiv to do 4 passes' "$SUBMISSION_DIR/$MAIN_TEX"; then
  printf '\n\\typeout{get arXiv to do 4 passes: Label(s) may have changed. Rerun}\n' >> "$SUBMISSION_DIR/$MAIN_TEX"
fi

echo "6. Removing unused flattened figure files ..."
prune_unused_figures "$SUBMISSION_DIR" "$SUBMISSION_DIR/$MAIN_TEX"

echo "7. Renaming copied figures in document order ..."
rename_figures_in_order "$SUBMISSION_DIR" "$SUBMISSION_DIR/$MAIN_TEX"

echo "8. Compiling submission copy ..."
(
  cd "$SUBMISSION_DIR"

  if command_exists latexmk; then
    latexmk -pdf -interaction=nonstopmode -halt-on-error "$MAIN_TEX"
  else
    require_command pdflatex
    pdflatex -interaction=nonstopmode -halt-on-error "$MAIN_TEX"

    jobname="${MAIN_TEX%.tex}"
    if [[ "${#BIB_FILES[@]}" -gt 0 && -f "$jobname.aux" ]] && grep -q '\\bibdata{' "$jobname.aux"; then
      require_command bibtex
      bibtex "$jobname"
    fi

    pdflatex -interaction=nonstopmode -halt-on-error "$MAIN_TEX"
    pdflatex -interaction=nonstopmode -halt-on-error "$MAIN_TEX"
    pdflatex -interaction=nonstopmode -halt-on-error "$MAIN_TEX"
  fi
)

jobname="${MAIN_TEX%.tex}"
if [[ "${#BIB_FILES[@]}" -gt 0 ]]; then
  if [[ ! -f "$SUBMISSION_DIR/$jobname.bbl" ]]; then
    echo "Warning: no .bbl file was generated." >&2
  fi
fi

echo "9. Cleaning generated files, keeping .bbl ..."
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

find "$SUBMISSION_DIR" -type f -name '*.bib' -delete
find "$SUBMISSION_DIR" -depth -type d -empty -delete

echo "10. Final submission contents:"
find "$SUBMISSION_DIR" -mindepth 1 | sed "s#^$OUTPUT_DIR/##" | sort

echo
echo "11. Creating tarball: $TAR_PATH"
(
  cd "$SUBMISSION_DIR"
  rm -f "$(basename "$TAR_PATH")"
  tar -cvvf "$TAR_PATH" --exclude="$(basename "$TAR_PATH")" * >/dev/null
)

echo
echo "Done."
echo "Prepared submission directory:"
echo "  $SUBMISSION_DIR"
echo "Tarball to upload:"
echo "  $TAR_PATH"
