\name{xml_rectangle}
\alias{xml_rectangle}
\title{Rectangle a canonical XML node table}
\description{Apply an explicit profile/specification while preserving repeated values and output order. Parallelism is an execution option of the same public workflow.}
\usage{
xml_rectangle(
nodes,
spec,
parallel = FALSE,
workers = NULL,
strategy = "auto",
chunk_records = NULL,
task_records = NULL,
progress = FALSE)
}
\arguments{
\item{nodes}{A canonical XML node table.}
\item{spec}{A compiled rectangle specification or an \code{xml_profile}.}
\item{parallel}{Execution mode: \code{FALSE}, \code{TRUE}, or \code{"auto"}.}
\item{workers}{Optional positive number of parallel workers.}
\item{strategy}{Parallel scheduling strategy or \code{"auto"}.}
\item{chunk_records}{Optional number of complete records in an outer processing chunk.}
\item{task_records}{Optional number of records per inner parallel task.}
\item{progress}{Logical; whether to emit progress events through \pkg{progressr}.}
}
\details{Use \code{parallel = FALSE} for the exact sequential path, \code{parallel = TRUE} to request tuned parallel defaults, or \code{parallel = "auto"} to let the engine avoid parallel overhead on small in-memory workloads.}
\seealso{\code{xml_profile()}, \code{rectangle_xml()}}
