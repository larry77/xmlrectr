.with_xmlrect_engine_env <- function(canonical = NULL, analyst = NULL, code) {
  old_canonical <- Sys.getenv("XML_RECT_CANONICAL_ENGINE", unset = NA_character_)
  old_analyst <- Sys.getenv("XML_RECT_ANALYST_ENGINE", unset = NA_character_)
  on.exit({
    if (is.na(old_canonical)) {
      Sys.unsetenv("XML_RECT_CANONICAL_ENGINE")
    } else {
      Sys.setenv(XML_RECT_CANONICAL_ENGINE = old_canonical)
    }
    if (is.na(old_analyst)) {
      Sys.unsetenv("XML_RECT_ANALYST_ENGINE")
    } else {
      Sys.setenv(XML_RECT_ANALYST_ENGINE = old_analyst)
    }
  }, add = TRUE)

  if (!is.null(canonical)) Sys.setenv(XML_RECT_CANONICAL_ENGINE = canonical)
  if (!is.null(analyst)) Sys.setenv(XML_RECT_ANALYST_ENGINE = analyst)
  force(code)
}


testthat::test_that("package native canonical reader matches the R reference", {
  file <- fixture_path("orders.xml")

  reference <- .with_xmlrect_engine_env(
    canonical = "r",
    code = xml_to_nodes_memory(file)
  )

  native <- .with_xmlrect_engine_env(
    canonical = "native",
    code = xml_to_nodes_memory(file)
  )

  testthat::expect_identical(native, reference)
})


testthat::test_that("package direct native analyst path matches the R reference", {
  file <- fixture_path("orders.xml")

  reference <- .with_xmlrect_engine_env(
    canonical = "r",
    analyst = "r",
    code = rectangle_xml_analyst(file)
  )

  native <- .with_xmlrect_engine_env(
    canonical = "native",
    analyst = "native",
    code = rectangle_xml_analyst(file)
  )

  testthat::expect_identical(native, reference)
})
