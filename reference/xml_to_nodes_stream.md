# Read XML with the sequential streaming canonical engine

Work with the canonical XML-node representation that preserves node
identity, parentage, source order, namespaces, node types and scalar
values.

## Usage

``` r
xml_to_nodes_stream(
file,
document_id = NULL,
whitespace = c("preserve", "drop_blank"),
chunk_rows = 100000L)
```

## Arguments

- file:

  Path to the XML file.

- document_id:

  Optional identifier attached to canonical rows; by default it is
  derived from the input file.

- whitespace:

  How blank text nodes are handled.

- chunk_rows:

  Positive maximum number of canonical rows buffered per emitted chunk.

## See also

[`xml_profile()`](https://larry77.github.io/xmlrectr/reference/xml_profile.md),
[`rectangle_xml()`](https://larry77.github.io/xmlrectr/reference/rectangle_xml.md)
