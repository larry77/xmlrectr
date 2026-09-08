\name{rectangle_xml_analyst_parquet}
\alias{rectangle_xml_analyst_parquet}
\title{Write the analyst-oriented XML table to Parquet}
\description{Create or work with the exploratory single-table analyst projection, which keeps universal xml_* provenance/entity columns alongside atomic analytical values.}
\usage{
rectangle_xml_analyst_parquet(
file,
output,
whitespace = c("drop_blank", "preserve"),
infer_types = TRUE,
include_misc = TRUE,
overwrite = FALSE,
compression = "snappy")
}
\arguments{
\item{file}{Path to the XML file.}
\item{output}{Destination Parquet file.}
\item{whitespace}{How blank text nodes are handled.}
\item{infer_types}{Logical; whether conservative scalar type inference is applied.}
\item{include_misc}{Logical; whether miscellaneous XML content/provenance columns are retained.}
\item{overwrite}{Logical; whether an existing destination may be replaced.}
\item{compression}{Parquet compression codec passed to \pkg{arrow}.}
}

\seealso{\code{xml_profile()}, \code{rectangle_xml()}}
