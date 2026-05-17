# CV generator

This directory contains the source for generating `CV.pdf` from the current
site data.

Run from this `cv/` directory:

```sh
make pdf
```

This fetches the latest researchmap presentations and writes `build/CV.pdf`.
You can also invoke the generator directly:

```sh
./generate_cv.rb
```

If Ruby cannot find `bibtex-ruby`, run through Bundler instead:

```sh
bundle exec ruby generate_cv.rb
```

The script writes:

- `build/CV.tex`
- `build/CV.pdf`

It reads the latest local data from:

- `_pages/about.md`
- `_pages/teaching.md`
- `_data/cv.yml`
- `_data/grants.yml`
- `_data/activities.yml`
- `_bibliography/papers.bib`

Invited talks are fetched from the researchmap API:

- `https://api.researchmap.jp/yudaitanabe/presentations`

Only entries with `invited: true` are included in the `Invited Talks`
section. The fetched JSON is cached under `cache/` and can be reused with
`--researchmap-offline`.

The generated PDF is intentionally not copied into `assets/pdf/`.
Copy it manually when you want to publish it.

HTML and Markdown links in the source files are converted to LaTeX
`\href{...}{...}` links, and publication titles/DOIs link to their DOI or URL
when available.

Useful options:

```sh
make offline
make tex
ruby generate_cv.rb --no-pdf
ruby generate_cv.rb --build-dir /tmp/cv-build
ruby generate_cv.rb --researchmap-offline
ruby generate_cv.rb --researchmap-id yudaitanabe
```

The default LaTeX engine is `xelatex`, so Japanese-only researchmap entries can
be rendered. Use `--latex-engine pdflatex` only when the generated data is
ASCII/Latin-script compatible.
