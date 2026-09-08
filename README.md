# xmlrectr

**From unfamiliar XML to analysis-ready R tables.**

`xmlrectr` is an ambitious attempt at a universal XML **rectangler** for R.

It is not trying to be a universal XML parser. Excellent XML parsers already exist. The problem addressed here is different: **how do you turn hierarchical XML into a table or tibble that is genuinely useful for analysis with the tidyverse, base R, Arrow, and other tools built around tabular data?**

That problem becomes especially difficult when you are simply handed an XML file and know little or nothing about it. You may have no schema, no documentation, no knowledge of the XML vocabulary, and no predefined extraction rules. `xmlrectr` can inspect the actual document structure and, in many cases, construct a workable analyst-friendly tibble automatically.

When you *do* know the XML structure, have documentation or an XSD, or know exactly what you want to expose, the package becomes more explicit rather than less useful. You can review structural proposals, provide row and identifier choices, select and rename fields, use schema evidence, save reusable profiles, and obtain a rectangle closely aligned with your analytical purpose.

The package is deliberately generic. It contains no special rules for MARC, FHIR, EAD, ONIX, GPX, UBL, or any other XML vocabulary.

---

## Why XML rectangling is hard

XML is hierarchical. Analytical data is usually rectangular.

A naive "flatten everything" strategy can easily:

- lose repeated values;
- multiply independent repeated branches into accidental Cartesian products;
- confuse elements that share names but belong to different namespaces;
- collapse document order that carries information;
- propagate parent text or context to the wrong descendants;
- invent associations that are not actually present in the source;
- create list-columns or highly irregular structures that are awkward for ordinary R analysis.

There is also an unavoidable conceptual limit: **an arbitrary XML document does not have one mathematically unique tabular interpretation**. Domain knowledge can always improve a rectangle.

`xmlrectr` therefore does not claim to infer the intended semantics of every XML document. Instead, it aims to make a useful, conservative structural interpretation when knowledge is scarce, while exposing progressively more control when the user knows more.

The core design is:

```text
unknown XML
    |
    +--> automatic analyst-oriented rectangle
    |
    +--> structural proposal
             |
             v
        human review
             |
             v
        reusable profile
             |
             v
        compiled rectangle
```

XSD information can contribute evidence, but it is advisory rather than blindly authoritative.

---

## Two kinds of automation

A major goal of `xmlrectr` is to automate **both the analytical problem and the computational problem**, while keeping both layers tunable.

### 1. Analytical automation: how should this XML become a table?

For exploration, `rectangle_xml_analyst()` can start from the XML file itself:

```r
library(xmlrectr)

file <- system.file("extdata", "orders.xml", package = "xmlrectr")

analyst <- rectangle_xml_analyst(file)
analyst
```

The result is one self-contained tibble with:

- universal `xml_*` provenance and entity columns;
- atomic analyst-facing columns;
- no list-columns;
- explicit entity and parent-entity identities;
- repeated branches kept as separate observations rather than silently multiplied;
- namespace-aware source information;
- inferred scalar values where the structure supports them.

This is the deliberately ambitious part of the package: **starting from unfamiliar XML and attempting to produce something an R analyst can immediately inspect and work with.**

For one-off exploration, this may be all you need.

For repeated or production use, once you understand the structure you will usually want to move to an explicit profile so that the intended rectangle becomes a stable, reviewable contract.

### 2. Computational automation: how should the work be executed?

Once a rectangle is defined, execution has its own set of choices: sequential or parallel processing, worker count, chunk size, task size, memory ownership, and whether a large document should be streamed instead of fully materialised.

Those choices are intentionally separated from the analytical meaning of the rectangle.

For the normal rectangling APIs, one argument can ask `xmlrectr` to choose whether parallel execution is worthwhile:

```r
out <- rectangle_xml(
  file,
  profile,
  parallel = "auto"
)
```

Automatic execution planning is based on the **observed structural workload and available resources**, not on XML vocabulary names, filenames, or rules tuned to the validation corpus. The package does not apply one fixed worker/chunk recipe to every document.

Advanced controls remain available, but they are optional. The point of the architecture is that you should not need to turn every screw before getting useful work done on a large, nested or unfamiliar XML file.

---

## Automatic when you need it, explicit when you want it

`xmlrectr` is designed to support a continuum of prior knowledge.

### You know almost nothing about the XML

Start with the automatic analyst table:

```r
analyst <- rectangle_xml_analyst(file)
```

This is the quickest route from an unfamiliar document to an R tibble.

### You want to understand the structure before deciding

Ask the package for a proposal:

```r
proposal <- propose_xml_profile(file)

review_xml_proposal(proposal, "rows")
review_xml_proposal(proposal, "ids")
review_xml_proposal(proposal, "fields")
```

