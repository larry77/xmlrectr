skip_parallel_packages <- function(shared = FALSE) {
  packages <- c("purrr", "furrr", "futurize", "future", "future.mirai")
  if (isTRUE(shared)) packages <- c(packages, "mori")
  for (package in packages) testthat::skip_if_not_installed(package)
  invisible(TRUE)
}


collect_parallel_streamed_rectangle <- function(
  file,
  spec,
  strategy,
  workers = 2L,
  chunk_rows = 1L,
  batch_rows = 2L,
  chunk_records = 4L,
  task_records = 1L,
  id_check = "memory"
) {
  batches <- list()

  stats <- xml_stream_rectangle_parallel(
    file = file,
    spec = spec,
    callback = function(batch) {
      batches[[length(batches) + 1L]] <<- batch
      invisible(NULL)
    },
    chunk_rows = chunk_rows,
    batch_rows = batch_rows,
    id_check = id_check,
    workers = workers,
    strategy = strategy,
    chunk_records = chunk_records,
    task_records = task_records
  )

  result <- if (length(batches) == 0L) {
    .xml_rectangle_result_schema(spec)
  } else {
    tibble::as_tibble(do.call(rbind, unname(batches)))
  }
  rownames(result) <- NULL

  list(data = result, batches = batches, stats = stats)
}


testthat::test_that("parallel in-memory rectangles are identical to sequential", {
  testthat::skip_if_not_installed("XML")
  skip_parallel_packages()

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
      profile = xml_profile(rows = "item", namespace = "urn:example:a")
    )
  )

  for (case in cases) {
    file <- fixture_path(case$file)
    spec <- compile_xml_profile(case$profile, file)
    nodes <- xml_to_nodes_memory(file, whitespace = spec$whitespace)
    reference <- xml_rectangle(nodes, spec)

    actual <- xml_rectangle_parallel(
      nodes,
      spec,
      workers = 2L,
      strategy = "parallel_chunks",
      chunk_records = 4L,
      task_records = 1L
    )

    testthat::expect_identical(actual, reference, info = case$file)
  }
})


testthat::test_that("mori shared chunks preserve the exact rectangle contract", {
  testthat::skip_if_not_installed("XML")
  skip_parallel_packages(shared = TRUE)

  file <- fixture_path("orders.xml")
  spec <- compile_xml_profile(
    xml_profile(rows = "order", id = "id"),
    file
  )
  nodes <- xml_to_nodes_memory(file, whitespace = spec$whitespace)
  reference <- xml_rectangle(nodes, spec)

  actual <- xml_rectangle_parallel(
    nodes,
    spec,
    workers = 2L,
    strategy = "shared_chunk",
    chunk_records = 3L,
    task_records = 1L
  )

  testthat::expect_identical(actual, reference)
})


testthat::test_that("parallel streaming preserves order and provenance", {
  testthat::skip_if_not_installed("XML")
  skip_parallel_packages()

  file <- fixture_path("orders.xml")
  spec <- compile_xml_profile(
    xml_profile(rows = "order", id = "id"),
    file
  )
  reference <- rectangle_xml(file, spec)

  sequential_stats <- xml_stream_rectangle(
    file = file,
    spec = spec,
    callback = function(batch) invisible(NULL),
    chunk_rows = 1L,
    batch_rows = 2L
  )

  actual <- collect_parallel_streamed_rectangle(
    file,
    spec,
    strategy = "parallel_chunks",
    workers = 2L,
    chunk_rows = 1L,
    batch_rows = 2L,
    chunk_records = 3L,
    task_records = 1L
  )

  testthat::expect_identical(actual$data, reference)
  testthat::expect_identical(
    actual$stats$record_count,
    sequential_stats$record_count
  )
  testthat::expect_identical(actual$stats$result_rows, as.integer(nrow(reference)))
  testthat::expect_identical(actual$stats$parallel_strategy, "parallel_chunks")
  testthat::expect_identical(actual$stats$workers, 2L)
  testthat::expect_true(actual$stats$parallel_tasks >= 1L)
})


