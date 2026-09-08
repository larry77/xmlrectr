testthat::test_that("analyst projection stays one atomic table", {
  result <- rectangle_xml_analyst(fixture_path("analyst-features.xml"))

  testthat::expect_s3_class(result, "tbl_df")
  testthat::expect_false(any(vapply(result, is.list, logical(1))))
  testthat::expect_equal(nrow(result), 7L)
  entity_counts <- table(result$xml_entity)
  expected_counts <- c(catalog = 1L, item = 2L, payment = 2L, xml_misc = 2L)

  testthat::expect_setequal(names(entity_counts), names(expected_counts))
  testthat::expect_equal(
    unname(as.integer(entity_counts[names(expected_counts)])),
    unname(as.integer(expected_counts))
  )
})


testthat::test_that("independent repeated branches do not form a Cartesian product", {
  result <- rectangle_xml_analyst(
    fixture_path("independent-repeats.xml"),
    include_misc = FALSE
  )

  testthat::expect_equal(sum(result$xml_entity == "item"), 2L)
  testthat::expect_equal(sum(result$xml_entity == "payment"), 2L)
  testthat::expect_equal(nrow(result), 5L)

  item <- result[result$xml_entity == "item", , drop = FALSE]
  payment <- result[result$xml_entity == "payment", , drop = FALSE]

  testthat::expect_equal(
    item$shipments__shipment__attr_id,
    c("S-001", "S-001")
  )
  testthat::expect_equal(
    payment$shipments__shipment__attr_id,
    c("S-001", "S-001")
  )
  testthat::expect_equal(item$item__attr_sku, c("A-10", "B-20"))
  testthat::expect_equal(payment$payment__attr_method, c("card", "voucher"))
})


testthat::test_that("singleton context is folded into descendant entity rows", {
  result <- rectangle_xml_analyst(
    fixture_path("analyst-features.xml"),
    include_misc = FALSE
  )
  item <- result[result$xml_entity == "item", , drop = FALSE]
  payment <- result[result$xml_entity == "payment", , drop = FALSE]

  testthat::expect_true("catalog__group__attr_id" %in% names(result))
  testthat::expect_equal(item$catalog__group__attr_id, c("G-1", "G-1"))
  testthat::expect_equal(payment$catalog__group__attr_id, c("G-1", "G-1"))
  testthat::expect_equal(item$catalog__group__attr_note, c("", ""))
})


testthat::test_that("context flows downward but repeated child values never flow upward", {
  result <- rectangle_xml_analyst(
    fixture_path("orders.xml"),
    include_misc = FALSE
  )
  root <- result[result$xml_entity == "orders", , drop = FALSE]
  order <- result[result$xml_entity == "order", , drop = FALSE]
  item <- result[result$xml_entity == "item", , drop = FALSE]

  testthat::expect_true(all(is.na(root$item__attr_sku)))
  testthat::expect_true(all(is.na(order$item__attr_sku)))
  testthat::expect_equal(
    item$order__attr_id,
    c("A-001", "A-001", "A-002")
  )
  testthat::expect_equal(
    item$order__customer__name,
    c("Ana Silva", "Ana Silva", "Marc Dubois")
  )
})


testthat::test_that("empty elements and mixed content are analyst-visible", {
  result <- rectangle_xml_analyst(
    fixture_path("analyst-features.xml"),
    include_misc = FALSE
  )
  item <- result[result$xml_entity == "item", , drop = FALSE]

  testthat::expect_true(is.logical(result$item__flag__present))
  testthat::expect_true(item$item__flag__present[[1L]])
  testthat::expect_true(is.na(item$item__flag__present[[2L]]))
  testthat::expect_equal(
    item$item__description__text_content[[1L]],
    "Hello bold world."
  )
  testthat::expect_equal(item$item__description__b[[1L]], "bold")
})


