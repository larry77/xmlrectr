testthat::test_that("the empty canonical schema is stable", {
  empty <- xml_nodes_schema()

  testthat::expect_s3_class(empty, "tbl_df")
  testthat::expect_identical(names(empty), .xml_node_columns)
  testthat::expect_true(validate_xml_nodes(empty))
})


testthat::test_that("orders remain nested, repeated, and character-faithful", {
  nodes <- xml_to_nodes_memory(
    fixture_path("orders.xml"),
    whitespace = "drop_blank"
  )

  testthat::expect_true(validate_xml_nodes(nodes))
  testthat::expect_identical(nodes$node_id, seq_len(nrow(nodes)))
  testthat::expect_false(
    any(
      nodes$node_type == "text" &
        grepl("^[[:space:]]*$", nodes$value)
    )
  )

  elements <- nodes[nodes$node_type == "element", , drop = FALSE]
  order_ids <- elements$node_id[elements$local_name == "order"]
  item_rows <- elements[
    elements$local_name == "item" &
      elements$parent_id %in% order_ids,
    ,
    drop = FALSE
  ]

  testthat::expect_length(order_ids, 2L)
  testthat::expect_equal(nrow(item_rows), 3L)

  postal_code <- elements$node_id[
    elements$local_name == "postal-code"
  ]

  postal_text <- nodes$value[
    nodes$parent_id == postal_code &
      nodes$node_type == "text"
  ]

  # Leading zeroes demonstrate why raw XML values must remain character data
  # until an explicit rectangling specification requests type conversion.
  testthat::expect_identical(postal_text, "00123")
})


testthat::test_that("malformed XML raises a dedicated parse error", {
  condition <- tryCatch(
    inspect_xml(fixture_path("malformed.xml")),
    xml_parse_error = function(condition) condition
  )

  testthat::expect_s3_class(condition, "xml_parse_error")
  testthat::expect_match(
    conditionMessage(condition),
    "Could not parse XML source"
  )
})


testthat::test_that("whitespace policy is explicit and local", {
  preserved <- xml_to_nodes_memory(
    fixture_path("orders.xml"),
    whitespace = "preserve"
  )

  dropped <- xml_to_nodes_memory(
    fixture_path("orders.xml"),
    whitespace = "drop_blank"
  )

  blank_text <- preserved$node_type == "text" &
    grepl("^[[:space:]]*$", preserved$value)

  testthat::expect_true(any(blank_text))
  testthat::expect_gt(nrow(preserved), nrow(dropped))
  testthat::expect_true(validate_xml_nodes(preserved))
  testthat::expect_true(validate_xml_nodes(dropped))
})


testthat::test_that("mixed text is not collapsed into an element value", {
  nodes <- xml_to_nodes_memory(
    fixture_path("mixed-content.xml"),
    whitespace = "drop_blank"
  )

  paragraph_id <- nodes$node_id[
    nodes$node_type == "element" &
      nodes$local_name == "p"
  ]

  paragraph_contents <- xml_node_children(nodes, paragraph_id)

  testthat::expect_identical(
    paragraph_contents$node_type,
    c("text", "element", "text")
  )

  testthat::expect_identical(
    paragraph_contents$value,
    c("Hello ", NA_character_, " world & friends.")
  )

  emphasized_id <- paragraph_contents$node_id[
    paragraph_contents$node_type == "element"
  ]

  testthat::expect_identical(
    xml_node_children(nodes, emphasized_id)$value,
    "very"
  )

  testthat::expect_true(any(nodes$node_type == "cdata"))
  testthat::expect_true(any(nodes$node_type == "comment"))
  testthat::expect_true(any(nodes$node_type == "pi"))
  testthat::expect_identical(
    nodes$value[nodes$node_type == "cdata"],
    "2 < 3 and 5 > 4"
  )
})


testthat::test_that("document-level nodes have an explicit parent", {
  nodes <- xml_to_nodes_memory(
    fixture_path("document-misc.xml"),
    whitespace = "drop_blank"
  )

  document_id <- nodes$node_id[nodes$node_type == "document"]
  top_level <- xml_node_children(nodes, document_id)

  testthat::expect_identical(
    top_level$node_type,
    c("pi", "comment", "element", "comment", "pi")
  )
  testthat::expect_identical(
    top_level$sibling_order,
    seq_len(nrow(top_level))
  )
})