The proposal is **evidence**, not an executable command. It lets the package inspect the XML and suggest plausible structural choices without pretending that software can know your analytical intent.

### You know what you want to expose

Define it explicitly:

```r
profile <- xml_profile(
  rows = "order",
  id = "id"
)

out <- rectangle_xml(file, profile)
```

A profile can also select and rename fields, specify types, provide namespace information, and choose the desired layout.

You can save the reviewed decision:

```r
write_xml_profile(profile, "orders-profile.json")
profile2 <- read_xml_profile("orders-profile.json")
```

and reuse it across files belonging to the same XML family.

For repeated processing, compile the profile once:

```r
spec <- compile_xml_profile(profile, file)

out <- rectangle_xml(
  file,
  spec,
  parallel = "auto"
)
```

This is where domain knowledge pays off: when you know the XML structure and the analytical question, the package can produce a rectangle much more closely aligned with your desiderata than any fully automatic method could infer.

---

## XSD-assisted work

If an XSD is available, `xmlrectr` can use it as additional structural evidence:

```r
xml <- system.file("extdata", "types.xml", package = "xmlrectr")
xsd <- system.file("extdata", "types.xsd", package = "xmlrectr")

proposal <- propose_xml_profile(xml, xsd = xsd)

review_xml_proposal(proposal, "xsd")
```

`inspect_xsd()` can expose useful declaration, occurrence, required-attribute and scalar-type information.

The important design choice is that **XSD is advisory**. A schema describes valid document structure, but it does not necessarily tell an analyst what should constitute a row, which repeated structures should become separate entities, or which fields are relevant to a particular analysis.

So the workflow remains:

```text
XML structure + optional XSD + user knowledge
                    |
                    v
              reviewed profile
                    |
                    v
             analytical rectangle
```

---

## What the analyst representation tries to preserve

The automatic analyst representation is designed as **one self-contained atomic table per XML document**.

Its structural contract is conservative:

- `xml_entity` and `xml_entity_id` identify analytical entities;
- entity IDs are nonblank and unique;
- parent IDs refer to entities in the same table;
- repeated branches remain separate rows;
- independent repetitions are not multiplied into accidental Cartesian products;
- analyst columns are atomic rather than list-columns;
- all-`NA` analyst columns are avoided;
- source attributes and text remain structurally accounted for;
- namespace information and source paths remain available through `xml_*` provenance columns;
- derived text is not blindly propagated into descendants;
- order-sensitive sibling structures are preserved rather than being folded into invented key-value associations.

The underlying canonical representation is even more explicit. It records document order, node identity, parentage, depth, namespaces, attributes, text/CDATA and other retained XML node types.

That canonical layer is the loss-aware structural foundation on which higher-level rectangles are built.

---

## Built for real XML, not only toy examples

The ambition to work with arbitrary XML is useful only if the implementation can cope with XML as it exists in practice: large documents, deep nesting, repeated records, namespaces and irregular structures.

A substantial part of the development of `xmlrectr` has therefore focused on performance, memory behaviour and execution architecture.

### Native structural acceleration

Performance-critical canonical reading and structural/indexing operations have native C implementations using `libxml2`.

The R implementation remains the semantic reference: compiled code is used to accelerate structural bottlenecks, not to introduce a second set of rectangling semantics.

### Bounded-memory streaming

For XML that should not be represented as one complete in-memory canonical table, `xmlrectr` provides a streaming path based on complete record subtrees.

```r
batches <- list()

stats <- xml_stream_rectangle(
  "large.xml",
  spec,
  callback = function(batch) {
    batches[[length(batches) + 1L]] <<- batch
  },
  parallel = "auto"
)
```

Parsing and record-boundary detection remain coordinator-side. Workers receive complete independent record payloads rather than live `xml2`/libxml external pointers or parser state.

### CSV and Parquet output

Large results can be written without first collecting the entire rectangle into one R object:

```r
rectangle_xml_csv(
  "large.xml",
  spec,
  output = "large.csv",
  parallel = "auto"
)
```

For typed analytical output:

```r
rectangle_xml_parquet(
  "large.xml",
  spec,
  output_dir = "large-parquet",
  parallel = "auto"
)
```

Parquet support requires the optional `arrow` package.

---

## Parallel execution without a second API

Parallelism is an execution choice of the same rectangling operation, not a separate family of user-facing functions.

```r
# Exact sequential path
seq_out <- rectangle_xml(
  file,
  spec,
  parallel = FALSE
)

# Request parallel execution with tuned automatic settings
par_out <- rectangle_xml(
  file,
  spec,
  parallel = TRUE
)

# Let the engine decide whether parallel work is worthwhile
auto_out <- rectangle_xml(
  file,
  spec,
  parallel = "auto"
)
```

