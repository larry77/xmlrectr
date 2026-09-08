# Package tests run inside the xmlrectr namespace. Fixtures remain ordinary XML
# files so the behavioural tests are as close as possible to the validated
# standalone P6.1 suite.
fixture_path <- function(name) {
  testthat::test_path("fixtures", name)
}
