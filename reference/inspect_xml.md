# Inspect XML structure before defining a rectangle

Work with the canonical XML-node representation that preserves node
identity, parentage, source order, namespaces, node types and scalar
values.

## Usage

``` r
inspect_xml(
x,
whitespace = c("drop_blank", "preserve"))
```

## Arguments

- x:

  An XML file path or an existing canonical node table.

- whitespace:

  How blank text nodes are handled when an XML file is read.

## See also

[`xml_profile()`](https://larry77.github.io/xmlrectr/reference/xml_profile.md),
[`rectangle_xml()`](https://larry77.github.io/xmlrectr/reference/rectangle_xml.md)
