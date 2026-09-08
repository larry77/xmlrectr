# Create a human-facing reusable XML profile

Discover structural evidence and define a reviewable, reusable
extraction contract. Proposals and XSD evidence are advisory rather than
silently executable.

## Usage

``` r
xml_profile(
rows,
id = NULL,
fields = NULL,
types = NULL,
namespace = NULL,
layout = c("safe", "wide", "long"))
```

## Arguments

- rows:

  Visible XML element name or path defining one output record.

- id:

  Optional visible value name/path used as record identifier; omit or
  use `FALSE` for generated IDs.

- fields:

  Optional character vector of values to retain. Named entries rename
  output columns.

- types:

  Optional named character vector declaring output types.

- namespace:

  Optional namespace URI used to disambiguate the row element.

- layout:

  One-table layout policy: safe automatic layout, explicitly wide, or
  explicitly long.

## See also

`xml_profile()`,
[`rectangle_xml()`](https://larry77.github.io/xmlrectr/reference/rectangle_xml.md)
