collect_streamed_rectangle <- function(
  file,
  spec,
  chunk_rows = 3L,
  batch_rows = 2L,
  id_check = "memory"
) {
  batches <- list()
  stats <- xml_stream_rectangle(
    file = file,
    spec = spec,
    chunk_rows = chunk_rows,
    batch_rows = batch_rows,
    id_check = id_check,
    callback = function(batch) {
      # Unit tests deliberately collect these small batches.  Production code
      # should consume or persist each one to retain the end-to-end memory bound.
      batches[[length(batches) + 1L]] <<- batch
      invisible(NULL)
    }
  )

  result <- if (length(batches) == 0L) {
    .xml_rectangle_result_schema(spec)
  } else {
    tibble::as_tibble(do.call(rbind, unname(batches)))
  }
  rownames(result) <- NULL

  list(data = result, batches = batches, stats = stats)
}


testthat::test_that("streamed rectangles exactly match in-memory rectangles", {
  testthat::skip_if_not_installed("XML")

  cases <- list(
    list(
      file = "people.xml",
      profile = xml_profile(rows = "person", id = "id")
    ),
    list(
      file = "orders.xml",
      profile = xml_profile(rows = "order", id = "id")
    ),
    list(
      file = "independent-repeats.xml",
      profile = xml_profile(rows = "shipment", id = "id")
    ),
    list(
      file = "marc-mini.xml",
      profile = xml_profile(rows = "record")
    ),
    list(
      file = "namespaces.xml",
      profile = xml_profile(
        rows = "item",
        namespace = "urn:example:a"
      )
    )
  )

  for (case in cases) {
    file <- fixture_path(case$file)
    spec <- compile_xml_profile(case$profile, file)
    reference <- rectangle_xml(file, spec)
    streamed <- collect_streamed_rectangle(
      file,
      spec,
      # Single-node parser chunks force record starts, attributes, values, and
      # record ends to cross physical callback boundaries.
      chunk_rows = 1L,
      batch_rows = 2L
    )

    testthat::expect_identical(
      streamed$data,
      reference,
      info = case$file
    )
    testthat::expect_true(
      all(vapply(streamed$batches, nrow, integer(1)) <= 2L),
      info = case$file
    )
    testthat::expect_identical(
      streamed$stats$result_rows,
      as.integer(nrow(reference)),
      info = case$file
    )
  }
})


testthat::test_that("streaming requires an already compiled profile", {
  testthat::skip_if_not_installed("XML")

  testthat::expect_error(
    xml_stream_rectangle(
      fixture_path("people.xml"),
      xml_profile(rows = "person"),
      callback = function(batch) invisible(NULL)
    ),
    "Compile the profile once"
  )
})


testthat::test_that("source ID checking matches the in-memory contract", {
  testthat::skip_if_not_installed("XML")

  sample <- fixture_path("people.xml")
  spec <- compile_xml_profile(
    xml_profile(rows = "person", id = "id"),
    sample
  )
  duplicate_file <- tempfile(fileext = ".xml")
  on.exit(unlink(duplicate_file), add = TRUE)
  duplicate_xml <- readLines(sample, warn = FALSE)
  duplicate_xml <- sub("P-002", "P-001", duplicate_xml, fixed = TRUE)
  writeLines(duplicate_xml, duplicate_file, useBytes = TRUE)

  testthat::expect_error(
    rectangle_xml(duplicate_file, spec),
    "not unique"
  )
  testthat::expect_error(
    collect_streamed_rectangle(
      duplicate_file,
      spec,
      chunk_rows = 1L,
      batch_rows = 1L,
      id_check = "memory"
    ),
    "not unique"
  )

  unchecked <- collect_streamed_rectangle(
    duplicate_file,
    spec,
    chunk_rows = 1L,
    batch_rows = 1L,
    id_check = "none"
  )
  testthat::expect_identical(
    unchecked$data$record_id,
    c("P-001", "P-001")
  )
})


