\name{make_rectangle}
\alias{make_rectangle}
\title{Create a lower-level rectangle specification}
\description{Discover structural evidence and define a reviewable, reusable extraction contract. Proposals and XSD evidence are advisory rather than silently executable.}
\usage{
make_rectangle(
structure,
one_row_per = NULL,
namespace = NULL,
identify_by = NULL,
fields = NULL,
types = NULL,
representation = c("auto", "wide", "long"))
}
\arguments{
\item{structure}{An inspected XML structure returned by \code{inspect_xml()}.}
\item{one_row_per}{Optional visible element name or path defining one output record. If omitted, an unambiguous proposed record path is used.}
\item{namespace}{Optional namespace URI used to disambiguate the row element.}
\item{identify_by}{Optional visible value name or path used as the record identifier; omit to generate sequential identifiers.}
\item{fields}{Optional character vector of values to retain. Named entries rename output columns.}
\item{types}{Optional named character vector declaring output types for selected fields.}
\item{representation}{Requested table representation: automatic safe choice, wide, or long.}
}

\seealso{\code{xml_profile()}, \code{rectangle_xml()}}
