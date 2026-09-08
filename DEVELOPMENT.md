# xmlrectr development, architecture and validation

This document is the technical companion to `README.md`.

The README is intentionally user-facing: install the package, inspect
unknown XML, create a profile, rectangle the file, and optionally enable
automatic parallel execution. This document records the engineering
decisions needed to maintain that simple interface without losing the
semantics established during the standalone prototype work.

## 1. Current package-stage boundary

`xmlrectr` 0.0.0.9000 begins from the validated **P6.1** standalone
engine. Package conversion is deliberately conservative:

- the validated R engine is initially kept in one large `R/xmlrectr.R`
  file;
- native algorithms are unchanged, with the DLL registration name
  adapted from the standalone `xmlrectnative` library to the package DLL
  `xmlrectr`;
- public execution semantics remain unchanged;
- tests are ported before any broad code modularization;
- packaging, documentation and CI changes are kept separate from new XML
  semantics.

Once package-level checks are green, the large R file can be split
mechanically into logical modules. Behavioural changes should not be
mixed into that split.

## 2. Core semantic model

### Canonical XML node table

The canonical table is the common representation used by the in-memory
and streaming layers. It preserves:

- `document_id`
- `node_id`
- `parent_id`
- `node_order`
- `sibling_order`
- `depth`
- `node_type`
- `qualified_name`
- `local_name`
- `prefix`
- `namespace_uri`
- `value`

The R implementation remains the semantic reference. Native code may
accelerate structural work but must not change this contract.

### Profile workflow

The intended explicit workflow is:

``` text
propose_xml_profile()
        ↓
review_xml_proposal()
        ↓
xml_profile()
        ↓
compile_xml_profile()
        ↓
rectangle_xml() / streaming writers
```

A proposal is review-only. It must never silently become an executable
profile.

### XSD boundary

