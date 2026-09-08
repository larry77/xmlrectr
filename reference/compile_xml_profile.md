# Compile a profile into an executable rectangle specification

Discover structural evidence and define a reviewable, reusable
extraction contract. Proposals and XSD evidence are advisory rather than
silently executable.

## Usage

``` r
compile_xml_profile(
profile,
sample,
whitespace = c("drop_blank", "preserve"))
```

## Arguments

- profile:

  A human-facing profile created by
  [`xml_profile()`](https://larry77.github.io/xmlrectr/reference/xml_profile.md)
  or coercible with
  [`as_xml_profile()`](https://larry77.github.io/xmlrectr/reference/as_xml_profile.md).

- sample:

  A representative XML sample accepted by
  [`rectangle_spec()`](https://larry77.github.io/xmlrectr/reference/rectangle_spec.md),
  or a previously inspected `xml_structure`.

- whitespace:

  How blank text nodes are handled while inspecting the sample:
  `"drop_blank"` or `"preserve"`.

## See also

[`xml_profile()`](https://larry77.github.io/xmlrectr/reference/xml_profile.md),
[`rectangle_xml()`](https://larry77.github.io/xmlrectr/reference/rectangle_xml.md)
