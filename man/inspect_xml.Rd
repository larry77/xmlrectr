\name{inspect_xml}
\alias{inspect_xml}
\title{Inspect XML structure before defining a rectangle}
\description{Work with the canonical XML-node representation that preserves node identity, parentage, source order, namespaces, node types and scalar values.}
\usage{
inspect_xml(
x,
whitespace = c("drop_blank", "preserve"))
}
\arguments{
\item{x}{An XML file path or an existing canonical node table.}
\item{whitespace}{How blank text nodes are handled when an XML file is read.}
}

\seealso{\code{xml_profile()}, \code{rectangle_xml()}}
