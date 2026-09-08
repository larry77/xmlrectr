\name{xml_analyst_expand_context}
\alias{xml_analyst_expand_context}
\title{Expand analyst-table entity context}
\description{Create or work with the exploratory single-table analyst projection, which keeps universal xml_* provenance/entity columns alongside atomic analytical values.}
\usage{
xml_analyst_expand_context(x, entity = NULL, levels = Inf)
}
\arguments{
\item{x}{A table returned by \code{xml_analyst_table()} or \code{rectangle_xml_analyst()}.}
\item{entity}{Optional entity name or vector of entity names to retain.}
\item{levels}{Maximum number of ancestor-entity levels from which contextual values may be propagated; \code{Inf} means all available levels.}
}

\seealso{\code{xml_profile()}, \code{rectangle_xml()}}
