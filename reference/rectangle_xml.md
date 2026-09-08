# Read and rectangle an XML file

Apply an explicit profile/specification while preserving repeated values
and output order. Parallelism is an execution option of the same public
workflow.

## Usage

``` r
rectangle_xml(
file,
spec,
whitespace = NULL,
parallel = FALSE,
workers = NULL,
strategy = "auto",
chunk_records = NULL,
task_records = NULL,
progress = FALSE)
```

## Arguments

- file:

  Path to the XML file to rectangle in memory.

- spec:

  A compiled rectangle specification or an `xml_profile`.

- whitespace:

  Optional blank-text policy. When omitted, the policy stored in the
  specification/profile is used.

- parallel:

  Execution mode: `FALSE` for sequential, `TRUE` for parallel, or
  `"auto"` to choose automatically.

- workers:

  Optional positive number of parallel workers. When omitted, a balanced
  default is chosen.

- strategy:

  Parallel scheduling strategy. `"auto"` chooses the context-appropriate
  default.

- chunk_records:

  Optional number of complete records in an outer processing chunk.

- task_records:

  Optional number of records assigned to each inner parallel task.

- progress:

  Logical; whether to emit progress events through progressr for
  supported in-memory parallel execution.

## Details

Use `parallel = FALSE` for the exact sequential path, `parallel = TRUE`
to request tuned parallel defaults, or `parallel = "auto"` to let the
engine avoid parallel overhead on small in-memory workloads.

## See also

[`xml_profile()`](https://larry77.github.io/xmlrectr/reference/xml_profile.md),
`rectangle_xml()`
