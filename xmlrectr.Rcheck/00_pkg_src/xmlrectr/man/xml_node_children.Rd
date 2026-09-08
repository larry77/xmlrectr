\name{xml_node_children}
\alias{xml_node_children}
\title{Return direct canonical children of XML nodes}
\description{Work with the canonical XML-node representation that preserves node identity, parentage, source order, namespaces, node types and scalar values.}
\usage{
xml_node_children(
nodes,
node_id,
document_id = NULL,
include_attributes = FALSE)
}
\arguments{
\item{nodes}{A canonical XML node table.}
\item{node_id}{Positive canonical node identifier whose children are requested.}
\item{document_id}{Optional document identifier used to disambiguate node IDs in combined tables.}
\item{include_attributes}{Logical; whether attribute rows owned by the node are included with child content.}
}

\seealso{\code{xml_profile()}, \code{rectangle_xml()}}
