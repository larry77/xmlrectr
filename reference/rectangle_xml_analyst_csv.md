# Write the analyst-oriented XML table to CSV

Create or work with the exploratory single-table analyst projection,
which keeps universal xml\_\* provenance/entity columns alongside atomic
analytical values.

## Usage

``` r
rectangle_xml_analyst_csv(
file,
output,
whitespace = c("drop_blank", "preserve"),
infer_types = TRUE,
include_misc = TRUE,
na = "\\N",
overwrite = FALSE)
```

## Arguments

- file:

  Path to the XML file.

- output:

  Destination CSV file.

- whitespace:

  How blank text nodes are handled.

- infer_types:

  Logical; whether conservative scalar type inference is applied.

- include_misc:

  Logical; whether miscellaneous XML content/provenance columns are
  retained.

- na:

  Character string written for missing values.

- overwrite:

  Logical; whether an existing destination may be replaced.

## See also

[`xml_profile()`](https://larry77.github.io/xmlrectr/reference/xml_profile.md),
[`rectangle_xml()`](https://larry77.github.io/xmlrectr/reference/rectangle_xml.md)
