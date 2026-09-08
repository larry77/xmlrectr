# Package index

## Package overview

- [`xmlrectr`](https://larry77.github.io/xmlrectr/reference/xmlrectr-package.md)
  [`xmlrectr-package`](https://larry77.github.io/xmlrectr/reference/xmlrectr-package.md)
  : xmlrectr: generic XML rectangling

## Discover XML structure

Canonical readers and structural inspection.

- [`xml_nodes_schema()`](https://larry77.github.io/xmlrectr/reference/xml_nodes_schema.md)
  : Return the canonical XML node-table schema
- [`xml_to_nodes_memory()`](https://larry77.github.io/xmlrectr/reference/xml_to_nodes_memory.md)
  : Read an XML file into the canonical node table
- [`xml_text_to_nodes_memory()`](https://larry77.github.io/xmlrectr/reference/xml_text_to_nodes_memory.md)
  : Read XML text into the canonical node table
- [`xml_stream_nodes()`](https://larry77.github.io/xmlrectr/reference/xml_stream_nodes.md)
  : Stream canonical XML node batches
- [`xml_to_nodes_stream()`](https://larry77.github.io/xmlrectr/reference/xml_to_nodes_stream.md)
  : Read XML with the sequential streaming canonical engine
- [`validate_xml_nodes()`](https://larry77.github.io/xmlrectr/reference/validate_xml_nodes.md)
  : Validate the canonical XML node-table contract
- [`xml_node_children()`](https://larry77.github.io/xmlrectr/reference/xml_node_children.md)
  : Return direct canonical children of XML nodes
- [`inspect_xml()`](https://larry77.github.io/xmlrectr/reference/inspect_xml.md)
  : Inspect XML structure before defining a rectangle

## Proposals and profiles

Review structural evidence and define reusable extraction contracts.

- [`propose_xml_profile()`](https://larry77.github.io/xmlrectr/reference/propose_xml_profile.md)
  : Propose candidate rows, identifiers and fields
- [`review_xml_proposal()`](https://larry77.github.io/xmlrectr/reference/review_xml_proposal.md)
  : Review one part of an XML profile proposal
- [`xml_profile()`](https://larry77.github.io/xmlrectr/reference/xml_profile.md)
  : Create a human-facing reusable XML profile
- [`as_xml_profile()`](https://larry77.github.io/xmlrectr/reference/as_xml_profile.md)
  : Coerce a portable object to an XML profile
- [`write_xml_profile()`](https://larry77.github.io/xmlrectr/reference/write_xml_profile.md)
  : Write an XML profile to JSON or YAML
- [`read_xml_profile()`](https://larry77.github.io/xmlrectr/reference/read_xml_profile.md)
  : Read an XML profile from JSON or YAML
- [`compile_xml_profile()`](https://larry77.github.io/xmlrectr/reference/compile_xml_profile.md)
  : Compile a profile into an executable rectangle specification
- [`inspect_xsd()`](https://larry77.github.io/xmlrectr/reference/inspect_xsd.md)
  : Inspect advisory XSD evidence
- [`make_rectangle()`](https://larry77.github.io/xmlrectr/reference/make_rectangle.md)
  : Create a lower-level rectangle specification
- [`rectangle_spec()`](https://larry77.github.io/xmlrectr/reference/rectangle_spec.md)
  : Create an explicit rectangle specification
- [`review_rectangle()`](https://larry77.github.io/xmlrectr/reference/review_rectangle.md)
  : Review a compiled rectangle specification

## Rectangle XML

In-memory, streaming, CSV and Parquet execution through the unified
interface.

- [`xml_rectangle()`](https://larry77.github.io/xmlrectr/reference/xml_rectangle.md)
  : Rectangle a canonical XML node table
- [`rectangle_xml()`](https://larry77.github.io/xmlrectr/reference/rectangle_xml.md)
  : Read and rectangle an XML file
- [`xml_stream_rectangle()`](https://larry77.github.io/xmlrectr/reference/xml_stream_rectangle.md)
  : Stream complete XML records through a rectangle callback
- [`rectangle_xml_csv()`](https://larry77.github.io/xmlrectr/reference/rectangle_xml_csv.md)
  : Rectangle XML to a staged CSV file
- [`rectangle_xml_parquet()`](https://larry77.github.io/xmlrectr/reference/rectangle_xml_parquet.md)
  : Rectangle XML to a staged Parquet dataset

## Analyst-oriented table

- [`xml_analyst_table()`](https://larry77.github.io/xmlrectr/reference/xml_analyst_table.md)
  : Project canonical XML into one analyst-oriented table
- [`xml_analyst_expand_context()`](https://larry77.github.io/xmlrectr/reference/xml_analyst_expand_context.md)
  : Expand analyst-table entity context
- [`rectangle_xml_analyst()`](https://larry77.github.io/xmlrectr/reference/rectangle_xml_analyst.md)
  : Create an analyst-oriented table directly from XML
- [`rectangle_xml_analyst_csv()`](https://larry77.github.io/xmlrectr/reference/rectangle_xml_analyst_csv.md)
  : Write the analyst-oriented XML table to CSV
- [`rectangle_xml_analyst_parquet()`](https://larry77.github.io/xmlrectr/reference/rectangle_xml_analyst_parquet.md)
  : Write the analyst-oriented XML table to Parquet

## Advanced parallel execution

Explicit low-level entry points retained for diagnostics and tuning.

- [`xml_rectangle_parallel()`](https://larry77.github.io/xmlrectr/reference/xml_rectangle_parallel.md)
  : Rectangle canonical nodes with explicit parallel execution
- [`rectangle_xml_parallel()`](https://larry77.github.io/xmlrectr/reference/rectangle_xml_parallel.md)
  : Read and rectangle XML with explicit parallel execution
- [`xml_stream_rectangle_parallel()`](https://larry77.github.io/xmlrectr/reference/xml_stream_rectangle_parallel.md)
  : Stream XML records with explicit parallel execution
