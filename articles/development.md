# Architecture and validation

## Semantic reference first

`xmlrectr` was packaged only after the standalone engine reached a
frozen P6.1 validation point. The R implementation remains the semantic
reference; native C code accelerates canonical reading and
structural/indexing work without changing entity choice, naming, typing
or source-key policy.

## Canonical contract

Both in-memory and streaming execution preserve the same canonical
columns: `document_id`, `node_id`, `parent_id`, `node_order`,
`sibling_order`, `depth`, `node_type`, `qualified_name`, `local_name`,
`prefix`, `namespace_uri` and `value`.

## Parallel execution

Only complete independent XML record subtrees are sent to workers. The
coordinator retains SAX parsing, record-boundary detection, global
identifier checks, result ordering, callbacks and output publication.

Two strategies are retained intentionally:

- `parallel_chunks` for throughput;
- `shared_chunk` for reduced input-memory pressure through `mori`.

The public interface does not require users to choose between them for
routine work: `parallel = "auto"` applies structural scheduling rules
and automatic worker/chunk/task defaults.

## Validation before package conversion

The P6.1 standalone engine passed:

- the complete focused unit/regression suite;
- exact in-memory and streaming sequential/forced-parallel parity on 30
  structurally diverse real-world XML documents;
- exact parity on the same 30-file corpus through `parallel = "auto"`;
- synthetic scaling, worker-scaling and memory experiments used to
  derive the current balanced defaults.

The 30-file auto-policy run selected sequential execution for 29 small
workloads and parallel execution for the one sufficiently large/coarse
workload, while all outputs remained identical to the sequential oracle.

## Package conversion rule

The first package version intentionally keeps the validated R engine
consolidated in one file. Package-level regression tests should pass
before mechanically splitting the source into modules. New semantics
should never be mixed into a refactoring-only split.

The full engineering history, scheduler rationale, benchmark
interpretation and release checklist are maintained in the repository’s
`DEVELOPMENT.md`.
