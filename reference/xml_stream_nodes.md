# Stream canonical XML node batches

Work with the canonical XML-node representation that preserves node
identity, parentage, source order, namespaces, node types and scalar
values.

## Usage

``` r
xml_stream_nodes(
file,
callback,
document_id = NULL,
whitespace = c("preserve", "drop_blank"),
chunk_rows = 100000L)
```

## Arguments

- file:

  Path to the XML file.

- callback:

  Function called with each emitted canonical node-table chunk.

- document_id:

  Optional identifier attached to canonical rows; by default it is
  derived from the input file.

- whitespace:

  How blank text nodes are handled.

- chunk_rows:

  Positive maximum number of canonical rows buffered before the callback
  is invoked.

## See also

[`xml_profile()`](https://larry77.github.io/xmlrectr/reference/xml_profile.md),
[`rectangle_xml()`](https://larry77.github.io/xmlrectr/reference/rectangle_xml.md)
