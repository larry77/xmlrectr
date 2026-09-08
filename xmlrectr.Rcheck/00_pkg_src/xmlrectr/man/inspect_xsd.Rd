\name{inspect_xsd}
\alias{inspect_xsd}
\title{Inspect advisory XSD evidence}
\description{Discover structural evidence and define a reviewable, reusable extraction contract. Proposals and XSD evidence are advisory rather than silently executable.}
\usage{
inspect_xsd(xsd)
}
\arguments{
\item{xsd}{Path to an XML Schema (XSD) file to inspect as advisory structural evidence.}
}
\details{This is deliberately an advisory XSD inspection layer, not a complete XSD validator or resolver.}
\seealso{\code{xml_profile()}, \code{rectangle_xml()}}
