# Project canonical XML into one analyst-oriented table

Create or work with the exploratory single-table analyst projection,
which keeps universal xml\_\* provenance/entity columns alongside atomic
analytical values.

## Usage

``` r
xml_analyst_table(
nodes,
infer_types = TRUE,
include_misc = TRUE,
.validate_nodes = TRUE)
```

## Arguments

- nodes:

  A canonical XML node table.

- infer_types:

  Logical; whether conservative scalar type inference is applied to
  analyst data columns.

- include_misc:

  Logical; whether miscellaneous XML content/provenance columns are
  retained.

- .validate_nodes:

  Internal logical fast-path control. Ordinary callers should leave this
  at `TRUE`.

## See also

[`xml_profile()`](https://larry77.github.io/xmlrectr/reference/xml_profile.md),
[`rectangle_xml()`](https://larry77.github.io/xmlrectr/reference/rectangle_xml.md)
