testthat::test_that("a plain profile compiles to the existing exact spec", {
  file <- fixture_path("orders.xml")
  profile <- xml_profile(
    rows = "order",
    id = "id",
    fields = c(
      order_status = "status",
      customer = "customer/name"
    )
  )
  compiled <- compile_xml_profile(profile, file)
  direct <- rectangle_spec(
    file,
    one_row_per = "order",
    identify_by = "id",
    fields = c(
      order_status = "status",
      customer = "customer/name"
    )
  )

  testthat::expect_s3_class(profile, "xml_profile")
  testthat::expect_s3_class(compiled, "xml_rect_spec")
  testthat::expect_identical(compiled$record_path_key, direct$record_path_key)
  testthat::expect_identical(compiled$identifier, direct$identifier)
  testthat::expect_identical(compiled$representation, "wide")
  testthat::expect_identical(compiled$fields, direct$fields)
  testthat::expect_identical(compiled$profile, profile)
})


testthat::test_that("profiles work directly with files and canonical tables", {
  file <- fixture_path("orders.xml")
  profile <- xml_profile(
    rows = "order",
    id = "id",
    fields = c(customer = "customer/name")
  )
  from_file <- rectangle_xml(file, profile)
  nodes <- xml_to_nodes_memory(file, whitespace = "drop_blank")
  from_canonical <- xml_rectangle(nodes, profile)
  compiled <- compile_xml_profile(profile, nodes)
  from_compiled <- xml_rectangle(nodes, compiled)

  testthat::expect_identical(from_file, from_canonical)
  testthat::expect_identical(from_canonical, from_compiled)
  testthat::expect_identical(
    from_file$customer,
    c("Ana Silva", "Marc Dubois")
  )
})


testthat::test_that("safe layout retains repetitions without list-columns", {
  file <- fixture_path("independent-repeats.xml")
  profile <- xml_profile(rows = "shipment", id = "id")
  compiled <- compile_xml_profile(profile, file)
  result <- rectangle_xml(file, profile)

  testthat::expect_identical(compiled$representation, "long")
  testthat::expect_false(any(vapply(result, is.list, logical(1))))
  testthat::expect_setequal(
    unique(result$entity),
    c("shipment", "items/item", "payments/payment")
  )

  unsafe <- xml_profile(rows = "shipment", id = "id", layout = "wide")
  testthat::expect_error(
    compile_xml_profile(unsafe, file),
    class = "xml_profile_error"
  )
  testthat::expect_error(
    compile_xml_profile(unsafe, file),
    "layout = \"long\""
  )
})


testthat::test_that("namespace ambiguity is explained in profile language", {
  file <- fixture_path("namespaces.xml")
  ambiguous <- xml_profile(rows = "item")

  testthat::expect_error(
    compile_xml_profile(ambiguous, file),
    class = "xml_profile_error"
  )
  testthat::expect_error(
    compile_xml_profile(ambiguous, file),
    "rows = \"item\".*ambiguous"
  )

  resolved <- xml_profile(
    rows = "item",
    namespace = "urn:example:a"
  )
  compiled <- compile_xml_profile(resolved, file)
  result <- rectangle_xml(file, resolved)

  testthat::expect_identical(compiled$record_name, "item")
  testthat::expect_identical(result$value, "Namespace A")
})


testthat::test_that("portable list profiles are strict and predictable", {
  portable <- list(
    version = 1,
    rows = "order",
    id = "id",
    fields = list(
      order_status = "status",
      customer = "customer/name"
    ),
    layout = "safe"
  )
  profile <- as_xml_profile(portable)

  testthat::expect_s3_class(profile, "xml_profile")
  testthat::expect_identical(
    profile$fields,
    c(
      order_status = "status",
      customer = "customer/name"
    )
  )
  testthat::expect_identical(as_xml_profile(profile), profile)
  testthat::expect_identical(as.list(profile)$version, 1L)

  testthat::expect_error(
    as_xml_profile(list(id = "id")),
    "must contain `rows`",
    class = "xml_profile_error"
  )
  testthat::expect_error(
    as_xml_profile(list(rows = "order", xpath = "//order")),
    "Unknown profile setting",
    class = "xml_profile_error"
  )
  testthat::expect_error(
    xml_profile(rows = "order", id = TRUE),
    class = "xml_profile_error"
  )
  testthat::expect_error(
    xml_profile(
      rows = "order",
      fields = c(named = "status", "customer/name")
    ),
    "Either name every",
    class = "xml_profile_error"
  )
})


testthat::test_that("JSON and YAML profile files round-trip", {
  profile <- xml_profile(
    rows = "order",
    id = "id",
    fields = c(
      order_status = "status",
      customer = "customer/name"
    )
  )

  testthat::skip_if_not_installed("jsonlite")
  json_file <- tempfile(fileext = ".json")
  on.exit(unlink(json_file), add = TRUE)
  write_xml_profile(profile, json_file)
  testthat::expect_identical(read_xml_profile(json_file), profile)
  testthat::expect_error(
    write_xml_profile(profile, json_file),
    "already exists",
    class = "xml_profile_error"
  )

  testthat::skip_if_not_installed("yaml")
  yaml_file <- tempfile(fileext = ".yaml")
  on.exit(unlink(yaml_file), add = TRUE)
  write_xml_profile(profile, yaml_file)
  testthat::expect_identical(read_xml_profile(yaml_file), profile)

  # Exercise the two portable shapes not present in the named-field example:
  # null/all fields with a generated ID, and an unnamed sequence of sources.
  for (portable_profile in list(
    xml_profile(rows = "order"),
    xml_profile(
      rows = "order",
      fields = c("status", "customer/name")
    )
  )) {
    for (extension in c("json", "yaml")) {
      portable_file <- tempfile(fileext = paste0(".", extension))
      on.exit(unlink(portable_file), add = TRUE)
      write_xml_profile(portable_profile, portable_file)
      testthat::expect_identical(
        read_xml_profile(portable_file),
        portable_profile
      )
    }
  }

  malformed_file <- tempfile(fileext = ".json")
  on.exit(unlink(malformed_file), add = TRUE)
  writeLines("{ not valid JSON", malformed_file, useBytes = TRUE)
  testthat::expect_error(
    read_xml_profile(malformed_file),
    "Could not read XML profile",
    class = "xml_profile_error"
  )
})


testthat::test_that("included portable examples produce the expected table", {
  testthat::skip_if_not_installed("jsonlite")
  testthat::skip_if_not_installed("yaml")

  json_profile <- read_xml_profile(
    fixture_path("orders-profile.json")
  )
  yaml_profile <- read_xml_profile(
    fixture_path("orders-profile.yaml")
  )
  file <- fixture_path("orders.xml")
  json_result <- rectangle_xml(file, json_profile)
  yaml_result <- rectangle_xml(file, yaml_profile)

  testthat::expect_identical(json_profile, yaml_profile)
  testthat::expect_identical(json_result, yaml_result)
  testthat::expect_identical(
    names(json_result),
    c(
      "document_id",
      "record_index",
      "record_id",
      "record_node_id",
      "order_status",
      "customer"
    )
  )
})