testthat::test_that("derived subtree text does not propagate to descendant entities", {
  xml <- tempfile(fileext = ".xml")
  on.exit(unlink(xml), add = TRUE)

  writeLines(
    paste0(
      "<root>header",
      "<group>",
      "<item id=\"A\">alpha</item>",
      "<item id=\"B\">beta</item>",
      "</group>",
      "</root>"
    ),
    xml,
    useBytes = TRUE
  )

  result <- rectangle_xml_analyst(xml, include_misc = FALSE)
  root <- result[result$xml_entity == "root", , drop = FALSE]
  item <- result[result$xml_entity == "item", , drop = FALSE]

  testthat::expect_equal(root$root__text_content[[1L]], "headeralphabeta")
  testthat::expect_true(all(is.na(item$root__text_content)))
})


testthat::test_that("analyst metadata measures generic context amplification", {
  xml <- tempfile(fileext = ".xml")
  on.exit(unlink(xml), add = TRUE)

  writeLines(
    "<root><group code=\"G\"><item>A</item><item>B</item></group></root>",
    xml,
    useBytes = TRUE
  )

  result <- rectangle_xml_analyst(xml, include_misc = FALSE)
  metadata <- attr(result, "xml_analyst_metadata")
  amplification <- metadata$amplification

  testthat::expect_true(is.data.frame(amplification))
  testthat::expect_true(!is.null(metadata$amplification_summary))

  code <- amplification[
    amplification$column == "root__group__attr_code",
    ,
    drop = FALSE
  ]

  testthat::expect_equal(nrow(code), 1L)
  testthat::expect_equal(code$field_kind, "attribute")
  testthat::expect_equal(code$owner_rows, 1L)
  testthat::expect_equal(code$emitted_rows, 3L)
  testthat::expect_equal(code$context_rows, 2L)
  testthat::expect_equal(code$owner_bytes, 1)
  testthat::expect_equal(code$emitted_bytes, 3)
  testthat::expect_equal(code$row_amplification, 3)
  testthat::expect_equal(code$byte_amplification, 3)
  testthat::expect_equal(code$max_propagation_depth, 2L)
})


testthat::test_that("context propagation stops after one entity hop", {
  xml <- tempfile(fileext = ".xml")
  on.exit(unlink(xml), add = TRUE)

  writeLines(
    paste0(
      "<root code=\"R\">",
      "<middle code=\"M1\"><leaf>A</leaf><leaf>B</leaf></middle>",
      "<middle code=\"M2\"><leaf>C</leaf><leaf>D</leaf></middle>",
      "</root>"
    ),
    xml,
    useBytes = TRUE
  )

  result <- rectangle_xml_analyst(xml, include_misc = FALSE)
  middle <- result[result$xml_entity == "middle", , drop = FALSE]
  leaf <- result[result$xml_entity == "leaf", , drop = FALSE]

  # Immediate parent context is convenient on the child row.
  testthat::expect_equal(middle$root__attr_code, c("R", "R"))
  testthat::expect_equal(leaf$middle__attr_code, c("M1", "M1", "M2", "M2"))

  # Grandparent context remains recoverable through xml_parent_entity_id but is
  # not duplicated transitively into every deeper descendant row.
  testthat::expect_true(all(is.na(leaf$root__attr_code)))

  metadata <- attr(result, "xml_analyst_metadata")
  root_code <- metadata$amplification[
    metadata$amplification$column == "root__attr_code",
    ,
    drop = FALSE
  ]
  testthat::expect_equal(root_code$owner_rows, 1L)
  testthat::expect_equal(root_code$emitted_rows, 3L)
  testthat::expect_equal(root_code$context_rows, 2L)
})


testthat::test_that("safe type inference creates useful analyst columns", {
  result <- rectangle_xml_analyst(
    fixture_path("types.xml"),
    include_misc = FALSE
  )
  measurement <- result[result$xml_entity == "measurement", , drop = FALSE]

  testthat::expect_true(is.integer(measurement$measurement__count))
  testthat::expect_true(is.double(measurement$measurement__ratio))
  testthat::expect_true(is.logical(measurement$measurement__active))
  testthat::expect_s3_class(measurement$measurement__observed, "Date")
  testthat::expect_true(is.character(measurement$measurement__code))
  testthat::expect_equal(measurement$measurement__code, c("00123", "00007"))
})


