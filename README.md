# Prepare an arXiv submission tree through Trevor Campbell step 11

# Usage

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

# Examples

```sh
./prepare_arxiv_submission.sh
./prepare_arxiv_submission.sh paper.tex
./prepare_arxiv_submission.sh .
./prepare_arxiv_submission.sh . main.tex
./prepare_arxiv_submission.sh /path/to/paper
./prepare_arxiv_submission.sh /path/to/paper paper.tex
```

# Output

`SOURCE_DIR/arxiv_submission/`

`SOURCE_DIR/arxiv_submission/ax.tar`

# Notes

- This script only copies a small set of inputs into `arxiv_submission/`.
- It copies the chosen main `.tex` file.
- It copies one `.bib` file if found:
  same basename as the main `.tex` is preferred, then common names such as `bibliography.bib` or `references.bib`.
- It copies `figures/` and `plots/` if they exist.
- It flattens copied `figures/` and `plots/` into the submission root.
- It rewrites copied `\includegraphics{...}` paths to match the flattened filenames.
- It removes comments from the copied main `.tex`.
- It adds the arXiv multi-pass trigger line if missing.
- It compiles the copied submission tree.
- It keeps the generated `.bbl`, removes the copied `.bib`, removes build products, and creates `ax.tar` inside `arxiv_submission/`.