testthat::test_that("consumer failures are not mislabeled as malformed XML", {
  testthat::skip_if_not_installed("XML")

  file <- fixture_path("people.xml")
  spec <- compile_xml_profile(
    xml_profile(rows = "person", id = "id"),
    file
  )
  condition <- tryCatch(
    xml_stream_rectangle(
      file,
      spec,
      chunk_rows = 1L,
      batch_rows = 1L,
      callback = function(batch) stop("consumer deliberately failed")
    ),
    error = function(condition) condition
  )

  testthat::expect_s3_class(condition, "error")
  testthat::expect_false(inherits(condition, "xml_parse_error"))
  testthat::expect_match(
    conditionMessage(condition),
    "consumer deliberately failed"
  )
})


testthat::test_that("CSV publication is staged and inspectable", {
  testthat::skip_if_not_installed("XML")

  file <- fixture_path("people.xml")
  spec <- compile_xml_profile(
    xml_profile(rows = "person", id = "id"),
    file
  )
  output <- tempfile(fileext = ".csv")
  on.exit(unlink(output), add = TRUE)
  writeLines("previous complete result", output, useBytes = TRUE)

  staged_files <- function() {
    # Staging names deliberately share the final filename as a prefix.  Looking
    # only for that exact prefix avoids confusing unrelated hidden files in the
    # system temporary directory with a leak from this writer.
    candidates <- list.files(
      dirname(output),
      all.files = TRUE,
      full.names = TRUE,
      no.. = TRUE
    )
    candidates[
      startsWith(
        basename(candidates),
        paste0(".", basename(output), "-staged-")
      )
    ]
  }

  # A parser failure occurs after the staged file has been created.  The old
  # destination must nevertheless remain byte-for-byte untouched.
  testthat::expect_error(
    rectangle_xml_csv(
      fixture_path("malformed.xml"),
      spec,
      output,
      overwrite = TRUE,
      chunk_rows = 1L,
      batch_rows = 1L
    ),
    class = "xml_parse_error"
  )
  testthat::expect_identical(
    readLines(output, warn = FALSE),
    "previous complete result"
  )
  testthat::expect_length(staged_files(), 0L)

  stats <- rectangle_xml_csv(
    file,
    spec,
    output,
    overwrite = TRUE,
    chunk_rows = 1L,
    batch_rows = 1L
  )
  csv <- utils::read.csv(
    output,
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  reference <- rectangle_xml(file, spec)

  testthat::expect_identical(names(csv), names(reference))
  testthat::expect_identical(nrow(csv), nrow(reference))
  testthat::expect_identical(csv$record_id, reference$record_id)
  testthat::expect_identical(stats$result_rows, as.integer(nrow(reference)))
  testthat::expect_identical(
    stats$output_file,
    normalizePath(output, winslash = "/")
  )
  testthat::expect_length(staged_files(), 0L)

  testthat::expect_error(
    rectangle_xml_csv(file, spec, output),
    "already exists"
  )
})


testthat::test_that("a valid value-free result still gets a CSV schema", {
  testthat::skip_if_not_installed("XML")

  sample <- fixture_path("marc-mini.xml")
  spec <- compile_xml_profile(
    xml_profile(rows = "record"),
    sample
  )
  empty_record_file <- tempfile(fileext = ".xml")
  output <- tempfile(fileext = ".csv")
  on.exit(unlink(c(empty_record_file, output)), add = TRUE)
  writeLines(
    c(
      '<collection xmlns="http://www.loc.gov/MARC21/slim">',
      "  <record/>",
      "</collection>"
    ),
    empty_record_file,
    useBytes = TRUE
  )

  stats <- rectangle_xml_csv(
    empty_record_file,
    spec,
    output,
    chunk_rows = 1L,
    batch_rows = 1L
  )

  testthat::expect_identical(stats$record_count, 1L)
  testthat::expect_identical(stats$result_rows, 0L)
  testthat::expect_identical(
    length(readLines(output, warn = FALSE)),
    1L
  )
})
