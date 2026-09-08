\name{xml_stream_rectangle}
\alias{xml_stream_rectangle}
\title{Stream complete XML records through a rectangle callback}
\description{Apply an explicit profile/specification while preserving repeated values and output order. Parallelism is an execution option of the same public workflow.}
\usage{
xml_stream_rectangle(
file,
spec,
callback,
document_id = NULL,
whitespace = NULL,
chunk_rows = 100000L,
batch_rows = 100000L,
id_check = c("memory", "none"),
parallel = FALSE,
workers = NULL,
strategy = "auto",
chunk_records = NULL,
task_records = NULL)
}
\arguments{
\item{file}{Path to the XML file.}
\item{spec}{A compiled rectangle specification.}
\item{callback}{Function called with each emitted rectangled result batch.}
\item{document_id}{Optional identifier attached to canonical rows.}
\item{whitespace}{Optional blank-text policy; when omitted, the specification policy is used.}
\item{chunk_rows}{Positive number controlling the canonical SAX node-buffer capacity.}
\item{batch_rows}{Maximum number of rectangled rows passed to a callback batch.}
\item{id_check}{For source identifiers, \code{"memory"} checks global uniqueness; \code{"none"} avoids retaining the uniqueness set.}
\item{parallel}{Execution mode: sequential, explicitly parallel, or automatic.}
\item{workers}{Optional positive number of parallel workers.}
\item{strategy}{Parallel scheduling strategy or \code{"auto"}.}
\item{chunk_records}{Optional number of complete XML records in an outer parallel chunk.}
\item{task_records}{Optional number of records per inner parallel task.}
}
\details{The streaming parser and record-boundary detection remain coordinator-side. Parallel workers receive only complete independent record subtrees.}
\seealso{\code{xml_profile()}, \code{rectangle_xml()}}
