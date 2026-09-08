# Stream complete XML records through a rectangle callback

Apply an explicit profile/specification while preserving repeated values
and output order. Parallelism is an execution option of the same public
workflow.

## Usage

``` r
xml_stream_rectangle(
file,
spec,
callback,
document_id = NULL,
whitespace = NULL,
chunk_rows = 100000L,
batch_rows = 100000L,
id_check = c("memory", "none"),
parallel = FALSE,
workers = NULL,
strategy = "auto",
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

- parallel:

  Execution mode: sequential, explicitly parallel, or automatic.

- workers:

  Optional positive number of parallel workers.

- strategy:

  Parallel scheduling strategy or `"auto"`.

- chunk_records:

  Optional number of complete XML records in an outer parallel chunk.

- task_records:

  Optional number of records per inner parallel task.

## Details

The streaming parser and record-boundary detection remain
coordinator-side. Parallel workers receive only complete independent
record subtrees.

## See also

[`xml_profile()`](https://larry77.github.io/xmlrectr/reference/xml_profile.md),
[`rectangle_xml()`](https://larry77.github.io/xmlrectr/reference/rectangle_xml.md)
