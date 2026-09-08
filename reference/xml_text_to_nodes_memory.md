# Read XML text into the canonical node table

Work with the canonical XML-node representation that preserves node
identity, parentage, source order, namespaces, node types and scalar
values.

## Usage

``` r
xml_text_to_nodes_memory(
text,
document_id = "inline-xml",
whitespace = c("preserve", "drop_blank"),
initial_capacity = 1024L)
```

## Arguments

- text:

  One character string containing XML markup.

- document_id:

  Identifier assigned to all canonical rows from the supplied XML text.

- whitespace:

  How blank text nodes are handled.

- initial_capacity:

  Positive initial size of the internal row buffer; it grows
  automatically as needed.

## See also

[`xml_profile()`](https://larry77.github.io/xmlrectr/reference/xml_profile.md),
[`rectangle_xml()`](https://larry77.github.io/xmlrectr/reference/rectangle_xml.md)