testthat::test_that("direct source identifiers are surfaced without replacing generated keys", {
  result <- rectangle_xml_analyst(
    fixture_path("orders.xml"),
    include_misc = FALSE
  )
  order <- result[result$xml_entity == "order", , drop = FALSE]

  testthat::expect_equal(order$xml_key_column, rep("order__attr_id", 2L))
  testthat::expect_equal(order$xml_key_value, c("A-001", "A-002"))
  testthat::expect_true(all(grepl("^e[0-9]{9}$", order$xml_entity_id)))
})


testthat::test_that("namespace distinctions remain visible when needed", {
  result <- rectangle_xml_analyst(
    fixture_path("namespaces.xml"),
    include_misc = FALSE
  )

  testthat::expect_equal(nrow(result), 1L)
  testthat::expect_true(any(grepl("a_item", names(result), fixed = TRUE)))
  testthat::expect_true(any(grepl("b_item", names(result), fixed = TRUE)))
  testthat::expect_match(result$xml_namespaces[[1L]], "urn:example:a")
  testthat::expect_match(result$xml_namespaces[[1L]], "urn:example:b")
})


testthat::test_that("default namespaces stay readable beside auxiliary namespaces", {
  xml <- tempfile(fileext = ".xml")
  on.exit(unlink(xml), add = TRUE)

  writeLines(
    paste0(
      '<Patient xmlns="urn:example:patient" ',
      'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ',
      'xsi:schemaLocation="urn:example:patient patient.xsd">',
      '<id value="p-1"/>',
      '</Patient>'
    ),
    xml,
    useBytes = TRUE
  )

  result <- rectangle_xml_analyst(xml, include_misc = FALSE)

  testthat::expect_true("Patient__id__attr_value" %in% names(result))
  testthat::expect_false(any(grepl("Patient__ns[0-9]+_id", names(result))))
  testthat::expect_true("Patient__attr_xsi_schemaLocation" %in% names(result))
  testthat::expect_match(result$xml_namespaces[[1L]], "\\(default\\)=urn:example:patient")
  testthat::expect_match(result$xml_namespaces[[1L]], "xsi=http://www.w3.org/2001/XMLSchema-instance")
})


testthat::test_that("namespace descriptions collapse synthetic aliases by URI", {
  nodes <- xml_to_nodes_memory(fixture_path("namespaces.xml"))
  uri <- "urn:example:a"
  rows <- !is.na(nodes$namespace_uri) & nodes$namespace_uri == uri
  nodes$prefix[rows] <- paste0("ns", seq_len(sum(rows)))

  info <- .xml_analyst_namespace_info(nodes)
  pieces <- strsplit(info$description, "; ", fixed = TRUE)[[1L]]
  matching <- pieces[endsWith(pieces, paste0("=", uri))]

  testthat::expect_equal(length(matching), 1L)
})


testthat::test_that("nested singleton identifiers can surface as source keys", {
  xml <- tempfile(fileext = ".xml")
  on.exit(unlink(xml), add = TRUE)

  writeLines(
    paste0(
      '<patients>',
      '<patient><id value="p-1"/><name>Ana</name></patient>',
      '<patient><id value="p-2"/><name>Marc</name></patient>',
      '</patients>'
    ),
    xml,
    useBytes = TRUE
  )

  result <- rectangle_xml_analyst(xml, include_misc = FALSE)
  patient <- result[result$xml_entity == "patient", , drop = FALSE]

  testthat::expect_equal(
    patient$xml_key_column,
    rep("patient__id__attr_value", 2L)
  )
  testthat::expect_equal(patient$xml_key_value, c("p-1", "p-2"))
})


testthat::test_that("nested unrelated ids are not promoted to the owner key", {
  result <- rectangle_xml_analyst(
    fixture_path("analyst-features.xml"),
    include_misc = FALSE
  )
  catalog <- result[result$xml_entity == "catalog", , drop = FALSE]

  testthat::expect_true(is.na(catalog$xml_key_column[[1L]]))
  testthat::expect_true(is.na(catalog$xml_key_value[[1L]]))
})


testthat::test_that("identifier wrapper metadata is not mistaken for the identifier value", {
  xml <- tempfile(fileext = ".xml")
  on.exit(unlink(xml), add = TRUE)

  writeLines(
    paste0(
      '<records>',
      '<record><identifier source="A">R-1</identifier></record>',
      '<record><identifier source="B">R-2</identifier></record>',
      '</records>'
    ),
    xml,
    useBytes = TRUE
  )

  result <- rectangle_xml_analyst(xml, include_misc = FALSE)
  record <- result[result$xml_entity == "record", , drop = FALSE]

  testthat::expect_false(any(grepl("attr_source$", record$xml_key_column), na.rm = TRUE))
  testthat::expect_equal(record$xml_key_value, c("R-1", "R-2"))
})


