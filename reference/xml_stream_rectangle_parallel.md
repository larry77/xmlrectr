# Stream XML records with explicit parallel execution

Lower-level explicit parallel entry point retained for diagnostics,
regression tests and advanced tuning. Routine use should normally use
the corresponding ordinary function with the parallel argument.

## Usage

``` r
xml_stream_rectangle_parallel(
file,
spec,
callback,
document_id = NULL,
whitespace = NULL,
chunk_rows = 100000L,
batch_rows = 100000L,
id_check = c("memory", "none"),
workers = NULL,
strategy = c("shared_chunk", "parallel_chunks"),
chunk_records = NULL,
task_records = NULL)
```

## Arguments

- file:

  Path to the XML file.

- spec:

  A compiled rectangle specification.

- callback:

  Function called with each emitted rectangled result batch.

- document_id:

  Optional identifier attached to canonical rows.

- whitespace:

  Optional blank-text policy; when omitted, the specification policy is
  used.

- chunk_rows:

  Positive number controlling the canonical SAX node-buffer capacity.

- batch_rows:

  Maximum number of rectangled rows passed to a callback batch.

- id_check:

  For source identifiers, `"memory"` checks global uniqueness; `"none"`
  avoids retaining the uniqueness set.

- workers:

  Optional positive number of parallel workers.

- strategy:

  Parallel scheduling strategy.

- chunk_records:

  Optional number of complete XML records in an outer parallel chunk.

- task_records:

  Optional number of records per inner parallel task.

## See also

[`xml_profile()`](https://larry77.github.io/xmlrectr/reference/xml_profile.md),
[`rectangle_xml()`](https://larry77.github.io/xmlrectr/reference/rectangle_xml.md)
