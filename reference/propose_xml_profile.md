# Propose candidate rows, identifiers and fields

Discover structural evidence and define a reviewable, reusable
extraction contract. Proposals and XSD evidence are advisory rather than
silently executable.

## Usage

``` r
propose_xml_profile(
sample,
rows = NULL,
namespace = NULL,
xsd = NULL,
whitespace = c("drop_blank", "preserve"))
```

## Arguments

- sample:

  An XML sample accepted by
  [`inspect_xml()`](https://larry77.github.io/xmlrectr/reference/inspect_xml.md)
  or an existing `xml_structure`.

- rows:

  Optional visible row element name or path to evaluate instead of
  relying only on automatic row candidates.

- namespace:

  Optional namespace URI used to disambiguate row candidates.

- xsd:

  Optional XSD file whose directly declared structure is added as
  advisory evidence.

- whitespace:

  How blank text nodes are handled while inspecting the XML sample.

## Details

The returned proposal is review-only and is not an executable profile.

## See also

[`xml_profile()`](https://larry77.github.io/xmlrectr/reference/xml_profile.md),
[`rectangle_xml()`](https://larry77.github.io/xmlrectr/reference/rectangle_xml.md)
