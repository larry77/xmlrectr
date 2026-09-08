# Read an XML profile from JSON or YAML

Discover structural evidence and define a reviewable, reusable
extraction contract. Proposals and XSD evidence are advisory rather than
silently executable.

## Usage

``` r
read_xml_profile(
file,
format = c("auto", "json", "yaml"))
```

## Arguments

- file:

  Path to a serialized XML profile.

- format:

  Profile serialization format. `"auto"` infers JSON or YAML from the
  filename extension.

## See also

[`xml_profile()`](https://larry77.github.io/xmlrectr/reference/xml_profile.md),
[`rectangle_xml()`](https://larry77.github.io/xmlrectr/reference/rectangle_xml.md)
