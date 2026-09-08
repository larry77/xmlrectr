\name{write_xml_profile}
\alias{write_xml_profile}
\title{Write an XML profile to JSON or YAML}
\description{Discover structural evidence and define a reviewable, reusable extraction contract. Proposals and XSD evidence are advisory rather than silently executable.}
\usage{
write_xml_profile(
profile,
file,
format = c("auto", "json", "yaml"),
overwrite = FALSE)
}
\arguments{
\item{profile}{An \code{xml_profile} or compatible profile object.}
\item{file}{Destination JSON or YAML file.}
\item{format}{Serialization format. \code{"auto"} infers it from the destination extension.}
\item{overwrite}{Logical; whether an existing destination may be replaced.}
}

\seealso{\code{xml_profile()}, \code{rectangle_xml()}}
