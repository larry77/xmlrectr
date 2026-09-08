testthat::test_that("structure proposals expose choices without creating an executable profile", {
  file <- fixture_path("types.xml")
  proposal <- propose_xml_profile(file)

  testthat::expect_s3_class(proposal, "xml_profile_proposal")
  testthat::expect_false(inherits(proposal, "xml_profile"))
  testthat::expect_identical(proposal$row_selection, "heuristic_for_review")
  testthat::expect_identical(proposal$selected_rows, "measurements/measurement")
  testthat::expect_identical(proposal$profile_template$id, FALSE)
  testthat::expect_null(proposal$profile_template$types)

  rows <- review_xml_proposal(proposal, "rows")
  testthat::expect_true("measurements/measurement" %in% rows$rows)
  testthat::expect_identical(rows$priority[[1L]], "primary")

  ids <- review_xml_proposal(proposal, "ids")
  testthat::expect_true("@id" %in% ids$source)
  id_row <- match("@id", ids$source)
  testthat::expect_identical(ids$priority[[id_row]], "strong")
})


testthat::test_that("sample type proposals are conservative about lexical evidence", {
  proposal <- propose_xml_profile(fixture_path("types.xml"))
  fields <- review_xml_proposal(proposal, "fields")

  type_for <- function(source) {
    fields$sample_type[match(source, fields$source)]
  }

  testthat::expect_identical(type_for("count"), "integer")
  testthat::expect_identical(type_for("ratio"), "double")
  testthat::expect_identical(type_for("active"), "logical")
  testthat::expect_identical(type_for("observed"), "date")
  testthat::expect_identical(type_for("code"), "character")

  code_row <- match("code", fields$source)
  testthat::expect_match(fields$sample_reason[[code_row]], "leading zero")
  testthat::expect_true(all(fields$wide_safe))
  testthat::expect_identical(
    .xml_infer_sample_type(c("0", "1"))$type,
    "character"
  )
})


testthat::test_that("ambiguous repeated record structures require an explicit row choice", {
  file <- fixture_path("ambiguous-records.xml")
  proposal <- propose_xml_profile(file)

  testthat::expect_identical(proposal$row_selection, "choice_required")
  testthat::expect_null(proposal$selected_rows)
  testthat::expect_null(proposal$profile_template)
  testthat::expect_equal(
    sum(proposal$row_candidates$priority == "primary"),
    2L
  )
  testthat::expect_equal(nrow(proposal$field_candidates), 0L)

  selected <- propose_xml_profile(file, rows = "order")
  testthat::expect_identical(selected$row_selection, "user")
  testthat::expect_identical(selected$selected_rows, "root/orders/order")
  testthat::expect_true("status" %in% selected$field_candidates$source)
})


testthat::test_that("XSD inspection exposes direct declarations and built-in type evidence", {
  xsd <- inspect_xsd(fixture_path("types.xsd"))

  testthat::expect_s3_class(xsd, "xml_xsd_inspection")
  testthat::expect_true(nrow(xsd$declarations) >= 8L)

  count_row <- match(
    "measurements/measurement/count",
    xsd$declarations$selector
  )
  testthat::expect_false(is.na(count_row))
  testthat::expect_identical(
    xsd$declarations$analytical_type[[count_row]],
    "integer"
  )

  id_row <- match(
    "measurements/measurement/@id",
    xsd$declarations$selector
  )
  testthat::expect_true(xsd$declarations$required[[id_row]])

  measurement_row <- match(
    "measurements/measurement",
    xsd$declarations$selector
  )
  testthat::expect_true(xsd$declarations$repeated[[measurement_row]])

  custom_row <- match("custom", xsd$declarations$selector)
  testthat::expect_true(is.na(xsd$declarations$analytical_type[[custom_row]]))
})


testthat::test_that("XSD evidence is matched to sample fields but never accepted automatically", {
  proposal <- propose_xml_profile(
    fixture_path("types.xml"),
    xsd = fixture_path("types.xsd")
  )
  fields <- review_xml_proposal(proposal, "fields")

  xsd_type_for <- function(source) {
    fields$xsd_analytical_type[match(source, fields$source)]
  }

  testthat::expect_identical(xsd_type_for("count"), "integer")
  testthat::expect_identical(xsd_type_for("ratio"), "double")
  testthat::expect_identical(xsd_type_for("active"), "logical")
  testthat::expect_identical(xsd_type_for("observed"), "date")
  testthat::expect_identical(xsd_type_for("code"), "character")
  testthat::expect_true(all(fields$xsd_match == "matched"))

  # Even with agreeing XSD evidence, the conservative template contains no
  # accepted analytical types. The user must explicitly create xml_profile().
  testthat::expect_null(proposal$profile_template$types)
  testthat::expect_false(inherits(proposal$profile_template, "xml_profile"))
})


testthat::test_that("malformed and non-schema XSD inputs fail explicitly", {
  testthat::expect_error(
    inspect_xsd(fixture_path("malformed.xsd")),
    class = "xml_parse_error"
  )

  testthat::expect_error(
    inspect_xsd(fixture_path("types.xml")),
    "XML Schema",
    class = "xml_proposal_error"
  )
})
