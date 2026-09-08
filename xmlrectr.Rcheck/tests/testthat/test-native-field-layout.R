testthat::test_that("native field layout preserves frozen occurrence and source ordering", {
  layout <- .xml_native_field_layout(
    owner_id = c(10L, 10L, 20L, 10L, 20L, 10L),
    entity_path_id = c(1L, 1L, 1L, 2L, 1L, 1L),
    source_signature = c("a", "a", "a", "b", "a", "a"),
    field_order = c(5L, 2L, 7L, 4L, 1L, 9L)
  )

  testthat::expect_equal(layout$catalog_id, c(1L, 1L, 1L, 2L, 1L, 1L))
  testthat::expect_equal(layout$catalog_first_field, c(1L, 4L))
  testthat::expect_equal(layout$value_occurrence, c(2L, 1L, 2L, 1L, 1L, 3L))
  testthat::expect_equal(layout$catalog_max_occurrence, c(3L, 1L))
  testthat::expect_equal(layout$slot_id, c(2L, 1L, 2L, 4L, 1L, 3L))
  testthat::expect_equal(layout$slot_first_field, c(5L, 1L, 6L, 4L))
  testthat::expect_equal(layout$data_slot_order, c(1L, 4L, 2L, 3L))
})
