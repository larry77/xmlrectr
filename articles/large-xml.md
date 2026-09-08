# Large XML, streaming and parallel execution

``` r

library(xmlrectr)
```

## Compile once

Large-file workflows should normally begin with a reviewed profile and a
compiled specification:

``` r

file <- system.file("extdata", "orders.xml", package = "xmlrectr")
profile <- xml_profile(rows = "order", id = "id")
spec <- compile_xml_profile(profile, file)
```

The small bundled file is used only to make the examples reproducible.
The same functions are designed for much larger XML documents.

## In-memory execution

``` r

out <- rectangle_xml(
  "large.xml",
  spec,
  parallel = "auto"
)
```

The in-memory automatic decision examines independent record spans and
structural workload. It does not recognize filenames or XML
vocabularies.

## Streaming execution

For files that should not be represented as one complete canonical table
in memory, use the streaming engine:

``` r

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

SAX parsing and record-boundary detection remain coordinator-side.
Workers receive only complete independent record subtrees; libxml/xml2
external pointers and live parser state never cross a worker boundary.

## CSV output

``` r

rectangle_xml_csv(
  "large.xml",
  spec,
  output = "large.csv",
  parallel = "auto"
)
```

CSV publication is staged so a failed run does not silently publish a
partial final file.

## Parquet output

``` r

rectangle_xml_parquet(
  "large.xml",
  spec,
  output_dir = "large-parquet",
  compression = "snappy",
  parallel = "auto"
)
```

Parquet requires the optional `arrow` package and is the preferred
analytical backend when preserving declared column types and processing
large results.

## Automatic workers and scheduling

Most users should not need to specify workers, chunk sizes or task
sizes.

``` r

rectangle_xml("large.xml", spec, parallel = TRUE)
```

The balanced defaults use structural workload and available cores.
Advanced controls remain available when benchmarking or when a
machine-specific memory constraint matters:

``` r

rectangle_xml(
  "large.xml",
  spec,
  parallel = TRUE,
  workers = 8,
  strategy = "shared_chunk",
  chunk_records = 2048,
  task_records = 128
)
```

## The two parallel strategies

### `parallel_chunks`

This is throughput-oriented. Several independently owned vectorized
chunks can be processed concurrently. In-memory automatic execution
normally selects this strategy.

### `shared_chunk`

This is RAM-oriented. One bounded outer chunk is shared through `mori`,
and workers process coarse vectorized ranges from that shared input.
Empirical PSS measurements during development showed a real reduction in
memory pressure, so this strategy is intentionally retained even when
independently owned chunks are sometimes faster.

## Why streaming auto does not pre-count the XML

An in-memory call already owns the complete canonical table, so the
scheduler can cheaply inspect record spans before choosing sequential or
parallel work. Streaming is different: making a complete preliminary
pass just to count records would undermine the bounded single-pass
design. Therefore streaming auto does not add a second full scan merely
for presentation or scheduling.

## Correctness invariants

Sequential and parallel execution must produce the same rectangle.
Parallel scheduling may change completion order internally, but the
coordinator restores source/document order before publishing results and
keeps global identifier checks and writers coordinator-side.
