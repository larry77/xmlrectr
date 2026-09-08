# Write an XML profile to JSON or YAML

Discover structural evidence and define a reviewable, reusable
extraction contract. Proposals and XSD evidence are advisory rather than
silently executable.

## Usage

``` r
write_xml_profile(
profile,
file,
format = c("auto", "json", "yaml"),
overwrite = FALSE)
```

## Arguments

- profile:

  An `xml_profile` or compatible profile object.

- file:

  Destination JSON or YAML file.

- format:

  Serialization format. `"auto"` infers it from the destination
  extension.

- overwrite:

  Logical; whether an existing destination may be replaced.

## See also

[`xml_profile()`](https://larry77.github.io/xmlrectr/reference/xml_profile.md),
[`rectangle_xml()`](https://larry77.github.io/xmlrectr/reference/rectangle_xml.md)
