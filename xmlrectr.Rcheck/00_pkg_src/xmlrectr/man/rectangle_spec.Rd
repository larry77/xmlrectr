\name{rectangle_spec}
\alias{rectangle_spec}
\title{Create an explicit rectangle specification}
\description{Discover structural evidence and define a reviewable, reusable extraction contract. Proposals and XSD evidence are advisory rather than silently executable.}
\usage{
rectangle_spec(
sample,
one_row_per = NULL,
namespace = NULL,
identify_by = NULL,
fields = NULL,
types = NULL,
representation = c("auto", "wide", "long"),
whitespace = c("drop_blank", "preserve"))
}
\arguments{
\item{sample}{An XML sample accepted by \code{inspect_xml()} or an existing \code{xml_structure}.}
\item{one_row_per}{Optional visible element name or path defining one output record.}
\item{namespace}{Optional namespace URI used to disambiguate the row element.}
\item{identify_by}{Optional visible value name or path used as the record identifier.}
\item{fields}{Optional character vector of values to retain. Named entries rename output columns.}
\item{types}{Optional named character vector declaring output types for selected fields.}
\item{representation}{Requested table representation: automatic safe choice, wide, or long.}
\item{whitespace}{How blank text nodes are handled when the sample is read.}
}

\seealso{\code{xml_profile()}, \code{rectangle_xml()}}
