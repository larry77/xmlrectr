## ----setup, include=FALSE-----------------------------------------------------
knitr::opts_chunk$set(collapse = TRUE, comment = "#>")

## -----------------------------------------------------------------------------
library(xmlrectr)

## -----------------------------------------------------------------------------
file <- system.file("extdata", "orders.xml", package = "xmlrectr")
proposal <- propose_xml_profile(file)
proposal

## -----------------------------------------------------------------------------
review_xml_proposal(proposal, "rows")

## -----------------------------------------------------------------------------
review_xml_proposal(proposal, "ids")
review_xml_proposal(proposal, "fields")

## -----------------------------------------------------------------------------
profile <- xml_profile(
  rows = "order",
  id = "id"
)
profile

## ----eval=FALSE---------------------------------------------------------------
# write_xml_profile(profile, "orders-profile.json")
# profile <- read_xml_profile("orders-profile.json")

## -----------------------------------------------------------------------------
out <- rectangle_xml(file, profile)
out

## -----------------------------------------------------------------------------
spec <- compile_xml_profile(profile, file)
out2 <- rectangle_xml(file, spec)
identical(out, out2)

## ----eval=FALSE---------------------------------------------------------------
# rectangle_xml(file, spec, parallel = FALSE)   # exact sequential path
# rectangle_xml(file, spec, parallel = TRUE)    # request tuned parallel defaults
# rectangle_xml(file, spec, parallel = "auto")  # engine chooses

## -----------------------------------------------------------------------------
typed_xml <- system.file("extdata", "types.xml", package = "xmlrectr")
typed_xsd <- system.file("extdata", "types.xsd", package = "xmlrectr")

xsd_proposal <- propose_xml_profile(typed_xml, xsd = typed_xsd)
review_xml_proposal(xsd_proposal, "xsd")

## -----------------------------------------------------------------------------
analyst <- rectangle_xml_analyst(file)
analyst

