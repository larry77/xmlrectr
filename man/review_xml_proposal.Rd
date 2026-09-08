\name{review_xml_proposal}
\alias{review_xml_proposal}
\title{Review one part of an XML profile proposal}
\description{Discover structural evidence and define a reviewable, reusable extraction contract. Proposals and XSD evidence are advisory rather than silently executable.}
\usage{
review_xml_proposal(
proposal,
what = c("rows", "ids", "fields", "xsd"))
}
\arguments{
\item{proposal}{A proposal returned by \code{propose_xml_profile()}.}
\item{what}{Which proposal component to review: row candidates, ID candidates, fields, or XSD evidence.}
}

\seealso{\code{xml_profile()}, \code{rectangle_xml()}}
