# Create an analyst-oriented table directly from XML

Create or work with the exploratory single-table analyst projection,
which keeps universal xml\_\* provenance/entity columns alongside atomic
analytical values.

## Usage

``` r
rectangle_xml_analyst(
file,
whitespace = c("drop_blank", "preserve"),
infer_types = TRUE,
include_misc = TRUE)
```

## Arguments

- file:

  Path to the XML file.

- whitespace:

  How blank text nodes are handled.

- infer_types:

  Logical; whether conservative scalar type inference is applied to
  analyst data columns.

- include_misc:

  Logical; whether miscellaneous XML content/provenance columns are
  retained.

## See also

[`xml_profile()`](https://larry77.github.io/xmlrectr/reference/xml_profile.md),
[`rectangle_xml()`](https://larry77.github.io/xmlrectr/reference/rectangle_xml.md)
