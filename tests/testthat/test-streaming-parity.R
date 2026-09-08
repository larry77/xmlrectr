testthat::test_that("streaming and in-memory readers share one contract", {
  testthat::skip_if_not_installed("XML")

  fixtures <- c(
    "orders.xml",
    "mixed-content.xml",
    "namespaces.xml",
    "marc-mini.xml",
    "document-misc.xml"
  )

  for (fixture in fixtures) {
    file <- fixture_path(fixture)

    reference <- xml_to_nodes_memory(
      file,
      whitespace = "drop_blank"
    )

    streamed <- xml_to_nodes_stream(
      file,
      whitespace = "drop_blank",

      # Deliberately split ordinary parent/child groups across chunks.  Parent
      # identifiers must remain valid even when their rows were emitted in an
      # earlier callback.
      chunk_rows = 3L
    )

    testthat::expect_identical(
      streamed,
      reference,
      info = fixture
    )
  }
})


testthat::test_that("streaming preserves blank text when requested", {
  testthat::skip_if_not_installed("XML")

  file <- fixture_path("orders.xml")

  reference <- xml_to_nodes_memory(
    file,
    whitespace = "preserve"
  )

  streamed <- xml_to_nodes_stream(
    file,
    whitespace = "preserve",
    chunk_rows = 1L
  )

  testthat::expect_identical(streamed, reference)
})


testthat::test_that("streaming decodes numeric attribute references", {
  testthat::skip_if_not_installed("XML")

  file <- tempfile(fileext = ".xml")
  on.exit(unlink(file), add = TRUE)
  writeLines(
    '<root value="A &#38; B &#x3c; C &#62; D &#x1F642;"/>',
    con = file,
    useBytes = TRUE
  )

  reference <- xml_to_nodes_memory(file, whitespace = "drop_blank")
  streamed <- xml_to_nodes_stream(
    file,
    whitespace = "drop_blank",
    chunk_rows = 2L
  )

  testthat::expect_identical(streamed, reference)
})


testthat::test_that("the callback path emits bounded, globally indexed chunks", {
  testthat::skip_if_not_installed("XML")

  received <- list()

  stats <- xml_stream_nodes(
    fixture_path("orders.xml"),
    whitespace = "drop_blank",
    chunk_rows = 5L,
    callback = function(chunk) {
      # A real bounded workflow would write or aggregate here.  This test keeps
      # the small fixture solely so it can inspect cross-chunk invariants.
      received[[length(received) + 1L]] <<- chunk
      invisible(NULL)
    }
  )

  sizes <- vapply(received, nrow, integer(1))
  combined <- tibble::as_tibble(
    do.call(rbind, unname(received))
  )
  rownames(combined) <- NULL

  testthat::expect_true(all(sizes <= 5L))
  testthat::expect_true(all(sizes[-length(sizes)] == 5L))
  testthat::expect_identical(
    combined$node_id,
    seq_len(nrow(combined))
  )
  testthat::expect_identical(stats$node_count, nrow(combined))
  testthat::expect_identical(stats$chunk_count, length(received))
  testthat::expect_true(validate_xml_nodes(combined))
})


testthat::test_that("streaming reports malformed XML and invalid callbacks", {
  testthat::skip_if_not_installed("XML")

  condition <- tryCatch(
    xml_to_nodes_stream(fixture_path("malformed.xml")),
    xml_parse_error = function(condition) condition
  )

  testthat::expect_s3_class(condition, "xml_parse_error")
  testthat::expect_match(
    conditionMessage(condition),
    "Could not stream XML source"
  )

  testthat::expect_error(
    xml_stream_nodes(
      fixture_path("orders.xml"),
      callback = "not a function"
    ),
    "callback"
  )
})