The sequential implementation is the semantic reference. Parallel execution is required to preserve the same result:

```r
identical(seq_out, par_out)
```

For ordinary use, `parallel = "auto"` is the recommended low-complexity choice when you want the engine to avoid process and scheduling overhead on small record workloads.

### Why the scheduler is adaptive

Parallel XML rectangling is not simply a matter of running `workers = parallel::detectCores()`.

A useful execution plan depends on:

- how many independent record subtrees exist;
- how coarse or fine those records are;
- the structural amount of work per record;
- available cores;
- task scheduling overhead;
- memory pressure and input ownership.

`xmlrectr` therefore uses structural workload information to decide whether and how to parallelise. Worker, chunk and task controls are available for advanced use, but the routine path is intentionally automated.

### Two retained parallel strategies

Two strategies exist because throughput and memory pressure are not the same optimisation problem.

`parallel_chunks` is throughput-oriented: independently owned vectorised chunks can be processed concurrently.

`shared_chunk` is memory-oriented: one bounded outer chunk can be shared through `mori`, reducing input-memory duplication while workers process coarse ranges from that shared input.

You normally do not need to select between them manually. They remain exposed because advanced users may have machine-specific memory or throughput constraints.

---

## Tuning for technically minded users

Most users should stop at:

```r
rectangle_xml(file, spec, parallel = "auto")
```

The following controls exist for benchmarking, unusually constrained machines, or specialist tuning:

```r
rectangle_xml(
  file,
  spec,
  parallel = TRUE,
  workers = 4,
  strategy = "shared_chunk",
  chunk_records = 2048,
  task_records = 128
)
```

These settings should be tuned against **your actual XML and your actual machine**. A configuration that is optimal for one record structure or hardware platform need not be optimal for another.

The package deliberately exposes this machinery without requiring ordinary users to manage it.

---

## A reproducible way to benchmark your own XML

Absolute elapsed times are highly machine-dependent. For performance work, compare strategies **on the same machine and the same XML**.

A simple reproducible pattern is:

```r
spec <- compile_xml_profile(profile, file)

t_seq <- system.time(
  seq_out <- rectangle_xml(
    file,
    spec,
    parallel = FALSE
  )
)

t_auto <- system.time(
  auto_out <- rectangle_xml(
    file,
    spec,
    parallel = "auto"
  )
)

t_forced <- system.time(
  forced_out <- rectangle_xml(
    file,
    spec,
    parallel = TRUE
  )
)

stopifnot(
  identical(seq_out, auto_out),
  identical(seq_out, forced_out)
)

rbind(
  sequential = t_seq,
  auto = t_auto,
  forced_parallel = t_forced
)
```

For serious benchmarking, repeat runs and compare within-machine speedups rather than quoting a single elapsed time. Small XML documents may correctly be faster sequentially because process startup and scheduling have a cost. Larger, sufficiently coarse record workloads are where parallel execution can pay off.

This is also why `parallel = "auto"` exists: **parallelism is a tool, not a goal in itself**.

---

## Battle-tested, not vocabulary-tuned

Before conversion into the R package, the frozen validated engine was exercised against a deliberately diverse corpus of **30 real-world XML documents**.

The validation included:

- the focused unit/regression suite;
- exact in-memory sequential/forced-parallel parity;
- exact streaming sequential/forced-parallel parity;
- exact parity through the unified `parallel = "auto"` interface;
- synthetic scaling and memory experiments used to refine the balanced execution defaults.

In the 30-file automatic-policy run, 29 smaller workloads remained sequential and the one sufficiently large/coarse workload was selected for parallel execution. All outputs remained identical to the sequential semantic oracle.

Crucially, the engine was **not** modified with vocabulary-specific rules or filename-specific exceptions to make these files pass.

<details>
<summary><strong>Current 30-file real-world validation corpus</strong></summary>

The corpus covers very different XML domains and structures:

1. UBL invoice
2. FHIR patient
3. GPX route
4. KML places
5. METS metadata
6. MODS records
7. JUnit report
8. Nmap scan
9. DocBook book
10. PubMed articles
11. BLAST result
12. BioSample record
13. RDF vocabulary
14. GraphML graph
15. RSS feed
16. Atom feed
17. XLIFF 2.0
18. XLIFF 1.2
19. MusicXML score
20. OpenStreetMap
21. SVG drawing
22. SDMX Generic
23. SDMX Structure
24. OOXML shared strings
25. Maven project
26. Android manifest
27. EAD finding aid
28. SoapUI project
29. TEI person data
30. ONIX books

The purpose of this corpus is structural diversity, not optimisation for these particular vocabularies. General structural rules are preferred over corpus-specific special cases.

</details>

