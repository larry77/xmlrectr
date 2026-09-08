testthat::test_that("wide profiles convert declared analytical types", {
  file <- fixture_path("types.xml")
  profile <- xml_profile(
    rows = "measurement",
    id = "id",
    fields = c(
      count = "count",
      ratio = "ratio",
      active = "active",
      observed = "observed",
      code = "code"
    ),
    types = c(
      count = "integer",
      ratio = "double",
      active = "logical",
      observed = "date"
    )
  )

  spec <- compile_xml_profile(profile, file)
  result <- rectangle_xml(file, spec)

  testthat::expect_identical(result$count, c(12L, -7L))
  testthat::expect_identical(result$ratio, c(3.5, 125))
  testthat::expect_identical(result$active, c(TRUE, FALSE))
  testthat::expect_s3_class(result$observed, "Date")
  testthat::expect_identical(
    result$observed,
    as.Date(c("2026-09-04", "2026-09-05"))
  )
  # No declaration means character, which is important for identifiers and
  # codes whose leading zeroes are semantically meaningful.
  testthat::expect_identical(result$code, c("00123", "00007"))

  review <- review_rectangle(spec)
  testthat::expect_identical(
    review$declared_type,
    c("integer", "double", "logical", "date", "character")
  )
})


testthat::test_that("typing never changes the canonical raw values", {
  file <- fixture_path("types.xml")
  nodes <- xml_to_nodes_memory(file, whitespace = "drop_blank")

  testthat::expect_type(nodes$value, "character")
  testthat::expect_true("00123" %in% nodes$value)
  testthat::expect_true("1.25e2" %in% nodes$value)

  profile <- xml_profile(
    rows = "measurement",
    fields = c(count = "count"),
    types = c(count = "integer")
  )
  result <- xml_rectangle(nodes, profile)
  testthat::expect_type(result$count, "integer")
  testthat::expect_true("12" %in% nodes$value)
})


testthat::test_that("invalid lexical values raise a dedicated type error", {
  file <- fixture_path("types.xml")
  profile <- xml_profile(
    rows = "measurement",
    fields = c(code = "code"),
    types = c(code = "integer")
  )
  spec <- compile_xml_profile(profile, file)

  bad_file <- tempfile(fileext = ".xml")
  on.exit(unlink(bad_file), add = TRUE)
  xml <- readLines(file, warn = FALSE)
  xml <- sub("<code>00007</code>", "<code>seven</code>", xml, fixed = TRUE)
  writeLines(xml, bad_file, useBytes = TRUE)

  condition <- tryCatch(
    rectangle_xml(bad_file, spec),
    error = function(condition) condition
  )
  testthat::expect_s3_class(condition, "xml_type_error")
  testthat::expect_identical(condition$declared_type, "integer")
  testthat::expect_identical(condition$value, "seven")
  testthat::expect_match(conditionMessage(condition), "Could not convert")
})


testthat::test_that("non-character typing is rejected for long rectangles", {
  file <- fixture_path("independent-repeats.xml")
  profile <- xml_profile(
    rows = "shipment",
    types = c("items/item/quantity" = "integer")
  )

  testthat::expect_error(
    compile_xml_profile(profile, file),
    "requires a wide rectangle",
    class = "xml_profile_error"
  )
})


testthat::test_that("type declarations are strict portable profile data", {
  profile <- xml_profile(
    rows = "measurement",
    fields = c(count = "count", observed = "observed"),
    types = c(count = "integer", observed = "date")
  )

  testthat::expect_identical(
    as_xml_profile(as.list(profile)),
    profile
  )
  testthat::expect_error(
    xml_profile(rows = "measurement", types = c(count = "factor")),
    "Supported types",
    class = "xml_profile_error"
  )
  testthat::expect_error(
    xml_profile(rows = "measurement", types = c("integer")),
    "named mapping",
    class = "xml_profile_error"
  )

  testthat::skip_if_not_installed("jsonlite")
  json_file <- tempfile(fileext = ".json")
  on.exit(unlink(json_file), add = TRUE)
  write_xml_profile(profile, json_file)
  testthat::expect_identical(read_xml_profile(json_file), profile)

  testthat::skip_if_not_installed("yaml")
  yaml_file <- tempfile(fileext = ".yaml")
  on.exit(unlink(yaml_file), add = TRUE)
  write_xml_profile(profile, yaml_file)
  testthat::expect_identical(read_xml_profile(yaml_file), profile)
})


testthat::test_that("streaming typed wide output matches in-memory output", {
  testthat::skip_if_not_installed("XML")

  file <- fixture_path("types.xml")
  spec <- compile_xml_profile(
    xml_profile(
      rows = "measurement",
      id = "id",
      fields = c(
        count = "count",
        ratio = "ratio",
        active = "active",
        observed = "observed"
      ),
      types = c(
        count = "integer",
        ratio = "double",
        active = "logical",
        observed = "date"
      )
    ),
    file
  )

  reference <- rectangle_xml(file, spec)
  batches <- list()
  xml_stream_rectangle(
    file,
    spec,
    chunk_rows = 1L,
    batch_rows = 1L,
    callback = function(batch) {
      batches[[length(batches) + 1L]] <<- batch
    }
  )
  streamed <- tibble::as_tibble(do.call(rbind, unname(batches)))
  rownames(streamed) <- NULL

  testthat::expect_identical(streamed, reference)
})


testthat::test_that("typed streaming conversion failures preserve staged CSV safety", {
  testthat::skip_if_not_installed("XML")

  file <- fixture_path("types.xml")
  spec <- compile_xml_profile(
    xml_profile(
      rows = "measurement",
      fields = c(count = "count"),
      types = c(count = "integer")
    ),
    file
  )

  bad_file <- tempfile(fileext = ".xml")
  output <- tempfile(fileext = ".csv")
  on.exit(unlink(c(bad_file, output)), add = TRUE)

  xml <- readLines(file, warn = FALSE)
  xml <- sub("<count>-7</count>", "<count>seven</count>", xml, fixed = TRUE)
  writeLines(xml, bad_file, useBytes = TRUE)
  writeLines("previous complete result", output, useBytes = TRUE)

  testthat::expect_error(
    rectangle_xml_csv(
      bad_file,
      spec,
      output,
      overwrite = TRUE,
      chunk_rows = 1L,
      batch_rows = 1L
    ),
    class = "xml_type_error"
  )
  testthat::expect_identical(
    readLines(output, warn = FALSE),
    "previous complete result"
  )
})
