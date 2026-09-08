\name{rectangle_xml_analyst_csv}
\alias{rectangle_xml_analyst_csv}
\title{Write the analyst-oriented XML table to CSV}
\description{Create or work with the exploratory single-table analyst projection, which keeps universal xml_* provenance/entity columns alongside atomic analytical values.}
\usage{
rectangle_xml_analyst_csv(
file,
output,
whitespace = c("drop_blank", "preserve"),
infer_types = TRUE,
include_misc = TRUE,
na = "\\\\N",
overwrite = FALSE)
}
\arguments{
\item{file}{Path to the XML file.}
\item{output}{Destination CSV file.}
\item{whitespace}{How blank text nodes are handled.}
\item{infer_types}{Logical; whether conservative scalar type inference is applied.}
\item{include_misc}{Logical; whether miscellaneous XML content/provenance columns are retained.}
\item{na}{Character string written for missing values.}
\item{overwrite}{Logical; whether an existing destination may be replaced.}
}

\seealso{\code{xml_profile()}, \code{rectangle_xml()}}
