# Create a lower-level rectangle specification

Discover structural evidence and define a reviewable, reusable
extraction contract. Proposals and XSD evidence are advisory rather than
silently executable.

## Usage

``` r
make_rectangle(
structure,
one_row_per = NULL,
namespace = NULL,
identify_by = NULL,
fields = NULL,
types = NULL,
representation = c("auto", "wide", "long"))
```

## Arguments

- structure:

  An inspected XML structure returned by
  [`inspect_xml()`](https://larry77.github.io/xmlrectr/reference/inspect_xml.md).

- one_row_per:

  Optional visible element name or path defining one output record. If
  omitted, an unambiguous proposed record path is used.

- namespace:

  Optional namespace URI used to disambiguate the row element.

- identify_by:

  Optional visible value name or path used as the record identifier;
  omit to generate sequential identifiers.

- fields:

  Optional character vector of values to retain. Named entries rename
  output columns.

- types:

  Optional named character vector declaring output types for selected
  fields.

- representation:

  Requested table representation: automatic safe choice, wide, or long.

## See also

[`xml_profile()`](https://larry77.github.io/xmlrectr/reference/xml_profile.md),
[`rectangle_xml()`](https://larry77.github.io/xmlrectr/reference/rectangle_xml.md)
