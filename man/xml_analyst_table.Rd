\name{xml_analyst_table}
\alias{xml_analyst_table}
\title{Project canonical XML into one analyst-oriented table}
\description{Create or work with the exploratory single-table analyst projection, which keeps universal xml_* provenance/entity columns alongside atomic analytical values.}
\usage{
xml_analyst_table(
nodes,
infer_types = TRUE,
include_misc = TRUE,
.validate_nodes = TRUE)
}
\arguments{
\item{nodes}{A canonical XML node table.}
\item{infer_types}{Logical; whether conservative scalar type inference is applied to analyst data columns.}
\item{include_misc}{Logical; whether miscellaneous XML content/provenance columns are retained.}
\item{.validate_nodes}{Internal logical fast-path control. Ordinary callers should leave this at \code{TRUE}.}
}

\seealso{\code{xml_profile()}, \code{rectangle_xml()}}
