# Expand analyst-table entity context

Create or work with the exploratory single-table analyst projection,
which keeps universal xml\_\* provenance/entity columns alongside atomic
analytical values.

## Usage

``` r
xml_analyst_expand_context(x, entity = NULL, levels = Inf)
```

## Arguments

- x:

  A table returned by
  [`xml_analyst_table()`](https://larry77.github.io/xmlrectr/reference/xml_analyst_table.md)
  or
  [`rectangle_xml_analyst()`](https://larry77.github.io/xmlrectr/reference/rectangle_xml_analyst.md).

- entity:

  Optional entity name or vector of entity names to retain.

- levels:

  Maximum number of ancestor-entity levels from which contextual values
  may be propagated; `Inf` means all available levels.

## See also

[`xml_profile()`](https://larry77.github.io/xmlrectr/reference/xml_profile.md),
[`rectangle_xml()`](https://larry77.github.io/xmlrectr/reference/rectangle_xml.md)
