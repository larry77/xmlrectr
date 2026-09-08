\name{rectangle_xml_analyst}
\alias{rectangle_xml_analyst}
\title{Create an analyst-oriented table directly from XML}
\description{Create or work with the exploratory single-table analyst projection, which keeps universal xml_* provenance/entity columns alongside atomic analytical values.}
\usage{
rectangle_xml_analyst(
file,
whitespace = c("drop_blank", "preserve"),
infer_types = TRUE,
include_misc = TRUE)
}
\arguments{
\item{file}{Path to the XML file.}
\item{whitespace}{How blank text nodes are handled.}
\item{infer_types}{Logical; whether conservative scalar type inference is applied to analyst data columns.}
\item{include_misc}{Logical; whether miscellaneous XML content/provenance columns are retained.}
}

\seealso{\code{xml_profile()}, \code{rectangle_xml()}}