testthat::test_that("descriptive addresses and boolean id-looking fields are not source keys", {
  xml <- tempfile(fileext = ".xml")
  on.exit(unlink(xml), add = TRUE)

  writeLines(
    paste0(
      '<records>',
      '<record><EmailAddress>a@example.test</EmailAddress><hideGroupId>true</hideGroupId></record>',
      '<record><EmailAddress>b@example.test</EmailAddress><hideGroupId>false</hideGroupId></record>',
      '</records>'
    ),
    xml,
    useBytes = TRUE
  )

  result <- rectangle_xml_analyst(xml, include_misc = FALSE)
  record <- result[result$xml_entity == "record", , drop = FALSE]

  testthat::expect_true(all(is.na(record$xml_key_column)))
  testthat::expect_true(all(is.na(record$xml_key_value)))
})


testthat::test_that("nested machine-style identifier attributes remain eligible", {
  xml <- tempfile(fileext = ".xml")
  on.exit(unlink(xml), add = TRUE)

  writeLines(
    paste0(
      '<hosts>',
      '<host><address addr="192.0.2.1"/></host>',
      '<host><address addr="192.0.2.2"/></host>',
      '</hosts>'
    ),
    xml,
    useBytes = TRUE
  )

  result <- rectangle_xml_analyst(xml, include_misc = FALSE)
  host <- result[result$xml_entity == "host", , drop = FALSE]

  testthat::expect_equal(
    host$xml_key_column,
    rep("host__address__attr_addr", 2L)
  )
  testthat::expect_equal(host$xml_key_value, c("192.0.2.1", "192.0.2.2"))
})


testthat::test_that("deeper id-looking scalars are not promoted across folded wrappers", {
  xml <- tempfile(fileext = ".xml")
  on.exit(unlink(xml), add = TRUE)

  writeLines(
    paste0(
      '<records>',
      '<record><parent><groupId>g-1</groupId></parent><value>A</value></record>',
      '<record><parent><groupId>g-2</groupId></parent><value>B</value></record>',
      '</records>'
    ),
    xml,
    useBytes = TRUE
  )

  result <- rectangle_xml_analyst(xml, include_misc = FALSE)
  record <- result[result$xml_entity == "record", , drop = FALSE]

  testthat::expect_true(all(is.na(record$xml_key_column)))
  testthat::expect_true(all(is.na(record$xml_key_value)))
})


testthat::test_that("direct identifiers outrank deeper identifier-like context", {
  xml <- tempfile(fileext = ".xml")
  on.exit(unlink(xml), add = TRUE)

  writeLines(
    paste0(
      '<records>',
      '<record><recordId>a</recordId><parent><groupId>g1</groupId></parent></record>',
      '<record><recordId>b</recordId><parent><groupId>g2</groupId></parent></record>',
      '</records>'
    ),
    xml,
    useBytes = TRUE
  )

  result <- rectangle_xml_analyst(xml, include_misc = FALSE)
  record <- result[result$xml_entity == "record", , drop = FALSE]

  testthat::expect_equal(record$xml_key_column, rep("record__recordId", 2L))
  testthat::expect_equal(record$xml_key_value, c("a", "b"))
})






testthat::test_that("unrelated suffix-ID fields are not asserted as entity keys", {
  xml <- tempfile(fileext = ".xml")
  on.exit(unlink(xml), add = TRUE)

  writeLines(
    paste0(
      '<dependencies>',
      '<dependency><groupId>g1</groupId><artifactId>a1</artifactId></dependency>',
      '<dependency><groupId>g2</groupId><artifactId>a2</artifactId></dependency>',
      '</dependencies>'
    ),
    xml,
    useBytes = TRUE
  )

  result <- rectangle_xml_analyst(xml, include_misc = FALSE)
  dependency <- result[result$xml_entity == "dependency", , drop = FALSE]

  testthat::expect_true(all(is.na(dependency$xml_key_column)))
  testthat::expect_true(all(is.na(dependency$xml_key_value)))
})

