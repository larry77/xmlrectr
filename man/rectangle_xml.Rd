\name{rectangle_xml}
\alias{rectangle_xml}
\title{Read and rectangle an XML file}
\description{Apply an explicit profile/specification while preserving repeated values and output order. Parallelism is an execution option of the same public workflow.}
\usage{
rectangle_xml(
file,
spec,
whitespace = NULL,
parallel = FALSE,
workers = NULL,
strategy = "auto",
chunk_records = NULL,
task_records = NULL,
progress = FALSE)
}
\arguments{
\item{file}{Path to the XML file to rectangle in memory.}
\item{spec}{A compiled rectangle specification or an \code{xml_profile}.}
\item{whitespace}{Optional blank-text policy. When omitted, the policy stored in the specification/profile is used.}
\item{parallel}{Execution mode: \code{FALSE} for sequential, \code{TRUE} for parallel, or \code{"auto"} to choose automatically.}
\item{workers}{Optional positive number of parallel workers. When omitted, a balanced default is chosen.}
\item{strategy}{Parallel scheduling strategy. \code{"auto"} chooses the context-appropriate default.}
\item{chunk_records}{Optional number of complete records in an outer processing chunk.}
\item{task_records}{Optional number of records assigned to each inner parallel task.}
\item{progress}{Logical; whether to emit progress events through \pkg{progressr} for supported in-memory parallel execution.}
}
\details{Use \code{parallel = FALSE} for the exact sequential path, \code{parallel = TRUE} to request tuned parallel defaults, or \code{parallel = "auto"} to let the engine avoid parallel overhead on small in-memory workloads.}
\seealso{\code{xml_profile()}, \code{rectangle_xml()}}
