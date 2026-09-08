# Rectangle a canonical XML node table

Apply an explicit profile/specification while preserving repeated values
and output order. Parallelism is an execution option of the same public
workflow.

## Usage

``` r
xml_rectangle(
nodes,
spec,
parallel = FALSE,
workers = NULL,
strategy = "auto",
chunk_records = NULL,
task_records = NULL,
progress = FALSE)
```

## Arguments

- nodes:

  A canonical XML node table.

- spec:

  A compiled rectangle specification or an `xml_profile`.

- parallel:

  Execution mode: `FALSE`, `TRUE`, or `"auto"`.

- workers:

  Optional positive number of parallel workers.

- strategy:

  Parallel scheduling strategy or `"auto"`.

- chunk_records:

  Optional number of complete records in an outer processing chunk.

- task_records:

  Optional number of records per inner parallel task.

- progress:

  Logical; whether to emit progress events through progressr.

## Details

Use `parallel = FALSE` for the exact sequential path, `parallel = TRUE`
to request tuned parallel defaults, or `parallel = "auto"` to let the
engine avoid parallel overhead on small in-memory workloads.

## See also

[`xml_profile()`](https://larry77.github.io/xmlrectr/reference/xml_profile.md),
[`rectangle_xml()`](https://larry77.github.io/xmlrectr/reference/rectangle_xml.md)
