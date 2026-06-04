# Prepare an arXiv submission

`prepare_arxiv_submission.sh` prepares a reduced arXiv upload tree from a LaTeX project, following the Trevor Campbell workflow [1] through the compile-and-package stage while starting from a restricted set of inputs.

[1] <https://trevorcampbell.me/html/arxiv.html>

## Usage

```sh
./prepare_arxiv_submission.sh
./prepare_arxiv_submission.sh [SOURCE_DIR]
./prepare_arxiv_submission.sh [MAIN_TEX]
./prepare_arxiv_submission.sh [SOURCE_DIR] [MAIN_TEX]
```

If no source directory is provided, the script uses the current working directory.

If no main `.tex` file is provided, the script looks for these files in order:

1. `article.tex`
2. `paper.tex`
3. `main.tex`

If none of those files exists, the script exits with an error.

If a single `.tex` argument is provided, the script uses that file as the main document and assumes the current directory, unless the argument includes a path.

## Examples

```sh
./prepare_arxiv_submission.sh
./prepare_arxiv_submission.sh paper.tex
./prepare_arxiv_submission.sh .
./prepare_arxiv_submission.sh . main.tex
./prepare_arxiv_submission.sh /path/to/paper
./prepare_arxiv_submission.sh /path/to/paper paper.tex
```

## Output

The script creates:

- `SOURCE_DIR/arxiv_submission/`
- `SOURCE_DIR/arxiv_submission/ax.tar`

## What It Copies

The script starts by copying only a limited set of source material into `arxiv_submission/`:

- the selected main `.tex` file
- one `.bib` file, chosen in this order:
  same basename as the main `.tex`, then common names such as `bibliography.bib`, `references.bib`, `refs.bib`, `ref.bib`, or `bib.bib`
- the `figures/` directory, if present
- the `plots/` directory, if present

It does not copy the rest of the source tree.

## What It Does Inside `arxiv_submission/`

After copying, the script modifies only the submission copy.

1. It flattens files from `figures/` and `plots/` into the submission root.
2. It rewrites `\includegraphics{...}` paths in the copied main `.tex` to match the flattened filenames.
3. It removes LaTeX comments from the copied main `.tex`.
4. It appends the standard arXiv rerun trigger line if it is missing.
5. It scans the copied main `.tex` for `\includegraphics` usage and deletes flattened figure files that are not referenced.
6. It compiles the copied submission tree with `latexmk` if available, otherwise with `pdflatex` and `bibtex`.
7. It keeps the generated `.bbl` file.
8. It removes copied `.bib` files after compilation.
9. It removes common LaTeX build artifacts from the submission copy.
10. It removes the compiled manuscript PDF while keeping figure PDFs.
11. It creates `ax.tar` inside `arxiv_submission/`.

## Important Behavior

- Flattening aborts if it would overwrite an existing file or if duplicate filenames appear within flattened asset trees.
- Only figures referenced by `\includegraphics` in the copied main `.tex` are kept in the final submission folder.
- The tarball is built from the final contents of `arxiv_submission/` and excludes `ax.tar` itself.
- After a successful BibTeX run, `.bbl` should remain and `.bib` files should be gone from the submission folder.

## Requirements

Required tools:

- `perl`
- `find`
- `tar`

Compilation tools:

- preferred: `latexmk`
- fallback: `pdflatex`
- `bibtex` is required when the document needs a bibliography and `latexmk` is not used

## Expected Final Contents

Depending on the paper, the final `arxiv_submission/` directory typically contains:

- the rewritten main `.tex`
- the generated `.bbl` if bibliography data was used
- only the flattened figure files actually referenced by the paper
- `ax.tar`
