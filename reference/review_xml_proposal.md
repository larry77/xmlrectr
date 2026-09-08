# Review one part of an XML profile proposal

Discover structural evidence and define a reviewable, reusable
extraction contract. Proposals and XSD evidence are advisory rather than
silently executable.

## Usage

``` r
review_xml_proposal(
proposal,
what = c("rows", "ids", "fields", "xsd"))
```

## Arguments

- proposal:

  A proposal returned by
  [`propose_xml_profile()`](https://larry77.github.io/xmlrectr/reference/propose_xml_profile.md).

- what:

  Which proposal component to review: row candidates, ID candidates,
  fields, or XSD evidence.

## See also

[`xml_profile()`](https://larry77.github.io/xmlrectr/reference/xml_profile.md),
[`rectangle_xml()`](https://larry77.github.io/xmlrectr/reference/rectangle_xml.md)
