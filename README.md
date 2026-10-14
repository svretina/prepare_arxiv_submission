# Prepare an arXiv submission

`prepare_arxiv_submission.sh` prepares a reduced arXiv upload tree from a LaTeX project, following the Trevor Campbell workflow [1] through the compile-and-package stage while starting from a restricted set of inputs.

[1] <https://trevorcampbell.me/html/arxiv.html>

## Usage

```sh
./prepare_arxiv_submission.sh
./prepare_arxiv_submission.sh [SOURCE_DIR_OR_MAIN_TEX]
./prepare_arxiv_submission.sh [SOURCE_DIR] [MAIN_TEX]
```

The submission folder is always created in the directory from which you run the
command, as `./arxiv_submission/`, even when the source files are elsewhere.
The selected `.tex` file's directory supplies the figures, plots, and
bibliography files.

If no main `.tex` file is provided, the script looks for these files in order:

1. `article.tex`
2. `paper.tex`
3. `main.tex`

If none of those files exists, the script asks for the main file name. You may
omit the `.tex` extension; the script adds it. A blank response is an error.

If a main-file argument includes a path, its parent directory is used as the
source directory. With two arguments, the first is the directory relative to
which the main-file path is resolved. The `.tex` extension is optional.

## Examples

```sh
./prepare_arxiv_submission.sh
./prepare_arxiv_submission.sh paper.tex
./prepare_arxiv_submission.sh .
./prepare_arxiv_submission.sh . main.tex
./prepare_arxiv_submission.sh /path/to/paper
./prepare_arxiv_submission.sh /path/to/paper paper.tex
# Run from the desired output directory; source files live in ./paper/ and
# the submission is created as ./arxiv_submission/.
./prepare_arxiv_submission.sh ./paper/name.tex
```

## Output

The script creates in the directory where the command was run:

- `./arxiv_submission/`
- `./arxiv_submission/ax.tar`

## What It Copies

The script starts by copying only a limited set of source material into `arxiv_submission/`:

- the selected main `.tex` file
- every `.bib` file explicitly named in the main `.tex` through `\bibliography`,
  `\addbibresource`, `\addglobalbib`, or `\addsectionbib`; names without the
  `.bib` suffix are resolved with it added
- the `figures/` directory, if present
- the `plots/` directory, if present

It does not copy the rest of the source tree.

## What It Does Inside `arxiv_submission/`

After copying, the script modifies only the submission copy.

1. It flattens files from `figures/` and `plots/` into the submission root.
2. It rewrites `\includegraphics{...}` paths in the copied main `.tex` to match the flattened filenames.
3. It removes LaTeX comments and strips `\iffalse...\fi` blocks from the copied main `.tex`.
4. It appends the standard arXiv rerun trigger line if it is missing.
5. It scans the copied main `.tex` for `\includegraphics` usage and deletes flattened figure files that are not referenced.
6. It renames the remaining copied figures in document order and updates only the copied main `.tex`: `fig1.ext`, `fig2.ext`, and, inside `subfigure` environments or `\subfloat`/`\subfigure` commands, `fig2a.ext`, `fig2b.ext`, and so on. Source figures and the source `.tex` are unchanged.
7. It compiles the copied submission tree with `latexmk` if available, otherwise with `pdflatex` and `bibtex`.
8. It keeps the generated `.bbl` file.
9. It removes copied `.bib` files after compilation.
10. It removes common LaTeX build artifacts from the submission copy.
11. It removes the compiled manuscript PDF while keeping figure PDFs.
12. It creates `ax.tar` inside `arxiv_submission/`.

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
