Implements the guidelines of
<https://trevorcampbell.me/html/arxiv.html>
for preparing an arXiv submission.

# Prepare a LaTeX paper source tree for arXiv submission

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

   SOURCE_DIR/arxiv_submission/
   SOURCE_DIR/ax.tar

# Notes

- This script edits only the copied `arxiv_submission/` directory.
- It flattens subdirectories into the submission root.
- It rewrites common LaTeX references so files are addressed from the root.
- It removes comments from `.tex` files.
- It compiles the document, keeps the generated `.bbl`, removes `.bib` and build files, then creates `ax.tar`.
