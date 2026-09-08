\name{compile_xml_profile}
\alias{compile_xml_profile}
\title{Compile a profile into an executable rectangle specification}
\description{Discover structural evidence and define a reviewable, reusable extraction contract. Proposals and XSD evidence are advisory rather than silently executable.}
\usage{
compile_xml_profile(
profile,
sample,
whitespace = c("drop_blank", "preserve"))
}
\arguments{
\item{profile}{A human-facing profile created by \code{xml_profile()} or coercible with \code{as_xml_profile()}.}
\item{sample}{A representative XML sample accepted by \code{rectangle_spec()}, or a previously inspected \code{xml_structure}.}
\item{whitespace}{How blank text nodes are handled while inspecting the sample: \code{"drop_blank"} or \code{"preserve"}.}
}

\seealso{\code{xml_profile()}, \code{rectangle_xml()}}
