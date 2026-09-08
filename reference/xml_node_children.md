# Return direct canonical children of XML nodes

Work with the canonical XML-node representation that preserves node
identity, parentage, source order, namespaces, node types and scalar
values.

## Usage

``` r
xml_node_children(
nodes,
node_id,
document_id = NULL,
include_attributes = FALSE)
```

## Arguments

- nodes:

  A canonical XML node table.

- node_id:

  Positive canonical node identifier whose children are requested.

- document_id:

  Optional document identifier used to disambiguate node IDs in combined
  tables.

- include_attributes:

  Logical; whether attribute rows owned by the node are included with
  child content.

## See also

[`xml_profile()`](https://larry77.github.io/xmlrectr/reference/xml_profile.md),
[`rectangle_xml()`](https://larry77.github.io/xmlrectr/reference/rectangle_xml.md)