testthat::test_that("namespace identity is explicit for elements and attributes", {
  nodes <- xml_to_nodes_memory(
    fixture_path("namespaces.xml"),
    whitespace = "drop_blank"
  )

  a_item <- nodes[
    nodes$node_type == "element" &
      nodes$qualified_name == "a:item",
    ,
    drop = FALSE
  ]

  b_item <- nodes[
    nodes$node_type == "element" &
      nodes$qualified_name == "b:item",
    ,
    drop = FALSE
  ]

  a_id <- nodes[
    nodes$node_type == "attribute" &
      nodes$qualified_name == "a:id",
    ,
    drop = FALSE
  ]

  testthat::expect_identical(a_item$local_name, "item")
  testthat::expect_identical(a_item$prefix, "a")
  testthat::expect_identical(a_item$namespace_uri, "urn:example:a")
  testthat::expect_identical(b_item$namespace_uri, "urn:example:b")
  testthat::expect_identical(a_id$namespace_uri, "urn:example:a")
  testthat::expect_identical(a_id$value, "42")
})


testthat::test_that("MARCXML values and blank indicators survive the generic layer", {
  nodes <- xml_to_nodes_memory(
    fixture_path("marc-mini.xml"),
    whitespace = "drop_blank"
  )

  records <- nodes[
    nodes$node_type == "element" &
      nodes$local_name == "record",
    ,
    drop = FALSE
  ]

  controlfields <- nodes$node_id[
    nodes$node_type == "element" &
      nodes$local_name == "controlfield"
  ]

  control_values <- nodes$value[
    nodes$node_type == "text" &
      nodes$parent_id %in% controlfields
  ]

  blank_indicators <- nodes$value[
    nodes$node_type == "attribute" &
      nodes$local_name == "ind2"
  ]

  testthat::expect_equal(nrow(records), 2L)
  testthat::expect_true(
    all(records$namespace_uri == "http://www.loc.gov/MARC21/slim")
  )
  testthat::expect_true("  12345 " %in% control_values)
  testthat::expect_true(" " %in% blank_indicators)
})


testthat::test_that("the builder grows without changing the contract", {
  count <- 1500L
  items <- paste0(
    "<item id=\"",
    seq_len(count),
    "\">value</item>",
    collapse = ""
  )

  nodes <- xml_text_to_nodes_memory(
    paste0("<root>", items, "</root>"),
    document_id = "generated",
    whitespace = "drop_blank",
    initial_capacity = 4L
  )

  testthat::expect_equal(
    sum(
      nodes$node_type == "element" &
        nodes$local_name == "item"
    ),
    count
  )

  testthat::expect_true(validate_xml_nodes(nodes))
})


testthat::test_that("invalid XML and broken relationships fail clearly", {
  testthat::expect_error(
    xml_to_nodes_memory(fixture_path("malformed.xml")),
    "Could not parse XML source"
  )

  nodes <- xml_to_nodes_memory(
    fixture_path("orders.xml"),
    whitespace = "drop_blank"
  )

  broken <- nodes
  first_child <- which(!is.na(broken$parent_id))[[1L]]
  broken$parent_id[[first_child]] <- 999999L

  testthat::expect_error(
    validate_xml_nodes(broken),
    "missing parent"
  )
})


testthat::test_that("DTD declarations are parser metadata, not canonical rows", {
  xml <- tempfile(fileext = ".xml")
  on.exit(unlink(xml), add = TRUE)

  writeLines(
    c(
      '<?xml version="1.0"?>',
      '<!DOCTYPE root [<!ELEMENT root (#PCDATA)>]>',
      '<root>value</root>'
    ),
    xml,
    useBytes = TRUE
  )

  nodes <- xml_to_nodes_memory(xml, whitespace = "drop_blank")

  testthat::expect_false(any(nodes$node_type == "dtd"))
  testthat::expect_identical(
    nodes$node_type,
    c("document", "element", "text")
  )
  testthat::expect_identical(nodes$node_id, 1:3)
  testthat::expect_identical(nodes$parent_id, c(NA_integer_, 1L, 2L))
  testthat::expect_identical(nodes$sibling_order, c(NA_integer_, 1L, 1L))
})
