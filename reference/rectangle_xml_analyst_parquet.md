# Write the analyst-oriented XML table to Parquet

Create or work with the exploratory single-table analyst projection,
which keeps universal xml\_\* provenance/entity columns alongside atomic
analytical values.

## Usage

``` r
rectangle_xml_analyst_parquet(
file,
output,
whitespace = c("drop_blank", "preserve"),
infer_types = TRUE,
include_misc = TRUE,
overwrite = FALSE,
compression = "snappy")
```

## Arguments

- file:

  Path to the XML file.

- output:

  Destination Parquet file.

- whitespace:

  How blank text nodes are handled.

- infer_types:

  Logical; whether conservative scalar type inference is applied.

- include_misc:

  Logical; whether miscellaneous XML content/provenance columns are
  retained.

- overwrite:

  Logical; whether an existing destination may be replaced.

- compression:

  Parquet compression codec passed to arrow.

## See also

[`xml_profile()`](https://larry77.github.io/xmlrectr/reference/xml_profile.md),
[`rectangle_xml()`](https://larry77.github.io/xmlrectr/reference/rectangle_xml.md)