testthat::test_that("exact ID outranks broader suffix-ID fields", {
  xml <- tempfile(fileext = ".xml")
  on.exit(unlink(xml), add = TRUE)

  writeLines(
    paste0(
      '<invoices>',
      '<invoice><CustomizationID>profile-A</CustomizationID><ID>INV-1</ID></invoice>',
      '<invoice><CustomizationID>profile-B</CustomizationID><ID>INV-2</ID></invoice>',
      '</invoices>'
    ),
    xml,
    useBytes = TRUE
  )

  result <- rectangle_xml_analyst(xml, include_misc = FALSE)
  invoice <- result[result$xml_entity == "invoice", , drop = FALSE]

  testthat::expect_equal(invoice$xml_key_column, rep("invoice__ID", 2L))
  testthat::expect_equal(invoice$xml_key_value, c("INV-1", "INV-2"))
})


testthat::test_that("references URIs and generic names are not asserted as source keys", {
  xml <- tempfile(fileext = ".xml")
  on.exit(unlink(xml), add = TRUE)

  writeLines(
    paste0(
      '<records>',
      '<record name="A"><reference>R-A</reference><uri>https://example.test/a</uri></record>',
      '<record name="B"><reference>R-B</reference><uri>https://example.test/b</uri></record>',
      '</records>'
    ),
    xml,
    useBytes = TRUE
  )

  result <- rectangle_xml_analyst(xml, include_misc = FALSE)
  record <- result[result$xml_entity == "record", , drop = FALSE]

  testthat::expect_true(all(is.na(record$xml_key_column)))
  testthat::expect_true(all(is.na(record$xml_key_value)))
})


testthat::test_that("a folded child accession does not identify its owner wrapper", {
  xml <- tempfile(fileext = ".xml")
  on.exit(unlink(xml), add = TRUE)

  writeLines(
    paste0(
      '<sets>',
      '<set><sample accession="S-1"><title>A</title></sample></set>',
      '<set><sample accession="S-2"><title>B</title></sample></set>',
      '</sets>'
    ),
    xml,
    useBytes = TRUE
  )

  result <- rectangle_xml_analyst(xml, include_misc = FALSE)
  set <- result[result$xml_entity == "set", , drop = FALSE]

  testthat::expect_true(all(is.na(set$xml_key_column)))
  testthat::expect_true(all(is.na(set$xml_key_value)))
})

testthat::test_that("one entity type uses one source-key column", {
  xml <- tempfile(fileext = ".xml")
  on.exit(unlink(xml), add = TRUE)

  writeLines(
    paste0(
      '<records>',
      '<record><id>A</id><reference>R-A</reference></record>',
      '<record><reference>R-B</reference></record>',
      '</records>'
    ),
    xml,
    useBytes = TRUE
  )

  result <- rectangle_xml_analyst(xml, include_misc = FALSE)
  record <- result[result$xml_entity == "record", , drop = FALSE]

  chosen <- unique(stats::na.omit(record$xml_key_column))
  testthat::expect_equal(length(chosen), 1L)
  testthat::expect_true(all(record$xml_key_column[!is.na(record$xml_key_column)] == chosen))
})


testthat::test_that("ancestor context can be expanded on demand from the same table", {
  xml <- tempfile(fileext = ".xml")
  on.exit(unlink(xml), add = TRUE)

  # Repeated middle/leaf branches force all three levels to be analytical
  # entities. A singleton-only fixture would legitimately be eligible for
  # context folding and therefore would not test ancestor expansion itself.
  writeLines(
    paste0(
      '<root code="R">',
      '<middle code="M1">',
      '<leaf id="L1">A</leaf><leaf id="L2">B</leaf>',
      '</middle>',
      '<middle code="M2">',
      '<leaf id="L3">C</leaf><leaf id="L4">D</leaf>',
      '</middle>',
      '</root>'
    ),
    xml,
    useBytes = TRUE
  )

  result <- rectangle_xml_analyst(xml, include_misc = FALSE)
  leaf <- result[result$xml_entity == "leaf", , drop = FALSE]
  expanded <- xml_analyst_expand_context(result, entity = "leaf")

  testthat::expect_equal(nrow(leaf), 4L)
  testthat::expect_true("root__attr_code" %in% names(leaf))
  testthat::expect_true(all(is.na(leaf$root__attr_code)))
  testthat::expect_equal(
    expanded$root__attr_code,
    rep("R", 4L)
  )
  testthat::expect_equal(
    expanded$middle__attr_code,
    c("M1", "M1", "M2", "M2")
  )
  testthat::expect_equal(
    expanded$leaf__attr_id,
    c("L1", "L2", "L3", "L4")
  )
})