testthat::test_that("parallel streaming shared chunks equal sequential streaming", {
  testthat::skip_if_not_installed("XML")
  skip_parallel_packages(shared = TRUE)

  file <- fixture_path("independent-repeats.xml")
  spec <- compile_xml_profile(
    xml_profile(rows = "shipment", id = "id"),
    file
  )
  reference <- rectangle_xml(file, spec)

  actual <- collect_parallel_streamed_rectangle(
    file,
    spec,
    strategy = "shared_chunk",
    workers = 2L,
    chunk_rows = 1L,
    batch_rows = 2L,
    chunk_records = 4L,
    task_records = 2L
  )

  testthat::expect_identical(actual$data, reference)
  testthat::expect_identical(actual$stats$parallel_strategy, "shared_chunk")
  testthat::expect_identical(actual$stats$task_records, 2L)
})


testthat::test_that("parallel source-ID checking matches sequential semantics", {
  testthat::skip_if_not_installed("XML")
  skip_parallel_packages()

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
    rectangle_xml_parallel(
      duplicate_file,
      spec,
      workers = 2L,
      strategy = "parallel_chunks",
      chunk_records = 2L,
      task_records = 2L
    ),
    "not unique"
  )

  unchecked <- collect_parallel_streamed_rectangle(
    duplicate_file,
    spec,
    strategy = "parallel_chunks",
    workers = 2L,
    chunk_records = 2L,
    task_records = 2L,
    id_check = "none"
  )

  testthat::expect_identical(
    unchecked$data$record_id,
    c("P-001", "P-001")
  )
})


testthat::test_that("parallel calls restore the caller's future plan", {
  testthat::skip_if_not_installed("XML")
  skip_parallel_packages()

  old <- future::plan()
  on.exit(future::plan(old), add = TRUE)
  future::plan(future::sequential)

  file <- fixture_path("people.xml")
  spec <- compile_xml_profile(
    xml_profile(rows = "person", id = "id"),
    file
  )

  invisible(
    rectangle_xml_parallel(
      file,
      spec,
      workers = 2L,
      strategy = "parallel_chunks",
      chunk_records = 2L,
      task_records = 1L
    )
  )

  testthat::expect_true(inherits(future::plan(), "sequential"))
})


testthat::test_that("one worker delegates to the frozen sequential implementation", {
  testthat::skip_if_not_installed("XML")

  file <- fixture_path("orders.xml")
  spec <- compile_xml_profile(
    xml_profile(rows = "order", id = "id"),
    file
  )
  nodes <- xml_to_nodes_memory(file, whitespace = spec$whitespace)

  testthat::expect_identical(
    xml_rectangle_parallel(nodes, spec, workers = 1L),
    xml_rectangle(nodes, spec)
  )
})


testthat::test_that("automatic task granularity avoids one future per record", {
  testthat::skip_if_not_installed("XML")
  skip_parallel_packages(shared = TRUE)

  file <- fixture_path("orders.xml")
  spec <- compile_xml_profile(
    xml_profile(rows = "order", id = "id"),
    file
  )
  reference <- rectangle_xml(file, spec)

  actual <- collect_parallel_streamed_rectangle(
    file,
    spec,
    strategy = "shared_chunk",
    workers = 2L,
    chunk_records = 32L,
    task_records = NULL,
    chunk_rows = 1L,
    batch_rows = 2L
  )

  testthat::expect_identical(actual$data, reference)
  testthat::expect_identical(actual$stats$chunk_records, 32L)
  testthat::expect_identical(actual$stats$task_records, 4L)
})



testthat::test_that("vectorized tasks can contain several records", {
  testthat::skip_if_not_installed("XML")
  skip_parallel_packages(shared = TRUE)

  file <- fixture_path("independent-repeats.xml")
  spec <- compile_xml_profile(
    xml_profile(rows = "shipment", id = "id"),
    file
  )
  nodes <- xml_to_nodes_memory(file, whitespace = spec$whitespace)
  reference <- xml_rectangle(nodes, spec)

  shared <- xml_rectangle_parallel(
    nodes,
    spec,
    workers = 2L,
    strategy = "shared_chunk",
    chunk_records = 8L,
    task_records = 4L
  )

  owned <- xml_rectangle_parallel(
    nodes,
    spec,
    workers = 2L,
    strategy = "parallel_chunks",
    chunk_records = 8L,
    task_records = 4L
  )

  testthat::expect_identical(shared, reference)
  testthat::expect_identical(owned, reference)
})


