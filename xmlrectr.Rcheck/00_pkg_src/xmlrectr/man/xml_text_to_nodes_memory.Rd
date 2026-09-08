\name{xml_text_to_nodes_memory}
\alias{xml_text_to_nodes_memory}
\title{Read XML text into the canonical node table}
\description{Work with the canonical XML-node representation that preserves node identity, parentage, source order, namespaces, node types and scalar values.}
\usage{
xml_text_to_nodes_memory(
text,
document_id = "inline-xml",
whitespace = c("preserve", "drop_blank"),
initial_capacity = 1024L)
}
\arguments{
\item{text}{One character string containing XML markup.}
\item{document_id}{Identifier assigned to all canonical rows from the supplied XML text.}
\item{whitespace}{How blank text nodes are handled.}
\item{initial_capacity}{Positive initial size of the internal row buffer; it grows automatically as needed.}
}

\seealso{\code{xml_profile()}, \code{rectangle_xml()}}