testthat::test_that("miscellaneous XML nodes stay in the same table", {
  result <- rectangle_xml_analyst(fixture_path("analyst-features.xml"))
  misc <- result[result$xml_entity == "xml_misc", , drop = FALSE]

  testthat::expect_equal(sort(misc$xml_misc__type), c("comment", "pi"))
  testthat::expect_true("analyst-visible comment" %in% misc$xml_misc__value)
  testthat::expect_true("check" %in% misc$xml_misc__name)
})


testthat::test_that("analyst CSV distinguishes missing values from empty strings", {
  output <- tempfile(fileext = ".csv")
  on.exit(unlink(output), add = TRUE)

  rectangle_xml_analyst_csv(
    fixture_path("analyst-features.xml"),
    output = output,
    include_misc = FALSE
  )

  lines <- readLines(output, warn = FALSE)
  testthat::expect_true(any(grepl("\\N", lines, fixed = TRUE)))
  testthat::expect_true(any(grepl('""', lines, fixed = TRUE)))
})


testthat::test_that("analyst CSV refuses an ambiguous missing-value sentinel", {
  xml <- tempfile(fileext = ".xml")
  output <- tempfile(fileext = ".csv")
  on.exit(unlink(c(xml, output)), add = TRUE)
  writeLines("<root><value>\\N</value></root>", xml, useBytes = TRUE)

  testthat::expect_error(
    rectangle_xml_analyst_csv(xml, output = output),
    "occurs as genuine source data",
    fixed = TRUE
  )
  testthat::expect_false(file.exists(output))
})


testthat::test_that("analyst Parquet is one logical table when Arrow is available", {
  testthat::skip_if_not_installed("arrow")
  output <- tempfile(fileext = ".parquet")
  on.exit(unlink(output), add = TRUE)

  expected <- rectangle_xml_analyst(
    fixture_path("analyst-features.xml"),
    include_misc = FALSE
  )
  rectangle_xml_analyst_parquet(
    fixture_path("analyst-features.xml"),
    output = output,
    include_misc = FALSE
  )
  reopened <- as.data.frame(arrow::read_parquet(output))

  testthat::expect_equal(nrow(reopened), nrow(expected))
  testthat::expect_equal(names(reopened), names(expected))
})


testthat::test_that("analyst audit accounts for structural source material", {
  nodes <- xml_to_nodes_memory(fixture_path("analyst-features.xml"))
  result <- xml_analyst_table(nodes)
  audit <- attr(result, "xml_analyst_metadata")$audit

  testthat::expect_equal(audit$canonical_nodes, nrow(nodes))
  testthat::expect_equal(
    audit$canonical_attributes,
    audit$projected_attributes
  )
  testthat::expect_equal(
    audit$canonical_text_nodes,
    audit$projected_text_nodes
  )
  testthat::expect_equal(
    audit$expected_entity_rows,
    sum(result$xml_entity != "xml_misc")
  )
})


testthat::test_that("malformed XML remains a parse error in analyst mode", {
  testthat::expect_error(
    rectangle_xml_analyst(fixture_path("malformed.xml")),
    class = "xml_parse_error"
  )
})


testthat::test_that("analyst subtree text fallback is independently valid", {
  nodes <- data.frame(
    depth = c(0L, 1L, 2L, 2L, 3L),
    node_type = c("document", "element", "text", "element", "text"),
    value = c(NA_character_, NA_character_, "A", NA_character_, "B"),
    stringsAsFactors = FALSE
  )

  testthat::expect_identical(
    xmlrectr:::.xml_analyst_subtree_text(nodes, element_row = 2L),
    "AB"
  )
})