testthat::test_that("task grouping never crosses real ancestor instances", {
  testthat::skip_if_not_installed("XML")
  skip_parallel_packages(shared = TRUE)

  file <- tempfile(fileext = ".xml")
  on.exit(unlink(file), add = TRUE)

  writeLines(
    c(
      "<root>",
      "  <group name=\"A\">",
      "    <record id=\"R1\"><value>1</value></record>",
      "    <record id=\"R2\"><value>2</value></record>",
      "  </group>",
      "  <group name=\"B\">",
      "    <record id=\"R3\"><value>3</value></record>",
      "    <record id=\"R4\"><value>4</value></record>",
      "  </group>",
      "</root>"
    ),
    file,
    useBytes = TRUE
  )

  spec <- compile_xml_profile(
    xml_profile(rows = "record", id = "id"),
    file
  )
  nodes <- xml_to_nodes_memory(file, whitespace = spec$whitespace)
  reference <- xml_rectangle(nodes, spec)

  actual <- xml_rectangle_parallel(
    nodes,
    spec,
    workers = 2L,
    strategy = "shared_chunk",
    chunk_records = 4L,
    task_records = 4L
  )

  testthat::expect_identical(actual, reference)

  streamed <- collect_parallel_streamed_rectangle(
    file,
    spec,
    strategy = "shared_chunk",
    workers = 2L,
    chunk_records = 4L,
    task_records = 4L,
    chunk_rows = 1L,
    batch_rows = 2L
  )

  testthat::expect_identical(streamed$data, reference)
  testthat::expect_identical(streamed$stats$parallel_tasks, 2L)
})


testthat::test_that("P4 strategies expose distinct buffering bounds", {
  testthat::skip_if_not_installed("XML")
  skip_parallel_packages(shared = TRUE)

  file <- fixture_path("independent-repeats.xml")
  spec <- compile_xml_profile(
    xml_profile(rows = "shipment", id = "id"),
    file
  )

  owned <- collect_parallel_streamed_rectangle(
    file,
    spec,
    strategy = "parallel_chunks",
    workers = 2L,
    chunk_records = 2L,
    task_records = 1L,
    chunk_rows = 1L,
    batch_rows = 2L
  )

  shared <- collect_parallel_streamed_rectangle(
    file,
    spec,
    strategy = "shared_chunk",
    workers = 2L,
    chunk_records = 2L,
    task_records = 1L,
    chunk_rows = 1L,
    batch_rows = 2L
  )

  testthat::expect_identical(owned$data, shared$data)
  testthat::expect_identical(owned$stats$buffered_records, 4L)
  testthat::expect_identical(shared$stats$buffered_records, 2L)
})


testthat::test_that("parallel progress flag is validated without changing results", {
  testthat::skip_if_not_installed("XML")

  file <- fixture_path("people.xml")
  spec <- compile_xml_profile(
    xml_profile(rows = "person", id = "id"),
    file
  )
  nodes <- xml_to_nodes_memory(file, whitespace = spec$whitespace)

  testthat::expect_error(
    xml_rectangle_parallel(nodes, spec, workers = 1L, progress = NA),
    "progress"
  )

  testthat::expect_identical(
    xml_rectangle_parallel(nodes, spec, workers = 1L, progress = FALSE),
    xml_rectangle(nodes, spec)
  )
})


testthat::test_that("progressor remains active after helper returns", {
  testthat::skip_if_not_installed("progressr")

  make_and_signal <- function() {
    p <- .xml_parallel_make_progressor(TRUE, 2L)
    p(amount = 1L, message = "first")
    p(amount = 1L, message = "second")
    invisible(TRUE)
  }

  old_enable <- getOption("progressr.enable")
  on.exit(options(progressr.enable = old_enable), add = TRUE)
  options(progressr.enable = TRUE)

  testthat::expect_warning(
    progressr::with_progress(make_and_signal()),
    NA
  )
})


testthat::test_that("P5 in-memory automatic chunking follows strategy semantics", {
  testthat::expect_identical(
    .xml_parallel_in_memory_chunk_records(
      strategy = "parallel_chunks",
      workers = 4L,
      records = 956L,
      chunk_records = NULL
    ),
    239L
  )

  testthat::expect_identical(
    .xml_parallel_in_memory_chunk_records(
      strategy = "shared_chunk",
      workers = 4L,
      records = 956L,
      chunk_records = NULL
    ),
    956L
  )

  testthat::expect_identical(
    .xml_parallel_in_memory_chunk_records(
      strategy = "shared_chunk",
      workers = 4L,
      records = 956L,
      chunk_records = 128L
    ),
    128L
  )
})


