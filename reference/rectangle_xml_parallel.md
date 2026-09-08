# Read and rectangle XML with explicit parallel execution

Lower-level explicit parallel entry point retained for diagnostics,
regression tests and advanced tuning. Routine use should normally use
the corresponding ordinary function with the parallel argument.

## Usage

``` r
rectangle_xml_parallel(
file,
spec,
whitespace = NULL,
workers = NULL,
strategy = c("shared_chunk", "parallel_chunks"),
chunk_records = NULL,
task_records = NULL,
progress = FALSE)
```

## Arguments

- file:

  Path to the XML file.

- spec:

  A compiled rectangle specification or an `xml_profile`.

- whitespace:

  Optional blank-text policy.

- workers:

  Optional positive number of parallel workers.

- strategy:

  Parallel scheduling strategy.

- chunk_records:

  Optional number of complete records in an outer processing chunk.

- task_records:

  Optional number of records per inner task.

- progress:

  Logical; whether to emit progress events through progressr.

## See also

[`xml_profile()`](https://larry77.github.io/xmlrectr/reference/xml_profile.md),
[`rectangle_xml()`](https://larry77.github.io/xmlrectr/reference/rectangle_xml.md)
