\name{read_xml_profile}
\alias{read_xml_profile}
\title{Read an XML profile from JSON or YAML}
\description{Discover structural evidence and define a reviewable, reusable extraction contract. Proposals and XSD evidence are advisory rather than silently executable.}
\usage{
read_xml_profile(
file,
format = c("auto", "json", "yaml"))
}
\arguments{
\item{file}{Path to a serialized XML profile.}
\item{format}{Profile serialization format. \code{"auto"} infers JSON or YAML from the filename extension.}
}

\seealso{\code{xml_profile()}, \code{rectangle_xml()}}
