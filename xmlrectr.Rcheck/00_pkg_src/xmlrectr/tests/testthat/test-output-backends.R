read_parquet_parts <- function(directory) {
  files <- sort(
    list.files(
      directory,
      pattern = "^part-[0-9]{6}\\.parquet$",
      full.names = TRUE
    )
  )

  testthat::expect_gt(length(files), 0L)

  parts <- lapply(
    files,
    function(path) arrow::read_parquet(path, as_data_frame = TRUE)
  )

  result <- if (length(parts) == 1L) {
    tibble::as_tibble(parts[[1L]])
  } else {
    tibble::as_tibble(do.call(rbind, unname(parts)))
  }
  rownames(result) <- NULL

  list(data = result, files = files)
}


testthat::test_that("Parquet dataset output preserves typed rectangular data", {
  testthat::skip_if_not_installed("XML")
  testthat::skip_if_not_installed("arrow")

  file <- fixture_path("types.xml")
  spec <- compile_xml_profile(
    xml_profile(
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
    ),
    file
  )
  output <- tempfile(pattern = "xml-parquet-")
  on.exit(unlink(output, recursive = TRUE, force = TRUE), add = TRUE)

  stats <- rectangle_xml_parquet(
    file,
    spec,
    output_dir = output,
    chunk_rows = 1L,
    batch_rows = 1L
  )
  stored <- read_parquet_parts(output)
  reference <- rectangle_xml(file, spec)

  testthat::expect_identical(stored$data, reference)
  testthat::expect_identical(
    basename(stored$files),
    sprintf("part-%06d.parquet", seq_along(stored$files))
  )
  testthat::expect_identical(stats$output_format, "parquet")
  testthat::expect_identical(stats$output_parts, as.integer(length(stored$files)))
  testthat::expect_identical(
    stats$output_dir,
    normalizePath(output, winslash = "/", mustWork = TRUE)
  )
  testthat::expect_type(stored$data$count, "integer")
  testthat::expect_type(stored$data$ratio, "double")
  testthat::expect_type(stored$data$active, "logical")
  testthat::expect_s3_class(stored$data$observed, "Date")
  testthat::expect_identical(stored$data$code, c("00123", "00007"))
})


testthat::test_that("Parquet publication is staged and rollback-safe", {
  testthat::skip_if_not_installed("XML")
  testthat::skip_if_not_installed("arrow")

  file <- fixture_path("people.xml")
  spec <- compile_xml_profile(
    xml_profile(rows = "person", id = "id"),
    file
  )
  output <- tempfile(pattern = "xml-parquet-")
  dir.create(output)
  sentinel <- file.path(output, "previous-complete-result.txt")
  writeLines("previous complete result", sentinel, useBytes = TRUE)
  on.exit(unlink(output, recursive = TRUE, force = TRUE), add = TRUE)

  staged_directories <- function() {
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

  testthat::expect_error(
    rectangle_xml_parquet(
      fixture_path("malformed.xml"),
      spec,
      output_dir = output,
      overwrite = TRUE,
      chunk_rows = 1L,
      batch_rows = 1L
    ),
    class = "xml_parse_error"
  )
  testthat::expect_true(file.exists(sentinel))
  testthat::expect_identical(
    readLines(sentinel, warn = FALSE),
    "previous complete result"
  )
  testthat::expect_length(staged_directories(), 0L)

  stats <- rectangle_xml_parquet(
    file,
    spec,
    output_dir = output,
    overwrite = TRUE,
    chunk_rows = 1L,
    batch_rows = 1L
  )
  stored <- read_parquet_parts(output)
  reference <- rectangle_xml(file, spec)

  testthat::expect_false(file.exists(sentinel))
  testthat::expect_identical(stored$data, reference)
  testthat::expect_identical(stats$result_rows, as.integer(nrow(reference)))
  testthat::expect_length(staged_directories(), 0L)

  testthat::expect_error(
    rectangle_xml_parquet(file, spec, output_dir = output),
    "already exists"
  )
})


testthat::test_that("value-free rectangles still persist a typed Parquet schema", {
  testthat::skip_if_not_installed("XML")
  testthat::skip_if_not_installed("arrow")

  sample <- fixture_path("marc-mini.xml")
  spec <- compile_xml_profile(
    xml_profile(rows = "record"),
    sample
  )
  empty_record_file <- tempfile(fileext = ".xml")
  output <- tempfile(pattern = "xml-parquet-empty-")
  on.exit(
    unlink(c(empty_record_file, output), recursive = TRUE, force = TRUE),
    add = TRUE
  )
  writeLines(
    c(
      '<collection xmlns="http://www.loc.gov/MARC21/slim">',
      "  <record/>",
      "</collection>"
    ),
    empty_record_file,
    useBytes = TRUE
  )

  stats <- rectangle_xml_parquet(
    empty_record_file,
    spec,
    output_dir = output,
    chunk_rows = 1L,
    batch_rows = 1L
  )
  stored <- read_parquet_parts(output)

  testthat::expect_identical(stats$record_count, 1L)
  testthat::expect_identical(stats$result_rows, 0L)
  testthat::expect_identical(stats$output_parts, 1L)
  testthat::expect_identical(nrow(stored$data), 0L)
  testthat::expect_identical(
    names(stored$data),
    names(.xml_rectangle_result_schema(spec))
  )
})


testthat::test_that("Parquet conversion failures preserve an existing dataset", {
  testthat::skip_if_not_installed("XML")
  testthat::skip_if_not_installed("arrow")

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
  output <- tempfile(pattern = "xml-parquet-")
  dir.create(output)
  sentinel <- file.path(output, "previous-complete-result.txt")
  on.exit(
    unlink(c(bad_file, output), recursive = TRUE, force = TRUE),
    add = TRUE
  )

  xml <- readLines(file, warn = FALSE)
  xml <- sub("<count>-7</count>", "<count>seven</count>", xml, fixed = TRUE)
  writeLines(xml, bad_file, useBytes = TRUE)
  writeLines("previous complete result", sentinel, useBytes = TRUE)

  testthat::expect_error(
    rectangle_xml_parquet(
      bad_file,
      spec,
      output_dir = output,
      overwrite = TRUE,
      chunk_rows = 1L,
      batch_rows = 1L
    ),
    class = "xml_type_error"
  )
  testthat::expect_true(file.exists(sentinel))
  testthat::expect_identical(
    readLines(sentinel, warn = FALSE),
    "previous complete result"
  )
})
