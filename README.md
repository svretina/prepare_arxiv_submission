Implements the guidelines of
<https://trevorcampbell.me/html/arxiv.html>
for preparing an arXiv submission.

```sh
./prepare_arxiv_submission.sh
```

# Prepare a LaTeX paper source tree for arXiv submission

#

# Usage

```sh
./prepare_arxiv_submission.sh [SOURCE_DIR] [MAIN_TEX]
```

# Examples

```sh
./prepare_arxiv_submission.sh . main.tex
./prepare_arxiv_submission.sh /path/to/paper paper.tex
```

# Output

   SOURCE_DIR/arxiv_submission/
   SOURCE_DIR/ax.tar

# Notes

- This script edits only the copied arxiv_submission/ directory.
- It flattens subdirectories into the submission root.
- It rewrites common LaTeX references so files are addressed from the root.
- It removes comments from .tex files.
- It compiles the document, keeps the generated .bbl, removes .bib and build files, then creates ax.tar.
