testthat::test_that("inspection proposes familiar record names", {
  structure <- inspect_xml(fixture_path("orders.xml"))

  testthat::expect_s3_class(structure, "xml_structure")
  testthat::expect_identical(
    structure$likely_records$display_path,
    "orders/order"
  )
  testthat::expect_identical(
    structure$likely_records$occurrences,
    2L
  )
  testthat::expect_true(
    "orders/order/item" %in%
      structure$index$paths$display_path[
        structure$index$paths$repeated
      ]
  )
})


testthat::test_that("plain names create a reviewable long specification", {
  spec <- rectangle_spec(
    fixture_path("orders.xml"),
    one_row_per = "order",
    identify_by = "id"
  )

  testthat::expect_s3_class(spec, "xml_rect_spec")
  testthat::expect_identical(spec$representation, "long")
  testthat::expect_identical(spec$identifier$source_label, "@id")
  testthat::expect_identical(spec$records_observed, 2L)

  review <- review_rectangle(spec)

  testthat::expect_s3_class(review, "tbl_df")
  testthat::expect_true(
    all(
      c("output_name", "source", "entity", "under_repetition") %in%
        names(review)
    )
  )
  testthat::expect_true(any(review$source == "item/@sku"))
  testthat::expect_true(any(review$source == "customer/name"))
})


testthat::test_that("orders become one atomic table without multiplication", {
  spec <- rectangle_spec(
    fixture_path("orders.xml"),
    one_row_per = "order",
    identify_by = "id"
  )

  result <- rectangle_xml(fixture_path("orders.xml"), spec)

  testthat::expect_s3_class(result, "tbl_df")
  testthat::expect_false(any(vapply(result, is.list, logical(1))))
  testthat::expect_setequal(unique(result$record_id), c("A-001", "A-002"))

  items <- result[result$entity == "item", , drop = FALSE]
  testthat::expect_setequal(
    unique(items$field),
    c(
      "sku",
      "quantity",
      "description",
      "unit-price/currency",
      "unit-price"
    )
  )
  testthat::expect_identical(
    sort(unique(items$entity_index[items$record_id == "A-001"])),
    c(1L, 2L)
  )

  customer_names <- result[
    result$source == "customer/name",
    ,
    drop = FALSE
  ]
  testthat::expect_identical(
    customer_names$value,
    c("Ana Silva", "Marc Dubois")
  )
})


testthat::test_that("independent repetitions do not form a Cartesian product", {
  file <- fixture_path("independent-repeats.xml")
  spec <- rectangle_spec(
    file,
    one_row_per = "shipment",
    identify_by = "id"
  )
  result <- rectangle_xml(file, spec)

  items <- result[result$entity == "items/item", , drop = FALSE]
  payments <- result[result$entity == "payments/payment", , drop = FALSE]

  testthat::expect_equal(nrow(items), 4L)
  testthat::expect_equal(nrow(payments), 4L)
  testthat::expect_identical(sort(unique(items$entity_index)), c(1L, 2L))
  testthat::expect_identical(
    sort(unique(payments$entity_index)),
    c(1L, 2L)
  )
  testthat::expect_false(any(vapply(result, is.list, logical(1))))
})


testthat::test_that("the same interface rectangles a MARCXML sample", {
  file <- fixture_path("marc-mini.xml")
  spec <- rectangle_spec(
    file,
    one_row_per = "record",
    identify_by = FALSE
  )
  result <- rectangle_xml(file, spec)

  testthat::expect_identical(spec$representation, "long")
  testthat::expect_setequal(unique(result$record_id), c("1", "2"))
  testthat::expect_true(any(result$entity == "datafield/subfield"))
  testthat::expect_true("  12345 " %in% result$value)
  testthat::expect_false(any(vapply(result, is.list, logical(1))))
})


testthat::test_that("scalar records automatically produce a wide table", {
  file <- fixture_path("people.xml")
  spec <- rectangle_spec(
    file,
    one_row_per = "person",
    identify_by = "id"
  )
  result <- rectangle_xml(file, spec)

  testthat::expect_identical(spec$representation, "wide")
  testthat::expect_equal(nrow(result), 2L)
  testthat::expect_false(any(vapply(result, is.list, logical(1))))
  testthat::expect_identical(result$record_id, c("P-001", "P-002"))
  testthat::expect_identical(result$name, c("Amina Okafor", "Jonas Berg"))
  testthat::expect_identical(
    result[["birth-date"]],
    c("1988-04-12", "1976-11-03")
  )
})


testthat::test_that("users can select and rename scalar fields", {
  file <- fixture_path("orders.xml")
  spec <- rectangle_spec(
    file,
    one_row_per = "order",
    identify_by = "id",
    fields = c(
      order_status = "status",
      customer = "customer/name"
    )
  )
  result <- rectangle_xml(file, spec)

  testthat::expect_identical(spec$representation, "wide")
  testthat::expect_identical(
    names(result),
    c(
      "document_id",
      "record_index",
      "record_id",
      "record_node_id",
      "order_status",
      "customer"
    )
  )
  testthat::expect_identical(result$order_status, c("paid", "pending"))
  testthat::expect_identical(result$customer, c("Ana Silva", "Marc Dubois"))
})


testthat::test_that("unsafe wide output and ambiguous names stop clearly", {
  testthat::expect_error(
    rectangle_spec(
      fixture_path("orders.xml"),
      one_row_per = "order",
      representation = "wide"
    ),
    "cannot be represented safely"
  )

  testthat::expect_error(
    rectangle_spec(
      fixture_path("namespaces.xml"),
      one_row_per = "item"
    ),
    "is ambiguous"
  )

  namespace_spec <- rectangle_spec(
    fixture_path("namespaces.xml"),
    one_row_per = "item",
    namespace = "urn:example:a"
  )

  testthat::expect_identical(namespace_spec$record_name, "item")
})
