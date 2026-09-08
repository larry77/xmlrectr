# xmlrectr 0.0.0.9000

* First package-stage development release.
* Preserves the validated P6.1 generic XML rectangling engine.
* Unifies sequential and parallel execution behind `parallel = FALSE`, `TRUE`,
  or `"auto"` on the ordinary rectangling functions.
* Includes conservative proposal/profile workflow, streaming, CSV/Parquet
  output, analyst-oriented single-table projection, and registered native C
  acceleration through libxml2.
* Adds pkgdown/GitHub Pages scaffolding and package-level regression tests.
* Package-check cleanup: complete public argument documentation, portable
  pkg-config Makevars syntax, explicit utils imports, and a regression-tested
  fallback fix in analyst subtree-text extraction.

- Prepared GitHub/pkgdown publication metadata for `larry77/xmlrectr`, added GitHub installation instructions, and added Windows CI/source-install guidance.
