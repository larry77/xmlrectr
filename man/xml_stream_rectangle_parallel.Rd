\name{xml_stream_rectangle_parallel}
\alias{xml_stream_rectangle_parallel}
\title{Stream XML records with explicit parallel execution}
\description{Lower-level explicit parallel entry point retained for diagnostics, regression tests and advanced tuning. Routine use should normally use the corresponding ordinary function with the parallel argument.}
\usage{
xml_stream_rectangle_parallel(
file,
spec,
callback,
document_id = NULL,
whitespace = NULL,
chunk_rows = 100000L,
batch_rows = 100000L,
id_check = c("memory", "none"),
workers = NULL,
strategy = c("shared_chunk", "parallel_chunks"),
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
\item{workers}{Optional positive number of parallel workers.}
\item{strategy}{Parallel scheduling strategy.}
\item{chunk_records}{Optional number of complete XML records in an outer parallel chunk.}
\item{task_records}{Optional number of records per inner parallel task.}
}

\seealso{\code{xml_profile()}, \code{rectangle_xml()}}