testthat::test_that("P5 in-memory automatic chunks preserve exact results", {
  testthat::skip_if_not_installed("XML")
  skip_parallel_packages(shared = TRUE)

  file <- fixture_path("independent-repeats.xml")
  spec <- compile_xml_profile(
    xml_profile(rows = "shipment", id = "id"),
    file
  )
  nodes <- xml_to_nodes_memory(file, whitespace = spec$whitespace)
  reference <- xml_rectangle(nodes, spec)

  shared <- xml_rectangle_parallel(
    nodes,
    spec,
    workers = 2L,
    strategy = "shared_chunk"
  )
  owned <- xml_rectangle_parallel(
    nodes,
    spec,
    workers = 2L,
    strategy = "parallel_chunks"
  )

  testthat::expect_identical(shared, reference)
  testthat::expect_identical(owned, reference)
})


testthat::test_that("unified in-memory interface preserves sequential and parallel results", {
  testthat::skip_if_not_installed("XML")
  skip_parallel_packages(shared = TRUE)

  file <- fixture_path("independent-repeats.xml")
  spec <- compile_xml_profile(
    xml_profile(rows = "shipment", id = "id"),
    file
  )
  nodes <- xml_to_nodes_memory(file, whitespace = spec$whitespace)

  reference <- xml_rectangle(nodes, spec, parallel = FALSE)

  owned <- xml_rectangle(
    nodes,
    spec,
    parallel = TRUE,
    workers = 2L,
    strategy = "parallel_chunks",
    chunk_records = 4L
  )

  shared <- xml_rectangle(
    nodes,
    spec,
    parallel = TRUE,
    workers = 2L,
    strategy = "shared_chunk",
    chunk_records = 4L,
    task_records = 2L
  )

  testthat::expect_identical(owned, reference)
  testthat::expect_identical(shared, reference)
})


testthat::test_that("rectangle_xml exposes parallelism as an execution argument", {
  testthat::skip_if_not_installed("XML")
  skip_parallel_packages()

  file <- fixture_path("orders.xml")
  profile <- xml_profile(rows = "order", id = "id")

  reference <- rectangle_xml(file, profile, parallel = FALSE)
  actual <- rectangle_xml(
    file,
    profile,
    parallel = TRUE,
    workers = 2L,
    strategy = "parallel_chunks",
    chunk_records = 2L
  )

  testthat::expect_identical(actual, reference)
})


testthat::test_that("unified streaming interface preserves the sequential contract", {
  testthat::skip_if_not_installed("XML")
  skip_parallel_packages(shared = TRUE)

  file <- fixture_path("orders.xml")
  spec <- compile_xml_profile(
    xml_profile(rows = "order", id = "id"),
    file
  )

  collect <- function(parallel, strategy = "auto") {
    batches <- list()
    stats <- xml_stream_rectangle(
      file = file,
      spec = spec,
      callback = function(batch) {
        batches[[length(batches) + 1L]] <<- batch
        invisible(NULL)
      },
      chunk_rows = 1L,
      batch_rows = 2L,
      parallel = parallel,
      workers = 2L,
      strategy = strategy,
      chunk_records = 4L,
      task_records = 1L
    )

    data <- if (length(batches) == 0L) {
      .xml_rectangle_result_schema(spec)
    } else {
      tibble::as_tibble(do.call(rbind, unname(batches)))
    }
    rownames(data) <- NULL

    list(data = data, stats = stats)
  }

  sequential <- collect(FALSE)
  shared <- collect(TRUE, "shared_chunk")

  testthat::expect_identical(shared$data, sequential$data)
  testthat::expect_identical(shared$stats$parallel_strategy, "shared_chunk")
  testthat::expect_identical(shared$stats$workers, 2L)
})


testthat::test_that("automatic execution policy uses structural workload rather than file names", {
  small <- data.frame(
    record_index = 1:100,
    start = seq.int(1L, by = 10L, length.out = 100L),
    end = seq.int(10L, by = 10L, length.out = 100L)
  )

  large <- data.frame(
    record_index = 1:900,
    start = seq.int(1L, by = 150L, length.out = 900L),
    end = seq.int(150L, by = 150L, length.out = 900L)
  )

  heavy <- data.frame(
    record_index = 1:4,
    start = c(1L, 30001L, 60001L, 90001L),
    end = c(30000L, 60000L, 90000L, 120000L)
  )

  testthat::expect_false(.xml_parallel_auto_worth_it(small, workers = 4L))
  testthat::expect_true(.xml_parallel_auto_worth_it(large, workers = 4L))
  testthat::expect_true(.xml_parallel_auto_worth_it(heavy, workers = 4L))
})