XSD is advisory evidence.
[`inspect_xsd()`](https://larry77.github.io/xmlrectr/reference/inspect_xsd.md)
deliberately exposes a conservative subset useful for rectangling
decisions; it is not a full schema validator and must not silently
pretend to resolve arbitrary imports/includes, substitution groups,
wildcards or user-defined derivation chains.

## 3. Analyst-oriented single-table layer

The analyst layer provides one self-contained atomic table per XML
document. Important invariants include:

- no list-columns;
- explicit `xml_entity` / `xml_entity_id` provenance;
- entity IDs nonblank and unique;
- parent entity IDs refer to entities represented in the table;
- no accidental propagation of derived text into unrelated descendant
  entity rows;
- no all-NA analytical columns;
- source ordering remains recoverable;
- order-sensitive alternating sibling structures remain explicit rather
  than being folded into misleading context columns.

The analyst layer is convenient for exploration. Explicit profiles
remain the stronger contract for production extraction from a known XML
family.

## 4. Unified execution interface

Daily use should not require a separate parallel API.

``` r

rectangle_xml(file, spec)                         # sequential
rectangle_xml(file, spec, parallel = TRUE)        # request parallel defaults
rectangle_xml(file, spec, parallel = "auto")      # engine chooses
```

The same principle applies to the canonical rectangle and streaming
writers. Lower-level `*_parallel()` functions remain available for
diagnostics and advanced control, but they are not the primary workflow.

### Meaning of `parallel`

- `FALSE`: exact sequential path.
- `TRUE`: require record-level parallel execution and choose omitted
  scheduling controls automatically.
- `"auto"`: use the same scheduler, but stay sequential when the
  observed in-memory record workload is too small to justify process
  overhead.

For bounded streaming, `"auto"` does not make an additional full pass
merely to count records; streaming is already the
large-file/bounded-memory path.

## 5. Parallel architecture

Only complete independent XML record subtrees are parallelized.

The coordinator retains responsibility for:

- SAX parsing;
- record-boundary detection;
- global source-ID uniqueness checks;
- output ordering;
- user callbacks;
- CSV publication;
- Parquet publication.

Workers never receive libxml/xml2 external pointers or live parser
state.

### `parallel_chunks`

Throughput-oriented strategy:

- several independently owned vectorized record chunks can be in flight;
- automatic in-memory chunking is approximately one owned chunk per
  worker;
- the chunk itself is the vectorization unit.

### `shared_chunk`

RAM-oriented strategy:

- one bounded input chunk is exposed through
  [`mori::share()`](https://shikokuchuo.net/mori/reference/share.html);
- workers process vectorized ranges from that shared input;
- automatic scheduling targets a small number of coarse tasks per
  worker.

The two strategies are intentionally retained because empirical PSS
measurement showed a real memory/speed trade-off rather than two
equivalent implementations.

## 6. Automatic scheduler policy

The scheduler must remain structural and general. It must never
recognize EAD, MARC, ONIX, FHIR, filenames in the validation corpus, or
any other XML vocabulary as a scheduling special case.

Current balanced defaults:

- automatic worker selection leaves a coordinator/core margin where
  possible and caps the balanced default at roughly four workers;
- explicit `workers` always overrides that policy;
- in-memory automatic strategy defaults to `parallel_chunks`;
- bounded streaming automatic strategy prefers `shared_chunk` when the
  shared stack is available;
- `parallel_chunks` uses about one owned vectorized chunk per worker;
- `shared_chunk` targets roughly four coarse tasks per worker;
- the in-memory auto crossover is based on record count, canonical node
  work per worker and record grain, not file size or XML names.

The P6.1 fast path performs a constant-time impossibility check before
computing record spans when the canonical table is too small to satisfy
the existing node work guard. That removed the systematic overhead
previously observed when `parallel = "auto"` ultimately selected the
sequential path.

## 7. Validation evidence before package conversion

### Unit/regression suite

The full standalone suite passed after the P6.1 fast-path change. In the
standalone tree, the native field-layout test was skipped unless the
native analyst engine had been built and explicitly requested. In the
package, the DLL is always part of installation, so package tests
exercise the registered native field-layout routine plus small
native-vs-R canonical and analyst parity checks unconditionally.

### 30-file forced-parallel real-world corpus

Thirty structurally diverse real XML documents were rectangled through
both the sequential and forced parallel paths. All 30 matched exactly in
both in-memory and streaming parity checks.

The corpus covered, among others, UBL, FHIR, GPX, KML, METS, MODS,
JUnit, Nmap, DocBook, PubMed, BLAST, BioSample, RDF/XML, GraphML, RSS,
Atom, XLIFF, MusicXML, OpenStreetMap, SVG, SDMX, SpreadsheetML, Maven,
Android, EAD, SoapUI, TEI and ONIX.

The forced-parallel run is a correctness stress test, not a performance
test: many of those XML documents take far less than a second
sequentially and are intentionally terrible candidates for process-level
parallelism.

### 30-file real-world `parallel = "auto"` corpus

After the P6.1 fast path:

- 30/30 results were identical to the sequential oracle;
- 29/30 workloads stayed sequential;
- the one sufficiently large/coarse workload selected four-worker
  `parallel_chunks`;
- sequential-auto timings became essentially indistinguishable from
  direct sequential execution, within normal run-to-run noise.

This is the relevant daily-use validation of the unified interface.

### Synthetic scaling

Synthetic scaling established the expected crossover: process overhead
dominates small jobs, while larger record workloads scale materially. On
one validation platform the automatic 1/2/4/8 MiB ladder stayed
sequential at 1 and 2 MiB, switched at 4 MiB, and produced approximately
1.28x and 1.75x speedups at 4 and 8 MiB respectively. These raw
crossover points are platform-specific and must not be hard-coded.

### Worker scaling and memory

Cross-machine experiments showed that four workers are a strong balanced
point, while additional workers can still reduce elapsed time with lower
parallel efficiency. Separate PSS sampling also confirmed the reason to
retain `shared_chunk`: its physical/private memory peak was lower than
independently owned parallel chunks, at the cost of somewhat lower
throughput in that run.

Raw elapsed times from different machines must never be compared as if
they were one benchmark series. Within-machine speedup/efficiency and
semantic parity are the meaningful comparisons.

## 8. Native C boundary in the package

The standalone distribution builds a relocatable library named
`xmlrectnative`. An installed R package is different: R builds and loads
a DLL named after the package.

Therefore the package version:

- registers routines in `R_init_xmlrectr()`;
- uses `useDynLib(xmlrectr, .registration = TRUE)`;
- uses `.Call(..., PACKAGE = "xmlrectr")`;
- links against system libxml2 through `pkg-config`.

This is packaging plumbing. The native algorithms themselves should
remain identical unless a separately validated performance/semantic
change is made.

## 9. Package tests

Run locally:

``` bash
R CMD build .
R CMD check xmlrectr_0.0.0.9000.tar.gz
```

Or from R:

``` r

testthat::test_local()
```

For the native field-layout path:

``` bash
XML_RECT_ANALYST_ENGINE=native R CMD check xmlrectr_0.0.0.9000.tar.gz
```

Heavy 30-file internet/corpus tests are not ordinary package-check
tests. Keep them as release/engine-validation infrastructure rather than
downloading a large external corpus during `R CMD check`.

## 10. GitHub and pkgdown

The repository includes:

- `.github/workflows/R-CMD-check.yaml` for package checks;
- `.github/workflows/pkgdown.yaml` for website deployment;
- `_pkgdown.yml` for navigation/reference organization.

Current pkgdown practice uses the package README as the website
homepage, manual pages as the reference section, and vignettes as
articles. The website workflow deploys to `gh-pages`.

The first public repository is `larry77/xmlrectr`. The maintainer
metadata and GitHub/pkgdown URLs are already wired into the package.
README and DEVELOPMENT content remain deliberately iterative; they
should be revised repeatedly after the repository is public.

A typical first publication from the package root is:

``` bash
git init
git add .
git commit -m "Initial xmlrectr package"
git branch -M main
gh repo create larry77/xmlrectr --source=. --remote=origin --public --push
```

After the first push:

1.  let the cross-platform R-CMD-check workflow pass, including Windows;
2.  let the pkgdown workflow create/update the `gh-pages` branch;
3.  in GitHub Settings -\> Pages, publish from `gh-pages` / root if
    Pages is not enabled automatically;
4.  inspect the public site at <https://larry77.github.io/xmlrectr/>;
5.  iterate on `README.md`, `DEVELOPMENT.md`, examples and pkgdown
    navigation.

The GPL-3 choice is adequate for the development repository but should
be reviewed once more before the first tagged public release.

## 11. Relationship to the standalone trio

The standalone three-file distribution remains a separate supported
artifact:

``` text
xml_rectangle.R
xmlrect_native.c
build-native.sh
```

Its native C source and compiled library may live in custom filesystem
locations. Package installation, by contrast, owns its DLL layout and
native registration.

Do not make the standalone script source the installed package or make
the package depend on external standalone files. They should remain
independent front ends over the same validated semantics.

After the package structure has matured and passed package-level checks,
lessons from packaging can be backported deliberately to a new
standalone trio. The frozen standalone P6.1 validation tree should
remain untouched.

Back-port checklist for the next standalone trio revision:

- the corrected `.xml_analyst_subtree_text()` fallback discovered by
  `R CMD check`;
- package-era documentation improvements and clearer dependency errors;
- Windows/toolchain guidance where it applies to standalone native
  compilation;
- any portability lessons revealed by macOS/Windows GitHub Actions;
- API wording improvements that do not alter the validated semantics;
- keep the standalone custom C-source and custom shared-library location
  support.

## 12. Near-term package roadmap

1.  Publish the initial GitHub repository and let Linux/macOS/Windows CI
    run.
2.  Fix any cross-platform native-build issue revealed by CI.
3.  Build and inspect the pkgdown GitHub Pages site.
4.  Iterate repeatedly on `README.md`, `DEVELOPMENT.md`, examples and
    navigation.
5.  Back-port relevant package lessons to a new standalone trio and
    validate it.
6.  Only then consider mechanically splitting `R/xmlrectr.R` into
    logical modules.
7.  Re-run focused/package tests after every structural split.
8.  Treat CRAN-readiness as a separate milestone from GitHub/package
    readiness.

## GitHub publication and documentation iteration

Repository: <https://github.com/larry77/xmlrectr>  
Website: <https://larry77.github.io/xmlrectr/>

`README.md` and `DEVELOPMENT.md` are intentionally living documents. The
first public versions establish the structure and installation path;
wording, examples, ordering and level of detail are expected to change
repeatedly as the package is used and reviewed. Documentation iteration
is not a signal that the validated rectangling core is unstable.

Windows is a first-class package target. CI includes `windows-latest`,
and the README documents source installation using the matching Rtools
toolchain.
