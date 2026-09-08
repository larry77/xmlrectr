## ----setup, include=FALSE-----------------------------------------------------
knitr::opts_chunk$set(collapse = TRUE, comment = "#>")

## -----------------------------------------------------------------------------
library(xmlrectr)

## -----------------------------------------------------------------------------
file <- system.file("extdata", "orders.xml", package = "xmlrectr")
profile <- xml_profile(rows = "order", id = "id")
spec <- compile_xml_profile(profile, file)

## ----eval=FALSE---------------------------------------------------------------
# out <- rectangle_xml(
#   "large.xml",
#   spec,
#   parallel = "auto"
# )

## ----eval=FALSE---------------------------------------------------------------
# batches <- list()
# 
# stats <- xml_stream_rectangle(
#   "large.xml",
#   spec,
#   callback = function(batch) {
#     batches[[length(batches) + 1L]] <<- batch
#   },
#   parallel = "auto"
# )

## ----eval=FALSE---------------------------------------------------------------
# rectangle_xml_csv(
#   "large.xml",
#   spec,
#   output = "large.csv",
#   parallel = "auto"
# )

## ----eval=FALSE---------------------------------------------------------------
# rectangle_xml_parquet(
#   "large.xml",
#   spec,
#   output_dir = "large-parquet",
#   compression = "snappy",
#   parallel = "auto"
# )

## ----eval=FALSE---------------------------------------------------------------
# rectangle_xml("large.xml", spec, parallel = TRUE)

## ----eval=FALSE---------------------------------------------------------------
# rectangle_xml(
#   "large.xml",
#   spec,
#   parallel = TRUE,
#   workers = 8,
#   strategy = "shared_chunk",
#   chunk_records = 2048,
#   task_records = 128
# )