This validation does **not** mean that every arbitrary XML document has one objectively correct analyst table. It means that the package's generic structural rules and execution engine have been exercised across a broad set of real-world XML shapes without resorting to vocabulary-specific parsers.

---

## Malformed XML

`xmlrectr` expects well-formed XML.

Malformed XML is detected and reported as an error or warning where appropriate. Repairing broken XML is intentionally outside the scope of the package: `xmlrectr` rectangles XML; it does not try to guess how a malformed source document should be rewritten.

Likewise, XSD inspection is intended to provide useful schema evidence for rectangling. `xmlrectr` is not a complete XSD validation or repair framework.

---

## Installation

At present, `xmlrectr` can be installed from GitHub.

The recommended method is `pak`:

```r
install.packages("pak")
pak::pak("larry77/xmlrectr")
```

Alternatively:

```r
install.packages("remotes")
remotes::install_github("larry77/xmlrectr")
```

Because `xmlrectr` contains native C code, the GitHub version is compiled from source and requires a working build toolchain and `libxml2` development files.

<details>
<summary><strong>Windows build requirements</strong></summary>

Windows is a first-class supported platform. Use the Rtools version matching your R installation and install it in the default location.

For the currently supported R series:

- R 4.6.x: Rtools45
- R 4.5.x: Rtools45
- R 4.4.x: Rtools44

With a normal R/Rtools installation, manual `PATH` configuration should not usually be necessary.

If compilation fails, first check the toolchain:

```r
install.packages("pkgbuild")
pkgbuild::has_build_tools(debug = TRUE)
```

Avoid mixing Rtools with unrelated MSYS2/MinGW/Strawberry Perl toolchains on `PATH`, as this can produce difficult-to-diagnose linking problems.

The GitHub Actions workflow compiles and tests the package on `windows-latest`.

</details>

<details>
<summary><strong>Linux build requirements</strong></summary>

On Debian/Ubuntu:

```bash
sudo apt install libxml2-dev pkg-config
```

Then install `xmlrectr` from R using `pak` or `remotes`.

</details>

<details>
<summary><strong>macOS build requirements</strong></summary>

With Homebrew:

```bash
brew install libxml2 pkg-config
export PKG_CONFIG_PATH="$(brew --prefix libxml2)/lib/pkgconfig:$PKG_CONFIG_PATH"
```

Then install `xmlrectr` from R.

</details>

For a local checkout:

```r
pak::local_install(".")
```

---

## Documentation

This README is intended to be a **self-contained introduction**. You should not need to install the package or open a vignette merely to understand what `xmlrectr` is trying to do.

For readers who want more detail, the repository also contains technical material that can be read directly on GitHub:

- [Getting started with unknown XML](vignettes/getting-started.Rmd)
- [Large XML, streaming and parallel execution](vignettes/large-xml.Rmd)
- [Architecture and validation](vignettes/development.Rmd)
- [Engineering history and development notes](DEVELOPMENT.md)

The same material is also published through the [pkgdown website](https://larry77.github.io/xmlrectr/).

The technical articles are intentionally more detailed than this README. They are the right place for readers interested in scheduler design, bounded-memory execution, native acceleration, benchmark interpretation, worker/chunk/task tuning, validation boundaries and the engineering decisions behind the simple public interface.

---

## Design principles

A few principles define the project:

- **Generic before vocabulary-specific.** Structural rules should work across XML vocabularies.
- **Sequential semantics are the reference.** Performance work must not change the rectangle.
- **Automation should be inspectable.** Proposals are reviewable and profiles are explicit.
- **XSD is evidence, not analytical truth.**
- **Do not invent relationships.** Independent repetitions should not become Cartesian products.
- **Preserve provenance.** Analyst-friendly output should remain traceable to the XML structure.
- **Performance matters on real data.** Streaming, native acceleration and parallel execution are part of the architecture, not afterthoughts.
- **Advanced machinery should not make routine use complicated.** Sensible structural and computational decisions should be available without manual tuning.

The intended experience is simple even though the implementation underneath is not:

> **Give `xmlrectr` an XML file. If you know nothing about it, start exploring immediately. If you know more, tell the package what you know. If the workload is large, let the execution engine do the heavy lifting.**

---

## Scope

`xmlrectr` aims to be a universal **rectangler**, not a universal semantic interpreter.

It is designed to take arbitrary well-formed XML and produce useful R-oriented tabular representations without requiring a vocabulary-specific parser. It can exploit schema information and user knowledge when they exist, but it does not require them for exploratory use.

That is a deliberately ambitious target. The package cannot know the domain meaning of every XML vocabulary, but it can do a great deal of the structural and computational work required to move from hierarchical XML to an analyst-friendly table.

That is the problem `xmlrectr` is built to solve.