testthat::test_that("automatic in-memory planning rejects impossible small workloads before span construction", {
  testthat::skip_if_not_installed("XML")
  skip_parallel_packages()

  file <- fixture_path("orders.xml")
  spec <- compile_xml_profile(
    xml_profile(rows = "order", id = "id"),
    file
  )
  nodes <- xml_to_nodes_memory(file, whitespace = spec$whitespace)

  testthat::expect_lt(
    nrow(nodes),
    .xml_parallel_auto_min_record_nodes_per_worker() * 2L
  )

  plan <- .xml_plan_in_memory_execution(
    nodes = nodes,
    spec = spec,
    parallel = "auto",
    workers = 2L,
    strategy = "parallel_chunks"
  )

  testthat::expect_false(plan$use_parallel)
  testthat::expect_identical(plan$workers, 1L)
  testthat::expect_null(plan$spans)
})


testthat::test_that("validated sequential fast path preserves exact results", {
  testthat::skip_if_not_installed("XML")

  file <- fixture_path("orders.xml")
  spec <- compile_xml_profile(
    xml_profile(rows = "order", id = "id"),
    file
  )
  nodes <- xml_to_nodes_memory(file, whitespace = spec$whitespace)

  ordinary <- .xml_rectangle_sequential(nodes, spec)
  validate_xml_nodes(nodes)
  already_validated <- .xml_rectangle_sequential(
    nodes,
    spec,
    .validated = TRUE
  )

  testthat::expect_identical(already_validated, ordinary)
})


testthat::test_that("automatic strategy defaults match execution context", {
  testthat::expect_identical(
    .xml_normalize_parallel_strategy("auto", context = "memory"),
    "parallel_chunks"
  )
  testthat::expect_identical(
    .xml_normalize_parallel_strategy("auto", context = "stream"),
    "shared_chunk"
  )
})


testthat::test_that("P6 shared automatic task granularity targets four tasks per worker", {
  settings <- .xml_parallel_chunk_settings(
    workers = 4L,
    strategy = "shared_chunk",
    chunk_records = 1024L,
    task_records = NULL
  )

  testthat::expect_identical(settings$task_records, 64L)

  owned <- .xml_parallel_chunk_settings(
    workers = 4L,
    strategy = "parallel_chunks",
    chunk_records = 850L,
    task_records = NULL
  )

  testthat::expect_identical(owned$task_records, 850L)
})


testthat::test_that("P6 streaming chunk defaults are bounded and strategy-specific", {
  testthat::expect_identical(
    .xml_parallel_stream_chunk_records("parallel_chunks", workers = 4L),
    512L
  )
  testthat::expect_identical(
    .xml_parallel_stream_chunk_records("shared_chunk", workers = 2L),
    512L
  )
  testthat::expect_identical(
    .xml_parallel_stream_chunk_records("shared_chunk", workers = 4L),
    1024L
  )
  testthat::expect_identical(
    .xml_parallel_stream_chunk_records("shared_chunk", workers = 11L),
    1024L
  )
})


testthat::test_that("CSV writer uses the same unified parallel execution interface", {
  testthat::skip_if_not_installed("XML")
  skip_parallel_packages()

  file <- fixture_path("orders.xml")
  spec <- compile_xml_profile(
    xml_profile(rows = "order", id = "id"),
    file
  )

  sequential_file <- tempfile(fileext = ".csv")
  parallel_file <- tempfile(fileext = ".csv")
  on.exit(unlink(c(sequential_file, parallel_file)), add = TRUE)

  rectangle_xml_csv(
    file = file,
    spec = spec,
    output = sequential_file,
    batch_rows = 2L,
    parallel = FALSE
  )

  rectangle_xml_csv(
    file = file,
    spec = spec,
    output = parallel_file,
    batch_rows = 2L,
    parallel = TRUE,
    workers = 2L,
    strategy = "parallel_chunks",
    chunk_records = 2L,
    task_records = 1L
  )

  sequential_bytes <- readBin(
    sequential_file,
    what = "raw",
    n = file.info(sequential_file)$size
  )
  parallel_bytes <- readBin(
    parallel_file,
    what = "raw",
    n = file.info(parallel_file)$size
  )

  testthat::expect_identical(parallel_bytes, sequential_bytes)
})
