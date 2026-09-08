# xmlrectr

**Rectangle arbitrary XML into analysis-friendly R tables.**

`xmlrectr` is for XML whose structure may be unfamiliar, deeply nested,
namespace-heavy, repetitive, or simply too large to treat as a small tree in
memory. It separates *discovering structure* from *deciding the analytical
shape*, then applies that decision consistently in memory, by streaming, or
with record-level parallel execution.

The package is intentionally generic: it does not contain rules for MARC,
FHIR, EAD, ONIX, GPX, or any other particular XML vocabulary.

## Why this package?

XML is hierarchical; analytical data is usually rectangular. Flattening XML
naively can lose repeated values, multiply independent repetitions into a
Cartesian product, or silently confuse namespaces. `xmlrectr` instead uses a
reviewable workflow:

```text
XML sample
   ↓
proposal
   ↓  human review
profile
   ↓
compiled rectangle specification
   ↓
one analysis-friendly table
```

An XSD can contribute useful evidence, but it does not by itself determine the
best analytical rectangle. `xmlrectr` therefore treats XSD information as
advisory rather than as an automatic flattening instruction.

## Installation

This is currently a development package rather than a CRAN release.

From a local checkout:

```r
# install.packages("pak")
pak::local_install(".")
```

Once the repository is published on GitHub:

```r
pak::pak("YOUR_GITHUB_USERNAME/xmlrectr")
```

The package contains native C code and requires the **libxml2 development
files** and `pkg-config` when installing from source. On Debian/Ubuntu, for
example:

```bash
sudo apt install libxml2-dev pkg-config
```

## Quick start: XML whose structure you do not yet know

```r
library(xmlrectr)

file <- system.file("extdata", "orders.xml", package = "xmlrectr")

proposal <- propose_xml_profile(file)
review_xml_proposal(proposal, "rows")
review_xml_proposal(proposal, "ids")
review_xml_proposal(proposal, "fields")
```

The proposal is **not executable**. It is evidence for a decision you make.
For this example:

```r
profile <- xml_profile(
  rows = "order",
  id = "id"
)

out <- rectangle_xml(
  file,
  profile,
  parallel = "auto"
)

out
```

You can save a reviewed profile and reuse it across files from the same XML
family:

```r
write_xml_profile(profile, "orders-profile.json")
profile2 <- read_xml_profile("orders-profile.json")
```

## Parallelism without a second API

Parallel execution is an execution choice of the **same functions**, not a
separate workflow.

```r
# Exact sequential path
out <- rectangle_xml(file, profile, parallel = FALSE)

# Explicitly request parallel execution; workers/chunks/tasks are chosen for you
out <- rectangle_xml(file, profile, parallel = TRUE)

# Let xmlrectr decide whether parallel work is worthwhile
out <- rectangle_xml(file, profile, parallel = "auto")
```

For normal use, `parallel = "auto"` is the intended low-complexity option when
you want the engine to avoid parallel overhead on small inputs. Advanced
controls (`workers`, `strategy`, `chunk_records`, `task_records`) remain
available but are not required for routine work.

Two internal execution strategies are retained because they have different
trade-offs:

- `parallel_chunks`: throughput-oriented, with independently owned vectorized
  chunks;
- `shared_chunk`: RAM-oriented, sharing one bounded input chunk with `mori`.

Automatic settings are based on structural workload, not XML vocabulary names
or corpus-specific filenames.

## Streaming, CSV and Parquet

A compiled profile can be applied without keeping the complete XML document in
memory:

```r
spec <- compile_xml_profile(profile, file)

rectangle_xml_csv(
  file,
  spec,
  output = "orders.csv",
  parallel = "auto"
)
```

For typed analytical output, Parquet is usually preferable:

```r
rectangle_xml_parquet(
  file,
  spec,
  output_dir = "orders-parquet",
  parallel = "auto"
)
```

Parquet support requires the optional `arrow` package.

## An even more automatic analyst table

When you want a single self-contained table for exploration rather than an
explicit reusable profile, use:

```r
analyst <- rectangle_xml_analyst(file)
```

This layer preserves universal `xml_*` provenance/entity columns and projects
analytical values into atomic columns. It is useful for inspection and data
exploration; explicit profiles remain preferable when you need a stable,
auditable extraction contract across a family of XML documents.

## XSD-assisted review

```r
xsd <- system.file("extdata", "types.xsd", package = "xmlrectr")
xml <- system.file("extdata", "types.xml", package = "xmlrectr")

proposal <- propose_xml_profile(xml, xsd = xsd)
review_xml_proposal(proposal, "xsd")
```

`inspect_xsd()` exposes useful direct declaration, occurrence, required-
attribute, and scalar-type evidence. It is deliberately **not** a complete XSD
processor or validator.

## What xmlrectr preserves

The underlying canonical representation records document order, parentage,
node identity, namespaces, attributes, text/CDATA and other retained XML node
types. Rectangle operations are designed to preserve repeated values and avoid
silent Cartesian multiplication.

Malformed XML is reported as an error. Repairing malformed XML is outside the
scope of the package.

## Documentation

- **Getting started:** `vignette("getting-started", package = "xmlrectr")`
- **Large XML, streaming and parallel execution:**
  `vignette("large-xml", package = "xmlrectr")`
- **Architecture and validation:** `vignette("development", package = "xmlrectr")`
- **Full engineering history and release checklist:** `DEVELOPMENT.md` in the
  repository.

The package website is built with pkgdown. The README becomes the website home
page, function documentation forms the reference section, and the vignettes
become articles.

## Development status

The package stage starts from the frozen P6.1 standalone engine. Before package
conversion that engine passed the complete unit suite, forced sequential/
parallel parity on 30 structurally diverse real-world XML files, and the same
30-file corpus through the unified `parallel = "auto"` interface.

See `DEVELOPMENT.md` for the validation boundary and the distinction between
package code and the separately maintained three-file standalone distribution.
