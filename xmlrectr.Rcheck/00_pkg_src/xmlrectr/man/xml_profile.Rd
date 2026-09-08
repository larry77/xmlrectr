\name{xml_profile}
\alias{xml_profile}
\title{Create a human-facing reusable XML profile}
\description{Discover structural evidence and define a reviewable, reusable extraction contract. Proposals and XSD evidence are advisory rather than silently executable.}
\usage{
xml_profile(
rows,
id = NULL,
fields = NULL,
types = NULL,
namespace = NULL,
layout = c("safe", "wide", "long"))
}
\arguments{
\item{rows}{Visible XML element name or path defining one output record.}
\item{id}{Optional visible value name/path used as record identifier; omit or use \code{FALSE} for generated IDs.}
\item{fields}{Optional character vector of values to retain. Named entries rename output columns.}
\item{types}{Optional named character vector declaring output types.}
\item{namespace}{Optional namespace URI used to disambiguate the row element.}
\item{layout}{One-table layout policy: safe automatic layout, explicitly wide, or explicitly long.}
}

\seealso{\code{xml_profile()}, \code{rectangle_xml()}}
