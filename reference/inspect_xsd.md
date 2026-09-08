# Inspect advisory XSD evidence

Discover structural evidence and define a reviewable, reusable
extraction contract. Proposals and XSD evidence are advisory rather than
silently executable.

## Usage

``` r
inspect_xsd(xsd)
```

## Arguments

- xsd:

  Path to an XML Schema (XSD) file to inspect as advisory structural
  evidence.

## Details

This is deliberately an advisory XSD inspection layer, not a complete
XSD validator or resolver.

## See also

[`xml_profile()`](https://larry77.github.io/xmlrectr/reference/xml_profile.md),
[`rectangle_xml()`](https://larry77.github.io/xmlrectr/reference/rectangle_xml.md)
