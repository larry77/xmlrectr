\name{xml_rectangle_parallel}
\alias{xml_rectangle_parallel}
\title{Rectangle canonical nodes with explicit parallel execution}
\description{Lower-level explicit parallel entry point retained for diagnostics, regression tests and advanced tuning. Routine use should normally use the corresponding ordinary function with the parallel argument.}
\usage{
xml_rectangle_parallel(
nodes,
spec,
workers = NULL,
strategy = c("shared_chunk", "parallel_chunks"),
chunk_records = NULL,
task_records = NULL,
progress = FALSE)
}
\arguments{
\item{nodes}{A canonical XML node table.}
\item{spec}{A compiled rectangle specification or an \code{xml_profile}.}
\item{workers}{Optional positive number of parallel workers.}
\item{strategy}{Parallel scheduling strategy.}
\item{chunk_records}{Optional number of complete records in an outer processing chunk.}
\item{task_records}{Optional number of records per inner task.}
\item{progress}{Logical; whether to emit progress events through \pkg{progressr}.}
}

\seealso{\code{xml_profile()}, \code{rectangle_xml()}}
