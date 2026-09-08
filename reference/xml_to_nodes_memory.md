# Read an XML file into the canonical node table

Work with the canonical XML-node representation that preserves node
identity, parentage, source order, namespaces, node types and scalar
values.

## Usage

``` r
xml_to_nodes_memory(
file,
document_id = NULL,
whitespace = c("preserve", "drop_blank"),
initial_capacity = 1024L)
```

## Arguments

- file:

  Path to the XML file.

- document_id:

  Optional identifier attached to all canonical rows; by default it is
  derived from the input file.

- whitespace:

  How blank text nodes are handled.

- initial_capacity:

  Positive initial size of the internal row buffer; it grows
  automatically as needed.

## See also

[`xml_profile()`](https://larry77.github.io/xmlrectr/reference/xml_profile.md),
[`rectangle_xml()`](https://larry77.github.io/xmlrectr/reference/rectangle_xml.md)
