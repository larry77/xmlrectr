# xmlrectr: generic XML rectangling for R
#
# This package engine is derived from the validated standalone XML rectangler.
# It keeps one canonical XML-node contract, explicit profile-based rectangling,
# analyst-oriented single-table projection, bounded streaming, CSV/Parquet
# writers, and record-level parallel execution behind one public interface.
#
# The source is intentionally kept consolidated in this first package version.
# That minimizes semantic drift from the validated standalone P6.1 engine.
# Mechanical modularization can happen only after package-level regression tests
# are green.


# -----------------------------------------------------------------------------
# Canonical node-table contract
# -----------------------------------------------------------------------------

.xml_node_columns <- c(
  "document_id",
  "node_id",
  "parent_id",
  "node_order",
  "sibling_order",
  "depth",
  "node_type",
  "qualified_name",
  "local_name",
  "prefix",
  "namespace_uri",
  "value"
)

.xml_nodes_with_names <- c(
  "element",
  "attribute",
  "pi"
)


.xml_rectangle_package_state <- new.env(parent = emptyenv())

.require_xml_rectangle_package <- function(package) {
  # Package availability does not change during one sourced prototype session.
  # Cache successful checks so the hot native analyst path does not repeatedly
  # enter requireNamespace()/namespace lookup machinery. The first use still
  # performs the normal check and preserves the same user-facing error.
  if (isTRUE(.xml_rectangle_package_state[[package]])) {
    return(invisible(TRUE))
  }

  if (!requireNamespace(package, quietly = TRUE)) {
    stop(
      sprintf(
        "Install the `%s` package to use this xmlrectr feature.",
        package
      ),
      call. = FALSE
    )
  }

  .xml_rectangle_package_state[[package]] <- TRUE
  invisible(TRUE)
}


#' Return an empty canonical XML node table
#'
#' This function is the executable schema definition.  Returning the same
#' column types for an empty document, a filtered document, and a populated
#' document prevents downstream Arrow and Parquet schemas from drifting.
xml_nodes_schema <- function() {
  .require_xml_rectangle_package("tibble")

  tibble::tibble(
    document_id = character(),
    node_id = integer(),
    parent_id = integer(),
    node_order = integer(),
    sibling_order = integer(),
    depth = integer(),
    node_type = character(),
    qualified_name = character(),
    local_name = character(),
    prefix = character(),
    namespace_uri = character(),
    value = character()
  )
}




# -----------------------------------------------------------------------------
# Experimental native canonical engine (v11)
# -----------------------------------------------------------------------------

.xml_native_core_state <- new.env(parent = emptyenv())
.xml_native_core_state$loaded <- FALSE

.xml_load_native_core <- function() {
  # Package installation loads the registered native DLL through NAMESPACE.
  # Keep this explicit guard so native-engine requests fail with a useful
  # package-level message rather than an opaque .Call() lookup error.
  if (
    is.loaded("C_xmlrect_native_read", PACKAGE = "xmlrectr") &&
      is.loaded("C_xmlrect_native_analyst_plan", PACKAGE = "xmlrectr")
  ) {
    .xml_native_core_state$loaded <- TRUE
    return(invisible(TRUE))
  }

  stop(
    paste0(
      "The xmlrectr native library is not loaded. Reinstall xmlrectr from ",
      "source and ensure the libxml2 development files are available."
    ),
    call. = FALSE
  )
}

.xml_requested_canonical_engine <- function() {
  engine <- tolower(trimws(
    Sys.getenv("XML_RECT_CANONICAL_ENGINE", unset = "r")
  ))

  if (!engine %in% c("r", "native")) {
    stop(
      "XML_RECT_CANONICAL_ENGINE must be either `r` or `native`.",
      call. = FALSE
    )
  }

  engine
}

.xml_to_nodes_memory_native_raw <- function(file, document_id, whitespace) {
  .xml_load_native_core()

  raw <- tryCatch(
    .Call(
      "C_xmlrect_native_read",
      file,
      document_id,
      identical(whitespace, "drop_blank"),
      PACKAGE = "xmlrectr"
    ),
    error = function(condition) {
      .stop_xml_parse_error(
        sprintf(
          "Could not parse XML source: %s",
          conditionMessage(condition)
        ),
        source = document_id
      )
    }
  )

  # The native reader already returns canonical columns with equal lengths.
  # Give the list ordinary data-frame semantics without copying any column
  # vectors.  The public reader validates and converts this to a tibble; the
  # direct native XML -> analyst path can consume this trusted internal bundle
  # without paying tibble dispatch costs throughout the hot projection path.
  class(raw) <- "data.frame"
  attr(raw, "row.names") <- c(NA_integer_, -length(raw[[1L]]))
  raw
}

.xml_to_nodes_memory_native <- function(file, document_id, whitespace) {
  .require_xml_rectangle_package("tibble")
  result <- .xml_to_nodes_memory_native_raw(file, document_id, whitespace)
  validate_xml_nodes(result)
  tibble::as_tibble(result)
}



# Analyst execution engine. The frozen R implementation remains the reference;
# the native engine accelerates structural indexing without changing the public
# analyst-table contract.
.xml_requested_analyst_engine <- function() {
  engine <- tolower(trimws(
    Sys.getenv("XML_RECT_ANALYST_ENGINE", unset = "r")
  ))
  if (!engine %in% c("r", "native")) {
    stop(
      "XML_RECT_ANALYST_ENGINE must be either `r` or `native`.",
      call. = FALSE
    )
  }
  engine
}

.xml_native_analyst_plan <- function(nodes) {
  .xml_load_native_core()
  .Call(
    "C_xmlrect_native_analyst_plan",
    nodes$node_id,
    nodes$parent_id,
    nodes$depth,
    nodes$node_type,
    nodes$local_name,
    nodes$namespace_uri,
    PACKAGE = "xmlrectr"
  )
}

.xml_native_entity_map <- function(
  element_node_id,
  element_parent_id,
  element_path_id,
  entity_path_id,
  maximum_node_id
) {
  .xml_load_native_core()
  .Call(
    "C_xmlrect_native_entity_map",
    as.integer(element_node_id),
    as.integer(element_parent_id),
    as.integer(element_path_id),
    as.integer(entity_path_id),
    as.integer(maximum_node_id),
    PACKAGE = "xmlrectr"
  )
}


.xml_native_project_fields <- function(
  entity_node_id,
  parent_entity_node_id,
  entity_depth,
  field_column_id,
  field_owner_id,
  field_values,
  column_logical,
  column_propagate
) {
  .xml_load_native_core()
  .Call(
    "C_xmlrect_native_project_fields",
    as.integer(entity_node_id),
    as.integer(parent_entity_node_id),
    as.integer(entity_depth),
    as.integer(field_column_id),
    as.integer(field_owner_id),
    field_values,
    as.logical(column_logical),
    as.logical(column_propagate),
    PACKAGE = "xmlrectr"
  )
}


.xml_native_field_layout <- function(
  owner_id,
  entity_path_id,
  source_signature,
  field_order
) {
  .xml_load_native_core()
  .Call(
    "C_xmlrect_native_field_layout",
    as.integer(owner_id),
    as.integer(entity_path_id),
    as.character(source_signature),
    as.integer(field_order),
    PACKAGE = "xmlrectr"
  )
}


.xml_native_infer_types <- function(columns) {
  .xml_load_native_core()
  .Call(
    "C_xmlrect_native_infer_types",
    unname(columns),
    PACKAGE = "xmlrectr"
  )
}

# -----------------------------------------------------------------------------
# Small validation helpers
# -----------------------------------------------------------------------------

.validate_one_string <- function(
  value,
  argument,
  allow_empty = FALSE
) {
  valid <- is.character(value) &&
    length(value) == 1L &&
    !is.na(value) &&
    (allow_empty || nzchar(value))

  if (!valid) {
    qualifier <- if (allow_empty) {
      "one non-missing character value"
    } else {
      "one non-empty character value"
    }

    stop(
      sprintf("`%s` must be %s.", argument, qualifier),
      call. = FALSE
    )
  }

  value
}


.stop_xml_parse_error <- function(message, source = NULL) {
  # A dedicated condition class lets calling code distinguish malformed XML
  # from a missing file, an ambiguous friendly name, or an unsafe rectangle.
  # The original parser message remains visible to the user; the function does
  # not attempt recovery because silently repairing input can change content.
  condition <- structure(
    list(
      message = message,
      call = NULL,
      source = source
    ),
    class = c("xml_parse_error", "error", "condition")
  )

  stop(condition)
}


.stop_xml_callback_error <- function(parent) {
  # XML::xmlEventParse() catches errors raised inside SAX handlers and passes
  # them through its own error path.  Mark consumer failures temporarily so
  # the outer parser wrapper can restore the original condition instead of
  # misreporting, for example, a failed database write as malformed XML.
  condition <- structure(
    list(
      message = conditionMessage(parent),
      call = NULL,
      parent = parent
    ),
    class = c("xml_callback_error", "error", "condition")
  )

  stop(condition)
}


.validate_initial_capacity <- function(initial_capacity) {
  valid <- is.numeric(initial_capacity) &&
    length(initial_capacity) == 1L &&
    !is.na(initial_capacity) &&
    is.finite(initial_capacity) &&
    initial_capacity >= 1 &&
    initial_capacity <= .Machine$integer.max &&
    initial_capacity == floor(initial_capacity)

  if (!valid) {
    stop(
      "`initial_capacity` must be one positive whole number.",
      call. = FALSE
    )
  }

  as.integer(initial_capacity)
}


.validate_chunk_rows <- function(chunk_rows) {
  valid <- is.numeric(chunk_rows) &&
    length(chunk_rows) == 1L &&
    !is.na(chunk_rows) &&
    is.finite(chunk_rows) &&
    chunk_rows >= 1 &&
    chunk_rows <= .Machine$integer.max &&
    chunk_rows == floor(chunk_rows)

  if (!valid) {
    stop(
      "`chunk_rows` must be one positive whole number.",
      call. = FALSE
    )
  }

  as.integer(chunk_rows)
}


# -----------------------------------------------------------------------------
# Efficient row builder
# -----------------------------------------------------------------------------

.new_xml_node_builder <- function(
  document_id,
  initial_capacity = 1024L
) {
  initial_capacity <- .validate_initial_capacity(initial_capacity)

  state <- new.env(parent = emptyenv())
  state$document_id_value <- document_id
  state$size <- 0L
  state$capacity <- initial_capacity

  # Atomic vectors are preallocated and doubled when necessary.  Repeatedly
  # growing a data frame with rbind() would make large in-memory documents much
  # slower and would create avoidable transient copies.
  state$document_id <- rep.int(NA_character_, initial_capacity)
  state$node_id <- rep.int(NA_integer_, initial_capacity)
  state$parent_id <- rep.int(NA_integer_, initial_capacity)
  state$node_order <- rep.int(NA_integer_, initial_capacity)
  state$sibling_order <- rep.int(NA_integer_, initial_capacity)
  state$depth <- rep.int(NA_integer_, initial_capacity)
  state$node_type <- rep.int(NA_character_, initial_capacity)
  state$qualified_name <- rep.int(NA_character_, initial_capacity)
  state$local_name <- rep.int(NA_character_, initial_capacity)
  state$prefix <- rep.int(NA_character_, initial_capacity)
  state$namespace_uri <- rep.int(NA_character_, initial_capacity)
  state$value <- rep.int(NA_character_, initial_capacity)

  grow <- function(required_size) {
    if (required_size <= state$capacity) {
      return(invisible(NULL))
    }

    # Coerce before multiplication so an already-large integer capacity cannot
    # overflow merely while calculating the next allocation size.
    doubled_capacity <- min(
      as.double(.Machine$integer.max),
      as.double(state$capacity) * 2
    )

    new_capacity <- max(
      as.double(required_size),
      doubled_capacity
    )

    if (new_capacity < required_size) {
      stop(
        "The XML document contains too many nodes for an R integer index.",
        call. = FALSE
      )
    }

    for (column in .xml_node_columns) {
      length(state[[column]]) <- new_capacity
    }

    state$capacity <- as.integer(new_capacity)
    invisible(NULL)
  }

  add <- function(
    parent_id,
    sibling_order,
    depth,
    node_type,
    qualified_name,
    local_name,
    prefix,
    namespace_uri,
    value
  ) {
    row <- state$size + 1L
    grow(row)

    # node_id is deliberately allocated in preorder.  node_order is retained
    # as a separate field so that identity and ordering do not become the same
    # conceptual property merely because they coincide in this implementation.
    state$document_id[[row]] <- state$document_id_value
    state$node_id[[row]] <- row
    state$parent_id[[row]] <- parent_id
    state$node_order[[row]] <- row
    state$sibling_order[[row]] <- sibling_order
    state$depth[[row]] <- depth
    state$node_type[[row]] <- node_type
    state$qualified_name[[row]] <- qualified_name
    state$local_name[[row]] <- local_name
    state$prefix[[row]] <- prefix
    state$namespace_uri[[row]] <- namespace_uri
    state$value[[row]] <- value

    state$size <- row
    row
  }

  finish <- function() {
    .require_xml_rectangle_package("tibble")

    if (state$size == 0L) {
      return(xml_nodes_schema())
    }

    keep <- seq_len(state$size)

    tibble::tibble(
      document_id = state$document_id[keep],
      node_id = state$node_id[keep],
      parent_id = state$parent_id[keep],
      node_order = state$node_order[keep],
      sibling_order = state$sibling_order[keep],
      depth = state$depth[keep],
      node_type = state$node_type[keep],
      qualified_name = state$qualified_name[keep],
      local_name = state$local_name[keep],
      prefix = state$prefix[keep],
      namespace_uri = state$namespace_uri[keep],
      value = state$value[keep]
    )
  }

  list(
    add = add,
    finish = finish
  )
}


# -----------------------------------------------------------------------------
# XML-node normalization
# -----------------------------------------------------------------------------

.xml_normalize_node_type <- function(node) {
  type <- xml2::xml_type(node)

  # xml2 has used both concise and libxml-inspired names at different API
  # boundaries.  Normalizing here keeps the public table independent of those
  # implementation details and gives the streaming engine a fixed vocabulary.
  aliases <- c(
    xml_document = "document",
    document = "document",
    element = "element",
    attribute = "attribute",
    text = "text",
    cdata = "cdata",
    entity_ref = "entity_ref",
    entity = "entity",
    comment = "comment",
    pi = "pi",
    document_type = "dtd",
    dtd = "dtd",
    document_frag = "document_fragment",
    namespace_decl = "namespace"
  )

  normalized <- unname(aliases[type])

  if (length(normalized) == 0L || is.na(normalized)) {
    # Unknown libxml node kinds are retained rather than silently discarded.
    # Their serialized representation is placed in `value` by
    # .xml_node_value(), allowing a later milestone to add first-class support.
    return(as.character(type))
  }

  normalized
}


.xml_name_parts <- function(node, node_type) {
  empty <- list(
    qualified_name = NA_character_,
    local_name = NA_character_,
    prefix = NA_character_,
    namespace_uri = NA_character_
  )

  if (!node_type %in% .xml_nodes_with_names) {
    return(empty)
  }

  # XPath's name functions work for both elements and attribute nodes and are
  # less ambiguous than guessing namespace prefixes from declarations in scope.
  qualified_name <- xml2::xml_find_chr(node, "name(.)")
  local_name <- xml2::xml_find_chr(node, "local-name(.)")
  namespace_uri <- xml2::xml_find_chr(node, "namespace-uri(.)")

  if (!nzchar(qualified_name)) {
    qualified_name <- NA_character_
  }

  if (!nzchar(local_name)) {
    local_name <- NA_character_
  }

  prefix <- if (
    !is.na(qualified_name) &&
      grepl(":", qualified_name, fixed = TRUE)
  ) {
    sub(":.*$", "", qualified_name)
  } else {
    ""
  }

  list(
    qualified_name = qualified_name,
    local_name = local_name,
    prefix = prefix,
    namespace_uri = namespace_uri
  )
}


.xml_node_value <- function(node, node_type) {
  if (node_type %in% c("document", "element")) {
    return(NA_character_)
  }

  if (node_type == "dtd") {
    return(as.character(node))
  }

  value <- tryCatch(
    xml2::xml_text(node, trim = FALSE),
    error = function(condition) {
      NA_character_
    }
  )

  if (length(value) == 1L && !is.na(value)) {
    return(as.character(value))
  }

  # Serialization is a conservative fallback for uncommon libxml node kinds.
  # It is intentionally not used for normal elements because doing so would
  # duplicate complete subtrees in the value column.
  serialized <- tryCatch(
    as.character(node),
    error = function(condition) {
      NA_character_
    }
  )

  if (length(serialized) == 0L) {
    NA_character_
  } else {
    serialized[[1L]]
  }
}


.xml_is_blank_text <- function(node, node_type) {
  if (node_type != "text") {
    return(FALSE)
  }

  value <- .xml_node_value(node, node_type)

  !is.na(value) && grepl("^[[:space:]]*$", value)
}


.xml_walk_node <- function(
  node,
  parent_id,
  sibling_order,
  depth,
  builder,
  whitespace
) {
  node_type <- .xml_normalize_node_type(node)

  if (
    whitespace == "drop_blank" &&
      .xml_is_blank_text(node, node_type)
  ) {
    return(invisible(NULL))
  }

  name <- .xml_name_parts(node, node_type)

  current_id <- builder$add(
    parent_id = parent_id,
    sibling_order = sibling_order,
    depth = depth,
    node_type = node_type,
    qualified_name = name$qualified_name,
    local_name = name$local_name,
    prefix = name$prefix,
    namespace_uri = name$namespace_uri,
    value = .xml_node_value(node, node_type)
  )

  if (node_type == "element") {
    attributes <- xml2::xml_find_all(node, "./@*")

    # XML attributes are properties of an element, not ordered child content.
    # We therefore represent them as rows whose parent is the owning element
    # while leaving sibling_order missing.  This avoids pretending that
    # attribute order carries XML semantic meaning.
    if (length(attributes) > 0L) {
      for (attribute_index in seq_along(attributes)) {
        attribute <- attributes[[attribute_index]]

        .xml_walk_node(
          node = attribute,
          parent_id = current_id,
          sibling_order = NA_integer_,
          depth = depth + 1L,
          builder = builder,
          whitespace = whitespace
        )
      }
    }
  }

  if (!node_type %in% c("document", "element")) {
    return(invisible(current_id))
  }

  contents <- xml2::xml_contents(node)
  retained_position <- 0L

  if (length(contents) > 0L) {
    for (child_index in seq_along(contents)) {
      child <- contents[[child_index]]
      child_type <- .xml_normalize_node_type(child)

      if (
        whitespace == "drop_blank" &&
          .xml_is_blank_text(child, child_type)
      ) {
        next
      }

      retained_position <- retained_position + 1L

      .xml_walk_node(
        node = child,
        parent_id = current_id,
        sibling_order = retained_position,
        depth = depth + 1L,
        builder = builder,
        whitespace = whitespace
      )
    }
  }

  invisible(current_id)
}


# -----------------------------------------------------------------------------
# Public in-memory readers
# -----------------------------------------------------------------------------

.xml_to_nodes_memory <- function(
  source,
  document_id,
  whitespace,
  initial_capacity
) {
  .require_xml_rectangle_package("xml2")
  .require_xml_rectangle_package("tibble")
  initial_capacity <- .validate_initial_capacity(initial_capacity)

  whitespace <- match.arg(
    whitespace,
    c("preserve", "drop_blank")
  )

  document <- tryCatch(
    # NONET is a security boundary for arbitrary input: external resources must
    # not be retrieved merely because an XML document references them.  We do
    # not request NOBLANKS because whitespace policy belongs to this script and
    # must behave identically in the later SAX implementation.
    xml2::read_xml(
      source,
      options = "NONET"
    ),
    error = function(condition) {
      .stop_xml_parse_error(
        sprintf(
          "Could not parse XML source: %s",
          conditionMessage(condition)
        ),
        source = document_id
      )
    }
  )

  # Select every canonical XML node in document order. `//node()` includes
  # top-level document children (including the document element, comments, and
  # processing instructions) plus all descendant nodes; `//@*` adds attributes.
  # XPath union ordering preserves canonical preorder: an element is followed
  # by its attributes and then its child content. This is equivalent to the
  # older three-branch union, with fewer redundant tree scans.
  xml_nodes <- xml2::xml_find_all(document, "//node() | //@*")

  if (length(xml_nodes) == 0L) {
    stop(
      "The parsed XML document contains no top-level nodes.",
      call. = FALSE
    )
  }

  raw_types <- xml2::xml_type(xml_nodes)
  aliases <- c(
    xml_document = "document",
    document = "document",
    element = "element",
    attribute = "attribute",
    text = "text",
    cdata = "cdata",
    entity_ref = "entity_ref",
    entity = "entity",
    comment = "comment",
    pi = "pi",
    document_type = "dtd",
    dtd = "dtd",
    document_frag = "document_fragment",
    namespace_decl = "namespace"
  )
  node_type <- unname(aliases[raw_types])
  node_type[is.na(node_type)] <- raw_types[is.na(node_type)]

  # xml_text() is vectorized and returns the scalar content needed for every
  # non-container node kind.  Values for documents and elements deliberately
  # remain missing so descendant text is never duplicated in ancestor rows.
  value <- rep.int(NA_character_, length(xml_nodes))
  value_rows <- which(!node_type %in% c("document", "element"))

  if (length(value_rows) > 0L) {
    value[value_rows] <- xml2::xml_text(
      xml_nodes[value_rows],
      trim = FALSE
    )
  }

  keep <- rep.int(TRUE, length(xml_nodes))

  if (whitespace == "drop_blank") {
    blank_text <- node_type == "text" &
      !is.na(value) &
      grepl("^[[:space:]]*$", value)
    keep[blank_text] <- FALSE
  }

  xml_nodes <- xml_nodes[keep]
  node_type <- node_type[keep]
  value <- value[keep]

  # xml_path() supplies a unique structural key for every retained libxml
  # node.  Removing its last segment yields the owning element's path.  A path
  # with no retained parent belongs directly to our explicit synthetic
  # document row, which also owns top-level comments and instructions.
  node_path <- xml2::xml_path(xml_nodes)
  parent_path <- sub("/[^/]+$", "", node_path)
  parent_match <- match(parent_path, node_path)
  parent_id <- ifelse(is.na(parent_match), 1L, parent_match + 1L)

  qualified_name <- rep.int(NA_character_, length(xml_nodes))
  local_name <- rep.int(NA_character_, length(xml_nodes))
  namespace_uri <- rep.int(NA_character_, length(xml_nodes))
  prefix <- rep.int(NA_character_, length(xml_nodes))
  named_rows <- which(node_type %in% .xml_nodes_with_names)

  if (length(named_rows) > 0L) {
    named_nodes <- xml_nodes[named_rows]

    # One XPath evaluation per named node instead of three. The lexical-name
    # length makes decoding exact even if the namespace URI contains `|`.
    encoded_name <- xml2::xml_find_chr(
      named_nodes,
      "concat(string-length(name(.)), '|', name(.), namespace-uri(.))"
    )
    separator <- regexpr("|", encoded_name, fixed = TRUE)
    name_length <- as.integer(substr(encoded_name, 1L, separator - 1L))
    payload_start <- separator + 1L
    qualified <- substring(
      encoded_name,
      payload_start,
      payload_start + name_length - 1L
    )
    uri <- substring(encoded_name, payload_start + name_length)

    qualified_name[named_rows] <- qualified
    local_name[named_rows] <- sub("^.*:", "", qualified)
    namespace_uri[named_rows] <- uri

    qualified_name[qualified_name == ""] <- NA_character_
    local_name[local_name == ""] <- NA_character_

    prefixed <- !is.na(qualified_name) &
      grepl(":", qualified_name, fixed = TRUE)
    prefix[prefixed] <- sub(":.*$", "", qualified_name[prefixed])
    prefix[!prefixed & !is.na(qualified_name)] <- ""
  }

  number_of_nodes <- length(xml_nodes) + 1L
  sibling_order <- rep.int(NA_integer_, number_of_nodes)
  depth <- rep.int(NA_integer_, number_of_nodes)
  depth[[1L]] <- 0L
  sibling_counts <- integer(number_of_nodes)

  # Only ordered child content contributes to sibling_order; attributes are
  # intentionally left missing because XML does not assign them child order.
  # Parent rows precede children, so depth and the next sibling number can be
  # assigned in one bounded linear pass.
  for (row in seq_along(xml_nodes)) {
    output_row <- row + 1L
    owner <- parent_id[[row]]
    depth[[output_row]] <- depth[[owner]] + 1L

    if (node_type[[row]] != "attribute") {
      sibling_counts[[owner]] <- sibling_counts[[owner]] + 1L
      sibling_order[[output_row]] <- sibling_counts[[owner]]
    }
  }

  result <- tibble::tibble(
    document_id = rep.int(document_id, number_of_nodes),
    node_id = seq_len(number_of_nodes),
    parent_id = c(NA_integer_, as.integer(parent_id)),
    node_order = seq_len(number_of_nodes),
    sibling_order = sibling_order,
    depth = depth,
    node_type = c("document", node_type),
    qualified_name = c(NA_character_, qualified_name),
    local_name = c(NA_character_, local_name),
    prefix = c(NA_character_, prefix),
    namespace_uri = c(NA_character_, namespace_uri),
    value = c(NA_character_, value)
  )

  validate_xml_nodes(result)
  result
}


#' Read an XML file into the canonical node table in memory
#'
#' `whitespace = "preserve"` retains whitespace-only text nodes, which is the
#' loss-conscious default.  `"drop_blank"` removes indentation-only text while
#' retaining spaces that occur inside non-blank text nodes.
xml_to_nodes_memory <- function(
  file,
  document_id = NULL,
  whitespace = c("preserve", "drop_blank"),
  initial_capacity = 1024L
) {
  whitespace <- match.arg(whitespace)
  file <- .validate_one_string(file, "file")

  if (!file.exists(file)) {
    stop(
      sprintf("XML file does not exist: %s", file),
      call. = FALSE
    )
  }

  normalized_file <- normalizePath(
    file,
    winslash = "/",
    mustWork = TRUE
  )

  if (is.null(document_id)) {
    document_id <- basename(normalized_file)
  }

  document_id <- .validate_one_string(
    document_id,
    "document_id"
  )

  if (identical(.xml_requested_canonical_engine(), "native")) {
    return(.xml_to_nodes_memory_native(
      file = normalized_file,
      document_id = document_id,
      whitespace = whitespace
    ))
  }

  .xml_to_nodes_memory(
    source = normalized_file,
    document_id = document_id,
    whitespace = whitespace,
    initial_capacity = initial_capacity
  )
}


#' Read literal XML text into the canonical node table in memory
#'
#' This companion is useful for unit tests, generated documents, and API
#' responses that are already in memory.  It remains explicit so a short path
#' string can never be mistaken for XML content.
xml_text_to_nodes_memory <- function(
  text,
  document_id = "inline-xml",
  whitespace = c("preserve", "drop_blank"),
  initial_capacity = 1024L
) {
  whitespace <- match.arg(whitespace)
  text <- .validate_one_string(
    text,
    "text",
    allow_empty = FALSE
  )

  document_id <- .validate_one_string(
    document_id,
    "document_id"
  )

  .xml_to_nodes_memory(
    source = text,
    document_id = document_id,
    whitespace = whitespace,
    initial_capacity = initial_capacity
  )
}


# -----------------------------------------------------------------------------
# Sequential streaming readers
# -----------------------------------------------------------------------------

.new_xml_chunk_builder <- function(
  document_id,
  chunk_rows,
  callback
) {
  .require_xml_rectangle_package("tibble")

  chunk_rows <- .validate_chunk_rows(chunk_rows)

  state <- new.env(parent = emptyenv())
  state$size <- 0L
  state$total_nodes <- 0L
  state$total_chunks <- 0L
  state$callback_error <- NULL

  allocate_chunk <- function() {
    # Only one output chunk is retained by the parser.  Once the callback has
    # accepted it these vectors are replaced, so memory does not grow with the
    # number of XML nodes.  The callback itself controls whether rows are kept,
    # aggregated, or written to an external format.
    state$document_id <- rep.int(document_id, chunk_rows)
    state$node_id <- rep.int(NA_integer_, chunk_rows)
    state$parent_id <- rep.int(NA_integer_, chunk_rows)
    state$node_order <- rep.int(NA_integer_, chunk_rows)
    state$sibling_order <- rep.int(NA_integer_, chunk_rows)
    state$depth <- rep.int(NA_integer_, chunk_rows)
    state$node_type <- rep.int(NA_character_, chunk_rows)
    state$qualified_name <- rep.int(NA_character_, chunk_rows)
    state$local_name <- rep.int(NA_character_, chunk_rows)
    state$prefix <- rep.int(NA_character_, chunk_rows)
    state$namespace_uri <- rep.int(NA_character_, chunk_rows)
    state$value <- rep.int(NA_character_, chunk_rows)
    state$size <- 0L
    invisible(NULL)
  }

  flush <- function() {
    if (state$size == 0L) {
      return(invisible(NULL))
    }

    keep <- seq_len(state$size)

    chunk <- tibble::tibble(
      document_id = state$document_id[keep],
      node_id = state$node_id[keep],
      parent_id = state$parent_id[keep],
      node_order = state$node_order[keep],
      sibling_order = state$sibling_order[keep],
      depth = state$depth[keep],
      node_type = state$node_type[keep],
      qualified_name = state$qualified_name[keep],
      local_name = state$local_name[keep],
      prefix = state$prefix[keep],
      namespace_uri = state$namespace_uri[keep],
      value = state$value[keep]
    )

    # Any callback error is allowed to propagate.  Silently continuing after a
    # failed database or file write would create a deceptively complete-looking
    # result with a missing middle section.
    tryCatch(
      callback(chunk),
      error = function(condition) {
        if (inherits(condition, "xml_callback_error")) {
          stop(condition)
        }

        state$callback_error <- condition
        .stop_xml_callback_error(condition)
      }
    )
    state$total_chunks <- state$total_chunks + 1L
    allocate_chunk()
    invisible(NULL)
  }

  add <- function(
    parent_id,
    sibling_order,
    depth,
    node_type,
    qualified_name,
    local_name,
    prefix,
    namespace_uri,
    value
  ) {
    if (state$total_nodes >= .Machine$integer.max) {
      stop(
        "The XML document contains too many nodes for an R integer index.",
        call. = FALSE
      )
    }

    row <- state$size + 1L
    node_id <- state$total_nodes + 1L

    state$node_id[[row]] <- node_id
    state$parent_id[[row]] <- parent_id
    state$node_order[[row]] <- node_id
    state$sibling_order[[row]] <- sibling_order
    state$depth[[row]] <- depth
    state$node_type[[row]] <- node_type
    state$qualified_name[[row]] <- qualified_name
    state$local_name[[row]] <- local_name
    state$prefix[[row]] <- prefix
    state$namespace_uri[[row]] <- namespace_uri
    state$value[[row]] <- value

    state$size <- row
    state$total_nodes <- node_id

    if (state$size == chunk_rows) {
      flush()
    }

    node_id
  }

  finish <- function() {
    flush()

    list(
      node_count = state$total_nodes,
      chunk_count = state$total_chunks
    )
  }

  allocate_chunk()

  list(
    add = add,
    finish = finish,
    callback_error = function() state$callback_error
  )
}


.sax_element_name_parts <- function(local_name, namespace) {
  local_name <- as.character(local_name)[[1L]]
  namespace_uri <- ""
  prefix <- ""

  if (length(namespace) > 0L && !is.na(namespace[[1L]])) {
    namespace_uri <- as.character(namespace[[1L]])

    namespace_names <- names(namespace)

    if (
      length(namespace_names) > 0L &&
        !is.na(namespace_names[[1L]])
    ) {
      prefix <- namespace_names[[1L]]
    }
  }

  # SAX2 normally supplies a local name and carries the prefix on the namespace
  # vector.  The fallback also accepts parsers that return a qualified name.
  if (grepl(":", local_name, fixed = TRUE)) {
    qualified_name <- local_name

    if (!nzchar(prefix)) {
      prefix <- sub(":.*$", "", local_name)
    }

    local_name <- sub("^[^:]*:", "", local_name)
  } else {
    qualified_name <- if (nzchar(prefix)) {
      paste0(prefix, ":", local_name)
    } else {
      local_name
    }
  }

  list(
    qualified_name = qualified_name,
    local_name = local_name,
    prefix = prefix,
    namespace_uri = namespace_uri
  )
}


.sax_attribute_name_parts <- function(
  attributes,
  attribute_index
) {
  attribute_names <- names(attributes)

  if (
    length(attribute_names) < attribute_index ||
      is.na(attribute_names[[attribute_index]]) ||
      !nzchar(attribute_names[[attribute_index]])
  ) {
    stop(
      "The SAX parser returned an attribute without a name.",
      call. = FALSE
    )
  }

  local_name <- attribute_names[[attribute_index]]
  namespace_uri <- ""
  prefix <- ""

  # In the XML package's SAX2 interface, this attribute is parallel to the
  # values vector: its values are namespace URIs and its names are prefixes.
  attribute_namespaces <- attr(
    attributes,
    "namespaces",
    exact = TRUE
  )

  if (
    length(attribute_namespaces) >= attribute_index &&
      !is.na(attribute_namespaces[[attribute_index]])
  ) {
    namespace_uri <- as.character(
      attribute_namespaces[[attribute_index]]
    )

    namespace_prefixes <- names(attribute_namespaces)

    if (
      length(namespace_prefixes) >= attribute_index &&
        !is.na(namespace_prefixes[[attribute_index]])
    ) {
      prefix <- namespace_prefixes[[attribute_index]]
    }
  }

  if (grepl(":", local_name, fixed = TRUE)) {
    qualified_name <- local_name

    if (!nzchar(prefix)) {
      prefix <- sub(":.*$", "", local_name)
    }

    local_name <- sub("^[^:]*:", "", local_name)
  } else {
    qualified_name <- if (nzchar(prefix)) {
      paste0(prefix, ":", local_name)
    } else {
      local_name
    }
  }

  list(
    qualified_name = qualified_name,
    local_name = local_name,
    prefix = prefix,
    namespace_uri = namespace_uri
  )
}


.decode_sax_numeric_references <- function(value) {
  # XML::xmlEventParse() exposes numeric character references in attribute
  # values literally (for example `&#38;`) even though the DOM reader returns
  # their decoded character.  Decode just this parser-specific residue so both
  # engines represent the same XML Infoset value.  Named/custom entities remain
  # the parser's responsibility, and malformed references are never repaired.
  value <- as.character(value)[[1L]]
  matches <- gregexpr(
    "&#(?:[xX][0-9A-Fa-f]+|[0-9]+);",
    value,
    perl = TRUE
  )[[1L]]

  if (length(matches) == 1L && matches[[1L]] == -1L) {
    return(value)
  }

  references <- regmatches(value, list(matches))[[1L]]
  code_points <- vapply(
    references,
    function(reference) {
      encoded <- sub("^&#", "", sub(";$", "", reference))

      if (grepl("^[xX]", encoded)) {
        strtoi(sub("^[xX]", "", encoded), base = 16L)
      } else {
        strtoi(encoded, base = 10L)
      }
    },
    integer(1)
  )
  decoded <- vapply(code_points, intToUtf8, character(1))
  regmatches(value, list(matches)) <- list(decoded)
  value
}


.xml_stream_nodes <- function(
  file,
  document_id,
  whitespace,
  chunk_rows,
  callback
) {
  .require_xml_rectangle_package("XML")
  .require_xml_rectangle_package("tibble")

  builder <- .new_xml_chunk_builder(
    document_id = document_id,
    chunk_rows = chunk_rows,
    callback = callback
  )

  state <- new.env(parent = emptyenv())
  state$element_ids <- integer()
  state$element_names <- character()
  state$child_counts <- integer()
  state$document_child_count <- 0L
  state$pending_type <- NULL
  state$pending_value <- ""
  state$pending_parent_id <- NA_integer_
  state$pending_depth <- NA_integer_

  document_node_id <- builder$add(
    parent_id = NA_integer_,
    sibling_order = NA_integer_,
    depth = 0L,
    node_type = "document",
    qualified_name = NA_character_,
    local_name = NA_character_,
    prefix = NA_character_,
    namespace_uri = NA_character_,
    value = NA_character_
  )

  current_parent_id <- function() {
    if (length(state$element_ids) == 0L) {
      document_node_id
    } else {
      state$element_ids[[length(state$element_ids)]]
    }
  }

  next_sibling_order <- function() {
    level <- length(state$child_counts)

    if (level == 0L) {
      state$document_child_count <- state$document_child_count + 1L
      return(state$document_child_count)
    }

    state$child_counts[[level]] <- state$child_counts[[level]] + 1L
    state$child_counts[[level]]
  }

  flush_pending <- function() {
    if (is.null(state$pending_type)) {
      return(invisible(NULL))
    }

    value <- state$pending_value
    node_type <- state$pending_type

    # The event parser is allowed to divide one logical text node into several
    # callbacks.  Whitespace filtering must therefore happen only after those
    # adjacent pieces have been coalesced; otherwise chunk boundaries could
    # change the result.
    keep <- !(
      node_type == "text" &&
        whitespace == "drop_blank" &&
        grepl("^[[:space:]]*$", value)
    )

    if (keep && nzchar(value)) {
      builder$add(
        parent_id = state$pending_parent_id,
        sibling_order = next_sibling_order(),
        depth = state$pending_depth,
        node_type = node_type,
        qualified_name = NA_character_,
        local_name = NA_character_,
        prefix = NA_character_,
        namespace_uri = NA_character_,
        value = value
      )
    }

    state$pending_type <- NULL
    state$pending_value <- ""
    state$pending_parent_id <- NA_integer_
    state$pending_depth <- NA_integer_
    invisible(NULL)
  }

  queue_character_data <- function(node_type, content) {
    content <- paste0(as.character(content), collapse = "")

    if (!nzchar(content)) {
      return(invisible(NULL))
    }

    parent_id <- current_parent_id()
    depth <- length(state$element_ids) + 1L

    same_logical_node <- !is.null(state$pending_type) &&
      identical(state$pending_type, node_type) &&
      identical(state$pending_parent_id, parent_id)

    if (same_logical_node) {
      state$pending_value <- paste0(state$pending_value, content)
      return(invisible(NULL))
    }

    flush_pending()
    state$pending_type <- node_type
    state$pending_value <- content
    state$pending_parent_id <- parent_id
    state$pending_depth <- depth
    invisible(NULL)
  }

  add_unnamed_content <- function(node_type, value) {
    flush_pending()

    builder$add(
      parent_id = current_parent_id(),
      sibling_order = next_sibling_order(),
      depth = length(state$element_ids) + 1L,
      node_type = node_type,
      qualified_name = NA_character_,
      local_name = NA_character_,
      prefix = NA_character_,
      namespace_uri = NA_character_,
      value = paste0(as.character(value), collapse = "")
    )

    invisible(NULL)
  }

  start_element <- function(
    name,
    attributes = character(),
    namespace = character(),
    namespaces = character()
  ) {
    flush_pending()
    name_parts <- .sax_element_name_parts(name, namespace)
    element_depth <- length(state$element_ids) + 1L

    element_id <- builder$add(
      parent_id = current_parent_id(),
      sibling_order = next_sibling_order(),
      depth = element_depth,
      node_type = "element",
      qualified_name = name_parts$qualified_name,
      local_name = name_parts$local_name,
      prefix = name_parts$prefix,
      namespace_uri = name_parts$namespace_uri,
      value = NA_character_
    )

    # Attributes immediately follow their owner in preorder, exactly as in the
    # in-memory implementation.  Namespace declarations themselves are not
    # attributes in the XML Infoset and are therefore not emitted as rows.
    if (length(attributes) > 0L) {
      for (attribute_index in seq_along(attributes)) {
        attribute_name <- .sax_attribute_name_parts(
          attributes,
          attribute_index
        )

        builder$add(
          parent_id = element_id,
          sibling_order = NA_integer_,
          depth = element_depth + 1L,
          node_type = "attribute",
          qualified_name = attribute_name$qualified_name,
          local_name = attribute_name$local_name,
          prefix = attribute_name$prefix,
          namespace_uri = attribute_name$namespace_uri,
          value = .decode_sax_numeric_references(
            attributes[[attribute_index]]
          )
        )
      }
    }

    state$element_ids <- c(state$element_ids, element_id)
    state$element_names <- c(
      state$element_names,
      name_parts$local_name
    )
    state$child_counts <- c(state$child_counts, 0L)
    invisible(NULL)
  }

  end_element <- function(name, uri = character(), ...) {
    flush_pending()
    level <- length(state$element_ids)

    if (level == 0L) {
      stop(
        "The SAX parser reported an element end without an open element.",
        call. = FALSE
      )
    }

    closing_name <- sub("^[^:]*:", "", as.character(name)[[1L]])

    if (!identical(closing_name, state$element_names[[level]])) {
      stop(
        sprintf(
          "The SAX parser closed `%s` while `%s` was open.",
          closing_name,
          state$element_names[[level]]
        ),
        call. = FALSE
      )
    }

    state$element_ids <- state$element_ids[-level]
    state$element_names <- state$element_names[-level]
    state$child_counts <- state$child_counts[-level]
    invisible(NULL)
  }

  processing_instruction <- function(target, content = "", ...) {
    flush_pending()
    target <- as.character(target)[[1L]]

    builder$add(
      parent_id = current_parent_id(),
      sibling_order = next_sibling_order(),
      depth = length(state$element_ids) + 1L,
      node_type = "pi",
      qualified_name = target,
      local_name = target,
      prefix = "",
      namespace_uri = "",
      value = paste0(as.character(content), collapse = "")
    )

    invisible(NULL)
  }

  handlers <- list(
    .startElement = start_element,
    .endElement = end_element,
    .text = function(content, ...) {
      queue_character_data("text", content)
    },
    .cdata = function(content, ...) {
      # A CDATA callback denotes a complete CDATA section, so adjacent CDATA
      # sections must remain separate nodes even when no text lies between.
      add_unnamed_content("cdata", content)
    },
    .comment = function(content, ...) {
      add_unnamed_content("comment", content)
    },
    .processingInstruction = processing_instruction,
    .endDocument = function(...) {
      flush_pending()
    }
  )

  tryCatch(
    XML::xmlEventParse(
      file,
      handlers = handlers,
      ignoreBlanks = FALSE,
      addContext = FALSE,
      useTagName = FALSE,
      asText = FALSE,
      trim = FALSE,
      useExpat = FALSE,
      replaceEntities = FALSE,
      validate = FALSE,
      saxVersion = 2L,
      useDotNames = TRUE
    ),
    error = function(condition) {
      callback_error <- builder$callback_error()

      if (!is.null(callback_error)) {
        stop(callback_error)
      }

      .stop_xml_parse_error(
        sprintf(
          "Could not stream XML source: %s",
          conditionMessage(condition)
        ),
        source = basename(file)
      )
    }
  )

  # Defensive finalization covers XML package versions that omit the explicit
  # end-document callback.  Calling flush_pending() twice is harmless.
  flush_pending()

  if (length(state$element_ids) != 0L) {
    .stop_xml_parse_error(
      "Could not stream XML source: one or more elements remain open.",
      source = basename(file)
    )
  }

  tryCatch(
    builder$finish(),
    xml_callback_error = function(condition) {
      stop(condition$parent)
    }
  )
}


#' Stream canonical XML node chunks through a callback
#'
#' The callback receives tibbles of at most `chunk_rows` rows.  The parser keeps
#' only the open-element stack, the current chunk, and the current text node in
#' memory.  For an end-to-end bounded workflow, the callback must also consume
#' or persist each chunk rather than accumulating all chunks in a list.
xml_stream_nodes <- function(
  file,
  callback,
  document_id = NULL,
  whitespace = c("preserve", "drop_blank"),
  chunk_rows = 100000L
) {
  whitespace <- match.arg(whitespace)
  file <- .validate_one_string(file, "file")

  if (!file.exists(file)) {
    stop(
      sprintf("XML file does not exist: %s", file),
      call. = FALSE
    )
  }

  if (!is.function(callback)) {
    stop("`callback` must be a function.", call. = FALSE)
  }

  chunk_rows <- .validate_chunk_rows(chunk_rows)
  normalized_file <- normalizePath(
    file,
    winslash = "/",
    mustWork = TRUE
  )

  if (is.null(document_id)) {
    document_id <- basename(normalized_file)
  }

  document_id <- .validate_one_string(
    document_id,
    "document_id"
  )

  stats <- .xml_stream_nodes(
    file = normalized_file,
    document_id = document_id,
    whitespace = whitespace,
    chunk_rows = chunk_rows,
    callback = callback
  )

  invisible(
    tibble::tibble(
      document_id = document_id,
      node_count = stats$node_count,
      chunk_count = stats$chunk_count
    )
  )
}


#' Read XML sequentially but return the complete canonical node table
#'
#' This convenience function is valuable for parity checks and documents that
#' do not fit comfortably as a DOM but whose final node table does fit in RAM.
#' Use `xml_stream_nodes()` directly when the final output must also be bounded.
xml_to_nodes_stream <- function(
  file,
  document_id = NULL,
  whitespace = c("preserve", "drop_blank"),
  chunk_rows = 100000L
) {
  .require_xml_rectangle_package("tibble")
  whitespace <- match.arg(whitespace)

  chunks <- list()

  xml_stream_nodes(
    file = file,
    document_id = document_id,
    whitespace = whitespace,
    chunk_rows = chunk_rows,
    callback = function(chunk) {
      chunks[[length(chunks) + 1L]] <<- chunk
      invisible(NULL)
    }
  )

  result <- if (length(chunks) == 0L) {
    xml_nodes_schema()
  } else {
    # Base rbind preserves the canonical atomic types and avoids introducing a
    # further dependency solely for test-oriented collection.
    tibble::as_tibble(do.call(rbind, unname(chunks)))
  }

  rownames(result) <- NULL
  validate_xml_nodes(result)
  result
}


# -----------------------------------------------------------------------------
# Contract validation
# -----------------------------------------------------------------------------

#' Validate a canonical XML node table
#'
#' Validation is intentionally stricter than ordinary dataframe validation.
#' These invariants will allow future DOM, SAX, Parquet, and parallel execution
#' paths to be compared without relying on implementation-specific objects.
validate_xml_nodes <- function(nodes) {
  if (!is.data.frame(nodes)) {
    stop("`nodes` must be a data frame or tibble.", call. = FALSE)
  }

  missing_columns <- setdiff(.xml_node_columns, names(nodes))

  if (length(missing_columns) > 0L) {
    stop(
      sprintf(
        "Canonical node table is missing column(s): %s.",
        paste(missing_columns, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  nodes <- nodes[, .xml_node_columns, drop = FALSE]

  character_columns <- c(
    "document_id",
    "node_type",
    "qualified_name",
    "local_name",
    "prefix",
    "namespace_uri",
    "value"
  )

  integer_columns <- c(
    "node_id",
    "parent_id",
    "node_order",
    "sibling_order",
    "depth"
  )

  wrong_character <- character_columns[
    !vapply(nodes[character_columns], is.character, logical(1))
  ]

  wrong_integer <- integer_columns[
    !vapply(nodes[integer_columns], is.integer, logical(1))
  ]

  if (length(wrong_character) > 0L || length(wrong_integer) > 0L) {
    problems <- c(
      if (length(wrong_character) > 0L) {
        sprintf(
          "character: %s",
          paste(wrong_character, collapse = ", ")
        )
      },
      if (length(wrong_integer) > 0L) {
        sprintf(
          "integer: %s",
          paste(wrong_integer, collapse = ", ")
        )
      }
    )

    stop(
      sprintf(
        "Canonical node columns have incorrect types (%s).",
        paste(problems, collapse = "; ")
      ),
      call. = FALSE
    )
  }

  if (nrow(nodes) == 0L) {
    return(invisible(TRUE))
  }

  if (anyNA(nodes$document_id) || any(!nzchar(nodes$document_id))) {
    stop("Every node must have a non-empty document_id.", call. = FALSE)
  }

  if (anyNA(nodes$node_id) || any(nodes$node_id < 1L)) {
    stop("Every node_id must be a positive integer.", call. = FALSE)
  }

  documents <- split(
    seq_len(nrow(nodes)),
    nodes$document_id,
    drop = TRUE
  )

  for (document in names(documents)) {
    rows <- documents[[document]]
    part <- nodes[rows, , drop = FALSE]

    if (anyDuplicated(part$node_id)) {
      stop(
        sprintf("document_id `%s` contains duplicate node_id values.", document),
        call. = FALSE
      )
    }

    expected <- seq_len(nrow(part))

    if (!identical(part$node_id, expected)) {
      stop(
        sprintf("document_id `%s` has non-sequential node_id values.", document),
        call. = FALSE
      )
    }

    if (!identical(part$node_order, expected)) {
      stop(
        sprintf("document_id `%s` has invalid node_order values.", document),
        call. = FALSE
      )
    }

    document_rows <- which(part$node_type == "document")

    if (length(document_rows) != 1L) {
      stop(
        sprintf("document_id `%s` must contain exactly one document node.", document),
        call. = FALSE
      )
    }

    document_row <- document_rows[[1L]]

    if (
      !is.na(part$parent_id[[document_row]]) ||
        part$depth[[document_row]] != 0L
    ) {
      stop(
        sprintf("document_id `%s` has an invalid document node.", document),
        call. = FALSE
      )
    }

    non_document_roots <- which(
      is.na(part$parent_id) &
        part$node_type != "document"
    )

    if (length(non_document_roots) > 0L) {
      stop(
        sprintf("document_id `%s` contains nodes without a parent.", document),
        call. = FALSE
      )
    }

    child_rows <- which(!is.na(part$parent_id))

    # node_id was already proven to be exactly 1..n in row order.  It can
    # therefore be used as a direct row index.  Calling match() separately for
    # every child made otherwise linear validation quadratic on large files.
    invalid_parent <- child_rows[
      part$parent_id[child_rows] < 1L |
        part$parent_id[child_rows] > nrow(part)
    ]

    if (length(invalid_parent) > 0L) {
      row <- invalid_parent[[1L]]
      stop(
        sprintf(
          "Node %d in document_id `%s` references a missing parent.",
          part$node_id[[row]],
          document
        ),
        call. = FALSE
      )
    }

    parent_rows <- part$parent_id[child_rows]
    wrong_order <- which(
      part$node_order[parent_rows] >= part$node_order[child_rows]
    )

    if (length(wrong_order) > 0L) {
      row <- child_rows[wrong_order[[1L]]]
      stop(
        sprintf(
          "Node %d in document_id `%s` precedes its parent.",
          part$node_id[[row]],
          document
        ),
        call. = FALSE
      )
    }

    wrong_depth <- which(
      part$depth[child_rows] != part$depth[parent_rows] + 1L
    )

    if (length(wrong_depth) > 0L) {
      row <- child_rows[wrong_depth[[1L]]]
      stop(
        sprintf(
          "Node %d in document_id `%s` has an invalid depth.",
          part$node_id[[row]],
          document
        ),
        call. = FALSE
      )
    }

    attribute_children <- which(part$node_type[child_rows] == "attribute")
    wrong_owner <- attribute_children[
      part$node_type[parent_rows[attribute_children]] != "element"
    ]

    if (length(wrong_owner) > 0L) {
      row <- child_rows[wrong_owner[[1L]]]
      stop(
        sprintf(
          "Attribute node %d in document_id `%s` is not owned by an element.",
          part$node_id[[row]],
          document
        ),
        call. = FALSE
      )
    }

    attributes <- part$node_type == "attribute"

    if (any(!is.na(part$sibling_order[attributes]))) {
      stop("Attribute rows must have missing sibling_order.", call. = FALSE)
    }

    content_rows <- which(
      part$node_type != "attribute" &
        part$node_type != "document"
    )

    if (
      length(content_rows) > 0L &&
        any(
          is.na(part$sibling_order[content_rows]) |
            part$sibling_order[content_rows] < 1L
        )
    ) {
      stop(
        "Every non-attribute child node must have a positive sibling_order.",
        call. = FALSE
      )
    }

    # Positions are checked per parent after attributes have been excluded.
    # A contiguous sequence guarantees deterministic reconstruction even when
    # indentation-only text has been intentionally removed.
    if (length(content_rows) > 0L) {
      groups <- split(
        content_rows,
        part$parent_id[content_rows],
        drop = TRUE
      )

      for (group in groups) {
        positions <- part$sibling_order[group]

        if (!identical(sort(positions), seq_along(positions))) {
          stop(
            sprintf(
              "document_id `%s` has invalid sibling_order values.",
              document
            ),
            call. = FALSE
          )
        }
      }
    }

    named_rows <- part$node_type %in% .xml_nodes_with_names

    if (
      any(is.na(part$qualified_name[named_rows])) ||
        any(is.na(part$local_name[named_rows]))
    ) {
      stop(
        sprintf("document_id `%s` contains an unnamed XML node.", document),
        call. = FALSE
      )
    }

    structural_rows <- part$node_type %in% c("document", "element")

    if (any(!is.na(part$value[structural_rows]))) {
      stop(
        "Document and element rows must not duplicate descendant text in value.",
        call. = FALSE
      )
    }
  }

  invisible(TRUE)
}


# -----------------------------------------------------------------------------
# Lightweight navigation helpers
# -----------------------------------------------------------------------------

#' Return direct canonical children of one node
#'
#' Attributes can be included when the caller wants the complete ownership
#' relation.  By default this returns only ordered XML content.
xml_node_children <- function(
  nodes,
  node_id,
  document_id = NULL,
  include_attributes = FALSE
) {
  validate_xml_nodes(nodes)

  if (
    !is.numeric(node_id) ||
      length(node_id) != 1L ||
      is.na(node_id) ||
      node_id < 1 ||
      node_id != floor(node_id)
  ) {
    stop("`node_id` must be one positive whole number.", call. = FALSE)
  }

  if (is.null(document_id)) {
    available_documents <- unique(nodes$document_id[nodes$node_id == node_id])

    if (length(available_documents) != 1L) {
      stop(
        "Supply `document_id` when node_id is absent or ambiguous.",
        call. = FALSE
      )
    }

    document_id <- available_documents[[1L]]
  } else {
    document_id <- .validate_one_string(document_id, "document_id")
  }

  keep <- nodes$document_id == document_id &
    !is.na(nodes$parent_id) &
    nodes$parent_id == as.integer(node_id)

  if (!include_attributes) {
    keep <- keep & nodes$node_type != "attribute"
  }

  result <- nodes[keep, , drop = FALSE]

  if (nrow(result) == 0L) {
    return(result)
  }

  if (include_attributes) {
    # Attributes are shown first because their sibling_order is intentionally
    # missing.  Content retains its semantic order after them.
    result <- result[
      order(
        result$node_type != "attribute",
        result$sibling_order,
        result$node_order,
        na.last = TRUE
      ),
      ,
      drop = FALSE
    ]
  } else {
    result <- result[
      order(result$sibling_order),
      ,
      drop = FALSE
    ]
  }

  rownames(result) <- NULL
  result
}


# -----------------------------------------------------------------------------
# Friendly structure inspection for analytical rectangling
# -----------------------------------------------------------------------------

.xml_expanded_name <- function(
  local_name,
  namespace_uri
) {
  ifelse(
    is.na(local_name),
    NA_character_,
    ifelse(
      is.na(namespace_uri) | !nzchar(namespace_uri),
      local_name,
      paste0("{", namespace_uri, "}", local_name)
    )
  )
}


.xml_path_key <- function(parts) {
  if (length(parts) == 0L) {
    return("")
  }

  # Namespace URIs may themselves contain slashes.  Length-prefixing every
  # expanded name creates an unambiguous internal key without exposing this
  # machinery in the friendly user interface.
  paste0(
    nchar(parts, type = "bytes"),
    ":",
    parts,
    collapse = "|"
  )
}


.xml_normalize_friendly_path <- function(path) {
  path <- .validate_one_string(path, "path")
  path <- gsub("[[:space:]]*>[[:space:]]*", "/", path)
  path <- gsub("^/+|/+$", "", path)
  parts <- strsplit(path, "/", fixed = TRUE)[[1L]]
  parts <- trimws(parts)
  parts <- parts[nzchar(parts)]

  if (length(parts) == 0L) {
    stop("A friendly XML path must contain at least one name.", call. = FALSE)
  }

  parts
}


.xml_suffix_matches <- function(path, suffix) {
  if (length(suffix) > length(path)) {
    return(FALSE)
  }

  identical(
    tail(path, length(suffix)),
    suffix
  )
}


.build_xml_structure_index <- function(nodes, validate = TRUE) {
  if (isTRUE(validate)) {
    validate_xml_nodes(nodes)
  }
  .require_xml_rectangle_package("tibble")

  if (length(unique(nodes$document_id)) != 1L) {
    stop(
      paste0(
        "Structure inspection currently expects one canonical XML ",
        "document at a time."
      ),
      call. = FALSE
    )
  }

  element_rows <- which(nodes$node_type == "element")

  if (length(element_rows) == 0L) {
    stop(
      "The canonical table contains no XML elements to inspect.",
      call. = FALSE
    )
  }

  maximum_node_id <- max(nodes$node_id)
  expanded_paths <- vector("list", maximum_node_id)
  local_paths <- vector("list", maximum_node_id)
  row_by_id <- rep.int(NA_integer_, maximum_node_id)
  row_by_id[nodes$node_id] <- seq_len(nrow(nodes))

  expanded_names <- .xml_expanded_name(
    nodes$local_name,
    nodes$namespace_uri
  )
  expanded_name_by_id <- rep.int(NA_character_, maximum_node_id)
  expanded_name_by_id[nodes$node_id] <- expanded_names

  path_key <- rep.int(NA_character_, nrow(nodes))
  display_path <- rep.int(NA_character_, nrow(nodes))

  # Canonical rows are in preorder, so every parent path is already available
  # when its child is visited.  No XPath evaluation or XML reparsing is needed.
  for (row in element_rows) {
    node_id <- nodes$node_id[[row]]
    parent_id <- nodes$parent_id[[row]]

    parent_expanded <- if (
      is.na(parent_id) ||
        is.null(expanded_paths[[parent_id]])
    ) {
      character()
    } else {
      expanded_paths[[parent_id]]
    }

    parent_local <- if (
      is.na(parent_id) ||
        is.null(local_paths[[parent_id]])
    ) {
      character()
    } else {
      local_paths[[parent_id]]
    }

    expanded_paths[[node_id]] <- c(
      parent_expanded,
      expanded_names[[row]]
    )

    local_paths[[node_id]] <- c(
      parent_local,
      nodes$local_name[[row]]
    )

    path_key[[row]] <- .xml_path_key(expanded_paths[[node_id]])
    display_path[[row]] <- paste(
      local_paths[[node_id]],
      collapse = "/"
    )
  }

  element_parent <- rep.int(NA_integer_, nrow(nodes))

  for (row in element_rows) {
    parent_id <- nodes$parent_id[[row]]

    if (!is.na(parent_id)) {
      parent_row <- row_by_id[[parent_id]]

      if (
        !is.na(parent_row) &&
          nodes$node_type[[parent_row]] == "element"
      ) {
        element_parent[[row]] <- parent_id
      }
    }
  }

  sibling_key <- paste(
    nodes$document_id[element_rows],
    ifelse(
      is.na(element_parent[element_rows]),
      "<document>",
      element_parent[element_rows]
    ),
    expanded_names[element_rows],
    sep = "\u001f"
  )

  sibling_occurrence <- integer(length(element_rows))
  sibling_count <- integer(length(element_rows))

  groups <- split(
    seq_along(element_rows),
    sibling_key,
    drop = TRUE
  )

  for (group in groups) {
    sibling_occurrence[group] <- seq_along(group)
    sibling_count[group] <- length(group)
  }

  element_child_counts <- integer(nrow(nodes))

  for (row in element_rows) {
    parent_id <- element_parent[[row]]

    if (!is.na(parent_id)) {
      parent_row <- row_by_id[[parent_id]]
      element_child_counts[[parent_row]] <-
        element_child_counts[[parent_row]] + 1L
    }
  }

  elements <- tibble::tibble(
    document_id = nodes$document_id[element_rows],
    node_id = nodes$node_id[element_rows],
    parent_id = nodes$parent_id[element_rows],
    depth = nodes$depth[element_rows],
    qualified_name = nodes$qualified_name[element_rows],
    local_name = nodes$local_name[element_rows],
    namespace_uri = nodes$namespace_uri[element_rows],
    expanded_name = expanded_names[element_rows],
    path_key = path_key[element_rows],
    display_path = display_path[element_rows],
    sibling_occurrence = as.integer(sibling_occurrence),
    sibling_count = as.integer(sibling_count),
    locally_repeated = sibling_count > 1L,
    has_element_children = element_child_counts[element_rows] > 0L,
    expanded_path = unname(expanded_paths[nodes$node_id[element_rows]]),
    local_path = unname(local_paths[nodes$node_id[element_rows]])
  )

  # Summaries are path-specific.  The same local element name in two different
  # namespaces or locations remains two different candidates.
  path_groups <- split(
    seq_len(nrow(elements)),
    elements$path_key,
    drop = TRUE
  )

  path_summaries <- lapply(
    path_groups,
    function(rows) {
      first <- rows[[1L]]

      tibble::tibble(
        path_key = elements$path_key[[first]],
        display_path = elements$display_path[[first]],
        local_name = elements$local_name[[first]],
        namespace_uri = elements$namespace_uri[[first]],
        depth = elements$depth[[first]],
        occurrences = as.integer(length(rows)),
        max_per_parent = as.integer(max(elements$sibling_count[rows])),
        repeated = any(elements$locally_repeated[rows]),
        complex = any(elements$has_element_children[rows]),
        expanded_path = list(elements$expanded_path[[first]]),
        local_path = list(elements$local_path[[first]])
      )
    }
  )

  paths <- do.call(rbind, unname(path_summaries))
  rownames(paths) <- NULL

  list(
    elements = elements,
    paths = tibble::as_tibble(paths),
    expanded_paths = expanded_paths,
    local_paths = local_paths,
    expanded_name_by_id = expanded_name_by_id
  )
}


# Native analyst-only structure index. The C helper computes dense integer tree
# relationships and dictionary-coded structural paths. Character paths are then
# materialised once per *distinct* path, not once per element occurrence.
# The returned object intentionally mirrors `.build_xml_structure_index()` so
# the semantic analyst code above it remains unchanged.
.build_xml_structure_index_native <- function(nodes) {
  .require_xml_rectangle_package("tibble")
  plan <- .xml_native_analyst_plan(nodes)

  element_rows <- plan$element_rows
  maximum_node_id <- max(nodes$node_id)
  expanded_names <- nodes$local_name
  has_namespace <- !is.na(nodes$local_name) &
    !is.na(nodes$namespace_uri) & nzchar(nodes$namespace_uri)
  expanded_names[has_namespace] <- paste0(
    "{", nodes$namespace_uri[has_namespace], "}", nodes$local_name[has_namespace]
  )
  expanded_name_by_id <- rep.int(NA_character_, maximum_node_id)
  expanded_name_by_id[nodes$node_id] <- expanded_names

  path_count <- length(plan$path_parent_id)
  path_expanded <- vector("list", path_count)
  path_local <- vector("list", path_count)
  path_key <- character(path_count)
  display_path <- character(path_count)
  path_first_rows <- element_rows[plan$path_first_element_pos]
  path_first_nodes <- nodes$node_id[path_first_rows]

  for (path_id in seq_len(path_count)) {
    row <- path_first_rows[[path_id]]
    parent_path_id <- plan$path_parent_id[[path_id]]
    last_expanded <- expanded_names[[row]]
    last_local <- nodes$local_name[[row]]

    if (is.na(parent_path_id)) {
      path_expanded[[path_id]] <- last_expanded
      path_local[[path_id]] <- last_local
    } else {
      path_expanded[[path_id]] <- c(path_expanded[[parent_path_id]], last_expanded)
      path_local[[path_id]] <- c(path_local[[parent_path_id]], last_local)
    }

    path_key[[path_id]] <- .xml_path_key(path_expanded[[path_id]])
    display_path[[path_id]] <- paste(path_local[[path_id]], collapse = "/")
  }

  element_path_id <- plan$element_path_id
  elements <- tibble::tibble(
    document_id = nodes$document_id[element_rows],
    node_id = nodes$node_id[element_rows],
    parent_id = nodes$parent_id[element_rows],
    depth = nodes$depth[element_rows],
    qualified_name = nodes$qualified_name[element_rows],
    local_name = nodes$local_name[element_rows],
    namespace_uri = nodes$namespace_uri[element_rows],
    expanded_name = expanded_names[element_rows],
    path_key = path_key[element_path_id],
    display_path = display_path[element_path_id],
    sibling_occurrence = as.integer(plan$sibling_occurrence),
    sibling_count = as.integer(plan$sibling_count),
    locally_repeated = plan$sibling_count > 1L,
    has_element_children = as.logical(plan$has_element_children),
    expanded_path = unname(path_expanded[element_path_id]),
    local_path = unname(path_local[element_path_id])
  )

  # `split(character)` in the frozen index presents path summaries in sorted
  # path-key order. Preserve that ordering exactly even though native path ids
  # themselves are first-occurrence ids.
  path_order <- order(path_key)
  paths <- tibble::tibble(
    path_key = path_key[path_order],
    display_path = display_path[path_order],
    local_name = nodes$local_name[path_first_rows[path_order]],
    namespace_uri = nodes$namespace_uri[path_first_rows[path_order]],
    depth = nodes$depth[path_first_rows[path_order]],
    occurrences = as.integer(plan$path_occurrences[path_order]),
    max_per_parent = as.integer(plan$path_max_per_parent[path_order]),
    repeated = as.logical(plan$path_repeated[path_order]),
    complex = as.logical(plan$path_complex[path_order]),
    expanded_path = unname(path_expanded[path_order]),
    local_path = unname(path_local[path_order])
  )

  expanded_paths <- vector("list", maximum_node_id)
  local_paths <- vector("list", maximum_node_id)
  expanded_paths[plan$element_node_id] <- unname(path_expanded[element_path_id])
  local_paths[plan$element_node_id] <- unname(path_local[element_path_id])

  path_id_by_node <- rep.int(NA_integer_, maximum_node_id)
  path_id_by_node[plan$element_node_id] <- element_path_id

  list(
    elements = elements,
    paths = paths,
    expanded_paths = expanded_paths,
    local_paths = local_paths,
    expanded_name_by_id = expanded_name_by_id,
    native_plan = plan,
    path_id_by_node = path_id_by_node,
    path_parent_id = plan$path_parent_id,
    path_first_node = path_first_nodes,
    path_key_by_id = path_key,
    display_path_by_id = display_path,
    path_expanded_by_id = path_expanded,
    path_local_by_id = path_local,
    path_id_by_key = stats::setNames(seq_len(path_count), path_key),
    subtree_end_rows = plan$subtree_end_rows
  )
}



.find_likely_record_paths <- function(paths) {
  repeated_complex <- paths[
    paths$repeated & paths$complex,
    ,
    drop = FALSE
  ]

  if (nrow(repeated_complex) > 0L) {
    shallowest_depth <- min(repeated_complex$depth)

    return(
      repeated_complex[
        repeated_complex$depth == shallowest_depth,
        ,
        drop = FALSE
      ]
    )
  }

  # A document with one non-repeated root can still sensibly produce one row.
  # This fallback also makes small example documents useful during spec design.
  roots <- paths[paths$depth == min(paths$depth), , drop = FALSE]
  roots
}


#' Inspect an XML sample using plain structural names
#'
#' The returned object retains the canonical sample and a namespace-aware path
#' index.  Printed output intentionally uses familiar element names; exact
#' expanded names remain available internally for reproducible execution.
inspect_xml <- function(
  x,
  whitespace = c("drop_blank", "preserve")
) {
  whitespace <- match.arg(whitespace)

  if (is.data.frame(x)) {
    validate_xml_nodes(x)
    nodes <- x
    source <- "canonical node table"
  } else {
    x <- .validate_one_string(x, "x")
    nodes <- xml_to_nodes_memory(
      x,
      whitespace = whitespace
    )
    source <- normalizePath(
      x,
      winslash = "/",
      mustWork = TRUE
    )
  }

  index <- .build_xml_structure_index(nodes)
  likely_records <- .find_likely_record_paths(index$paths)

  result <- list(
    source = source,
    whitespace = whitespace,
    nodes = nodes,
    index = index,
    likely_records = likely_records
  )

  class(result) <- "xml_structure"
  result
}


print.xml_structure <- function(x, ...) {
  cat("XML structure\n")
  cat("  Source: ", x$source, "\n", sep = "")
  cat(
    "  Documents: ",
    length(unique(x$nodes$document_id)),
    "\n",
    sep = ""
  )
  cat(
    "  Elements: ",
    sum(x$nodes$node_type == "element"),
    "\n",
    sep = ""
  )

  repeated <- x$index$paths[
    x$index$paths$repeated,
    ,
    drop = FALSE
  ]

  if (nrow(x$likely_records) == 1L) {
    cat(
      "  Likely row element: ",
      x$likely_records$display_path[[1L]],
      " (",
      x$likely_records$occurrences[[1L]],
      " observed)\n",
      sep = ""
    )
  } else {
    cat("  Likely row elements require a user choice:\n")

    for (row in seq_len(nrow(x$likely_records))) {
      cat(
        "    - ",
        x$likely_records$display_path[[row]],
        "\n",
        sep = ""
      )
    }
  }

  if (nrow(repeated) > 0L) {
    cat("  Observed repeated paths:\n")

    for (row in seq_len(nrow(repeated))) {
      cat(
        "    - ",
        repeated$display_path[[row]],
        " (up to ",
        repeated$max_per_parent[[row]],
        " per parent)\n",
        sep = ""
      )
    }
  }

  invisible(x)
}


.xml_path_starts_with <- function(path, prefix) {
  length(path) >= length(prefix) &&
    identical(
      head(path, length(prefix)),
      prefix
    )
}


.resolve_friendly_element <- function(
  structure,
  friendly_path,
  argument = "one_row_per",
  namespace = NULL
) {
  requested <- .xml_normalize_friendly_path(friendly_path)
  paths <- structure$index$paths

  if (!is.null(namespace)) {
    namespace <- .validate_one_string(namespace, "namespace")
  }

  matches <- vapply(
    paths$local_path,
    .xml_suffix_matches,
    logical(1),
    suffix = requested
  )

  candidates <- paths[matches, , drop = FALSE]

  if (!is.null(namespace)) {
    candidate_namespaces <- ifelse(
      is.na(candidates$namespace_uri),
      "",
      candidates$namespace_uri
    )
    candidates <- candidates[
      candidate_namespaces == namespace,
      ,
      drop = FALSE
    ]
  }

  if (nrow(candidates) == 0L) {
    stop(
      sprintf(
        "`%s = \"%s\"` does not match an element in the inspected XML%s.",
        argument,
        friendly_path,
        if (is.null(namespace)) {
          ""
        } else {
          paste0(" in namespace `", namespace, "`")
        }
      ),
      call. = FALSE
    )
  }

  if (nrow(candidates) > 1L) {
    descriptions <- paste0(
      "  - ",
      candidates$display_path,
      ifelse(
        !is.na(candidates$namespace_uri) &
          nzchar(candidates$namespace_uri),
        paste0("  [", candidates$namespace_uri, "]"),
        ""
      ),
      collapse = "\n"
    )

    stop(
      paste0(
        "`",
        argument,
        " = \"",
        friendly_path,
        "\"` is ambiguous. Use a longer visible path, or supply ",
        "`namespace` when the candidates differ only by namespace:\n",
        descriptions
      ),
      call. = FALSE
    )
  }

  candidates[1L, , drop = FALSE]
}


.xml_relative_parts <- function(path, ancestor_path) {
  if (!.xml_path_starts_with(path, ancestor_path)) {
    stop(
      "An internal XML path does not descend from its expected ancestor.",
      call. = FALSE
    )
  }

  if (length(path) == length(ancestor_path)) {
    return(character())
  }

  path[seq.int(length(ancestor_path) + 1L, length(path))]
}


.xml_join_visible_path <- function(parts, fallback = "value") {
  if (length(parts) == 0L) {
    fallback
  } else {
    paste(parts, collapse = "/")
  }
}


.xml_value_source_key <- function(
  value_kind,
  owner_relative_path,
  terminal_name
) {
  paste(
    value_kind,
    .xml_path_key(owner_relative_path),
    terminal_name,
    sep = "\u001e"
  )
}


.xml_long_value_schema <- function() {
  .require_xml_rectangle_package("tibble")

  tibble::tibble(
    document_id = character(),
    record_index = integer(),
    record_node_id = integer(),
    entity = character(),
    entity_index = integer(),
    entity_node_id = integer(),
    parent_entity_node_id = integer(),
    field = character(),
    source_label = character(),
    value_index = integer(),
    value = character(),
    value_kind = character(),
    source_node_id = integer(),
    source_path = character(),
    source_key = character()
  )
}


.xml_extract_long_values <- function(
  nodes,
  record_path_key,
  declared_entity_path_keys = character(),
  index = NULL
) {
  .require_xml_rectangle_package("tibble")

  if (is.null(index)) {
    validate_xml_nodes(nodes)
    index <- .build_xml_structure_index(nodes, validate = FALSE)
  }

  documents <- unique(nodes$document_id)

  if (length(documents) != 1L) {
    stop(
      paste0(
        "The rectangling prototype currently processes one canonical ",
        "document at a time."
      ),
      call. = FALSE
    )
  }

  elements <- index$elements
  maximum_node_id <- max(nodes$node_id)

  element_row_by_id <- rep.int(NA_integer_, maximum_node_id)
  element_row_by_id[elements$node_id] <- seq_len(nrow(elements))

  record_element_rows <- which(elements$path_key == record_path_key)

  if (length(record_element_rows) == 0L) {
    stop(
      "The selected row element does not occur in this XML document.",
      call. = FALSE
    )
  }

  record_node_ids <- elements$node_id[record_element_rows]
  record_index_by_node <- rep.int(NA_integer_, maximum_node_id)
  record_index_by_node[record_node_ids] <- seq_along(record_node_ids)

  # A path observed as repeated while the specification was prepared remains
  # an entity boundary even if a later document happens to contain one item.
  # Newly observed repetitions are also promoted so they cannot be flattened
  # into a misleading scalar field.
  record_path_row <- match(record_path_key, index$paths$path_key)
  record_expanded_path <- index$paths$expanded_path[[record_path_row]]

  inside_record <- vapply(
    elements$expanded_path,
    .xml_path_starts_with,
    logical(1),
    prefix = record_expanded_path
  )

  runtime_entity_paths <- unique(
    elements$path_key[
      elements$locally_repeated &
        inside_record &
        elements$path_key != record_path_key
    ]
  )

  entity_path_keys <- unique(
    c(declared_entity_path_keys, runtime_entity_paths)
  )

  record_for_element <- rep.int(NA_integer_, maximum_node_id)
  entity_for_element <- rep.int(NA_integer_, maximum_node_id)

  for (element_row in seq_len(nrow(elements))) {
    node_id <- elements$node_id[[element_row]]
    parent_id <- elements$parent_id[[element_row]]
    is_record <- elements$path_key[[element_row]] == record_path_key

    if (is_record) {
      record_for_element[[node_id]] <- node_id
      entity_for_element[[node_id]] <- node_id
      next
    }

    parent_element_row <- if (
      is.na(parent_id) ||
        parent_id > length(element_row_by_id)
    ) {
      NA_integer_
    } else {
      element_row_by_id[[parent_id]]
    }

    if (is.na(parent_element_row)) {
      next
    }

    record_for_element[[node_id]] <- record_for_element[[parent_id]]

    if (is.na(record_for_element[[node_id]])) {
      next
    }

    if (elements$path_key[[element_row]] %in% entity_path_keys) {
      entity_for_element[[node_id]] <- node_id
    } else {
      entity_for_element[[node_id]] <- entity_for_element[[parent_id]]
    }
  }

  value_rows <- which(
    nodes$node_type %in% c("attribute", "text", "cdata")
  )

  if (length(value_rows) == 0L) {
    return(.xml_long_value_schema())
  }

  # Real metadata and scientific XML files can contain tens of thousands of
  # scalar values.  Preallocating atomic vectors avoids constructing one tiny
  # tibble per value and then copying all of them during rbind().  The vectors
  # are bounded by the canonical input already held by this in-memory path.
  output_capacity <- length(value_rows)
  output <- list(
    document_id = rep.int(NA_character_, output_capacity),
    record_index = rep.int(NA_integer_, output_capacity),
    record_node_id = rep.int(NA_integer_, output_capacity),
    entity = rep.int(NA_character_, output_capacity),
    entity_index = rep.int(NA_integer_, output_capacity),
    entity_node_id = rep.int(NA_integer_, output_capacity),
    parent_entity_node_id = rep.int(NA_integer_, output_capacity),
    field = rep.int(NA_character_, output_capacity),
    source_label = rep.int(NA_character_, output_capacity),
    value_index = rep.int(1L, output_capacity),
    value = rep.int(NA_character_, output_capacity),
    value_kind = rep.int(NA_character_, output_capacity),
    source_node_id = rep.int(NA_integer_, output_capacity),
    source_path = rep.int(NA_character_, output_capacity),
    source_key = rep.int(NA_character_, output_capacity)
  )
  output_size <- 0L

  for (value_row in value_rows) {
    owner_id <- nodes$parent_id[[value_row]]

    if (
      is.na(owner_id) ||
        owner_id > length(element_row_by_id)
    ) {
      next
    }

    owner_element_row <- element_row_by_id[[owner_id]]

    if (is.na(owner_element_row)) {
      next
    }

    record_node_id <- record_for_element[[owner_id]]

    if (is.na(record_node_id)) {
      next
    }

    entity_node_id <- entity_for_element[[owner_id]]
    record_element_row <- element_row_by_id[[record_node_id]]
    entity_element_row <- element_row_by_id[[entity_node_id]]

    record_expanded_path <- elements$expanded_path[[record_element_row]]
    record_local_path <- elements$local_path[[record_element_row]]
    owner_expanded_path <- elements$expanded_path[[owner_element_row]]
    owner_local_path <- elements$local_path[[owner_element_row]]
    entity_local_path <- elements$local_path[[entity_element_row]]

    owner_relative_expanded <- .xml_relative_parts(
      owner_expanded_path,
      record_expanded_path
    )

    owner_relative_local <- .xml_relative_parts(
      owner_local_path,
      record_local_path
    )

    field_owner_local <- .xml_relative_parts(
      owner_local_path,
      entity_local_path
    )

    entity_relative_local <- .xml_relative_parts(
      entity_local_path,
      record_local_path
    )

    is_attribute <- nodes$node_type[[value_row]] == "attribute"
    value_kind <- nodes$node_type[[value_row]]

    if (is_attribute) {
      terminal_expanded <- .xml_expanded_name(
        nodes$local_name[[value_row]],
        nodes$namespace_uri[[value_row]]
      )

      source_label_parts <- c(
        owner_relative_local,
        paste0("@", nodes$local_name[[value_row]])
      )

      field_parts <- c(
        field_owner_local,
        nodes$local_name[[value_row]]
      )

      full_source_parts <- c(
        owner_local_path,
        paste0("@", nodes$local_name[[value_row]])
      )
    } else {
      terminal_expanded <- paste0("#", value_kind)
      source_label_parts <- owner_relative_local
      field_parts <- field_owner_local
      full_source_parts <- owner_local_path
    }

    parent_element_id <- elements$parent_id[[entity_element_row]]
    parent_entity_node_id <- if (
      entity_node_id == record_node_id ||
        is.na(parent_element_id) ||
        parent_element_id > length(entity_for_element)
    ) {
      NA_integer_
    } else {
      entity_for_element[[parent_element_id]]
    }

    entity_label <- .xml_join_visible_path(
      entity_relative_local,
      fallback = elements$local_name[[record_element_row]]
    )

    entity_index <- if (entity_node_id == record_node_id) {
      1L
    } else {
      as.integer(elements$sibling_occurrence[[entity_element_row]])
    }

    output_size <- output_size + 1L
    output$document_id[[output_size]] <- nodes$document_id[[value_row]]
    output$record_index[[output_size]] <- as.integer(
      record_index_by_node[[record_node_id]]
    )
    output$record_node_id[[output_size]] <- as.integer(record_node_id)
    output$entity[[output_size]] <- entity_label
    output$entity_index[[output_size]] <- entity_index
    output$entity_node_id[[output_size]] <- as.integer(entity_node_id)
    output$parent_entity_node_id[[output_size]] <- as.integer(
      parent_entity_node_id
    )
    output$field[[output_size]] <- .xml_join_visible_path(field_parts)
    output$source_label[[output_size]] <- .xml_join_visible_path(
      source_label_parts
    )
    output$value[[output_size]] <- nodes$value[[value_row]]
    output$value_kind[[output_size]] <- value_kind
    output$source_node_id[[output_size]] <- nodes$node_id[[value_row]]
    output$source_path[[output_size]] <- .xml_join_visible_path(
      full_source_parts
    )
    output$source_key[[output_size]] <- .xml_value_source_key(
      value_kind,
      owner_relative_expanded,
      terminal_expanded
    )
  }

  if (output_size == 0L) {
    return(.xml_long_value_schema())
  }

  result <- tibble::as_tibble(
    lapply(
      output,
      function(column) column[seq_len(output_size)]
    )
  )

  value_group <- paste(
    result$document_id,
    result$record_node_id,
    result$entity_node_id,
    result$source_key,
    sep = "\u001f"
  )

  groups <- split(
    seq_len(nrow(result)),
    value_group,
    drop = TRUE
  )

  for (group in groups) {
    result$value_index[group] <- seq_along(group)
  }

  tibble::as_tibble(result)
}


# -----------------------------------------------------------------------------
# Plain-language rectangle specifications
# -----------------------------------------------------------------------------

.xml_value_catalog <- function(values) {
  .require_xml_rectangle_package("tibble")

  columns <- c(
    "source_key",
    "source_label",
    "field",
    "entity",
    "value_kind"
  )

  if (nrow(values) == 0L) {
    return(
      tibble::tibble(
        source_key = character(),
        source_label = character(),
        field = character(),
        entity = character(),
        value_kind = character(),
        records_observed = integer(),
        max_per_record = integer(),
        under_repetition = logical()
      )
    )
  }

  first_rows <- which(!duplicated(values$source_key))
  catalog <- values[first_rows, columns, drop = FALSE]
  catalog$records_observed <- 0L
  catalog$max_per_record <- 0L
  catalog$under_repetition <- FALSE
  value_groups <- split(
    seq_len(nrow(values)),
    values$source_key,
    drop = TRUE
  )

  for (row in seq_len(nrow(catalog))) {
    occurrences <- values[
      value_groups[[catalog$source_key[[row]]]],
      ,
      drop = FALSE
    ]

    per_record <- table(occurrences$record_index)
    catalog$records_observed[[row]] <- length(per_record)
    catalog$max_per_record[[row]] <- as.integer(max(per_record))
    catalog$under_repetition[[row]] <- any(
      occurrences$entity_node_id != occurrences$record_node_id
    )
  }

  rownames(catalog) <- NULL
  tibble::as_tibble(catalog)
}


.xml_source_alias_parts <- function(source_label) {
  parts <- .xml_normalize_friendly_path(source_label)

  # Attribute markers are displayed in reviews because they explain where a
  # value came from.  Users may nevertheless write `id` instead of `@id` when
  # that shorter spelling is unambiguous.
  sub("^@", "", parts)
}


.resolve_friendly_value <- function(
  catalog,
  selector,
  argument = "field"
) {
  requested <- .xml_normalize_friendly_path(selector)
  labels <- lapply(
    catalog$source_label,
    .xml_normalize_friendly_path
  )

  exact_matches <- vapply(
    labels,
    .xml_suffix_matches,
    logical(1),
    suffix = requested
  )

  # Only use the attribute-free shorthand if the user did not explicitly
  # write an attribute marker.  An explicit `@id` is therefore a reliable way
  # to distinguish an attribute from a child element also named `id`.
  if (!any(startsWith(requested, "@"))) {
    aliases <- lapply(catalog$source_label, .xml_source_alias_parts)
    alias_matches <- vapply(
      aliases,
      .xml_suffix_matches,
      logical(1),
      suffix = requested
    )

    exact_matches <- exact_matches | alias_matches
  }

  candidates <- catalog[exact_matches, , drop = FALSE]

  if (nrow(candidates) == 0L) {
    stop(
      sprintf(
        "`%s = \"%s\"` does not match a value in the selected row element.",
        argument,
        selector
      ),
      call. = FALSE
    )
  }

  if (nrow(candidates) > 1L) {
    descriptions <- paste0(
      "  - ",
      candidates$source_label,
      " (",
      candidates$value_kind,
      ", in ",
      candidates$entity,
      ")",
      collapse = "\n"
    )

    stop(
      paste0(
        "`",
        argument,
        " = \"",
        selector,
        "\"` is ambiguous. Use one of the more specific sources:\n",
        descriptions
      ),
      call. = FALSE
    )
  }

  candidates[1L, , drop = FALSE]
}


.xml_default_column_name <- function(source_label) {
  name <- gsub("@", "", source_label, fixed = TRUE)
  name <- gsub("/", "_", name, fixed = TRUE)

  if (!nzchar(name)) {
    "value"
  } else {
    name
  }
}


.xml_select_spec_fields <- function(catalog, fields) {
  .require_xml_rectangle_package("tibble")

  if (is.null(fields)) {
    selected <- catalog
    selected$user_name <- rep.int(NA_character_, nrow(selected))
    return(selected)
  }

  if (
    !is.character(fields) ||
      length(fields) == 0L ||
      anyNA(fields) ||
      any(!nzchar(trimws(fields)))
  ) {
    stop(
      "`fields` must be NULL or a non-empty character vector of field names.",
      call. = FALSE
    )
  }

  requested_names <- names(fields)

  if (is.null(requested_names)) {
    requested_names <- rep.int("", length(fields))
  }

  if (anyNA(requested_names)) {
    stop(
      "Names supplied for `fields` cannot be missing.",
      call. = FALSE
    )
  }

  selections <- lapply(
    seq_along(fields),
    function(index) {
      match <- .resolve_friendly_value(
        catalog,
        fields[[index]],
        argument = "fields"
      )

      match$user_name <- if (nzchar(requested_names[[index]])) {
        requested_names[[index]]
      } else {
        NA_character_
      }

      match
    }
  )

  selected <- do.call(rbind, unname(selections))
  rownames(selected) <- NULL

  if (anyDuplicated(selected$source_key)) {
    stop(
      "`fields` selects the same XML value more than once.",
      call. = FALSE
    )
  }

  tibble::as_tibble(selected)
}


.xml_valid_record_identifier <- function(
  values,
  source_key,
  number_of_records
) {
  selected <- values[values$source_key == source_key, , drop = FALSE]
  counts <- tabulate(selected$record_index, nbins = number_of_records)

  length(counts) == number_of_records &&
    all(counts == 1L) &&
    !anyNA(selected$value) &&
    all(nzchar(selected$value)) &&
    !anyDuplicated(selected$value)
}


.xml_choose_record_identifier <- function(
  values,
  catalog,
  identify_by,
  number_of_records
) {
  if (identical(identify_by, FALSE)) {
    return(
      list(
        mode = "generated",
        source_key = NULL,
        source_label = NULL
      )
    )
  }

  if (!is.null(identify_by)) {
    selected <- .resolve_friendly_value(
      catalog,
      identify_by,
      argument = "identify_by"
    )

    if (
      !.xml_valid_record_identifier(
        values,
        selected$source_key[[1L]],
        number_of_records
      )
    ) {
      stop(
        paste0(
          "`identify_by = \"",
          identify_by,
          "\"` must provide exactly one non-empty, unique value per record."
        ),
        call. = FALSE
      )
    }

    return(
      list(
        mode = "source",
        source_key = selected$source_key[[1L]],
        source_label = selected$source_label[[1L]]
      )
    )
  }

  # A direct value named `id` is a useful convention, but inference remains
  # conservative: it must be outside repeated entities and prove unique and
  # complete in the sample.  Attributes win only when several valid `id`
  # conventions are present.
  terminal_names <- vapply(
    catalog$source_label,
    function(label) tail(.xml_source_alias_parts(label), 1L),
    character(1)
  )

  candidates <- which(
    terminal_names == "id" &
      !catalog$under_repetition
  )

  if (length(candidates) > 0L) {
    valid <- vapply(
      candidates,
      function(row) {
        .xml_valid_record_identifier(
          values,
          catalog$source_key[[row]],
          number_of_records
        )
      },
      logical(1)
    )

    candidates <- candidates[valid]
  }

  if (length(candidates) > 0L) {
    attribute_candidates <- candidates[
      catalog$value_kind[candidates] == "attribute"
    ]

    if (length(attribute_candidates) == 1L) {
      candidates <- attribute_candidates
    }
  }

  if (length(candidates) == 1L) {
    row <- candidates[[1L]]

    return(
      list(
        mode = "source",
        source_key = catalog$source_key[[row]],
        source_label = catalog$source_label[[row]]
      )
    )
  }

  list(
    mode = "generated",
    source_key = NULL,
    source_label = NULL
  )
}


.xml_descendant_repeated_paths <- function(structure, record) {
  paths <- structure$index$paths
  record_path <- record$expanded_path[[1L]]

  descendants <- vapply(
    paths$expanded_path,
    .xml_path_starts_with,
    logical(1),
    prefix = record_path
  )

  paths[
    descendants &
      paths$path_key != record$path_key[[1L]] &
      paths$repeated,
    ,
    drop = FALSE
  ]
}


.xml_finish_output_names <- function(selected, representation) {
  if (representation == "long") {
    selected$output_name <- ifelse(
      is.na(selected$user_name),
      selected$field,
      selected$user_name
    )

    return(selected)
  }

  defaults <- vapply(
    selected$source_label,
    .xml_default_column_name,
    character(1)
  )

  output_names <- ifelse(
    is.na(selected$user_name),
    defaults,
    selected$user_name
  )

  reserved <- c(
    "document_id",
    "record_index",
    "record_id",
    "record_node_id"
  )

  explicitly_reserved <- !is.na(selected$user_name) &
    output_names %in% reserved

  if (any(explicitly_reserved)) {
    stop(
      paste0(
        "The output name `",
        output_names[which(explicitly_reserved)[[1L]]],
        "` is reserved for record metadata."
      ),
      call. = FALSE
    )
  }

  duplicated_names <- duplicated(output_names) |
    duplicated(output_names, fromLast = TRUE)

  if (
    any(
      !is.na(selected$user_name) &
        duplicated_names
    )
  ) {
    stop(
      paste0(
        "A user-supplied field name duplicates another output name: `",
        output_names[
          which(!is.na(selected$user_name) & duplicated_names)[[1L]]
        ],
        "`."
      ),
      call. = FALSE
    )
  }

  # Automatically derived names can occasionally collide (for example an
  # attribute and an element with the same visible path).  Stable suffixes
  # retain both values, and review_rectangle() makes that mapping visible.
  selected$output_name <- make.unique(
    c(reserved, output_names),
    sep = "_"
  )[-seq_along(reserved)]

  selected
}


#' Create a rectangle specification from an inspected XML sample
#'
#' `one_row_per` and `identify_by` use visible XML names, optionally joined by
#' `/` for extra context.  No XPath or namespace-prefix declaration is needed
#' when those names are unambiguous.  Named `fields` rename values in the
#' resulting table, for example `c(customer = "customer/name")`.
make_rectangle <- function(
  structure,
  one_row_per = NULL,
  namespace = NULL,
  identify_by = NULL,
  fields = NULL,
  types = NULL,
  representation = c("auto", "wide", "long")
) {
  if (!inherits(structure, "xml_structure")) {
    stop(
      "`structure` must be the result of inspect_xml().",
      call. = FALSE
    )
  }

  representation <- match.arg(representation)
  types <- .xml_profile_types(types)

  if (is.null(one_row_per)) {
    if (nrow(structure$likely_records) != 1L) {
      stop(
        paste0(
          "The row element is not unambiguous. Supply a familiar name, ",
          "such as `one_row_per = \"order\"`."
        ),
        call. = FALSE
      )
    }

    record <- structure$likely_records[1L, , drop = FALSE]
  } else {
    record <- .resolve_friendly_element(
      structure,
      one_row_per,
      argument = "one_row_per",
      namespace = namespace
    )
  }

  repeated_paths <- .xml_descendant_repeated_paths(structure, record)
  values <- .xml_extract_long_values(
    structure$nodes,
    record_path_key = record$path_key[[1L]],
    declared_entity_path_keys = repeated_paths$path_key,
    index = structure$index
  )

  catalog <- .xml_value_catalog(values)

  if (nrow(catalog) == 0L) {
    stop(
      "The selected row element contains no attribute or text values.",
      call. = FALSE
    )
  }

  selected <- .xml_select_spec_fields(catalog, fields)
  needs_long <- any(
    selected$under_repetition |
      selected$max_per_record > 1L
  )

  chosen_representation <- if (representation == "auto") {
    if (needs_long) "long" else "wide"
  } else {
    representation
  }

  if (chosen_representation == "wide" && needs_long) {
    unsafe <- selected$source_label[
      selected$under_repetition |
        selected$max_per_record > 1L
    ]

    stop(
      paste0(
        "The selected fields cannot be represented safely in one wide ",
        "row without list-columns or a Cartesian product. Repeated source",
        if (length(unsafe) == 1L) " is: " else "s are: ",
        paste(unsafe, collapse = ", "),
        ". Use `representation = \"long\"` or select only scalar fields."
      ),
      call. = FALSE
    )
  }

  selected <- .xml_finish_output_names(
    selected,
    chosen_representation
  )
  selected <- .xml_apply_spec_types(
    selected,
    catalog = catalog,
    types = types,
    representation = chosen_representation
  )
  .xml_validate_sample_types(values, selected)

  identifier <- .xml_choose_record_identifier(
    values,
    catalog,
    identify_by,
    number_of_records = record$occurrences[[1L]]
  )

  result <- list(
    version = 1L,
    source = structure$source,
    whitespace = structure$whitespace,
    record_path_key = record$path_key[[1L]],
    record_path = record$display_path[[1L]],
    # The friendly path is ideal for review, while the expanded path is what
    # lets the streaming engine recognize records without reparsing prefixes
    # or consulting the original sample.  Namespace URIs, not lexical prefixes,
    # make the compiled specification portable across equivalent documents.
    record_expanded_path = record$expanded_path[[1L]],
    record_name = record$local_name[[1L]],
    records_observed = as.integer(record$occurrences[[1L]]),
    identifier = identifier,
    representation = chosen_representation,
    repeated_path_keys = repeated_paths$path_key,
    repeated_paths = repeated_paths$display_path,
    fields = selected,
    catalog = catalog
  )

  class(result) <- "xml_rect_spec"
  result
}


#' Inspect an XML sample and immediately create a rectangle specification
rectangle_spec <- function(
  sample,
  one_row_per = NULL,
  namespace = NULL,
  identify_by = NULL,
  fields = NULL,
  types = NULL,
  representation = c("auto", "wide", "long"),
  whitespace = c("drop_blank", "preserve")
) {
  representation <- match.arg(representation)
  whitespace <- match.arg(whitespace)

  structure <- if (inherits(sample, "xml_structure")) {
    sample
  } else {
    inspect_xml(sample, whitespace = whitespace)
  }

  make_rectangle(
    structure,
    one_row_per = one_row_per,
    namespace = namespace,
    identify_by = identify_by,
    fields = fields,
    types = types,
    representation = representation
  )
}


#' Alias that emphasizes the proposal-and-review workflow
propose_rectangle <- rectangle_spec


# -----------------------------------------------------------------------------
# Human-facing, portable XML profiles
# -----------------------------------------------------------------------------

.stop_xml_profile_error <- function(message, parent = NULL) {
  # Profile errors have their own condition class so an interactive form can
  # display them beside the relevant answer without having to parse prose.
  condition <- structure(
    list(
      message = message,
      call = NULL,
      parent = parent
    ),
    class = c("xml_profile_error", "error", "condition")
  )

  stop(condition)
}


.xml_profile_path <- function(value, argument) {
  parts <- tryCatch(
    .xml_normalize_friendly_path(value),
    error = function(condition) {
      .stop_xml_profile_error(
        sprintf("`%s` must be one non-empty visible XML name or path.", argument),
        parent = condition
      )
    }
  )

  paste(parts, collapse = "/")
}


.xml_profile_fields <- function(fields) {
  if (is.null(fields)) {
    return(NULL)
  }

  # YAML and JSON mappings normally arrive as named lists, while an R user
  # naturally supplies a character vector.  Accept both but require every
  # individual source selector to remain one scalar string.
  if (is.list(fields) && !is.data.frame(fields)) {
    scalar_strings <- vapply(
      fields,
      function(value) {
        is.character(value) &&
          length(value) == 1L &&
          !is.na(value)
      },
      logical(1)
    )

    if (!all(scalar_strings)) {
      .stop_xml_profile_error(
        "Every `fields` entry must contain one visible XML name or path."
      )
    }

    field_names <- names(fields)
    fields <- unlist(fields, use.names = FALSE)

    if (!is.null(field_names)) {
      names(fields) <- field_names
    }
  }

  if (
    !is.character(fields) ||
      length(fields) == 0L ||
      anyNA(fields)
  ) {
    .stop_xml_profile_error(
      paste0(
        "`fields` must be omitted to keep all values, or contain one or ",
        "more visible XML names or paths."
      )
    )
  }

  field_names <- names(fields)

  if (!is.null(field_names)) {
    named <- nzchar(trimws(field_names))

    if (any(named) && !all(named)) {
      .stop_xml_profile_error(
        "Either name every `fields` entry or leave every entry unnamed."
      )
    }

    if (all(named)) {
      if (anyDuplicated(field_names)) {
        .stop_xml_profile_error(
          "Output names in `fields` must be unique."
        )
      }

      names(fields) <- trimws(field_names)
    } else {
      names(fields) <- NULL
    }
  }

  normalized <- vapply(
    fields,
    .xml_profile_path,
    character(1),
    argument = "fields"
  )
  names(normalized) <- names(fields)
  normalized
}


.xml_supported_types <- function() {
  c("character", "integer", "double", "logical", "date")
}


.xml_profile_types <- function(types) {
  if (is.null(types)) {
    return(NULL)
  }

  if (is.list(types) && !is.data.frame(types)) {
    scalar_strings <- vapply(
      types,
      function(value) {
        is.character(value) &&
          length(value) == 1L &&
          !is.na(value)
      },
      logical(1)
    )

    if (!all(scalar_strings)) {
      .stop_xml_profile_error(
        "Every `types` entry must contain one supported type name."
      )
    }

    type_names <- names(types)
    types <- unlist(types, use.names = FALSE)

    if (!is.null(type_names)) {
      names(types) <- type_names
    }
  }

  if (
    !is.character(types) ||
      length(types) == 0L ||
      is.null(names(types)) ||
      anyNA(types) ||
      anyNA(names(types)) ||
      any(!nzchar(trimws(names(types)))) ||
      anyDuplicated(trimws(names(types)))
  ) {
    .stop_xml_profile_error(
      paste0(
        "`types` must be a named mapping from visible XML value names or ",
        "paths to supported type names."
      )
    )
  }

  selectors <- vapply(
    names(types),
    .xml_profile_path,
    character(1),
    argument = "types"
  )
  declared <- tolower(trimws(unname(types)))
  supported <- .xml_supported_types()

  if (any(!declared %in% supported)) {
    bad <- unique(declared[!declared %in% supported])
    .stop_xml_profile_error(
      paste0(
        "Unsupported type",
        if (length(bad) == 1L) "" else "s",
        ": ",
        paste(bad, collapse = ", "),
        ". Supported types are: ",
        paste(supported, collapse = ", "),
        "."
      )
    )
  }

  names(declared) <- selectors
  declared
}


.stop_xml_type_error <- function(
  message,
  source = NULL,
  output_name = NULL,
  declared_type = NULL,
  value = NULL
) {
  condition <- structure(
    list(
      message = message,
      call = NULL,
      source = source,
      output_name = output_name,
      declared_type = declared_type,
      value = value
    ),
    class = c("xml_type_error", "error", "condition")
  )

  stop(condition)
}


.xml_convert_values <- function(
  values,
  declared_type,
  source_label,
  output_name
) {
  if (identical(declared_type, "character")) {
    return(values)
  }

  present <- !is.na(values)
  lexical <- trimws(values)
  converted <- switch(
    declared_type,
    integer = {
      valid <- !present | grepl("^[+-]?[0-9]+$", lexical)
      parsed <- suppressWarnings(as.integer(lexical))
      valid <- valid & (!present | !is.na(parsed))
      list(value = parsed, valid = valid)
    },
    double = {
      pattern <- paste0(
        "^[+-]?(?:",
        "(?:[0-9]+(?:\\.[0-9]*)?)|(?:\\.[0-9]+)",
        ")(?:[eE][+-]?[0-9]+)?$"
      )
      valid <- !present | grepl(pattern, lexical, perl = TRUE)
      parsed <- suppressWarnings(as.double(lexical))
      valid <- valid & (!present | !is.na(parsed))
      list(value = parsed, valid = valid)
    },
    logical = {
      normalized <- tolower(lexical)
      valid_values <- c("true", "false", "1", "0")
      valid <- !present | normalized %in% valid_values
      parsed <- rep.int(NA, length(values))
      parsed[present & normalized %in% c("true", "1")] <- TRUE
      parsed[present & normalized %in% c("false", "0")] <- FALSE
      list(value = parsed, valid = valid)
    },
    date = {
      valid_shape <- !present | grepl(
        "^[0-9]{4}-[0-9]{2}-[0-9]{2}$",
        lexical
      )
      parsed <- suppressWarnings(as.Date(lexical, format = "%Y-%m-%d"))
      round_trip <- rep.int(TRUE, length(values))
      round_trip[present & !is.na(parsed)] <- (
        format(parsed[present & !is.na(parsed)], "%Y-%m-%d") ==
          lexical[present & !is.na(parsed)]
      )
      valid <- valid_shape & (!present | (!is.na(parsed) & round_trip))
      list(value = parsed, valid = valid)
    },
    stop("Internal error: unsupported declared XML type.", call. = FALSE)
  )

  if (any(!converted$valid)) {
    first <- which(!converted$valid)[[1L]]
    bad_value <- values[[first]]
    .stop_xml_type_error(
      paste0(
        "Could not convert value `",
        bad_value,
        "` from source `",
        source_label,
        "` to declared type `",
        declared_type,
        "` for output field `",
        output_name,
        "`."
      ),
      source = source_label,
      output_name = output_name,
      declared_type = declared_type,
      value = bad_value
    )
  }

  converted$value
}


.xml_typed_empty <- function(declared_type) {
  switch(
    declared_type,
    character = character(),
    integer = integer(),
    double = double(),
    logical = logical(),
    date = as.Date(character()),
    stop("Internal error: unsupported declared XML type.", call. = FALSE)
  )
}


.xml_apply_spec_types <- function(selected, catalog, types, representation) {
  selected$declared_type <- rep.int("character", nrow(selected))

  if (is.null(types)) {
    return(selected)
  }

  resolved <- lapply(
    seq_along(types),
    function(index) {
      match <- .resolve_friendly_value(
        catalog,
        names(types)[[index]],
        argument = "types"
      )
      list(
        source_key = match$source_key[[1L]],
        source_label = match$source_label[[1L]],
        declared_type = unname(types[[index]])
      )
    }
  )

  source_keys <- vapply(resolved, `[[`, character(1), "source_key")

  if (anyDuplicated(source_keys)) {
    stop(
      "`types` declares the same XML value more than once.",
      call. = FALSE
    )
  }

  selected_rows <- match(source_keys, selected$source_key)

  if (anyNA(selected_rows)) {
    first <- which(is.na(selected_rows))[[1L]]
    stop(
      paste0(
        "The typed source `",
        resolved[[first]]$source_label,
        "` is not among the selected `fields`."
      ),
      call. = FALSE
    )
  }

  declared <- vapply(resolved, `[[`, character(1), "declared_type")

  if (identical(representation, "long") && any(declared != "character")) {
    stop(
      paste0(
        "Non-character type conversion currently requires a wide rectangle. ",
        "A long rectangle keeps heterogeneous XML values in one atomic ",
        "`value` column, so converting different fields there would require ",
        "a list-column or information-losing coercion."
      ),
      call. = FALSE
    )
  }

  selected$declared_type[selected_rows] <- declared
  selected
}


.xml_validate_sample_types <- function(values, selected) {
  typed_rows <- which(selected$declared_type != "character")

  for (field_row in typed_rows) {
    occurrences <- values[
      values$source_key == selected$source_key[[field_row]],
      ,
      drop = FALSE
    ]

    .xml_convert_values(
      occurrences$value,
      declared_type = selected$declared_type[[field_row]],
      source_label = selected$source_label[[field_row]],
      output_name = selected$output_name[[field_row]]
    )
  }

  invisible(TRUE)
}


#' Declare the desired XML rectangle in plain language
#'
#' A profile contains only choices a user can reasonably make after looking at
#' the XML: the element that defines rows, an optional ID source, optional
#' selected/renamed fields, an optional namespace URI, and the one-table
#' layout.  It contains no XPath and no sample-specific internal node keys.
xml_profile <- function(
  rows,
  id = NULL,
  fields = NULL,
  types = NULL,
  namespace = NULL,
  layout = c("safe", "wide", "long")
) {
  rows <- .xml_profile_path(rows, "rows")

  if (is.null(id) || identical(id, FALSE)) {
    # Profiles are deliberately explicit: absent/false means generate a stable
    # sequence within each document.  Identifier guessing belongs to a later,
    # separately reviewable discovery layer.
    id <- FALSE
  } else if (identical(id, TRUE) || !is.character(id) || length(id) != 1L) {
    .stop_xml_profile_error(
      "`id` must be omitted/false for generated IDs, or name one XML value."
    )
  } else {
    id <- .xml_profile_path(id, "id")
  }

  fields <- .xml_profile_fields(fields)
  types <- .xml_profile_types(types)

  if (!is.null(namespace)) {
    namespace <- tryCatch(
      .validate_one_string(namespace, "namespace"),
      error = function(condition) {
        .stop_xml_profile_error(
          "`namespace` must be omitted or contain one namespace URI.",
          parent = condition
        )
      }
    )
  }

  layout <- tryCatch(
    match.arg(layout),
    error = function(condition) {
      .stop_xml_profile_error(
        "`layout` must be `safe`, `wide`, or `long`.",
        parent = condition
      )
    }
  )

  result <- list(
    version = 1L,
    rows = rows,
    id = id,
    fields = fields,
    types = types,
    namespace = namespace,
    layout = layout
  )
  class(result) <- "xml_profile"
  result
}


#' Convert a YAML/JSON-shaped list into a validated XML profile
as_xml_profile <- function(x) {
  if (inherits(x, "xml_profile")) {
    return(x)
  }

  if (!is.list(x) || is.data.frame(x) || is.null(names(x))) {
    .stop_xml_profile_error(
      "A portable XML profile must be a named list or an `xml_profile` object."
    )
  }

  if (anyNA(names(x)) || any(!nzchar(names(x))) || anyDuplicated(names(x))) {
    .stop_xml_profile_error(
      "Every portable profile setting must have one unique name."
    )
  }

  allowed <- c("version", "rows", "id", "fields", "types", "namespace", "layout")
  unknown <- setdiff(names(x), allowed)

  if (length(unknown) > 0L) {
    .stop_xml_profile_error(
      paste0(
        "Unknown profile setting",
        if (length(unknown) == 1L) "" else "s",
        ": ",
        paste(unknown, collapse = ", "),
        "."
      )
    )
  }

  if (!"rows" %in% names(x)) {
    .stop_xml_profile_error("A portable profile must contain `rows`.")
  }

  if ("version" %in% names(x)) {
    valid_version <- is.numeric(x$version) &&
      length(x$version) == 1L &&
      !is.na(x$version) &&
      x$version == 1

    if (!valid_version) {
      .stop_xml_profile_error(
        "This script currently supports XML profile version 1 only."
      )
    }
  }

  xml_profile(
    rows = x$rows,
    id = if ("id" %in% names(x)) x$id else NULL,
    fields = if ("fields" %in% names(x)) x$fields else NULL,
    types = if ("types" %in% names(x)) x$types else NULL,
    namespace = if ("namespace" %in% names(x)) x$namespace else NULL,
    layout = if ("layout" %in% names(x)) x$layout else "safe"
  )
}


as.list.xml_profile <- function(x, ...) {
  result <- unclass(as_xml_profile(x))

  if (!is.null(result$fields)) {
    # A named atomic vector becomes a JSON array and silently loses its names.
    # A list becomes an object/mapping instead, preserving the essential
    # output-name -> XML-source relationship in both JSON and YAML.
    result$fields <- as.list(result$fields)

    if (is.null(names(x$fields))) {
      result$fields <- unname(result$fields)
    }
  }

  if (!is.null(result$types)) {
    result$types <- as.list(result$types)
  }

  result
}


print.xml_profile <- function(x, ...) {
  cat("XML rectangle profile\n")
  cat("  Rows: ", x$rows, "\n", sep = "")
  cat(
    "  ID: ",
    if (identical(x$id, FALSE)) "generated sequence" else x$id,
    "\n",
    sep = ""
  )
  cat(
    "  Fields: ",
    if (is.null(x$fields)) {
      "all values"
    } else {
      paste0(length(x$fields), " selected")
    },
    "\n",
    sep = ""
  )
  cat(
    "  Types: ",
    if (is.null(x$types)) "all character" else paste0(length(x$types), " declared"),
    "\n",
    sep = ""
  )
  cat("  Layout: ", x$layout, " (one atomic table)\n", sep = "")

  if (!is.null(x$namespace)) {
    cat("  Row namespace: ", x$namespace, "\n", sep = "")
  }

  invisible(x)
}


.xml_profile_file_format <- function(file, format) {
  format <- match.arg(format, c("auto", "json", "yaml"))

  if (format != "auto") {
    return(format)
  }

  extension <- tolower(tools::file_ext(file))

  if (extension == "json") {
    return("json")
  }

  if (extension %in% c("yaml", "yml")) {
    return("yaml")
  }

  .stop_xml_profile_error(
    "Profile filenames must end in `.json`, `.yaml`, or `.yml`."
  )
}


#' Save a portable XML profile as JSON or YAML
write_xml_profile <- function(
  profile,
  file,
  format = c("auto", "json", "yaml"),
  overwrite = FALSE
) {
  profile <- as_xml_profile(profile)
  file <- .validate_one_string(file, "file")
  format <- .xml_profile_file_format(file, format)

  if (file.exists(file) && !isTRUE(overwrite)) {
    .stop_xml_profile_error(
      paste0("Profile file already exists: ", file, ". Use `overwrite = TRUE` to replace it.")
    )
  }

  parent <- dirname(file)

  if (!dir.exists(parent)) {
    .stop_xml_profile_error(
      paste0("Profile directory does not exist: ", parent, ".")
    )
  }

  payload <- as.list(profile)

  if (format == "json") {
    .require_xml_rectangle_package("jsonlite")
    jsonlite::write_json(
      payload,
      path = file,
      pretty = TRUE,
      auto_unbox = TRUE,
      null = "null"
    )
  } else {
    .require_xml_rectangle_package("yaml")
    yaml::write_yaml(payload, file = file)
  }

  invisible(
    normalizePath(file, winslash = "/", mustWork = TRUE)
  )
}


#' Read and validate a portable JSON or YAML XML profile
read_xml_profile <- function(
  file,
  format = c("auto", "json", "yaml")
) {
  file <- .validate_one_string(file, "file")

  if (!file.exists(file)) {
    .stop_xml_profile_error(paste0("Profile file does not exist: ", file, "."))
  }

  format <- .xml_profile_file_format(file, format)
  payload <- tryCatch(
    if (format == "json") {
      .require_xml_rectangle_package("jsonlite")
      jsonlite::read_json(file, simplifyVector = FALSE)
    } else {
      .require_xml_rectangle_package("yaml")
      yaml::read_yaml(file)
    },
    error = function(condition) {
      .stop_xml_profile_error(
        paste0("Could not read XML profile: ", conditionMessage(condition)),
        parent = condition
      )
    }
  )

  as_xml_profile(payload)
}


.translate_profile_error <- function(condition) {
  if (inherits(condition, c("xml_parse_error", "xml_profile_error"))) {
    stop(condition)
  }

  message <- conditionMessage(condition)
  message <- gsub("one_row_per", "rows", message, fixed = TRUE)
  message <- gsub("identify_by", "id", message, fixed = TRUE)
  message <- gsub("representation", "layout", message, fixed = TRUE)
  .stop_xml_profile_error(message, parent = condition)
}


#' Compile a human profile against one representative XML sample
#'
#' Compilation resolves visible names to exact namespace-aware path keys and
#' exposes the existing reviewable specification.  Reuse that compiled result
#' with rectangle_xml() when several files share one expected structure.
compile_xml_profile <- function(
  profile,
  sample,
  whitespace = c("drop_blank", "preserve")
) {
  profile <- as_xml_profile(profile)
  whitespace <- match.arg(whitespace)
  representation <- switch(
    profile$layout,
    safe = "auto",
    wide = "wide",
    long = "long"
  )

  result <- tryCatch(
    rectangle_spec(
      sample = sample,
      one_row_per = profile$rows,
      namespace = profile$namespace,
      identify_by = profile$id,
      fields = profile$fields,
      types = profile$types,
      representation = representation,
      whitespace = whitespace
    ),
    error = .translate_profile_error
  )
  result$profile <- profile
  result
}


#' Return the atomic field mapping stored in a rectangle specification
review_rectangle <- function(spec) {
  if (!inherits(spec, "xml_rect_spec")) {
    stop(
      "`spec` must be the result of rectangle_spec() or make_rectangle().",
      call. = FALSE
    )
  }

  fields <- spec$fields
  if (!"declared_type" %in% names(fields)) {
    fields$declared_type <- rep.int("character", nrow(fields))
  }

  result <- fields[
    ,
    c(
      "output_name",
      "source_label",
      "declared_type",
      "value_kind",
      "entity",
      "under_repetition",
      "max_per_record"
    ),
    drop = FALSE
  ]

  names(result)[names(result) == "source_label"] <- "source"
  rownames(result) <- NULL
  tibble::as_tibble(result)
}


.xml_declared_type_at <- function(fields, row) {
  if (!"declared_type" %in% names(fields)) {
    return("character")
  }

  value <- fields$declared_type[[row]]
  if (is.null(value) || is.na(value) || !nzchar(value)) "character" else value
}


print.xml_rect_spec <- function(x, ...) {
  cat("XML rectangle specification\n")
  cat("  One row per: ", x$record_path, "\n", sep = "")
  cat(
    "  Record identifier: ",
    if (x$identifier$mode == "source") {
      x$identifier$source_label
    } else {
      "generated sequence"
    },
    "\n",
    sep = ""
  )
  cat(
    "  Result: one ",
    x$representation,
    " table with atomic columns\n",
    sep = ""
  )
  cat("  Selected values: ", nrow(x$fields), "\n", sep = "")
  typed_count <- sum(vapply(
    seq_len(nrow(x$fields)),
    function(row) .xml_declared_type_at(x$fields, row) != "character",
    logical(1)
  ))
  if (typed_count > 0L) {
    cat("  Typed values: ", typed_count, "\n", sep = "")
  }

  if (any(x$fields$under_repetition)) {
    repeated_entities <- unique(
      x$fields$entity[x$fields$under_repetition]
    )
    cat(
      "  Repeated entities kept explicit: ",
      paste(repeated_entities, collapse = ", "),
      "\n",
      sep = ""
    )
  }

  cat("  Use review_rectangle() to inspect the field mapping.\n")
  invisible(x)
}


# -----------------------------------------------------------------------------
# Conservative structure and XSD-assisted proposal layer
# -----------------------------------------------------------------------------

.stop_xml_proposal_error <- function(message, parent = NULL) {
  condition <- structure(
    list(
      message = message,
      call = NULL,
      parent = parent
    ),
    class = c("xml_proposal_error", "error", "condition")
  )

  stop(condition)
}


.xml_proposal_row_candidates <- function(structure, xsd_inspection = NULL) {
  .require_xml_rectangle_package("tibble")
  paths <- structure$index$paths
  sample_repeated <- paths$repeated & paths$complex
  xsd_repeated <- rep.int(FALSE, nrow(paths))
  xsd_selector <- rep.int(NA_character_, nrow(paths))

  if (!is.null(xsd_inspection) && nrow(xsd_inspection$declarations) > 0L) {
    declarations <- xsd_inspection$declarations
    repeated_elements <- which(
      declarations$kind == "element" & declarations$repeated
    )

    for (row in seq_len(nrow(paths))) {
      if (!paths$complex[[row]] || length(repeated_elements) == 0L) {
        next
      }

      local_path <- paths$local_path[[row]]
      matches <- repeated_elements[vapply(
        declarations$selector[repeated_elements],
        function(selector) {
          declaration_path <- .xml_normalize_friendly_path(selector)
          .xml_suffix_matches(local_path, declaration_path)
        },
        logical(1)
      )]

      if (length(matches) == 1L) {
        xsd_repeated[[row]] <- TRUE
        xsd_selector[[row]] <- declarations$selector[[matches[[1L]]]]
      }
    }
  }

  supported <- sample_repeated | xsd_repeated

  if (!any(supported)) {
    minimum_depth <- min(paths$depth)
    selected_rows <- which(paths$depth == minimum_depth)
    candidates <- paths[selected_rows, , drop = FALSE]
    candidates$sample_repeated <- sample_repeated[selected_rows]
    candidates$xsd_repeated <- xsd_repeated[selected_rows]
    candidates$xsd_selector <- xsd_selector[selected_rows]
    candidates$priority <- rep.int("single_document", nrow(candidates))
    candidates$reason <- rep.int(
      "No repeated complex record element was supported by the sample or supplied XSD; the document root is the conservative fallback.",
      nrow(candidates)
    )
  } else {
    selected_rows <- which(supported)
    candidates <- paths[selected_rows, , drop = FALSE]
    candidates$sample_repeated <- sample_repeated[selected_rows]
    candidates$xsd_repeated <- xsd_repeated[selected_rows]
    candidates$xsd_selector <- xsd_selector[selected_rows]
    minimum_depth <- min(candidates$depth)
    candidates$priority <- ifelse(
      candidates$depth == minimum_depth,
      "primary",
      "alternative"
    )
    evidence <- ifelse(
      candidates$sample_repeated & candidates$xsd_repeated,
      "sample+xsd",
      ifelse(candidates$sample_repeated, "sample", "xsd")
    )
    candidates$reason <- ifelse(
      candidates$priority == "primary",
      paste0(
        "Repeated complex record candidate at the shallowest supported depth (evidence: ",
        evidence,
        ")."
      ),
      paste0(
        "Repeated complex record candidate nested below a shallower candidate (evidence: ",
        evidence,
        ")."
      )
    )
    candidates <- candidates[
      order(
        match(candidates$priority, c("primary", "alternative")),
        candidates$depth,
        -candidates$occurrences,
        candidates$display_path
      ),
      ,
      drop = FALSE
    ]
  }

  namespace <- ifelse(
    is.na(candidates$namespace_uri),
    "",
    candidates$namespace_uri
  )

  tibble::tibble(
    rows = candidates$display_path,
    namespace = namespace,
    occurrences = as.integer(candidates$occurrences),
    depth = as.integer(candidates$depth),
    max_per_parent = as.integer(candidates$max_per_parent),
    sample_repeated = candidates$sample_repeated,
    xsd_repeated = candidates$xsd_repeated,
    xsd_selector = candidates$xsd_selector,
    priority = candidates$priority,
    reason = candidates$reason,
    path_key = candidates$path_key
  )
}

.xml_proposal_choose_record <- function(
  structure,
  row_candidates,
  rows,
  namespace
) {
  if (!is.null(rows)) {
    record <- tryCatch(
      .resolve_friendly_element(
        structure,
        rows,
        argument = "rows",
        namespace = namespace
      ),
      error = function(condition) {
        .stop_xml_proposal_error(
          conditionMessage(condition),
          parent = condition
        )
      }
    )

    return(
      list(
        record = record,
        selection = "user",
        selector = record$display_path[[1L]]
      )
    )
  }

  preferred <- row_candidates[
    row_candidates$priority %in% c("primary", "single_document"),
    ,
    drop = FALSE
  ]

  if (nrow(preferred) != 1L) {
    return(
      list(
        record = NULL,
        selection = "choice_required",
        selector = NULL
      )
    )
  }

  record <- structure$index$paths[
    structure$index$paths$path_key == preferred$path_key[[1L]],
    ,
    drop = FALSE
  ]

  list(
    record = record,
    selection = "heuristic_for_review",
    selector = record$display_path[[1L]]
  )
}


.xml_proposal_numeric_pattern <- function() {
  paste0(
    "^[+-]?(?:",
    "(?:[0-9]+(?:\\.[0-9]*)?)|(?:\\.[0-9]+)",
    ")(?:[eE][+-]?[0-9]+)?$"
  )
}


.xml_has_numeric_leading_zero <- function(values) {
  values <- trimws(values)
  values <- sub("^[+-]", "", values)
  integer_part <- sub("[.eE].*$", "", values)
  any(grepl("^0[0-9]+$", integer_part))
}


.xml_infer_sample_type <- function(values) {
  values <- values[!is.na(values)]
  lexical <- trimws(values)

  if (length(lexical) == 0L) {
    return(
      list(
        type = "character",
        confidence = "none",
        reason = "No non-missing lexical values were observed."
      )
    )
  }

  if (any(!nzchar(lexical))) {
    return(
      list(
        type = "character",
        confidence = "high",
        reason = "Blank lexical values are preserved as character data."
      )
    )
  }

  valid_date_shape <- grepl(
    "^[0-9]{4}-[0-9]{2}-[0-9]{2}$",
    lexical
  )
  if (all(valid_date_shape)) {
    parsed_date <- suppressWarnings(as.Date(lexical, format = "%Y-%m-%d"))
    valid_date <- !is.na(parsed_date) & format(parsed_date, "%Y-%m-%d") == lexical

    if (all(valid_date)) {
      return(
        list(
          type = "date",
          confidence = if (length(unique(lexical)) >= 2L) "high" else "medium",
          reason = "Every observed value is a valid ISO date (YYYY-MM-DD)."
        )
      )
    }
  }

  logical_values <- tolower(lexical)
  if (
    all(logical_values %in% c("true", "false", "1", "0")) &&
      any(logical_values %in% c("true", "false"))
  ) {
    return(
      list(
        type = "logical",
        confidence = if (length(unique(logical_values)) >= 2L) "high" else "medium",
        reason = "Observed values use XML boolean lexical forms including true/false."
      )
    )
  }

  if (all(logical_values %in% c("1", "0"))) {
    return(
      list(
        type = "character",
        confidence = "medium",
        reason = "Only 0/1 were observed; these are too ambiguous to infer logical or numeric rather than coded character data."
      )
    )
  }

  integer_shape <- grepl("^[+-]?[0-9]+$", lexical)
  if (all(integer_shape)) {
    if (.xml_has_numeric_leading_zero(lexical)) {
      return(
        list(
          type = "character",
          confidence = "high",
          reason = "Numeric-looking values contain significant leading zeroes, so character is safer."
        )
      )
    }

    parsed_integer <- suppressWarnings(as.integer(lexical))
    if (all(!is.na(parsed_integer))) {
      return(
        list(
          type = "integer",
          confidence = if (length(unique(lexical)) >= 2L) "high" else "medium",
          reason = "Every observed value is an integer lexical form without leading-zero ambiguity."
        )
      )
    }
  }

  numeric_shape <- grepl(
    .xml_proposal_numeric_pattern(),
    lexical,
    perl = TRUE
  )
  if (all(numeric_shape)) {
    if (.xml_has_numeric_leading_zero(lexical)) {
      return(
        list(
          type = "character",
          confidence = "high",
          reason = "Numeric-looking values contain significant leading zeroes, so character is safer."
        )
      )
    }

    parsed_double <- suppressWarnings(as.double(lexical))
    if (all(is.finite(parsed_double))) {
      return(
        list(
          type = "double",
          confidence = if (length(unique(lexical)) >= 2L) "high" else "medium",
          reason = "Every observed value is a finite numeric lexical form and at least one is non-integer-shaped."
        )
      )
    }
  }

  list(
    type = "character",
    confidence = "high",
    reason = "No conservative non-character interpretation fits every observed lexical value."
  )
}


.xml_proposal_field_candidates <- function(values, catalog, number_of_records) {
  .require_xml_rectangle_package("tibble")

  if (nrow(catalog) == 0L) {
    return(
      tibble::tibble(
        source = character(),
        value_kind = character(),
        entity = character(),
        records_observed = integer(),
        coverage = double(),
        max_per_record = integer(),
        under_repetition = logical(),
        wide_safe = logical(),
        sample_type = character(),
        sample_confidence = character(),
        sample_reason = character(),
        source_key = character()
      )
    )
  }

  inferred <- lapply(
    catalog$source_key,
    function(source_key) {
      .xml_infer_sample_type(
        values$value[values$source_key == source_key]
      )
    }
  )

  tibble::tibble(
    source = catalog$source_label,
    value_kind = catalog$value_kind,
    entity = catalog$entity,
    records_observed = as.integer(catalog$records_observed),
    coverage = as.double(catalog$records_observed) / as.double(number_of_records),
    max_per_record = as.integer(catalog$max_per_record),
    under_repetition = catalog$under_repetition,
    wide_safe = !catalog$under_repetition & catalog$max_per_record <= 1L,
    sample_type = vapply(inferred, `[[`, character(1), "type"),
    sample_confidence = vapply(inferred, `[[`, character(1), "confidence"),
    sample_reason = vapply(inferred, `[[`, character(1), "reason"),
    source_key = catalog$source_key
  )
}


.xml_proposal_id_candidates <- function(values, catalog, number_of_records) {
  .require_xml_rectangle_package("tibble")

  if (nrow(catalog) == 0L) {
    return(
      tibble::tibble(
        source = character(),
        value_kind = character(),
        priority = character(),
        reason = character(),
        source_key = character()
      )
    )
  }

  valid <- vapply(
    catalog$source_key,
    function(source_key) {
      .xml_valid_record_identifier(
        values,
        source_key,
        number_of_records
      )
    },
    logical(1)
  )

  candidates <- catalog[valid, , drop = FALSE]
  if (nrow(candidates) == 0L) {
    return(
      tibble::tibble(
        source = character(),
        value_kind = character(),
        priority = character(),
        reason = character(),
        source_key = character()
      )
    )
  }

  terminal <- vapply(
    candidates$source_label,
    function(label) tail(.xml_source_alias_parts(label), 1L),
    character(1)
  )
  terminal_lower <- tolower(terminal)
  id_like <- terminal_lower == "id" | grepl("(^|[_-])id$", terminal_lower)

  priority <- ifelse(
    terminal_lower == "id" & candidates$value_kind == "attribute",
    "strong",
    ifelse(
      id_like,
      "strong",
      ifelse(candidates$value_kind == "attribute", "plausible", "possible")
    )
  )

  reason <- ifelse(
    terminal_lower == "id" & candidates$value_kind == "attribute",
    "Complete, unique scalar attribute conventionally named id.",
    ifelse(
      id_like,
      "Complete, unique scalar value with an ID-like name.",
      ifelse(
        candidates$value_kind == "attribute",
        "Complete, unique scalar attribute; semantics should be confirmed by the user.",
        "Complete, unique scalar value; semantics should be confirmed by the user."
      )
    )
  )

  order_index <- order(
    match(priority, c("strong", "plausible", "possible")),
    candidates$source_label
  )

  tibble::tibble(
    source = candidates$source_label[order_index],
    value_kind = candidates$value_kind[order_index],
    priority = priority[order_index],
    reason = reason[order_index],
    source_key = candidates$source_key[order_index]
  )
}


.xml_xsd_builtin_type <- function(type_qname, xsd_prefixes = c("xs", "xsd")) {
  if (is.null(type_qname) || length(type_qname) != 1L || is.na(type_qname)) {
    return(NA_character_)
  }

  type_qname <- trimws(type_qname)
  if (!nzchar(type_qname)) {
    return(NA_character_)
  }

  if (!grepl(":", type_qname, fixed = TRUE)) {
    # An unprefixed QName in an XSD is not assumed to be a built-in type.
    # It may name a user-defined type in the schema's target namespace.
    return(NA_character_)
  }

  prefix <- sub(":.*$", "", type_qname)
  if (!prefix %in% xsd_prefixes) {
    return(NA_character_)
  }

  sub("^.*:", "", type_qname)
}


.xml_xsd_analytical_type <- function(builtin_type) {
  if (is.na(builtin_type)) {
    return(NA_character_)
  }

  if (builtin_type %in% c(
    "byte", "short", "int", "unsignedByte", "unsignedShort"
  )) {
    return("integer")
  }

  if (builtin_type %in% c("decimal", "float", "double")) {
    return("double")
  }

  if (identical(builtin_type, "boolean")) {
    return("logical")
  }

  if (identical(builtin_type, "date")) {
    return("date")
  }

  if (builtin_type %in% c(
    "string", "normalizedString", "token", "language", "Name", "NCName",
    "NMTOKEN", "NMTOKENS", "ID", "IDREF", "IDREFS", "ENTITY", "ENTITIES",
    "QName", "anyURI", "hexBinary", "base64Binary", "duration", "dateTime",
    "time", "gYear", "gYearMonth", "gMonth", "gMonthDay", "gDay"
  )) {
    return("character")
  }

  NA_character_
}


.xml_xsd_declaration_selector <- function(node, kind, name) {
  xsd_uri <- "http://www.w3.org/2001/XMLSchema"
  ancestors <- xml2::xml_find_all(
    node,
    paste0(
      "ancestor::*[",
      "namespace-uri(.)='", xsd_uri, "' and ",
      "local-name(.)='element'",
      "]"
    )
  )

  ancestor_names <- vapply(
    ancestors,
    function(parent) {
      value <- xml2::xml_attr(parent, "name")
      if (is.na(value) || !nzchar(value)) {
        value <- xml2::xml_attr(parent, "ref")
      }
      if (is.na(value) || !nzchar(value)) {
        return("")
      }
      sub("^.*:", "", value)
    },
    character(1)
  )
  ancestor_names <- ancestor_names[nzchar(ancestor_names)]

  current <- if (identical(kind, "attribute")) paste0("@", name) else name
  paste(c(ancestor_names, current), collapse = "/")
}

#' Inspect directly declared XML Schema values as advisory evidence
#'
#' This is intentionally not a complete XSD validator. It exposes direct
#' element/attribute declarations, occurrence constraints, and a conservative
#' mapping of common built-in XSD scalar types to the analytical types supported
#' by this prototype. Imported schemas, substitution groups, wildcards, and
#' arbitrary user-defined type derivations are not silently resolved.
inspect_xsd <- function(xsd) {
  .require_xml_rectangle_package("xml2")
  .require_xml_rectangle_package("tibble")
  xsd <- .validate_one_string(xsd, "xsd")

  document <- tryCatch(
    xml2::read_xml(xsd),
    error = function(condition) {
      .stop_xml_parse_error(
        paste0("Could not parse XSD source: ", conditionMessage(condition)),
        source = xsd
      )
    }
  )

  root <- xml2::xml_root(document)
  xsd_uri <- "http://www.w3.org/2001/XMLSchema"
  root_uri <- xml2::xml_find_chr(root, "namespace-uri(.)")

  if (!identical(root_uri, xsd_uri) || xml2::xml_name(root) != "schema") {
    .stop_xml_proposal_error(
      "`xsd` must have an XML Schema `<schema>` root in the W3C XML Schema namespace."
    )
  }

  namespace_map <- xml2::xml_ns(root)
  namespace_values <- as.character(namespace_map)
  xsd_prefixes <- names(namespace_values)[namespace_values == xsd_uri]
  xsd_prefixes <- unique(c("xs", "xsd", xsd_prefixes))

  declaration_nodes <- xml2::xml_find_all(
    document,
    paste0(
      "//*[namespace-uri()='", xsd_uri,
      "' and (local-name()='element' or local-name()='attribute') and (@name or @ref)]"
    )
  )

  declarations <- lapply(
    declaration_nodes,
    function(node) {
      kind <- xml2::xml_name(node)
      name <- xml2::xml_attr(node, "name")
      ref <- xml2::xml_attr(node, "ref")
      if (is.na(name) || !nzchar(name)) {
        name <- sub("^.*:", "", ref)
      }

      type_qname <- xml2::xml_attr(node, "type")
      type_source <- "type_attribute"

      if (is.na(type_qname) || !nzchar(type_qname)) {
        restriction <- xml2::xml_find_first(
          node,
          paste0(
            "./*[namespace-uri()='", xsd_uri,
            "' and local-name()='simpleType']",
            "/*[namespace-uri()='", xsd_uri,
            "' and local-name()='restriction'][1]"
          )
        )
        if (!inherits(restriction, "xml_missing")) {
          type_qname <- xml2::xml_attr(restriction, "base")
          type_source <- "inline_restriction"
        }
      }

      if (is.na(type_qname) || !nzchar(type_qname)) {
        type_qname <- NA_character_
        type_source <- "unresolved"
      }

      builtin <- .xml_xsd_builtin_type(type_qname, xsd_prefixes = xsd_prefixes)
      analytical <- .xml_xsd_analytical_type(builtin)
      max_occurs <- xml2::xml_attr(node, "maxOccurs")
      min_occurs <- xml2::xml_attr(node, "minOccurs")
      use <- xml2::xml_attr(node, "use")

      if (is.na(max_occurs) || !nzchar(max_occurs)) {
        max_occurs <- "1"
      }
      if (is.na(min_occurs) || !nzchar(min_occurs)) {
        min_occurs <- if (identical(kind, "attribute")) "0" else "1"
      }
      repeated <- identical(max_occurs, "unbounded") || (
        grepl("^[0-9]+$", max_occurs) && as.double(max_occurs) > 1
      )
      required <- if (identical(kind, "attribute")) {
        identical(use, "required")
      } else {
        !identical(min_occurs, "0")
      }

      list(
        selector = .xml_xsd_declaration_selector(node, kind, name),
        kind = kind,
        name = name,
        type = type_qname,
        builtin_type = builtin,
        analytical_type = analytical,
        type_source = type_source,
        min_occurs = min_occurs,
        max_occurs = max_occurs,
        repeated = repeated,
        required = required
      )
    }
  )

  if (length(declarations) == 0L) {
    declaration_table <- tibble::tibble(
      selector = character(),
      kind = character(),
      name = character(),
      type = character(),
      builtin_type = character(),
      analytical_type = character(),
      type_source = character(),
      min_occurs = character(),
      max_occurs = character(),
      repeated = logical(),
      required = logical()
    )
  } else {
    declaration_table <- tibble::tibble(
      selector = vapply(declarations, `[[`, character(1), "selector"),
      kind = vapply(declarations, `[[`, character(1), "kind"),
      name = vapply(declarations, `[[`, character(1), "name"),
      type = vapply(declarations, `[[`, character(1), "type"),
      builtin_type = vapply(declarations, `[[`, character(1), "builtin_type"),
      analytical_type = vapply(declarations, `[[`, character(1), "analytical_type"),
      type_source = vapply(declarations, `[[`, character(1), "type_source"),
      min_occurs = vapply(declarations, `[[`, character(1), "min_occurs"),
      max_occurs = vapply(declarations, `[[`, character(1), "max_occurs"),
      repeated = vapply(declarations, `[[`, logical(1), "repeated"),
      required = vapply(declarations, `[[`, logical(1), "required")
    )
  }

  target_namespace <- xml2::xml_attr(root, "targetNamespace")
  if (is.na(target_namespace)) {
    target_namespace <- ""
  }

  result <- list(
    source = normalizePath(xsd, winslash = "/", mustWork = FALSE),
    target_namespace = target_namespace,
    declarations = declaration_table,
    limitations = c(
      "Direct declarations and inline restrictions are inspected.",
      "Imported/include schemas are not followed automatically.",
      "User-defined type derivations are reported but not silently reduced to analytical types."
    )
  )
  class(result) <- "xml_xsd_inspection"
  result
}


print.xml_xsd_inspection <- function(x, ...) {
  cat("XML Schema inspection\n")
  cat("  Source: ", x$source, "\n", sep = "")
  if (nzchar(x$target_namespace)) {
    cat("  Target namespace: ", x$target_namespace, "\n", sep = "")
  }
  cat("  Direct declarations: ", nrow(x$declarations), "\n", sep = "")
  mapped <- sum(!is.na(x$declarations$analytical_type))
  cat("  Declarations with analytical type evidence: ", mapped, "\n", sep = "")
  cat("  This is advisory schema inspection, not full XSD validation.\n")
  invisible(x)
}


.xml_xsd_match_fields <- function(fields, record, xsd_inspection) {
  declarations <- xsd_inspection$declarations
  fields$xsd_match <- rep.int("none", nrow(fields))
  fields$xsd_selector <- rep.int(NA_character_, nrow(fields))
  fields$xsd_type <- rep.int(NA_character_, nrow(fields))
  fields$xsd_analytical_type <- rep.int(NA_character_, nrow(fields))
  fields$xsd_required <- rep.int(NA, nrow(fields))
  fields$xsd_repeated <- rep.int(NA, nrow(fields))

  if (nrow(fields) == 0L || nrow(declarations) == 0L) {
    return(fields)
  }

  record_parts <- record$local_path[[1L]]

  for (row in seq_len(nrow(fields))) {
    source_parts <- .xml_normalize_friendly_path(fields$source[[row]])
    absolute_parts <- c(record_parts, source_parts)
    desired_kind <- if (identical(fields$value_kind[[row]], "attribute")) {
      "attribute"
    } else {
      "element"
    }

    candidate_rows <- which(declarations$kind == desired_kind)
    candidate_rows <- candidate_rows[vapply(
      declarations$selector[candidate_rows],
      function(selector) {
        declaration_parts <- .xml_normalize_friendly_path(selector)
        .xml_suffix_matches(absolute_parts, declaration_parts)
      },
      logical(1)
    )]

    if (length(candidate_rows) == 1L) {
      selected <- candidate_rows[[1L]]
      fields$xsd_match[[row]] <- "matched"
      fields$xsd_selector[[row]] <- declarations$selector[[selected]]
      fields$xsd_type[[row]] <- declarations$type[[selected]]
      fields$xsd_analytical_type[[row]] <- declarations$analytical_type[[selected]]
      fields$xsd_required[[row]] <- declarations$required[[selected]]
      fields$xsd_repeated[[row]] <- declarations$repeated[[selected]]
    } else if (length(candidate_rows) > 1L) {
      fields$xsd_match[[row]] <- "ambiguous"
    }
  }

  fields
}


#' Propose reviewable XML rectangle choices without executing them
#'
#' The proposal layer is deliberately advisory. It can rank likely row elements,
#' identify complete unique scalar ID candidates, summarize field multiplicity,
#' and suggest scalar types from lexical evidence. If `xsd` is supplied, direct
#' XSD declarations are matched conservatively and shown alongside sample-based
#' evidence. The function never returns an `xml_profile` and never rectangles
#' the source automatically.
propose_xml_profile <- function(
  sample,
  rows = NULL,
  namespace = NULL,
  xsd = NULL,
  whitespace = c("drop_blank", "preserve")
) {
  whitespace <- match.arg(whitespace)
  structure <- if (inherits(sample, "xml_structure")) {
    sample
  } else {
    inspect_xml(sample, whitespace = whitespace)
  }

  xsd_inspection <- if (is.null(xsd)) NULL else inspect_xsd(xsd)
  row_candidates <- .xml_proposal_row_candidates(
    structure,
    xsd_inspection = xsd_inspection
  )
  chosen <- .xml_proposal_choose_record(
    structure,
    row_candidates,
    rows = rows,
    namespace = namespace
  )

  if (is.null(chosen$record)) {
    field_candidates <- .xml_proposal_field_candidates(
      .xml_long_value_schema(),
      .xml_value_catalog(.xml_long_value_schema()),
      number_of_records = 1L
    )
    id_candidates <- .xml_proposal_id_candidates(
      .xml_long_value_schema(),
      .xml_value_catalog(.xml_long_value_schema()),
      number_of_records = 1L
    )
  } else {
    repeated_paths <- .xml_descendant_repeated_paths(structure, chosen$record)
    values <- .xml_extract_long_values(
      structure$nodes,
      record_path_key = chosen$record$path_key[[1L]],
      declared_entity_path_keys = repeated_paths$path_key,
      index = structure$index
    )
    catalog <- .xml_value_catalog(values)
    number_of_records <- chosen$record$occurrences[[1L]]
    field_candidates <- .xml_proposal_field_candidates(
      values,
      catalog,
      number_of_records
    )
    id_candidates <- .xml_proposal_id_candidates(
      values,
      catalog,
      number_of_records
    )

    if (!is.null(xsd_inspection)) {
      field_candidates <- .xml_xsd_match_fields(
        field_candidates,
        chosen$record,
        xsd_inspection
      )
    }
  }

  result <- list(
    version = 1L,
    source = structure$source,
    whitespace = structure$whitespace,
    row_selection = chosen$selection,
    selected_rows = chosen$selector,
    selected_namespace = if (
      is.null(chosen$record) ||
        is.na(chosen$record$namespace_uri[[1L]])
    ) {
      NULL
    } else {
      chosen$record$namespace_uri[[1L]]
    },
    row_candidates = row_candidates,
    id_candidates = id_candidates,
    field_candidates = field_candidates,
    xsd = xsd_inspection,
    profile_template = if (is.null(chosen$record)) {
      NULL
    } else {
      list(
        rows = chosen$selector,
        id = FALSE,
        fields = NULL,
        types = NULL,
        namespace = if (
          is.na(chosen$record$namespace_uri[[1L]]) ||
            !nzchar(chosen$record$namespace_uri[[1L]])
        ) NULL else chosen$record$namespace_uri[[1L]],
        layout = "safe"
      )
    }
  )
  class(result) <- "xml_profile_proposal"
  result
}


print.xml_profile_proposal <- function(x, ...) {
  cat("XML profile proposal (review only)\n")
  cat("  Source: ", x$source, "\n", sep = "")
  cat("  Row candidates: ", nrow(x$row_candidates), "\n", sep = "")

  if (identical(x$row_selection, "choice_required")) {
    cat("  Row selection: user choice required before field analysis\n")
  } else {
    cat(
      "  Row used for proposal analysis: ",
      x$selected_rows,
      " (",
      x$row_selection,
      ")\n",
      sep = ""
    )
    cat("  ID candidates: ", nrow(x$id_candidates), "\n", sep = "")
    cat("  Field candidates: ", nrow(x$field_candidates), "\n", sep = "")
    typed <- sum(x$field_candidates$sample_type != "character")
    cat("  Sample-based non-character type suggestions: ", typed, "\n", sep = "")
    if (!is.null(x$xsd)) {
      matched <- sum(x$field_candidates$xsd_match == "matched")
      cat("  Fields matched to direct XSD declarations: ", matched, "\n", sep = "")
    }
  }

  cat("  Nothing is executed or accepted automatically.\n")
  cat("  Use review_xml_proposal() and then create an explicit xml_profile().\n")
  invisible(x)
}


#' Review one part of an XML profile proposal
review_xml_proposal <- function(
  proposal,
  what = c("rows", "ids", "fields", "xsd")
) {
  if (!inherits(proposal, "xml_profile_proposal")) {
    stop(
      "`proposal` must be the result of propose_xml_profile().",
      call. = FALSE
    )
  }

  what <- match.arg(what)
  switch(
    what,
    rows = {
      result <- proposal$row_candidates
      result$path_key <- NULL
      result
    },
    ids = {
      result <- proposal$id_candidates
      result$source_key <- NULL
      result
    },
    fields = {
      result <- proposal$field_candidates
      result$source_key <- NULL
      result
    },
    xsd = {
      if (is.null(proposal$xsd)) {
        tibble::tibble()
      } else {
        proposal$xsd$declarations
      }
    }
  )
}


.xml_record_ids <- function(
  values,
  record_elements,
  spec,
  check_unique = TRUE
) {
  number_of_records <- nrow(record_elements)

  if (spec$identifier$mode == "generated") {
    return(as.character(seq_len(number_of_records)))
  }

  source_key <- spec$identifier$source_key
  selected <- values[values$source_key == source_key, , drop = FALSE]
  counts <- tabulate(selected$record_index, nbins = number_of_records)

  if (
    length(counts) != number_of_records ||
      any(counts != 1L) ||
      anyNA(selected$value) ||
      any(!nzchar(selected$value))
  ) {
    stop(
      paste0(
        "The identifier source `",
        spec$identifier$source_label,
        "` does not provide exactly one non-empty value per record."
      ),
      call. = FALSE
    )
  }

  identifiers <- rep.int(NA_character_, number_of_records)
  identifiers[selected$record_index] <- selected$value

  if (isTRUE(check_unique) && anyDuplicated(identifiers)) {
    stop(
      paste0(
        "The identifier source `",
        spec$identifier$source_label,
        "` is not unique in this XML document."
      ),
      call. = FALSE
    )
  }

  identifiers
}


.xml_rectangle_with_metadata <- function(
  nodes,
  spec,
  .validated = FALSE,
  .check_identifier_uniqueness = TRUE
) {
  if (!isTRUE(.validated)) {
    validate_xml_nodes(nodes)
  }
  .require_xml_rectangle_package("tibble")

  if (inherits(spec, "xml_profile")) {
    # Canonical data is already the source of truth here.  Compiling directly
    # against it preserves the shared representation and avoids reconstructing
    # or reparsing XML merely to resolve the human-facing names.
    spec <- compile_xml_profile(spec, nodes)
  }

  if (!inherits(spec, "xml_rect_spec")) {
    stop(
      paste0(
        "`spec` must be an xml_profile or the result of rectangle_spec() ",
        "or make_rectangle()."
      ),
      call. = FALSE
    )
  }

  index <- .build_xml_structure_index(nodes, validate = FALSE)
  record_elements <- index$elements[
    index$elements$path_key == spec$record_path_key,
    ,
    drop = FALSE
  ]

  if (nrow(record_elements) == 0L) {
    stop(
      paste0(
        "The XML document does not contain the specified row element `",
        spec$record_path,
        "`."
      ),
      call. = FALSE
    )
  }

  values <- .xml_extract_long_values(
    nodes,
    record_path_key = spec$record_path_key,
    declared_entity_path_keys = spec$repeated_path_keys,
    index = index
  )

  identifiers <- .xml_record_ids(
    values,
    record_elements,
    spec,
    check_unique = .check_identifier_uniqueness
  )
  selected_index <- match(values$source_key, spec$fields$source_key)
  selected_values <- values[!is.na(selected_index), , drop = FALSE]
  selected_index <- selected_index[!is.na(selected_index)]

  if (spec$representation == "long") {
    selected_values$field <- spec$fields$output_name[selected_index]
    selected_values$record_id <- identifiers[selected_values$record_index]
    selected_values$source <- selected_values$source_label

    result <- selected_values[
      ,
      c(
        "document_id",
        "record_index",
        "record_id",
        "entity",
        "entity_index",
        "field",
        "value_index",
        "value",
        "value_kind",
        "source",
        "record_node_id",
        "entity_node_id",
        "parent_entity_node_id",
        "source_node_id",
        "source_path"
      ),
      drop = FALSE
    ]

    rownames(result) <- NULL
    return(
      list(
        data = tibble::as_tibble(result),
        identifiers = identifiers
      )
    )
  }

  result <- tibble::tibble(
    document_id = record_elements$document_id,
    record_index = as.integer(seq_len(nrow(record_elements))),
    record_id = identifiers,
    record_node_id = record_elements$node_id
  )

  for (field_row in seq_len(nrow(spec$fields))) {
    source_key <- spec$fields$source_key[[field_row]]
    output_name <- spec$fields$output_name[[field_row]]
    occurrences <- values[values$source_key == source_key, , drop = FALSE]
    counts <- tabulate(
      occurrences$record_index,
      nbins = nrow(record_elements)
    )

    if (any(counts > 1L)) {
      stop(
        paste0(
          "The source `",
          spec$fields$source_label[[field_row]],
          "` repeats in the new XML document and cannot be placed in one ",
          "atomic wide column. Rebuild the specification as long."
        ),
        call. = FALSE
      )
    }

    column <- rep.int(NA_character_, nrow(record_elements))

    if (nrow(occurrences) > 0L) {
      column[occurrences$record_index] <- occurrences$value
    }

    result[[output_name]] <- .xml_convert_values(
      column,
      declared_type = .xml_declared_type_at(spec$fields, field_row),
      source_label = spec$fields$source_label[[field_row]],
      output_name = output_name
    )
  }

  list(
    data = result,
    identifiers = identifiers
  )
}


# Internal sequential oracle.  Keep this separate from the public dispatcher so
# the parallel implementation can always fall back without recursively entering
# automatic execution selection.
.xml_rectangle_sequential <- function(nodes, spec, .validated = FALSE) {
  # The streaming engine also needs the identifier when a long record happens
  # to contain none of the selected values.  Keep that bookkeeping private so
  # the public result remains an ordinary tibble with no hidden attributes.
  #
  # `.validated = TRUE` is strictly an internal fast path used by the unified
  # dispatcher after it has already validated the canonical node contract.
  # Public sequential calls retain the original validation behaviour.
  .xml_rectangle_with_metadata(nodes, spec, .validated = .validated)$data
}


#' Apply a rectangle specification to a canonical XML node table
#'
#' The result is always one data frame and every output column is atomic. A
#' long result retains explicit record and repeated-entity identifiers rather
#' than multiplying independent repetitions into a Cartesian product.
#'
#' Execution is intentionally a property of this same operation rather than a
#' separate user workflow. `parallel = FALSE` preserves the frozen sequential
#' path. `parallel = TRUE` requests parallel execution with automatically chosen
#' worker/chunk/task defaults. `parallel = "auto"` uses the same defaults but
#' stays sequential when the canonical record workload is too small to justify
#' process-level parallel overhead. Advanced controls remain optional.
xml_rectangle <- function(
  nodes,
  spec,
  parallel = FALSE,
  workers = NULL,
  strategy = "auto",
  chunk_records = NULL,
  task_records = NULL,
  progress = FALSE
) {
  mode <- .xml_normalize_parallel_mode(parallel)

  if (identical(mode, "sequential")) {
    return(.xml_rectangle_sequential(nodes, spec))
  }

  validate_xml_nodes(nodes)

  if (inherits(spec, "xml_profile")) {
    spec <- compile_xml_profile(spec, sample = nodes)
  }

  if (!inherits(spec, "xml_rect_spec")) {
    stop(
      paste0(
        "`spec` must be an xml_profile or the result of rectangle_spec() ",
        "or make_rectangle()."
      ),
      call. = FALSE
    )
  }

  stream_spec_error <- tryCatch(
    {
      .validate_stream_rectangle_spec(spec)
      NULL
    },
    error = function(condition) condition
  )

  if (!is.null(stream_spec_error)) {
    if (identical(mode, "auto")) {
      return(.xml_rectangle_sequential(nodes, spec, .validated = TRUE))
    }
    stop(stream_spec_error)
  }

  plan <- .xml_plan_in_memory_execution(
    nodes = nodes,
    spec = spec,
    parallel = parallel,
    workers = workers,
    strategy = strategy
  )

  if (!isTRUE(plan$use_parallel)) {
    return(.xml_rectangle_sequential(nodes, spec, .validated = TRUE))
  }

  .xml_rectangle_parallel_impl(
    nodes = nodes,
    spec = spec,
    workers = plan$workers,
    strategy = plan$strategy,
    chunk_records = chunk_records,
    task_records = task_records,
    progress = progress,
    spans = plan$spans,
    .validated = TRUE,
    .stream_spec_validated = TRUE
  )
}


#' Read an XML file in memory and apply a rectangle specification
#'
#' `parallel` uses the same execution contract as `xml_rectangle()`. Ordinary
#' use therefore needs no parallel-specific function name: set `parallel = TRUE`
#' to request the tuned defaults, or `parallel = "auto"` to let the engine avoid
#' parallel overhead for small record workloads.
rectangle_xml <- function(
  file,
  spec,
  whitespace = NULL,
  parallel = FALSE,
  workers = NULL,
  strategy = "auto",
  chunk_records = NULL,
  task_records = NULL,
  progress = FALSE
) {
  file <- .validate_one_string(file, "file")

  if (inherits(spec, "xml_profile")) {
    # The convenience path reads once, compiles the visible profile against
    # that canonical table, and immediately rectangles it. Users processing a
    # family of files should compile once explicitly and reuse the exact spec.
    whitespace <- if (is.null(whitespace)) {
      "drop_blank"
    } else {
      match.arg(whitespace, c("drop_blank", "preserve"))
    }

    nodes <- xml_to_nodes_memory(file, whitespace = whitespace)
    compiled <- compile_xml_profile(
      spec,
      sample = nodes,
      whitespace = whitespace
    )

    return(
      xml_rectangle(
        nodes = nodes,
        spec = compiled,
        parallel = parallel,
        workers = workers,
        strategy = strategy,
        chunk_records = chunk_records,
        task_records = task_records,
        progress = progress
      )
    )
  }

  if (!inherits(spec, "xml_rect_spec")) {
    stop(
      paste0(
        "`spec` must be an xml_profile or the result of rectangle_spec() ",
        "or make_rectangle()."
      ),
      call. = FALSE
    )
  }

  if (is.null(whitespace)) {
    whitespace <- spec$whitespace
  } else {
    whitespace <- match.arg(whitespace, c("drop_blank", "preserve"))
  }

  nodes <- xml_to_nodes_memory(file, whitespace = whitespace)

  xml_rectangle(
    nodes = nodes,
    spec = spec,
    parallel = parallel,
    workers = workers,
    strategy = strategy,
    chunk_records = chunk_records,
    task_records = task_records,
    progress = progress
  )
}


# -----------------------------------------------------------------------------
# End-to-end bounded streaming rectangling
# -----------------------------------------------------------------------------

.validate_stream_rectangle_spec <- function(spec) {
  if (inherits(spec, "xml_profile")) {
    stop(
      paste0(
        "Streaming requires a compiled rectangle specification. Compile the ",
        "profile once against a representative sample with ",
        "`compile_xml_profile()`, then reuse that result."
      ),
      call. = FALSE
    )
  }

  if (!inherits(spec, "xml_rect_spec")) {
    stop(
      paste0(
        "`spec` must be the compiled result of `compile_xml_profile()`, ",
        "`rectangle_spec()`, or `make_rectangle()`."
      ),
      call. = FALSE
    )
  }

  path <- spec$record_expanded_path
  valid_path <- is.character(path) &&
    length(path) > 0L &&
    !anyNA(path) &&
    all(nzchar(path))

  if (!valid_path) {
    stop(
      paste0(
        "This specification predates streaming support and does not contain ",
        "the namespace-aware record path. Recompile it from its profile or ",
        "representative XML sample."
      ),
      call. = FALSE
    )
  }

  invisible(TRUE)
}


.xml_rectangle_result_schema <- function(spec) {
  .require_xml_rectangle_package("tibble")

  if (identical(spec$representation, "long")) {
    return(
      tibble::tibble(
        document_id = character(),
        record_index = integer(),
        record_id = character(),
        entity = character(),
        entity_index = integer(),
        field = character(),
        value_index = integer(),
        value = character(),
        value_kind = character(),
        source = character(),
        record_node_id = integer(),
        entity_node_id = integer(),
        parent_entity_node_id = integer(),
        source_node_id = integer(),
        source_path = character()
      )
    )
  }

  result <- tibble::tibble(
    document_id = character(),
    record_index = integer(),
    record_id = character(),
    record_node_id = integer()
  )

  # The canonical layer always retains raw character data.  Wide rectangle
  # columns may opt into declared analytical types in the compiled spec.
  for (field_row in seq_len(nrow(spec$fields))) {
    output_name <- spec$fields$output_name[[field_row]]
    result[[output_name]] <- .xml_typed_empty(
      .xml_declared_type_at(spec$fields, field_row)
    )
  }

  result
}


.localize_stream_record <- function(prefix_rows, record_chunks) {
  .require_xml_rectangle_package("tibble")

  pieces <- c(list(prefix_rows), record_chunks)
  nodes <- tibble::as_tibble(do.call(rbind, unname(pieces)))
  rownames(nodes) <- NULL

  old_node_ids <- nodes$node_id
  old_parent_ids <- nodes$parent_id
  new_node_ids <- as.integer(seq_len(nrow(nodes)))
  new_parent_ids <- match(old_parent_ids, old_node_ids)

  missing_parent <- !is.na(old_parent_ids) & is.na(new_parent_ids)

  if (any(missing_parent)) {
    stop(
      "An internal streaming record buffer is missing an ancestor node.",
      call. = FALSE
    )
  }

  nodes$node_id <- new_node_ids
  nodes$parent_id <- as.integer(new_parent_ids)
  nodes$node_order <- new_node_ids

  # Only the ancestor chain is copied above the record.  Recalculate semantic
  # sibling positions so that the localized table is a valid, self-contained
  # canonical document even when omitted siblings preceded the record.
  nodes$sibling_order[] <- NA_integer_
  content_rows <- which(
    nodes$node_type != "document" &
      nodes$node_type != "attribute"
  )

  if (length(content_rows) > 0L) {
    groups <- split(
      content_rows,
      nodes$parent_id[content_rows],
      drop = TRUE
    )

    for (group in groups) {
      nodes$sibling_order[group] <- seq_along(group)
    }
  }

  validate_xml_nodes(nodes)

  list(
    nodes = nodes,
    # The vector is indexed by localized node_id and permits every provenance
    # column in the result to be restored to its original document-global ID.
    local_to_global = old_node_ids
  )
}


.restore_stream_result_coordinates <- function(
  result,
  local_to_global,
  record_index,
  record_id
) {
  id_columns <- intersect(
    c(
      "record_node_id",
      "entity_node_id",
      "parent_entity_node_id",
      "source_node_id"
    ),
    names(result)
  )

  for (column in id_columns) {
    local_ids <- result[[column]]
    translated <- rep.int(NA_integer_, length(local_ids))
    present <- !is.na(local_ids)

    if (any(present)) {
      translated[present] <- local_to_global[local_ids[present]]
    }

    result[[column]] <- translated
  }

  if (nrow(result) > 0L) {
    result$record_index[] <- as.integer(record_index)
    result$record_id[] <- record_id
  }

  result
}


.new_xml_rectangle_batcher <- function(
  callback,
  batch_rows
) {
  .require_xml_rectangle_package("tibble")
  batch_rows <- .validate_chunk_rows(batch_rows)

  state <- new.env(parent = emptyenv())
  state$parts <- list()
  state$size <- 0L
  state$total_rows <- 0L
  state$total_chunks <- 0L

  flush <- function() {
    if (state$size == 0L) {
      return(invisible(NULL))
    }

    batch <- if (length(state$parts) == 1L) {
      state$parts[[1L]]
    } else {
      tibble::as_tibble(do.call(rbind, unname(state$parts)))
    }
    rownames(batch) <- NULL

    # Do not update counters until the consumer has accepted the batch.  A
    # failed callback must never be reported as successful partial progress.
    callback(batch)
    state$total_rows <- state$total_rows + nrow(batch)
    state$total_chunks <- state$total_chunks + 1L
    state$parts <- list()
    state$size <- 0L
    invisible(NULL)
  }

  add <- function(result) {
    if (nrow(result) == 0L) {
      return(invisible(NULL))
    }

    first <- 1L

    while (first <= nrow(result)) {
      available <- batch_rows - state$size
      last <- min(nrow(result), first + available - 1L)
      state$parts[[length(state$parts) + 1L]] <- result[
        seq.int(first, last),
        ,
        drop = FALSE
      ]
      state$size <- state$size + last - first + 1L
      first <- last + 1L

      if (state$size == batch_rows) {
        flush()
      }
    }

    invisible(NULL)
  }

  finish <- function() {
    flush()

    list(
      result_rows = state$total_rows,
      result_chunks = state$total_chunks
    )
  }

  list(add = add, finish = finish)
}


#' Rectangle complete XML records sequentially with bounded parser memory
#'
#' The specification must first be compiled against a representative sample.
#' This avoids loading the large target merely to resolve friendly names.  The
#' SAX parser then retains one complete record subtree at a time and emits
#' result batches no larger than `batch_rows`.  Output ordering and global node
#' identifiers are identical to the in-memory path.
#'
#' With `id_check = "memory"`, source identifiers are retained in a small set
#' so duplicates can be rejected exactly as in-memory rectangling does.  Choose
#' `"none"` only when strict memory boundedness is more important and uniqueness
#' is guaranteed externally.  Generated sequence identifiers need no set.
.xml_stream_rectangle_sequential <- function(
  file,
  spec,
  callback,
  document_id = NULL,
  whitespace = NULL,
  chunk_rows = 100000L,
  batch_rows = 100000L,
  id_check = c("memory", "none")
) {
  .require_xml_rectangle_package("tibble")
  file <- .validate_one_string(file, "file")
  .validate_stream_rectangle_spec(spec)

  if (!is.function(callback)) {
    stop("`callback` must be a function.", call. = FALSE)
  }

  id_check <- match.arg(id_check)
  chunk_rows <- .validate_chunk_rows(chunk_rows)
  batch_rows <- .validate_chunk_rows(batch_rows)

  if (is.null(whitespace)) {
    whitespace <- spec$whitespace
  }

  whitespace <- match.arg(
    whitespace,
    c("preserve", "drop_blank")
  )

  batcher <- .new_xml_rectangle_batcher(
    callback = callback,
    batch_rows = batch_rows
  )

  state <- new.env(parent = emptyenv())
  state$document_row <- NULL
  state$element_paths <- list()
  state$element_rows <- list()
  state$active <- FALSE
  state$record_depth <- NA_integer_
  state$prefix_rows <- NULL
  state$record_chunks <- list()
  state$record_count <- 0L
  state$max_record_nodes <- 0L
  state$seen_ids <- new.env(hash = TRUE, parent = emptyenv())

  flush_record <- function() {
    if (!state$active) {
      return(invisible(NULL))
    }

    localized <- .localize_stream_record(
      prefix_rows = state$prefix_rows,
      record_chunks = state$record_chunks
    )
    record_node_count <- sum(
      vapply(state$record_chunks, nrow, integer(1))
    )
    state$record_count <- state$record_count + 1L
    state$max_record_nodes <- max(
      state$max_record_nodes,
      record_node_count
    )

    rectangled <- .xml_rectangle_with_metadata(
      localized$nodes,
      spec,
      .validated = TRUE
    )
    record_id <- if (spec$identifier$mode == "generated") {
      as.character(state$record_count)
    } else {
      rectangled$identifiers[[1L]]
    }

    if (
      spec$identifier$mode == "source" &&
        id_check == "memory"
    ) {
      if (exists(record_id, envir = state$seen_ids, inherits = FALSE)) {
        stop(
          paste0(
            "The identifier source `",
            spec$identifier$source_label,
            "` is not unique in this XML document."
          ),
          call. = FALSE
        )
      }

      assign(record_id, TRUE, envir = state$seen_ids)
    }

    result <- .restore_stream_result_coordinates(
      result = rectangled$data,
      local_to_global = localized$local_to_global,
      record_index = state$record_count,
      record_id = record_id
    )
    batcher$add(result)

    state$active <- FALSE
    state$record_depth <- NA_integer_
    state$prefix_rows <- NULL
    state$record_chunks <- list()
    invisible(NULL)
  }

  consume_canonical_chunk <- function(chunk) {
    # A record can begin or end in the middle of any canonical parser chunk.
    # Keep contiguous slices rather than thousands of one-row data frames: the
    # memory bound remains one record, while ordinary records stay efficient.
    segment_start <- if (state$active) 1L else NA_integer_

    for (row_number in seq_len(nrow(chunk))) {
      row_depth <- chunk$depth[[row_number]]

      if (
        state$active &&
          row_depth <= state$record_depth
      ) {
        if (!is.na(segment_start) && segment_start < row_number) {
          state$record_chunks[[length(state$record_chunks) + 1L]] <- chunk[
            seq.int(segment_start, row_number - 1L),
            ,
            drop = FALSE
          ]
        }

        flush_record()
        segment_start <- NA_integer_
      }

      node_type <- chunk$node_type[[row_number]]

      if (node_type == "document") {
        state$document_row <- chunk[row_number, , drop = FALSE]
        next
      }

      if (node_type != "element") {
        next
      }

      depth <- chunk$depth[[row_number]]
      ancestor_count <- depth - 1L

      if (ancestor_count == 0L) {
        state$element_paths <- list()
        state$element_rows <- list()
      } else {
        state$element_paths <- state$element_paths[seq_len(ancestor_count)]
        state$element_rows <- state$element_rows[seq_len(ancestor_count)]
      }

      expanded_name <- .xml_expanded_name(
        chunk$local_name[[row_number]],
        chunk$namespace_uri[[row_number]]
      )
      current_path <- c(
        unlist(state$element_paths, use.names = FALSE),
        expanded_name
      )

      if (identical(current_path, spec$record_expanded_path)) {
        if (is.null(state$document_row)) {
          stop(
            "The streaming parser encountered a record before its document node.",
            call. = FALSE
          )
        }

        prefix_pieces <- c(
          list(state$document_row),
          if (ancestor_count > 0L) state$element_rows else list()
        )
        state$prefix_rows <- tibble::as_tibble(
          do.call(rbind, unname(prefix_pieces))
        )
        state$active <- TRUE
        state$record_depth <- depth
        state$record_chunks <- list()
        segment_start <- row_number
      }

      state$element_paths[[depth]] <- expanded_name
      state$element_rows[[depth]] <- chunk[
        row_number,
        ,
        drop = FALSE
      ]
    }

    if (!is.na(segment_start) && segment_start <= nrow(chunk)) {
      state$record_chunks[[length(state$record_chunks) + 1L]] <- chunk[
        seq.int(segment_start, nrow(chunk)),
        ,
        drop = FALSE
      ]
    }

    invisible(NULL)
  }

  node_stats <- xml_stream_nodes(
    file = file,
    callback = consume_canonical_chunk,
    document_id = document_id,
    whitespace = whitespace,
    chunk_rows = chunk_rows
  )

  # The final record has no following sibling to trigger the depth boundary.
  flush_record()

  if (state$record_count == 0L) {
    stop(
      paste0(
        "The XML document does not contain the specified row element `",
        spec$record_path,
        "`."
      ),
      call. = FALSE
    )
  }

  result_stats <- batcher$finish()

  invisible(
    tibble::tibble(
      document_id = node_stats$document_id,
      node_count = node_stats$node_count,
      parser_chunks = node_stats$chunk_count,
      record_count = as.integer(state$record_count),
      result_rows = as.integer(result_stats$result_rows),
      result_chunks = as.integer(result_stats$result_chunks),
      max_record_nodes = as.integer(state$max_record_nodes),
      id_check = if (spec$identifier$mode == "generated") {
        "not needed (generated IDs)"
      } else {
        id_check
      }
    )
  )
}


#' Rectangle complete XML records with bounded parser memory
#'
#' The SAX parser and record-boundary detection remain coordinator-side.
#' `parallel = FALSE` preserves the frozen sequential streaming path.
#' `parallel = TRUE` enables complete-record parallel execution with tuned
#' defaults. `parallel = "auto"` enables parallel streaming when the required
#' local parallel stack is available; streaming already represents the
#' large/bounded-memory execution path, so it does not perform a second full
#' pass merely to estimate record count.
xml_stream_rectangle <- function(
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
  task_records = NULL
) {
  mode <- .xml_normalize_parallel_mode(parallel)

  if (identical(mode, "sequential")) {
    return(
      .xml_stream_rectangle_sequential(
        file = file,
        spec = spec,
        callback = callback,
        document_id = document_id,
        whitespace = whitespace,
        chunk_rows = chunk_rows,
        batch_rows = batch_rows,
        id_check = id_check
      )
    )
  }

  plan <- .xml_plan_stream_execution(
    parallel = parallel,
    workers = workers,
    strategy = strategy
  )

  if (!isTRUE(plan$use_parallel)) {
    return(
      .xml_stream_rectangle_sequential(
        file = file,
        spec = spec,
        callback = callback,
        document_id = document_id,
        whitespace = whitespace,
        chunk_rows = chunk_rows,
        batch_rows = batch_rows,
        id_check = id_check
      )
    )
  }

  xml_stream_rectangle_parallel(
    file = file,
    spec = spec,
    callback = callback,
    document_id = document_id,
    whitespace = whitespace,
    chunk_rows = chunk_rows,
    batch_rows = batch_rows,
    id_check = id_check,
    workers = plan$workers,
    strategy = plan$strategy,
    chunk_records = chunk_records,
    task_records = task_records
  )
}

# -----------------------------------------------------------------------------
# Parallel task-vectorized rectangling (v12 P4: dual strategy + progress)
# -----------------------------------------------------------------------------
#
# The sequential rectangler is fast because it works on many records at once:
# one structural index, one long-value extraction pass, and vectorized record
# bookkeeping.  P1/P2 accidentally destroyed that property by sending several
# records to each future and then calling `.xml_rectangle_with_metadata()` once
# per record inside the worker.
#
# P4 keeps the *task* as the unit of vectorization, but now implements the two
# execution strategies with genuinely different scheduling/memory semantics:
#
#   parallel_chunks
#     Throughput-oriented. The coordinator buffers at most one owned chunk per
#     worker. Each future receives one independent record chunk and vectorizes
#     all compatible records in that chunk. Up to `workers * chunk_records`
#     records can therefore be in the dispatch window. No mori sharing is used.
#
#   shared_chunk
#     RAM-oriented. The coordinator buffers only one `chunk_records` outer chunk,
#     builds coarse compatible task documents, packs that one outer chunk once,
#     and exposes it through `mori::share()`. Several workers then operate on
#     task ranges inside the same shared chunk.
#
# This mirrors the two strategies used in summarise_big: independent owned
# chunks for throughput versus several workers acting on one shared chunk for
# lower peak input memory.
#
# Parsing, duplicate-ID checking, ordered emission, CSV/Parquet writing and user
# callbacks remain coordinator-side.  No XML byte ranges or external pointers
# cross worker boundaries.

.xml_validate_parallel_integer <- function(value, argument) {
  valid <- is.numeric(value) &&
    length(value) == 1L &&
    !is.na(value) &&
    is.finite(value) &&
    value >= 1 &&
    value <= .Machine$integer.max &&
    value == floor(value)

  if (!valid) {
    stop(
      sprintf("`%s` must be one positive whole number.", argument),
      call. = FALSE
    )
  }

  as.integer(value)
}


.xml_normalize_parallel_mode <- function(parallel) {
  if (is.logical(parallel) && length(parallel) == 1L && !is.na(parallel)) {
    return(if (isTRUE(parallel)) "parallel" else "sequential")
  }

  if (is.character(parallel) && length(parallel) == 1L && !is.na(parallel)) {
    value <- tolower(trimws(parallel))
    if (identical(value, "auto")) return("auto")
  }

  stop(
    '`parallel` must be FALSE, TRUE, or "auto".',
    call. = FALSE
  )
}


.xml_normalize_parallel_strategy <- function(strategy, context) {
  if (!is.character(strategy) || length(strategy) != 1L || is.na(strategy)) {
    stop(
      '`strategy` must be "auto", "parallel_chunks", or "shared_chunk".',
      call. = FALSE
    )
  }

  strategy <- match.arg(
    strategy,
    c("auto", "parallel_chunks", "shared_chunk")
  )

  if (!identical(strategy, "auto")) return(strategy)

  # In-memory execution already owns the complete canonical table, so the
  # throughput-oriented owned-chunk strategy is the balanced default. Streaming
  # exists specifically to bound memory, therefore automatic streaming uses the
  # mori-backed shared-input strategy.
  if (identical(context, "memory")) {
    "parallel_chunks"
  } else if (identical(context, "stream")) {
    "shared_chunk"
  } else {
    stop("Unknown automatic parallel execution context.", call. = FALSE)
  }
}


.xml_parallel_stack_available <- function(strategy) {
  packages <- c("purrr", "future", "future.mirai", "futurize", "furrr")
  if (identical(strategy, "shared_chunk")) packages <- c(packages, "mori")

  all(vapply(packages, requireNamespace, logical(1), quietly = TRUE))
}


.xml_resolve_parallel_workers <- function(workers, balanced = TRUE) {
  if (!is.null(workers)) {
    return(.xml_validate_parallel_integer(workers, "workers"))
  }

  .require_xml_rectangle_package("future")

  available <- as.integer(future::availableCores())
  if (is.na(available) || available < 1L) available <- 1L

  # Preserve one core for the coordinator/desktop where possible. Cross-machine
  # P5 benchmarks showed that four workers capture most of the useful speedup
  # while avoiding the sharp efficiency drop seen when every logical core is
  # consumed. Explicit `workers` always overrides this balanced policy.
  usable <- if (available <= 2L) available else available - 1L
  if (isTRUE(balanced)) usable <- min(4L, usable)

  max(1L, as.integer(usable))
}


.xml_parallel_auto_min_record_nodes_per_worker <- function() {
  # Shared execution-policy constant. Keeping this in one helper ensures that
  # the O(1) pre-check and the exact span-based decision can never drift apart.
  25000
}


.xml_parallel_auto_worth_it <- function(spans, workers) {
  workers <- .xml_validate_parallel_integer(workers, "workers")

  if (workers < 2L || nrow(spans) < workers) return(FALSE)

  record_nodes <- as.double(spans$end - spans$start + 1L)
  records_per_worker <- nrow(spans) / workers
  record_nodes_per_worker <- sum(record_nodes) / workers
  median_record_nodes <- stats::median(record_nodes)

  # These are execution-grain guards, not XML/file-name special cases. They are
  # deliberately expressed in independent record count and canonical node work
  # per worker. P4/P5 cross-machine scaling showed process overhead dominating
  # below this region and useful speedup above it. Very large individual records
  # can satisfy the second branch even when record count is modest.
  enough_node_work <- record_nodes_per_worker >=
    .xml_parallel_auto_min_record_nodes_per_worker()
  enough_record_grain <- records_per_worker >= 128
  individually_heavy_records <- median_record_nodes >= 1000

  isTRUE(
    enough_node_work &&
      (enough_record_grain || individually_heavy_records)
  )
}


.xml_plan_in_memory_execution <- function(
  nodes,
  spec,
  parallel,
  workers,
  strategy
) {
  mode <- .xml_normalize_parallel_mode(parallel)
  strategy <- .xml_normalize_parallel_strategy(strategy, context = "memory")

  if (identical(mode, "sequential")) {
    return(list(use_parallel = FALSE, workers = 1L, strategy = strategy, spans = NULL))
  }

  if (identical(mode, "auto") && !.xml_parallel_stack_available(strategy)) {
    return(list(use_parallel = FALSE, workers = 1L, strategy = strategy, spans = NULL))
  }

  workers <- .xml_resolve_parallel_workers(workers, balanced = TRUE)
  if (workers < 2L) {
    return(list(use_parallel = FALSE, workers = 1L, strategy = strategy, spans = NULL))
  }

  # Fast, exact rejection for automatic mode. Record nodes are a subset of all
  # canonical nodes, so if the whole canonical table is below the existing
  # per-worker node-work floor, the later span-based test cannot possibly pass.
  # This avoids an unnecessary structure-index/span pass for small documents;
  # it does not introduce a new threshold or alter the decision policy.
  if (identical(mode, "auto")) {
    minimum_possible_nodes <-
      .xml_parallel_auto_min_record_nodes_per_worker() * workers

    if (nrow(nodes) < minimum_possible_nodes) {
      return(list(
        use_parallel = FALSE,
        workers = 1L,
        strategy = strategy,
        spans = NULL
      ))
    }
  }

  if (!.xml_parallel_stack_available(strategy)) {
    .xml_parallel_require_packages(strategy)
  }

  spans <- .xml_parallel_record_spans(nodes, spec)

  use_parallel <- if (identical(mode, "auto")) {
    .xml_parallel_auto_worth_it(spans, workers)
  } else {
    TRUE
  }

  list(
    use_parallel = isTRUE(use_parallel),
    workers = as.integer(workers),
    strategy = strategy,
    spans = spans
  )
}


.xml_plan_stream_execution <- function(parallel, workers, strategy) {
  mode <- .xml_normalize_parallel_mode(parallel)
  requested_strategy <- strategy
  strategy <- .xml_normalize_parallel_strategy(strategy, context = "stream")

  # Automatic streaming prefers shared input, but "auto" should not require
  # mori when the ordinary parallel stack is otherwise usable. Fall back to
  # owned chunks before falling all the way back to sequential execution.
  if (
    identical(requested_strategy, "auto") &&
      !.xml_parallel_stack_available(strategy) &&
      .xml_parallel_stack_available("parallel_chunks")
  ) {
    strategy <- "parallel_chunks"
  }

  if (identical(mode, "sequential")) {
    return(list(use_parallel = FALSE, workers = 1L, strategy = strategy))
  }

  if (identical(mode, "auto") && !.xml_parallel_stack_available(strategy)) {
    return(list(use_parallel = FALSE, workers = 1L, strategy = strategy))
  }

  workers <- .xml_resolve_parallel_workers(workers, balanced = TRUE)
  if (workers < 2L) {
    return(list(use_parallel = FALSE, workers = 1L, strategy = strategy))
  }

  if (!.xml_parallel_stack_available(strategy)) {
    .xml_parallel_require_packages(strategy)
  }

  # Streaming is already the bounded large-file path. Do not add a complete
  # preliminary pass merely to estimate record count for an "auto" decision.
  list(use_parallel = TRUE, workers = as.integer(workers), strategy = strategy)
}


.xml_parallel_stream_chunk_records <- function(
  strategy,
  workers,
  chunk_records = NULL
) {
  if (!is.null(chunk_records)) {
    return(.xml_validate_parallel_integer(chunk_records, "chunk_records"))
  }

  workers <- .xml_validate_parallel_integer(workers, "workers")

  if (identical(strategy, "parallel_chunks")) {
    # Throughput mode can retain several independently owned chunks. A moderate
    # per-worker vectorization unit avoids the pathological tiny-chunk behavior
    # seen in P1/P2 without letting the dispatch window grow without bound.
    return(512L)
  }

  if (identical(strategy, "shared_chunk")) {
    # One shared outer chunk: scale with the balanced worker count until four
    # workers, then cap the record bound. Actual record size remains visible via
    # max_record_nodes in returned streaming statistics.
    return(as.integer(min(1024L, max(256L, workers * 256L))))
  }

  stop("Unknown parallel strategy.", call. = FALSE)
}


.xml_parallel_in_memory_chunk_records <- function(
  strategy,
  workers,
  records,
  chunk_records = NULL
) {
  if (!is.null(chunk_records)) {
    return(.xml_validate_parallel_integer(chunk_records, "chunk_records"))
  }

  workers <- .xml_validate_parallel_integer(workers, "workers")
  records <- as.integer(records)
  if (length(records) != 1L || is.na(records) || records < 0L) {
    stop("`records` must be one non-negative integer.", call. = FALSE)
  }

  observed_records <- max(1L, records)

  if (identical(strategy, "parallel_chunks")) {
    return(max(1L, as.integer(ceiling(observed_records / workers))))
  }

  if (identical(strategy, "shared_chunk")) {
    return(observed_records)
  }

  stop("Unknown parallel strategy.", call. = FALSE)
}


.xml_parallel_chunk_settings <- function(
  workers,
  chunk_records,
  task_records,
  strategy = "shared_chunk"
) {
  chunk_records <- .xml_validate_parallel_integer(
    chunk_records,
    "chunk_records"
  )

  # `parallel_chunks` has one vectorized owned chunk per future and therefore no
  # useful second task subdivision. `shared_chunk` benefits from finer scheduling
  # because the common input is shared: P5 tuning showed a broad optimum around
  # 4-8 logical tasks/worker, so the conservative default is four.
  if (is.null(task_records)) {
    if (identical(strategy, "shared_chunk")) {
      target_tasks <- max(1, as.double(workers) * 4)
      task_records <- max(
        1L,
        as.integer(ceiling(as.double(chunk_records) / target_tasks))
      )
    } else {
      task_records <- chunk_records
    }
  } else {
    task_records <- .xml_validate_parallel_integer(
      task_records,
      "task_records"
    )
  }

  if (chunk_records < task_records) {
    stop(
      "`chunk_records` must be greater than or equal to `task_records`.",
      call. = FALSE
    )
  }

  list(
    chunk_records = chunk_records,
    task_records = task_records
  )
}


.xml_parallel_require_packages <- function(strategy) {
  for (package in c("purrr", "furrr", "futurize", "future", "future.mirai")) {
    .require_xml_rectangle_package(package)
  }

  if (identical(strategy, "shared_chunk")) {
    .require_xml_rectangle_package("mori")
  }

  invisible(TRUE)
}


.xml_parallel_validate_progress <- function(progress) {
  if (!is.logical(progress) || length(progress) != 1L || is.na(progress)) {
    stop("`progress` must be TRUE or FALSE.", call. = FALSE)
  }

  isTRUE(progress)
}


.xml_parallel_make_progressor <- function(progress, steps) {
  progress <- .xml_parallel_validate_progress(progress)
  if (!progress) return(NULL)

  .require_xml_rectangle_package("progressr")

  # The progressor is created in this helper but must live for the complete
  # caller frame (e.g. xml_rectangle_parallel()).  Without an explicit envir,
  # progressr binds on_exit finalization to this short-lived helper frame and
  # marks the progressor finished as soon as this function returns.
  progressr::progressor(
    steps = as.integer(steps),
    envir = parent.frame()
  )
}


.xml_parallel_futurized_map <- function(tasks, worker) {
  if (length(tasks) == 0L) return(list())

  purrr::map(tasks, worker) |>
    futurize::futurize(scheduling = Inf)
}


.xml_parallel_prefix_ids <- function(prefix_rows) {
  as.integer(prefix_rows$node_id)
}


.xml_parallel_same_prefix <- function(left, right) {
  identical(left$prefix_node_ids, right$prefix_node_ids)
}


.xml_parallel_group_records <- function(records, task_records) {
  if (length(records) == 0L) return(list())

  groups <- list()
  current <- list(records[[1L]])

  if (length(records) > 1L) {
    for (i in 2:length(records)) {
      candidate <- records[[i]]
      same_prefix <- .xml_parallel_same_prefix(current[[1L]], candidate)

      if (length(current) >= task_records || !same_prefix) {
        groups[[length(groups) + 1L]] <- current
        current <- list(candidate)
      } else {
        current[[length(current) + 1L]] <- candidate
      }
    }
  }

  groups[[length(groups) + 1L]] <- current
  groups
}


.xml_parallel_memory_record_payload <- function(
  nodes,
  start,
  end,
  record_index
) {
  ancestors <- integer()
  parent <- nodes$parent_id[[start]]

  while (!is.na(parent)) {
    ancestors <- c(parent, ancestors)
    parent <- nodes$parent_id[[parent]]
  }

  prefix_rows <- nodes[ancestors, , drop = FALSE]
  record_rows <- nodes[seq.int(start, end), , drop = FALSE]

  list(
    prefix_rows = prefix_rows,
    prefix_node_ids = .xml_parallel_prefix_ids(prefix_rows),
    record_rows = record_rows,
    record_index = as.integer(record_index),
    record_nodes = as.integer(end - start + 1L)
  )
}


.xml_parallel_stream_record_payload <- function(
  prefix_rows,
  record_chunks,
  record_index
) {
  record_rows <- if (length(record_chunks) == 1L) {
    record_chunks[[1L]]
  } else {
    tibble::as_tibble(do.call(rbind, unname(record_chunks)))
  }
  rownames(record_rows) <- NULL

  list(
    prefix_rows = prefix_rows,
    prefix_node_ids = .xml_parallel_prefix_ids(prefix_rows),
    record_rows = record_rows,
    record_index = as.integer(record_index),
    record_nodes = as.integer(nrow(record_rows))
  )
}


.xml_parallel_localize_record_task <- function(records) {
  if (length(records) == 0L) {
    stop("An internal parallel XML task contains no records.", call. = FALSE)
  }

  prefix <- records[[1L]]$prefix_node_ids
  compatible <- vapply(
    records,
    function(record) identical(record$prefix_node_ids, prefix),
    logical(1)
  )

  if (!all(compatible)) {
    stop(
      "An internal parallel XML task crosses incompatible ancestor chains.",
      call. = FALSE
    )
  }

  localized <- .localize_stream_record(
    prefix_rows = records[[1L]]$prefix_rows,
    record_chunks = lapply(records, function(record) record$record_rows)
  )

  list(
    nodes = localized$nodes,
    local_to_global = as.integer(localized$local_to_global),
    record_indices = as.integer(vapply(
      records,
      function(record) record$record_index,
      integer(1)
    )),
    record_nodes = as.integer(vapply(
      records,
      function(record) record$record_nodes,
      integer(1)
    ))
  )
}


.xml_parallel_restore_task_coordinates <- function(
  result,
  local_to_global,
  global_record_indices,
  record_ids
) {
  id_columns <- intersect(
    c(
      "record_node_id",
      "entity_node_id",
      "parent_entity_node_id",
      "source_node_id"
    ),
    names(result)
  )

  for (column in id_columns) {
    local_ids <- result[[column]]
    translated <- rep.int(NA_integer_, length(local_ids))
    present <- !is.na(local_ids)

    if (any(present)) {
      translated[present] <- local_to_global[local_ids[present]]
    }

    result[[column]] <- translated
  }

  if (nrow(result) > 0L) {
    local_record_index <- as.integer(result$record_index)

    if (
      anyNA(local_record_index) ||
        any(local_record_index < 1L) ||
        any(local_record_index > length(global_record_indices))
    ) {
      stop(
        "Parallel XML task returned an invalid local record index.",
        call. = FALSE
      )
    }

    result$record_index <- global_record_indices[local_record_index]
    result$record_id <- record_ids[local_record_index]
  }

  result
}


.xml_parallel_process_localized_task <- function(task, spec) {
  rectangled <- .xml_rectangle_with_metadata(
    task$nodes,
    spec,
    .validated = TRUE,
    # Global source-ID uniqueness is intentionally coordinator-side so
    # `id_check = "none"` retains the frozen streaming semantics.
    .check_identifier_uniqueness = FALSE
  )

  number_of_records <- length(task$record_indices)

  if (length(rectangled$identifiers) != number_of_records) {
    stop(
      "Parallel XML task did not recover every assigned record identifier.",
      call. = FALSE
    )
  }

  record_ids <- if (identical(spec$identifier$mode, "generated")) {
    as.character(task$record_indices)
  } else {
    as.character(rectangled$identifiers)
  }

  data <- .xml_parallel_restore_task_coordinates(
    result = rectangled$data,
    local_to_global = task$local_to_global,
    global_record_indices = task$record_indices,
    record_ids = record_ids
  )

  list(
    data = data,
    record_ids = record_ids,
    record_indices = as.integer(task$record_indices),
    record_nodes = as.integer(task$record_nodes)
  )
}


.xml_parallel_pack_shared_tasks <- function(tasks) {
  counts <- vapply(tasks, function(task) nrow(task$nodes), integer(1))
  starts <- cumsum(c(1L, counts[-length(counts)]))
  ends <- starts + counts - 1L

  pieces <- lapply(
    tasks,
    function(task) {
      piece <- as.data.frame(task$nodes, stringsAsFactors = FALSE)
      piece$.xml_global_node_id <- as.integer(task$local_to_global)
      piece
    }
  )

  data <- if (length(pieces) == 1L) {
    pieces[[1L]]
  } else {
    do.call(rbind, unname(pieces))
  }
  rownames(data) <- NULL

  list(
    data = data,
    starts = as.integer(starts),
    ends = as.integer(ends),
    record_indices = lapply(tasks, function(task) task$record_indices),
    record_nodes = lapply(tasks, function(task) task$record_nodes)
  )
}


.xml_parallel_split_owned_chunks <- function(records, chunk_records) {
  if (length(records) == 0L) return(list())

  starts <- seq.int(1L, length(records), by = chunk_records)
  lapply(
    starts,
    function(start) {
      finish <- min(length(records), start + chunk_records - 1L)
      records[seq.int(start, finish)]
    }
  )
}


.xml_parallel_process_owned_chunk <- function(records, spec) {
  if (length(records) == 0L) return(list())

  # The owned chunk itself is the vectorization unit. Split only when the real
  # ancestor-node chain changes; do not introduce a second scheduling layer.
  grouped_records <- .xml_parallel_group_records(
    records,
    task_records = length(records)
  )

  lapply(
    grouped_records,
    function(group) {
      task <- .xml_parallel_localize_record_task(group)
      .xml_parallel_process_localized_task(task, spec)
    }
  )
}


.xml_parallel_run_parallel_window <- function(
  records,
  spec,
  chunk_records,
  progressor = NULL
) {
  if (length(records) == 0L) {
    return(list(results = list(), chunks = 0L, tasks = 0L))
  }

  chunks <- .xml_parallel_split_owned_chunks(records, chunk_records)
  rm(records)

  mapped_chunks <- .xml_parallel_futurized_map(
    chunks,
    function(chunk) {
      results <- .xml_parallel_process_owned_chunk(chunk, spec)

      if (!is.null(progressor)) {
        completed <- sum(vapply(
          results,
          function(result) length(result$record_indices),
          integer(1)
        ))
        progressor(
          amount = completed,
          message = sprintf("parallel chunk: %d records", completed)
        )
      }

      results
    }
  )

  results <- if (length(mapped_chunks) == 0L) {
    list()
  } else {
    do.call(c, unname(mapped_chunks))
  }

  list(
    results = results,
    chunks = as.integer(length(chunks)),
    tasks = as.integer(length(chunks))
  )
}


.xml_parallel_run_shared_chunk <- function(
  records,
  spec,
  task_records,
  progressor = NULL
) {
  if (length(records) == 0L) {
    return(list(results = list(), chunks = 0L, tasks = 0L))
  }

  grouped_records <- .xml_parallel_group_records(records, task_records)
  tasks <- lapply(grouped_records, .xml_parallel_localize_record_task)
  rm(grouped_records, records)

  .xml_parallel_require_packages("shared_chunk")
  packed <- .xml_parallel_pack_shared_tasks(tasks)
  rm(tasks)

  shared_data <- mori::share(packed$data)
  starts <- packed$starts
  ends <- packed$ends
  record_indices <- packed$record_indices
  record_nodes <- packed$record_nodes
  rm(packed)

  task_slots <- as.list(seq_along(starts))

  mapped <- .xml_parallel_futurized_map(
    task_slots,
    function(slot) {
      rows <- seq.int(starts[[slot]], ends[[slot]])
      nodes <- shared_data[rows, .xml_node_columns, drop = FALSE]
      rownames(nodes) <- NULL

      task <- list(
        nodes = nodes,
        local_to_global = as.integer(
          shared_data$.xml_global_node_id[rows]
        ),
        record_indices = as.integer(record_indices[[slot]]),
        record_nodes = as.integer(record_nodes[[slot]])
      )

      result <- .xml_parallel_process_localized_task(task, spec)

      if (!is.null(progressor)) {
        completed <- length(result$record_indices)
        progressor(
          amount = completed,
          message = sprintf("shared task: %d records", completed)
        )
      }

      result
    }
  )

  list(
    results = mapped,
    chunks = 1L,
    tasks = as.integer(length(mapped))
  )
}


.new_xml_parallel_record_scheduler <- function(
  spec,
  emit,
  workers,
  strategy,
  chunk_records,
  task_records,
  id_check,
  progressor = NULL
) {
  if (!is.function(emit)) {
    stop("`emit` must be a function.", call. = FALSE)
  }

  workers <- .xml_validate_parallel_integer(workers, "workers")

  # The two strategies intentionally have different memory/concurrency bounds:
  #
  # * shared_chunk keeps one outer chunk total and shares it once with mori;
  # * parallel_chunks retains up to one owned chunk per worker and maps those
  #   independent chunks concurrently.  This mirrors the two execution modes in
  #   summarise_big instead of merely changing how one outer chunk is serialized.
  buffer_limit <- if (identical(strategy, "parallel_chunks")) {
    min(
      as.double(.Machine$integer.max),
      as.double(workers) * as.double(chunk_records)
    )
  } else {
    as.double(chunk_records)
  }
  buffer_limit <- as.integer(buffer_limit)

  state <- new.env(parent = emptyenv())
  state$records <- list()
  state$parallel_chunks <- 0L
  state$parallel_tasks <- 0L
  state$processed_records <- 0L
  state$max_record_nodes <- 0L
  state$seen_ids <- new.env(hash = TRUE, parent = emptyenv())

  check_ids <- function(task_result) {
    if (
      identical(spec$identifier$mode, "source") &&
        identical(id_check, "memory")
    ) {
      for (record_id in task_result$record_ids) {
        if (exists(record_id, envir = state$seen_ids, inherits = FALSE)) {
          stop(
            paste0(
              "The identifier source `",
              spec$identifier$source_label,
              "` is not unique in this XML document."
            ),
            call. = FALSE
          )
        }

        assign(record_id, TRUE, envir = state$seen_ids)
      }
    }

    invisible(NULL)
  }

  process <- function() {
    if (length(state$records) == 0L) {
      return(invisible(NULL))
    }

    records <- state$records
    state$records <- list()

    expected <- as.integer(vapply(
      records,
      function(record) record$record_index,
      integer(1)
    ))

    dispatched <- if (identical(strategy, "parallel_chunks")) {
      .xml_parallel_run_parallel_window(
        records = records,
        spec = spec,
        chunk_records = chunk_records,
        progressor = progressor
      )
    } else {
      .xml_parallel_run_shared_chunk(
        records = records,
        spec = spec,
        task_records = task_records,
        progressor = progressor
      )
    }

    mapped <- dispatched$results

    actual <- as.integer(unlist(
      lapply(mapped, function(result) result$record_indices),
      use.names = FALSE
    ))

    if (!identical(actual, expected)) {
      stop(
        "Parallel record execution returned results out of document order.",
        call. = FALSE
      )
    }

    for (result in mapped) {
      check_ids(result)
      emit(result$data)
    }

    state$parallel_chunks <- state$parallel_chunks + dispatched$chunks
    state$parallel_tasks <- state$parallel_tasks + dispatched$tasks
    state$processed_records <- state$processed_records + length(actual)
    invisible(NULL)
  }

  add <- function(record) {
    state$records[[length(state$records) + 1L]] <- record
    state$max_record_nodes <- max(
      state$max_record_nodes,
      as.integer(record$record_nodes)
    )

    if (length(state$records) >= buffer_limit) {
      process()
    }

    invisible(NULL)
  }

  finish <- function() {
    process()

    list(
      processed_records = as.integer(state$processed_records),
      parallel_chunks = as.integer(state$parallel_chunks),
      parallel_tasks = as.integer(state$parallel_tasks),
      max_record_nodes = as.integer(state$max_record_nodes),
      buffered_records = as.integer(buffer_limit)
    )
  }

  list(add = add, finish = finish)
}


.xml_parallel_record_spans <- function(nodes, spec) {
  index <- .build_xml_structure_index(nodes, validate = FALSE)
  records <- index$elements[
    index$elements$path_key == spec$record_path_key,
    ,
    drop = FALSE
  ]

  if (nrow(records) == 0L) {
    stop(
      paste0(
        "The XML document does not contain the specified row element `",
        spec$record_path,
        "`."
      ),
      call. = FALSE
    )
  }

  starts <- as.integer(records$node_id)
  ends <- integer(length(starts))

  for (i in seq_along(starts)) {
    start <- starts[[i]]
    limit <- if (i < length(starts)) {
      starts[[i + 1L]] - 1L
    } else {
      nrow(nodes)
    }

    if (start >= limit) {
      ends[[i]] <- start
      next
    }

    candidates <- seq.int(start + 1L, limit)
    boundary <- which(nodes$depth[candidates] <= nodes$depth[[start]])

    ends[[i]] <- if (length(boundary) == 0L) {
      limit
    } else {
      candidates[[boundary[[1L]]]] - 1L
    }
  }

  data.frame(
    record_index = as.integer(seq_along(starts)),
    start = starts,
    end = as.integer(ends),
    stringsAsFactors = FALSE
  )
}


# Internal parallel implementation. `spans` is accepted only so the unified
# `parallel = "auto"` dispatcher can reuse the structural work it already did
# when deciding whether process-level parallelism is worthwhile.
.xml_rectangle_parallel_impl <- function(
  nodes,
  spec,
  workers,
  strategy,
  chunk_records = NULL,
  task_records = NULL,
  progress = FALSE,
  spans = NULL,
  .validated = FALSE,
  .stream_spec_validated = FALSE
) {
  if (!isTRUE(.validated)) {
    validate_xml_nodes(nodes)
  }
  .require_xml_rectangle_package("tibble")

  if (inherits(spec, "xml_profile")) {
    spec <- compile_xml_profile(spec, sample = nodes)
  }

  if (!inherits(spec, "xml_rect_spec")) {
    stop(
      paste0(
        "`spec` must be an xml_profile or the result of rectangle_spec() ",
        "or make_rectangle()."
      ),
      call. = FALSE
    )
  }

  if (!isTRUE(.stream_spec_validated)) {
    .validate_stream_rectangle_spec(spec)
  }
  workers <- .xml_resolve_parallel_workers(workers, balanced = TRUE)
  strategy <- match.arg(strategy, c("shared_chunk", "parallel_chunks"))
  progress <- .xml_parallel_validate_progress(progress)

  if (workers == 1L) {
    return(.xml_rectangle_sequential(nodes, spec, .validated = TRUE))
  }

  .xml_parallel_require_packages(strategy)

  if (is.null(spans)) {
    spans <- .xml_parallel_record_spans(nodes, spec)
  }

  # In-memory execution already owns the complete canonical node table, so the
  # default can be selected from the observed number of records rather than an
  # arbitrary small fixed bound. `parallel_chunks` creates roughly one owned
  # vectorized chunk per worker; `shared_chunk` shares one whole outer chunk.
  chunk_records <- .xml_parallel_in_memory_chunk_records(
    strategy = strategy,
    workers = workers,
    records = nrow(spans),
    chunk_records = chunk_records
  )

  settings <- .xml_parallel_chunk_settings(
    workers = workers,
    strategy = strategy,
    chunk_records = chunk_records,
    task_records = task_records
  )

  previous_plan <- future::plan()
  on.exit(future::plan(previous_plan), add = TRUE)
  future::plan(
    future.mirai::mirai_multisession,
    workers = workers
  )

  parts <- list()
  progressor <- .xml_parallel_make_progressor(progress, nrow(spans))

  scheduler <- .new_xml_parallel_record_scheduler(
    spec = spec,
    emit = function(result) {
      if (nrow(result) > 0L) {
        parts[[length(parts) + 1L]] <<- result
      }
      invisible(NULL)
    },
    workers = workers,
    strategy = strategy,
    chunk_records = settings$chunk_records,
    task_records = settings$task_records,
    id_check = "memory",
    progressor = progressor
  )

  for (i in seq_len(nrow(spans))) {
    scheduler$add(
      .xml_parallel_memory_record_payload(
        nodes = nodes,
        start = spans$start[[i]],
        end = spans$end[[i]],
        record_index = spans$record_index[[i]]
      )
    )
  }

  stats <- scheduler$finish()

  if (!identical(stats$processed_records, as.integer(nrow(spans)))) {
    stop(
      "Parallel record execution did not process every XML record.",
      call. = FALSE
    )
  }

  result <- if (length(parts) == 0L) {
    .xml_rectangle_result_schema(spec)
  } else {
    tibble::as_tibble(do.call(rbind, unname(parts)))
  }
  rownames(result) <- NULL
  result
}


#' Apply a compiled rectangle specification in parallel
#'
#' This lower-level compatibility entry point remains useful for tests and
#' explicit execution. Daily use should normally call `xml_rectangle()` with
#' `parallel = TRUE` or `parallel = "auto"`.
xml_rectangle_parallel <- function(
  nodes,
  spec,
  workers = NULL,
  strategy = c("shared_chunk", "parallel_chunks"),
  chunk_records = NULL,
  task_records = NULL,
  progress = FALSE
) {
  .xml_rectangle_parallel_impl(
    nodes = nodes,
    spec = spec,
    workers = workers,
    strategy = match.arg(strategy),
    chunk_records = chunk_records,
    task_records = task_records,
    progress = progress
  )
}


#' Read one XML file and apply a compiled/profile rectangle in parallel
rectangle_xml_parallel <- function(
  file,
  spec,
  whitespace = NULL,
  workers = NULL,
  strategy = c("shared_chunk", "parallel_chunks"),
  chunk_records = NULL,
  task_records = NULL,
  progress = FALSE
) {
  file <- .validate_one_string(file, "file")

  if (is.null(whitespace)) {
    whitespace <- if (inherits(spec, "xml_rect_spec")) {
      spec$whitespace
    } else {
      "drop_blank"
    }
  }
  whitespace <- match.arg(whitespace, c("drop_blank", "preserve"))

  nodes <- xml_to_nodes_memory(file, whitespace = whitespace)

  if (inherits(spec, "xml_profile")) {
    spec <- compile_xml_profile(
      spec,
      sample = nodes,
      whitespace = whitespace
    )
  }

  xml_rectangle_parallel(
    nodes = nodes,
    spec = spec,
    workers = workers,
    strategy = strategy,
    chunk_records = chunk_records,
    task_records = task_records,
    progress = progress
  )
}


#' Rectangle complete XML records in parallel with bounded parser memory
#'
#' SAX parsing remains sequential.  Complete records are retained only up to the
#' bounded outer `chunk_records` limit.  Within that chunk, compatible consecutive
#' records are combined into task-local canonical documents and rectangled once
#' per future task.
xml_stream_rectangle_parallel <- function(
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
  task_records = NULL
) {
  .require_xml_rectangle_package("tibble")
  file <- .validate_one_string(file, "file")
  .validate_stream_rectangle_spec(spec)

  if (!is.function(callback)) {
    stop("`callback` must be a function.", call. = FALSE)
  }

  id_check <- match.arg(id_check)
  chunk_rows <- .validate_chunk_rows(chunk_rows)
  batch_rows <- .validate_chunk_rows(batch_rows)
  workers <- .xml_resolve_parallel_workers(workers, balanced = TRUE)
  strategy <- match.arg(strategy)

  if (workers == 1L) {
    return(
      .xml_stream_rectangle_sequential(
        file = file,
        spec = spec,
        callback = callback,
        document_id = document_id,
        whitespace = whitespace,
        chunk_rows = chunk_rows,
        batch_rows = batch_rows,
        id_check = id_check
      )
    )
  }

  .xml_parallel_require_packages(strategy)
  chunk_records <- .xml_parallel_stream_chunk_records(
    strategy = strategy,
    workers = workers,
    chunk_records = chunk_records
  )
  settings <- .xml_parallel_chunk_settings(
    workers = workers,
    strategy = strategy,
    chunk_records = chunk_records,
    task_records = task_records
  )

  previous_plan <- future::plan()
  on.exit(future::plan(previous_plan), add = TRUE)
  future::plan(
    future.mirai::mirai_multisession,
    workers = workers
  )

  if (is.null(whitespace)) {
    whitespace <- spec$whitespace
  }
  whitespace <- match.arg(whitespace, c("preserve", "drop_blank"))

  batcher <- .new_xml_rectangle_batcher(
    callback = callback,
    batch_rows = batch_rows
  )

  scheduler <- .new_xml_parallel_record_scheduler(
    spec = spec,
    emit = function(result) batcher$add(result),
    workers = workers,
    strategy = strategy,
    chunk_records = settings$chunk_records,
    task_records = settings$task_records,
    id_check = id_check
  )

  state <- new.env(parent = emptyenv())
  state$document_row <- NULL
  state$element_paths <- list()
  state$element_rows <- list()
  state$active <- FALSE
  state$record_depth <- NA_integer_
  state$prefix_rows <- NULL
  state$record_chunks <- list()
  state$record_count <- 0L

  flush_record <- function() {
    if (!state$active) {
      return(invisible(NULL))
    }

    state$record_count <- state$record_count + 1L

    scheduler$add(
      .xml_parallel_stream_record_payload(
        prefix_rows = state$prefix_rows,
        record_chunks = state$record_chunks,
        record_index = state$record_count
      )
    )

    state$active <- FALSE
    state$record_depth <- NA_integer_
    state$prefix_rows <- NULL
    state$record_chunks <- list()
    invisible(NULL)
  }

  consume_canonical_chunk <- function(chunk) {
    segment_start <- if (state$active) 1L else NA_integer_

    for (row_number in seq_len(nrow(chunk))) {
      row_depth <- chunk$depth[[row_number]]

      if (state$active && row_depth <= state$record_depth) {
        if (!is.na(segment_start) && segment_start < row_number) {
          state$record_chunks[[length(state$record_chunks) + 1L]] <- chunk[
            seq.int(segment_start, row_number - 1L),
            ,
            drop = FALSE
          ]
        }

        flush_record()
        segment_start <- NA_integer_
      }

      node_type <- chunk$node_type[[row_number]]

      if (node_type == "document") {
        state$document_row <- chunk[row_number, , drop = FALSE]
        next
      }

      if (node_type != "element") next

      depth <- chunk$depth[[row_number]]
      ancestor_count <- depth - 1L

      if (ancestor_count == 0L) {
        state$element_paths <- list()
        state$element_rows <- list()
      } else {
        state$element_paths <- state$element_paths[seq_len(ancestor_count)]
        state$element_rows <- state$element_rows[seq_len(ancestor_count)]
      }

      expanded_name <- .xml_expanded_name(
        chunk$local_name[[row_number]],
        chunk$namespace_uri[[row_number]]
      )
      current_path <- c(
        unlist(state$element_paths, use.names = FALSE),
        expanded_name
      )

      if (identical(current_path, spec$record_expanded_path)) {
        if (is.null(state$document_row)) {
          stop(
            "The streaming parser encountered a record before its document node.",
            call. = FALSE
          )
        }

        prefix_pieces <- c(
          list(state$document_row),
          if (ancestor_count > 0L) state$element_rows else list()
        )
        state$prefix_rows <- tibble::as_tibble(
          do.call(rbind, unname(prefix_pieces))
        )
        state$active <- TRUE
        state$record_depth <- depth
        state$record_chunks <- list()
        segment_start <- row_number
      }

      state$element_paths[[depth]] <- expanded_name
      state$element_rows[[depth]] <- chunk[
        row_number,
        ,
        drop = FALSE
      ]
    }

    if (!is.na(segment_start) && segment_start <= nrow(chunk)) {
      state$record_chunks[[length(state$record_chunks) + 1L]] <- chunk[
        seq.int(segment_start, nrow(chunk)),
        ,
        drop = FALSE
      ]
    }

    invisible(NULL)
  }

  node_stats <- xml_stream_nodes(
    file = file,
    callback = consume_canonical_chunk,
    document_id = document_id,
    whitespace = whitespace,
    chunk_rows = chunk_rows
  )

  flush_record()

  if (state$record_count == 0L) {
    stop(
      paste0(
        "The XML document does not contain the specified row element `",
        spec$record_path,
        "`."
      ),
      call. = FALSE
    )
  }

  parallel_stats <- scheduler$finish()
  result_stats <- batcher$finish()

  if (!identical(parallel_stats$processed_records, as.integer(state$record_count))) {
    stop(
      "Parallel streaming did not process every isolated XML record.",
      call. = FALSE
    )
  }

  invisible(
    tibble::tibble(
      document_id = node_stats$document_id,
      node_count = node_stats$node_count,
      parser_chunks = node_stats$chunk_count,
      record_count = as.integer(state$record_count),
      result_rows = as.integer(result_stats$result_rows),
      result_chunks = as.integer(result_stats$result_chunks),
      max_record_nodes = as.integer(parallel_stats$max_record_nodes),
      id_check = if (spec$identifier$mode == "generated") {
        "not needed (generated IDs)"
      } else {
        id_check
      },
      parallel_strategy = strategy,
      workers = as.integer(workers),
      parallel_record_chunks = as.integer(parallel_stats$parallel_chunks),
      parallel_tasks = as.integer(parallel_stats$parallel_tasks),
      buffered_records = as.integer(parallel_stats$buffered_records),
      chunk_records = as.integer(settings$chunk_records),
      task_records = as.integer(settings$task_records)
    )
  )
}


.path_exists <- function(path) {
  file.exists(path) || dir.exists(path)
}


.commit_staged_path <- function(staged_path, output_path) {
  if (!.path_exists(output_path)) {
    if (!file.rename(staged_path, output_path)) {
      stop(
        "Could not publish the completed staged output.",
        call. = FALSE
      )
    }

    return(invisible(TRUE))
  }

  # Staging always happens beside the requested destination.  Moving the old
  # destination aside and publishing with rename therefore stays on one file
  # system.  This helper works for both a single CSV file and a Parquet dataset
  # directory.
  backup_path <- tempfile(
    pattern = paste0(".", basename(output_path), "-backup-"),
    tmpdir = dirname(output_path)
  )

  if (!file.rename(output_path, backup_path)) {
    stop(
      "Could not move the existing output aside for safe replacement.",
      call. = FALSE
    )
  }

  published <- file.rename(staged_path, output_path)

  if (!published) {
    restored <- file.rename(backup_path, output_path)
    stop(
      if (restored) {
        "Could not publish the completed output; the previous output was restored."
      } else {
        paste0(
          "Could not publish the completed output or automatically restore ",
          "the previous output. Its backup remains at: ",
          backup_path
        )
      },
      call. = FALSE
    )
  }

  unlink(backup_path, recursive = TRUE, force = TRUE)
  invisible(TRUE)
}


.commit_staged_file <- function(staged_file, output_file) {
  .commit_staged_path(staged_file, output_file)
}


.validate_output_parent <- function(output, argument = "output") {
  output <- .validate_one_string(output, argument)
  output_parent <- dirname(output)

  if (!dir.exists(output_parent)) {
    stop(
      paste0("Output directory does not exist: ", output_parent, "."),
      call. = FALSE
    )
  }

  normalized_parent <- normalizePath(
    output_parent,
    winslash = "/",
    mustWork = TRUE
  )

  file.path(normalized_parent, basename(output))
}


.path_contains <- function(directory, path) {
  directory <- sub("/+$", "", directory)
  identical(directory, path) || startsWith(path, paste0(directory, "/"))
}


#' Rectangle a large XML file to a staged CSV
#'
#' Data are written to a temporary file beside `output`.  The requested path is
#' created or replaced only after parsing and rectangling finish successfully.
#' CSV is intentionally retained as the directly inspectable interchange/test
#' format.  For typed analytical storage use `rectangle_xml_parquet()`.
rectangle_xml_csv <- function(
  file,
  spec,
  output,
  overwrite = FALSE,
  document_id = NULL,
  whitespace = NULL,
  chunk_rows = 100000L,
  batch_rows = 100000L,
  id_check = c("memory", "none"),
  parallel = FALSE,
  workers = NULL,
  strategy = "auto",
  chunk_records = NULL,
  task_records = NULL
) {
  file <- .validate_one_string(file, "file")
  .validate_stream_rectangle_spec(spec)

  if (!is.logical(overwrite) || length(overwrite) != 1L || is.na(overwrite)) {
    stop("`overwrite` must be TRUE or FALSE.", call. = FALSE)
  }

  normalized_input <- normalizePath(file, winslash = "/", mustWork = TRUE)
  output_file <- .validate_output_parent(output, "output")

  if (identical(normalized_input, output_file)) {
    stop("The CSV output cannot replace its XML input file.", call. = FALSE)
  }

  if (dir.exists(output_file)) {
    stop(
      paste0("CSV output must be a file, but a directory exists at: ", output_file, "."),
      call. = FALSE
    )
  }

  if (file.exists(output_file) && !overwrite) {
    stop(
      paste0(
        "Output file already exists: ",
        output_file,
        ". Use `overwrite = TRUE` to replace it after a successful run."
      ),
      call. = FALSE
    )
  }

  staged_file <- tempfile(
    pattern = paste0(".", basename(output_file), "-staged-"),
    tmpdir = dirname(output_file),
    fileext = ".csv"
  )
  published <- FALSE
  on.exit(
    if (!published && file.exists(staged_file)) unlink(staged_file),
    add = TRUE
  )

  # Write the schema immediately so a valid document whose chosen fields are
  # absent still produces a useful header-only CSV rather than no file at all.
  utils::write.table(
    .xml_rectangle_result_schema(spec),
    file = staged_file,
    sep = ",",
    row.names = FALSE,
    col.names = TRUE,
    quote = TRUE,
    qmethod = "double",
    na = "",
    eol = "\n",
    fileEncoding = "UTF-8"
  )

  stats <- xml_stream_rectangle(
    file = normalized_input,
    spec = spec,
    callback = function(batch) {
      utils::write.table(
        batch,
        file = staged_file,
        append = TRUE,
        sep = ",",
        row.names = FALSE,
        col.names = FALSE,
        quote = TRUE,
        qmethod = "double",
        na = "",
        eol = "\n",
        fileEncoding = "UTF-8"
      )
      invisible(NULL)
    },
    document_id = document_id,
    whitespace = whitespace,
    chunk_rows = chunk_rows,
    batch_rows = batch_rows,
    id_check = id_check,
    parallel = parallel,
    workers = workers,
    strategy = strategy,
    chunk_records = chunk_records,
    task_records = task_records
  )

  .commit_staged_path(staged_file, output_file)
  published <- TRUE
  stats$output_file <- output_file
  stats$output_format <- "csv"
  invisible(stats)
}


#' Rectangle a large XML file to a staged Parquet dataset
#'
#' The destination is a directory containing deterministic `part-*.parquet`
#' files.  In this sequential implementation each emitted rectangular batch is
#' written as one part.  The whole directory is staged beside `output_dir` and
#' becomes visible only after the XML document has parsed, rectangled, converted
#' and persisted successfully.  This part-file contract is intentionally ready
#' for the later parallel executor: workers may eventually produce independent
#' parts without changing the public storage representation.
rectangle_xml_parquet <- function(
  file,
  spec,
  output_dir,
  overwrite = FALSE,
  compression = "snappy",
  document_id = NULL,
  whitespace = NULL,
  chunk_rows = 100000L,
  batch_rows = 100000L,
  id_check = c("memory", "none"),
  parallel = FALSE,
  workers = NULL,
  strategy = "auto",
  chunk_records = NULL,
  task_records = NULL
) {
  .require_xml_rectangle_package("arrow")
  file <- .validate_one_string(file, "file")
  .validate_stream_rectangle_spec(spec)
  compression <- .validate_one_string(compression, "compression")

  if (!is.logical(overwrite) || length(overwrite) != 1L || is.na(overwrite)) {
    stop("`overwrite` must be TRUE or FALSE.", call. = FALSE)
  }

  normalized_input <- normalizePath(file, winslash = "/", mustWork = TRUE)
  output_path <- .validate_output_parent(output_dir, "output_dir")

  # A Parquet target is a dataset directory.  Never reinterpret an existing
  # ordinary file as a directory, even with overwrite=TRUE.
  if (file.exists(output_path) && !dir.exists(output_path)) {
    stop(
      paste0(
        "Parquet output must be a directory, but a file exists at: ",
        output_path,
        "."
      ),
      call. = FALSE
    )
  }

  if (dir.exists(output_path)) {
    normalized_existing_output <- normalizePath(
      output_path,
      winslash = "/",
      mustWork = TRUE
    )

    if (.path_contains(normalized_existing_output, normalized_input)) {
      stop(
        "The Parquet output directory cannot contain its XML input file.",
        call. = FALSE
      )
    }
  }

  if (dir.exists(output_path) && !overwrite) {
    stop(
      paste0(
        "Output directory already exists: ",
        output_path,
        ". Use `overwrite = TRUE` to replace it after a successful run."
      ),
      call. = FALSE
    )
  }

  staged_dir <- tempfile(
    pattern = paste0(".", basename(output_path), "-staged-"),
    tmpdir = dirname(output_path)
  )

  if (!dir.create(staged_dir)) {
    stop("Could not create the staged Parquet directory.", call. = FALSE)
  }

  published <- FALSE
  on.exit(
    if (!published && dir.exists(staged_dir)) {
      unlink(staged_dir, recursive = TRUE, force = TRUE)
    },
    add = TRUE
  )

  part_count <- 0L

  write_part <- function(batch) {
    part_count <<- part_count + 1L
    part_path <- file.path(
      staged_dir,
      sprintf("part-%06d.parquet", part_count)
    )

    arrow::write_parquet(
      batch,
      sink = part_path,
      compression = compression
    )
    invisible(NULL)
  }

  stats <- xml_stream_rectangle(
    file = normalized_input,
    spec = spec,
    callback = write_part,
    document_id = document_id,
    whitespace = whitespace,
    chunk_rows = chunk_rows,
    batch_rows = batch_rows,
    id_check = id_check,
    parallel = parallel,
    workers = workers,
    strategy = strategy,
    chunk_records = chunk_records,
    task_records = task_records
  )

  # A valid rectangle can contain records yet emit no value rows.  Persist one
  # empty typed part so Arrow still discovers the exact dataset schema.
  if (part_count == 0L) {
    write_part(.xml_rectangle_result_schema(spec))
  }

  .commit_staged_path(staged_dir, output_path)
  published <- TRUE
  stats$output_dir <- output_path
  stats$output_format <- "parquet"
  stats$output_parts <- as.integer(part_count)
  stats$compression <- compression
  invisible(stats)
}



# -----------------------------------------------------------------------------
# Analyst-facing single-table projection
# -----------------------------------------------------------------------------

# The canonical node table and the hierarchical long rectangle remain the
# loss-aware structural contracts.  The functions below add a deliberately
# different final projection for analysts: one self-contained atomic table per
# XML document.  Repeated element paths become entity rows.  Scalar content in
# singleton wrappers is folded into the nearest entity, except when an exact
# alternating sibling-pair layout proves that folding would erase essential
# document order.  Ancestor context is copied down to descendant entity rows.
# Independent repetitions therefore remain separate rows rather than being
# multiplied into Cartesian products.

.xml_analyst_clean_token <- function(value, fallback = "value") {
  value <- ifelse(is.na(value), "", value)
  value <- gsub(":", "_", value, fixed = TRUE)
  value <- gsub("[^[:alnum:]_]+", "_", value)
  value <- gsub("_+", "_", value)
  value <- gsub("^_+|_+$", "", value)

  if (!nzchar(value)) {
    value <- fallback
  }

  if (grepl("^[0-9]", value)) {
    value <- paste0("x_", value)
  }

  value
}


.xml_analyst_namespace_info <- function(nodes) {
  named_rows <- nodes$node_type %in% c("element", "attribute") &
    !is.na(nodes$namespace_uri) &
    nzchar(nodes$namespace_uri)

  if (!any(named_rows)) {
    return(
      list(
        alias_by_uri = character(),
        fallback_alias_by_uri = character(),
        primary_default_uri = NA_character_,
        unqualified_collisions = character(),
        description = NA_character_
      )
    )
  }

  uris <- unique(nodes$namespace_uri[named_rows])
  alias_by_uri <- stats::setNames(rep.int("", length(uris)), uris)
  fallback_alias_by_uri <- stats::setNames(rep.int("", length(uris)), uris)

  element_rows <- which(nodes$node_type == "element")
  root_row <- if (length(element_rows) > 0L) element_rows[[1L]] else NA_integer_
  root_uri <- if (!is.na(root_row)) nodes$namespace_uri[[root_row]] else NA_character_
  root_prefix <- if (!is.na(root_row)) nodes$prefix[[root_row]] else NA_character_
  primary_default_uri <- if (
    !is.na(root_uri) && nzchar(root_uri) &&
      (is.na(root_prefix) || !nzchar(root_prefix))
  ) {
    root_uri
  } else {
    NA_character_
  }

  # Prefer a stable, human-supplied prefix when one survives parsing. Parser-
  # generated ns1/ns2/... prefixes are deliberately not treated as semantic:
  # a document may contain many such lexical aliases for the same URI.
  used <- character()

  for (uri in uris) {
    rows <- which(named_rows & nodes$namespace_uri == uri)
    prefixes <- unique(nodes$prefix[rows])
    prefixes <- prefixes[!is.na(prefixes) & nzchar(prefixes)]
    prefixes <- vapply(
      prefixes,
      .xml_analyst_clean_token,
      character(1),
      fallback = "ns"
    )
    human <- prefixes[!grepl("^ns[0-9]+$", prefixes)]

    candidate <- if (length(human) > 0L) human[[1L]] else ""

    # The root default namespace is intentionally unqualified in analyst names.
    if (!is.na(primary_default_uri) && identical(uri, primary_default_uri)) {
      candidate <- ""
    }

    if (nzchar(candidate)) {
      base <- candidate
      suffix <- 1L
      while (candidate %in% used) {
        suffix <- suffix + 1L
        candidate <- paste0(base, "_", suffix)
      }
      alias_by_uri[[uri]] <- candidate
      fallback_alias_by_uri[[uri]] <- candidate
      used <- c(used, candidate)
    }
  }

  # Every non-default URI needs one deterministic fallback alias. This also
  # collapses many synthetic prefixes that refer to the same namespace URI.
  generated <- 0L
  for (uri in uris) {
    if (!nzchar(fallback_alias_by_uri[[uri]])) {
      repeat {
        generated <- generated + 1L
        candidate <- paste0("ns", generated)
        if (!candidate %in% used) break
      }
      fallback_alias_by_uri[[uri]] <- candidate
      used <- c(used, candidate)
    }

    if (
      !nzchar(alias_by_uri[[uri]]) &&
        (is.na(primary_default_uri) || !identical(uri, primary_default_uri))
    ) {
      alias_by_uri[[uri]] <- fallback_alias_by_uri[[uri]]
    }
  }

  # Normally the root default namespace and truly unnamespaced elements may
  # both remain unqualified. If the same local name occurs in both, qualify the
  # default-namespace occurrence with its deterministic fallback alias so that
  # the two fields cannot collide.
  unqualified_collisions <- character()
  if (!is.na(primary_default_uri)) {
    element_named <- nodes$node_type == "element"
    default_names <- unique(
      nodes$local_name[
        element_named & !is.na(nodes$namespace_uri) &
          nodes$namespace_uri == primary_default_uri
      ]
    )
    bare_names <- unique(
      nodes$local_name[
        element_named & (is.na(nodes$namespace_uri) | !nzchar(nodes$namespace_uri))
      ]
    )
    unqualified_collisions <- intersect(default_names, bare_names)
  }

  labels <- vapply(
    uris,
    function(uri) {
      alias <- alias_by_uri[[uri]]
      if (nzchar(alias)) alias else "(default)"
    },
    character(1)
  )
  description <- paste0(labels, "=", uris, collapse = "; ")

  list(
    alias_by_uri = alias_by_uri,
    fallback_alias_by_uri = fallback_alias_by_uri,
    primary_default_uri = primary_default_uri,
    unqualified_collisions = unqualified_collisions,
    description = description
  )
}


.xml_analyst_node_token <- function(
  local_name,
  namespace_uri,
  namespace_info,
  node_type = "element"
) {
  local <- .xml_analyst_clean_token(local_name)

  if (is.na(namespace_uri) || !nzchar(namespace_uri)) {
    return(local)
  }

  alias <- namespace_info$alias_by_uri[[namespace_uri]]
  if (is.null(alias) || is.na(alias)) {
    alias <- ""
  }

  if (
    identical(node_type, "element") &&
      !is.na(namespace_info$primary_default_uri) &&
      identical(namespace_uri, namespace_info$primary_default_uri) &&
      !local_name %in% namespace_info$unqualified_collisions
  ) {
    alias <- ""
  }

  # Namespaced attributes are always visibly qualified. A default namespace
  # never applies to an unprefixed attribute in XML.
  if (identical(node_type, "attribute") && !nzchar(alias)) {
    alias <- namespace_info$fallback_alias_by_uri[[namespace_uri]]
  }

  if (
    identical(node_type, "element") &&
      !nzchar(alias) &&
      local_name %in% namespace_info$unqualified_collisions
  ) {
    alias <- namespace_info$fallback_alias_by_uri[[namespace_uri]]
  }

  if (is.null(alias) || is.na(alias) || !nzchar(alias)) {
    return(local)
  }

  paste0(alias, "_", local)
}


# Build namespace-aware analyst tokens once per distinct XML name signature.
# Large XML documents commonly repeat the same element and attribute names tens
# of thousands of times; cleaning and qualifying those names per occurrence is
# pure duplicate work. The cache key is structural (node type + local name +
# namespace URI), so this optimization is independent of any XML vocabulary.
.xml_analyst_node_token_index <- function(nodes, namespace_info) {
  maximum_node_id <- max(nodes$node_id)
  token_by_id <- rep.int(NA_character_, maximum_node_id)
  named_rows <- which(nodes$node_type %in% c("element", "attribute"))

  if (length(named_rows) == 0L) {
    return(token_by_id)
  }

  namespace_key <- nodes$namespace_uri[named_rows]
  namespace_key[is.na(namespace_key)] <- ""
  signature <- paste(
    nodes$node_type[named_rows],
    nodes$local_name[named_rows],
    namespace_key,
    sep = "\u001f"
  )
  first <- !duplicated(signature)
  first_rows <- named_rows[first]
  first_signature <- signature[first]

  unique_tokens <- vapply(
    first_rows,
    function(row) {
      .xml_analyst_node_token(
        nodes$local_name[[row]],
        nodes$namespace_uri[[row]],
        namespace_info,
        node_type = nodes$node_type[[row]]
      )
    },
    character(1)
  )

  token_by_id[nodes$node_id[named_rows]] <-
    unique_tokens[match(signature, first_signature)]
  token_by_id
}


.xml_analyst_token_paths <- function(
  nodes,
  index,
  namespace_info,
  node_token_by_id = NULL
) {
  if (is.null(node_token_by_id)) {
    node_token_by_id <- .xml_analyst_node_token_index(nodes, namespace_info)
  }
  maximum_node_id <- max(nodes$node_id)
  token_paths <- vector("list", maximum_node_id)

  for (row in seq_len(nrow(index$elements))) {
    node_id <- index$elements$node_id[[row]]
    parent_id <- index$elements$parent_id[[row]]
    token <- node_token_by_id[[node_id]]

    parent_path <- if (
      is.na(parent_id) ||
        parent_id > length(token_paths) ||
        is.null(token_paths[[parent_id]])
    ) {
      character()
    } else {
      token_paths[[parent_id]]
    }

    token_paths[[node_id]] <- c(parent_path, token)
  }

  token_paths
}


.xml_analyst_token_paths_native <- function(
  nodes,
  index,
  node_token_by_id
) {
  path_count <- length(index$path_parent_id)
  path_tokens <- vector("list", path_count)

  for (path_id in seq_len(path_count)) {
    node_id <- index$path_first_node[[path_id]]
    token <- node_token_by_id[[node_id]]
    parent_path_id <- index$path_parent_id[[path_id]]

    if (is.na(parent_path_id)) {
      path_tokens[[path_id]] <- token
    } else {
      path_tokens[[path_id]] <- c(path_tokens[[parent_path_id]], token)
    }
  }

  maximum_node_id <- max(nodes$node_id)
  token_paths <- vector("list", maximum_node_id)
  element_node_id <- index$native_plan$element_node_id
  element_path_id <- index$native_plan$element_path_id
  token_paths[element_node_id] <- unname(path_tokens[element_path_id])
  token_paths
}



.xml_analyst_minimal_aliases <- function(paths) {
  if (length(paths) == 0L) {
    return(character())
  }

  widths <- rep.int(1L, length(paths))

  repeat {
    aliases <- vapply(
      seq_along(paths),
      function(index) {
        paste(tail(paths[[index]], widths[[index]]), collapse = "__")
      },
      character(1)
    )

    duplicates <- duplicated(aliases) | duplicated(aliases, fromLast = TRUE)

    if (!any(duplicates)) {
      return(aliases)
    }

    changed <- FALSE

    for (index in which(duplicates)) {
      if (widths[[index]] < length(paths[[index]])) {
        widths[[index]] <- widths[[index]] + 1L
        changed <- TRUE
      }
    }

    if (!changed) {
      return(make.unique(aliases, sep = "__ns"))
    }
  }
}


# Some XML vocabularies encode ordered pairs as alternating sibling elements,
# for example A, value, A, value2, where the value element type may vary from
# pair to pair.  Folding those value siblings into the parent and then copying
# parent context to every repeated A row invents associations that are not in
# the source tree.  Detect only the strong structural form that can be proven
# from XML order alone: an even-length direct-child sequence of at least two
# pairs where the first child path occupies every odd position and never an
# even position, and at least one counterpart path is singleton within that
# parent occurrence (the case that would otherwise be folded).  No element
# names or vocabulary-specific rules are involved.
#
# For such a parent occurrence, promote the parent path and every direct child
# path to analyst entities.  The analyst table then preserves the ordered
# sibling sequence explicitly instead of guessing pair semantics.  Because
# entity selection is path-based, one proven occurrence makes the same paths
# explicit everywhere in the document, keeping the output contract stable.
.xml_analyst_alternating_sibling_paths <- function(index) {
  elements <- index$elements

  if (nrow(elements) < 5L) {
    return(character())
  }

  candidate_parent_ids <- unique(
    elements$parent_id[
      !is.na(elements$parent_id) & elements$sibling_occurrence > 1L
    ]
  )
  candidate_parent_ids <- candidate_parent_ids[!is.na(candidate_parent_ids)]

  if (length(candidate_parent_ids) == 0L) {
    return(character())
  }

  candidate_rows <- which(
    !is.na(elements$parent_id) &
      elements$parent_id %in% candidate_parent_ids
  )
  child_groups <- split(
    candidate_rows,
    elements$parent_id[candidate_rows],
    drop = TRUE
  )
  row_by_node_id <- rep.int(NA_integer_, max(elements$node_id))
  row_by_node_id[elements$node_id] <- seq_len(nrow(elements))
  selected <- character()

  for (rows in child_groups) {
    child_count <- length(rows)

    if (child_count < 4L || child_count %% 2L != 0L) {
      next
    }

    # `index$elements` is in document order and split() preserves that order,
    # but sort explicitly by node id so this helper remains robust if the index
    # implementation changes later.
    rows <- rows[order(elements$node_id[rows])]
    child_paths <- elements$path_key[rows]
    odd <- seq.int(1L, child_count, by = 2L)
    even <- seq.int(2L, child_count, by = 2L)
    anchor_path <- child_paths[[1L]]

    if (
      !all(child_paths[odd] == anchor_path) ||
        any(child_paths[even] == anchor_path) ||
        !any(elements$sibling_count[rows[even]] == 1L)
    ) {
      next
    }

    parent_id <- elements$parent_id[[rows[[1L]]]]
    parent_row <- if (
      parent_id >= 1L && parent_id <= length(row_by_node_id)
    ) {
      row_by_node_id[[parent_id]]
    } else {
      NA_integer_
    }

    if (!is.na(parent_row)) {
      selected <- c(selected, elements$path_key[[parent_row]])
    }
    selected <- c(selected, unique(child_paths))
  }

  unique(selected)
}


.xml_analyst_entity_paths <- function(index) {
  paths <- index$paths
  root_depth <- min(paths$depth)
  alternating_paths <- .xml_analyst_alternating_sibling_paths(index)
  keep <- paths$depth == root_depth |
    paths$repeated |
    paths$path_key %in% alternating_paths
  selected <- paths[keep, , drop = FALSE]

  first_node <- vapply(
    selected$path_key,
    function(path_key) {
      min(index$elements$node_id[index$elements$path_key == path_key])
    },
    integer(1)
  )

  selected <- selected[order(first_node), , drop = FALSE]
  rownames(selected) <- NULL
  selected
}


.xml_analyst_relative_tokens <- function(token_paths, node_id, owner_id) {
  current <- token_paths[[node_id]]
  owner <- token_paths[[owner_id]]

  if (length(current) < length(owner)) {
    stop("Internal analyst projection path mismatch.", call. = FALSE)
  }

  if (length(current) == length(owner)) {
    return(character())
  }

  current[seq.int(length(owner) + 1L, length(current))]
}


.xml_analyst_subtree_end_rows <- function(nodes) {
  n <- nrow(nodes)
  ends <- rep.int(n, n)
  stack <- integer()

  for (row in seq_len(n)) {
    depth <- nodes$depth[[row]]

    while (
      length(stack) > 0L &&
        nodes$depth[[stack[[length(stack)]]]] >= depth
    ) {
      ends[[stack[[length(stack)]]]] <- row - 1L
      stack <- stack[-length(stack)]
    }

    if (identical(nodes$node_type[[row]], "element")) {
      stack <- c(stack, row)
    }
  }

  ends
}


.xml_analyst_subtree_text <- function(
  nodes,
  element_row,
  subtree_end_rows = NULL,
  text_rows = NULL
) {
  if (is.null(subtree_end_rows)) {
    # Callers on the optimized analyst path normally pass a precomputed vector.
    # Keep this helper independently correct for direct/internal use by falling
    # back to the frozen R subtree-end calculation when none is supplied.
    subtree_end_rows <- .xml_analyst_subtree_end_rows(nodes)
  }
  if (is.null(text_rows)) {
    text_rows <- which(nodes$node_type %in% c("text", "cdata"))
  }

  last <- subtree_end_rows[[element_row]]
  if (is.na(last) || last <= element_row || length(text_rows) == 0L) {
    return("")
  }

  first_index <- findInterval(element_row, text_rows) + 1L
  last_index <- findInterval(last, text_rows)

  if (first_index > last_index || first_index > length(text_rows)) {
    return("")
  }

  rows <- text_rows[seq.int(first_index, last_index)]
  paste0(nodes$value[rows], collapse = "")
}


.xml_analyst_identifier_like <- function(column_name) {
  terminal <- sub("^.*__", "", tolower(column_name))
  terminal <- sub("^attr_", "", terminal)

  grepl(
    "(^|_)(id|identifier|accession|code|key|ref)$",
    terminal,
    perl = TRUE
  )
}


.xml_analyst_apply_types <- function(
  result,
  data_columns,
  infer_types,
  analyst_engine = NULL
) {
  if (!isTRUE(infer_types) || length(data_columns) == 0L) {
    return(result)
  }

  # P4: on the native analyst path infer and convert all eligible character
  # columns in one compiled batch.  The C kernel implements the same
  # conservative lexical rules as `.xml_infer_sample_type()` and only converts
  # when that function would report high confidence.  Identifier-like fields,
  # misc provenance and derived text_content remain character by policy.
  if (is.null(analyst_engine)) {
    analyst_engine <- .xml_requested_analyst_engine()
  }

  if (identical(analyst_engine, "native")) {
    eligible <- data_columns[
      vapply(result[data_columns], is.character, logical(1))
    ]
    if (length(eligible) > 0L) {
      skip <- vapply(eligible, .xml_analyst_identifier_like, logical(1)) |
        startsWith(eligible, "xml_misc__") |
        grepl("__text_content$", eligible)
      eligible <- eligible[!skip]
    }

    if (length(eligible) > 0L) {
      inferred_codes <- .xml_native_infer_types(result[eligible])
      type_names <- c("character", "date", "logical", "integer", "double")
      for (index in which(inferred_codes > 0L)) {
        column <- eligible[[index]]
        declared_type <- type_names[[inferred_codes[[index]] + 1L]]
        # Conversion remains in the frozen R implementation so every edge-case
        # validation/error message stays identical.  C replaces the expensive
        # repeated inference scans, not the semantic conversion boundary.
        result[[column]] <- .xml_convert_values(
          result[[column]],
          declared_type = declared_type,
          source_label = column,
          output_name = column
        )
      }
    }
    return(result)
  }

  for (column in data_columns) {
    if (is.logical(result[[column]])) {
      next
    }

    if (!is.character(result[[column]])) {
      next
    }

    if (
      .xml_analyst_identifier_like(column) ||
        startsWith(column, "xml_misc__") ||
        grepl("__text_content$", column)
    ) {
      next
    }

    inferred <- .xml_infer_sample_type(result[[column]])

    if (
      !identical(inferred$type, "character") &&
        identical(inferred$confidence, "high")
    ) {
      result[[column]] <- .xml_convert_values(
        result[[column]],
        declared_type = inferred$type,
        source_label = column,
        output_name = column
      )
    }
  }

  result
}


.xml_analyst_key_token <- function(value) {
  value <- tolower(value)
  value <- sub("^attr_", "", value)
  gsub("[^[:alnum:]_]+", "", value)
}


.xml_analyst_identifier_strength <- function(value) {
  token <- .xml_analyst_key_token(value)
  pieces <- strsplit(token, "_", fixed = TRUE)[[1L]]
  local <- pieces[[length(pieces)]]
  compact <- gsub("_", "", token, fixed = TRUE)
  local_compact <- gsub("[^[:alnum:]]+", "", local)

  # Source keys are intentionally conservative. Exact identity terms have the
  # strongest evidence. Broader *Id forms (artifactId, PMID, query_ID, ...)
  # remain eligible only when they are attached directly to the analytical
  # entity. Reference/location terms such as href, uri, url, ref and reference
  # are relationships or targets, not evidence that the value identifies the
  # current entity.
  if (local_compact %in% c("id", "identifier", "uuid", "guid", "accession", "recordreference", "about")) {
    return(1L)
  }

  if (grepl("id$", compact, perl = TRUE)) {
    return(2L)
  }

  99L
}


.xml_analyst_identifier_token <- function(value) {
  .xml_analyst_identifier_strength(value) < 99L
}


.xml_analyst_suffix_id_matches_entity <- function(value, entity) {
  token <- .xml_analyst_key_token(value)
  compact <- gsub("_", "", token, fixed = TRUE)
  stem <- sub("id$", "", compact, ignore.case = TRUE)

  entity_tail <- tail(strsplit(entity, "__", fixed = TRUE)[[1L]], 1L)
  entity_compact <- tolower(gsub("[^[:alnum:]]+", "", entity_tail))

  nzchar(stem) && identical(stem, entity_compact)
}


.xml_analyst_strong_nested_identifier_token <- function(value) {
  token <- .xml_analyst_key_token(value)
  compact <- gsub("_", "", token, fixed = TRUE)

  # Nested ownership evidence is weak after singleton folding. Keep only the
  # compact machine-address idiom used by network-like XML. Generic nested IDs,
  # accessions, references and URIs are deliberately not promoted to the owner
  # entity's source key.
  identical(compact, "addr")
}


.xml_analyst_boolean_key_values <- function(values) {
  lexical <- tolower(trimws(as.character(values)))
  lexical <- lexical[!is.na(lexical) & nzchar(lexical)]

  length(lexical) > 0L && all(lexical %in% c("true", "false"))
}


.xml_analyst_key_score <- function(column, entity) {
  prefix <- paste0(entity, "__")
  if (!startsWith(column, prefix)) {
    return(99L)
  }

  relative <- substring(column, nchar(prefix) + 1L)
  parts <- strsplit(relative, "__", fixed = TRUE)[[1L]]
  last <- parts[[length(parts)]]
  parent <- if (length(parts) > 1L) parts[[length(parts) - 1L]] else ""
  last_is_attribute <- startsWith(last, "attr_")
  last_token <- .xml_analyst_key_token(last)
  identifier_strength <- .xml_analyst_identifier_strength(last)

  # Strongest: an exact identity field directly on the entity itself. This
  # makes a direct <ID> beat broader fields such as <CustomizationID> without
  # knowing anything about UBL or any other vocabulary.
  if (length(parts) == 1L && identifier_strength == 1L) {
    return(1L)
  }

  # Broader direct *Id forms are useful best-effort identifiers but weaker than
  # exact ID/identifier/accession terms. Boolean-valued false positives are
  # screened later from the observed candidate values.
  if (
    length(parts) == 1L &&
      identifier_strength == 2L &&
      .xml_analyst_suffix_id_matches_entity(last, entity)
  ) {
    return(3L)
  }

  # XML vocabularies such as FHIR commonly encode an owning entity identifier
  # as <id value="...">. Only the value-bearing attribute is promoted; metadata
  # attributes on the same wrapper (for example @source or @type) are not keys.
  if (
    length(parts) == 2L &&
      last_is_attribute &&
      identical(last_token, "value") &&
      .xml_analyst_identifier_strength(parent) == 1L
  ) {
    return(2L)
  }

  # Nested attributes are normally not owner identifiers after singleton
  # folding. Keep only very strong machine-address evidence (address/@addr).
  if (
    length(parts) == 2L &&
      last_is_attribute &&
      .xml_analyst_strong_nested_identifier_token(last)
  ) {
    return(4L)
  }

  # Do not infer keys from generic names, references/URIs, nested accessions or
  # deeper ID-looking fields. These remain ordinary analyst columns and every
  # row still has the authoritative generated xml_entity_id.
  99L
}


.xml_analyst_key_candidates <- function(result, data_columns) {
  result$xml_key_column <- rep.int(NA_character_, nrow(result))
  result$xml_key_value <- rep.int(NA_character_, nrow(result))

  entity_types <- unique(result$xml_entity)
  entity_types <- entity_types[entity_types != "xml_misc"]

  for (entity in entity_types) {
    rows <- which(result$xml_entity == entity)
    prefix <- paste0(entity, "__")
    candidates <- data_columns[startsWith(data_columns, prefix)]

    if (length(candidates) == 0L) {
      next
    }

    scores <- vapply(
      candidates,
      .xml_analyst_key_score,
      integer(1),
      entity = entity
    )
    keep <- scores < 99L
    candidates <- candidates[keep]
    scores <- scores[keep]

    if (length(candidates) == 0L) {
      next
    }

    coverage <- integer(length(candidates))
    admissible <- logical(length(candidates))

    for (index in seq_along(candidates)) {
      values <- result[[candidates[[index]]]][rows]
      lexical <- as.character(values)
      valid <- !is.na(values) & nzchar(lexical)
      coverage[[index]] <- sum(valid)

      admissible[[index]] <-
        any(valid) &&
        !anyDuplicated(lexical[valid]) &&
        !.xml_analyst_boolean_key_values(values[valid])
    }

    candidates <- candidates[admissible]
    scores <- scores[admissible]
    coverage <- coverage[admissible]

    if (length(candidates) == 0L) {
      next
    }

    ordering <- order(scores, -coverage, match(candidates, data_columns))
    column <- candidates[[ordering[[1L]]]]
    values <- result[[column]][rows]
    lexical <- as.character(values)
    valid <- !is.na(values) & nzchar(lexical)

    # Use one source-key strategy per analytical entity type. Falling back to a
    # different column for individual rows makes xml_key_column itself unstable
    # and can silently mix distinct identifier semantics. Rows lacking the
    # chosen source key simply retain the generated xml_entity_id.
    target <- rows[valid]
    result$xml_key_column[target] <- column
    result$xml_key_value[target] <- lexical[valid]
  }

  result
}


#' Convert canonical XML nodes to one self-contained analyst table
#'
#' The final object is one tibble, not a list of related tables. Repeated XML
#' element paths become rows identified by `xml_entity`. Scalar values in
#' singleton wrappers are folded into their nearest entity. Exact alternating
#' sibling-pair structures are conservatively kept as explicit element entities
#' so document order is preserved rather than inventing sibling associations.
#' Values owned by an immediate parent entity are copied down as context, so
#' filtering one entity type normally yields a directly usable wide analytical
#' slice without transitively duplicating every ancestor field. More distant
#' ancestry remains available inside the same table through
#' `xml_parent_entity_id`. Independent repeated branches remain separate rows
#' and are never multiplied into a Cartesian product.
#'
#' The canonical node table remains the loss-aware representation. This analyst
#' projection deliberately repeats one entity hop of context while keeping the
#' complete entity lineage explicit in the same atomic table.
xml_analyst_table <- function(
  nodes,
  infer_types = TRUE,
  include_misc = TRUE,
  .validate_nodes = TRUE
) {
  if (isTRUE(.validate_nodes)) {
    validate_xml_nodes(nodes)
  }
  .require_xml_rectangle_package("tibble")

  # Analyst internals only require ordinary column vectors.  Dropping tibble's
  # subclass here is shallow (the vectors are shared) and avoids thousands of
  # `$.tbl_df` dispatches in a projection that can touch a large canonical
  # table repeatedly.  The final public result remains a tibble.
  if (inherits(nodes, "tbl_df")) {
    class(nodes) <- "data.frame"
  }

  if (length(unique(nodes$document_id)) != 1L) {
    stop(
      "`xml_analyst_table()` currently expects one XML document at a time.",
      call. = FALSE
    )
  }

  analyst_engine <- .xml_requested_analyst_engine()
  index <- if (identical(analyst_engine, "native")) {
    .build_xml_structure_index_native(nodes)
  } else {
    .build_xml_structure_index(nodes, validate = FALSE)
  }
  namespace_info <- .xml_analyst_namespace_info(nodes)
  node_token_by_id <- .xml_analyst_node_token_index(nodes, namespace_info)
  token_paths <- if (identical(analyst_engine, "native")) {
    .xml_analyst_token_paths_native(
      nodes,
      index,
      node_token_by_id = node_token_by_id
    )
  } else {
    .xml_analyst_token_paths(
      nodes,
      index,
      namespace_info,
      node_token_by_id = node_token_by_id
    )
  }
  entity_paths <- .xml_analyst_entity_paths(index)

  first_entity_nodes <- if (identical(analyst_engine, "native")) {
    path_ids <- unname(index$path_id_by_key[entity_paths$path_key])
    as.integer(index$path_first_node[path_ids])
  } else {
    vapply(
      entity_paths$path_key,
      function(path_key) {
        min(index$elements$node_id[index$elements$path_key == path_key])
      },
      integer(1)
    )
  }

  # Reuse the namespace-aware token paths for entity aliases as well as field
  # names. This keeps repeated entities from different namespaces distinct
  # without falling back to opaque make.unique() suffixes.
  entity_alias_paths <- unname(token_paths[first_entity_nodes])
  aliases <- .xml_analyst_minimal_aliases(entity_alias_paths)
  aliases[aliases == "xml_misc"] <- "xml_source_misc"
  alias_by_path <- stats::setNames(aliases, entity_paths$path_key)

  maximum_node_id <- max(nodes$node_id)
  element_path_by_id <- rep.int(NA_character_, maximum_node_id)
  element_path_by_id[index$elements$node_id] <- index$elements$path_key

  if (identical(analyst_engine, "native")) {
    entity_path_ids <- unname(index$path_id_by_key[entity_paths$path_key])
    entity_map <- .xml_native_entity_map(
      element_node_id = index$elements$node_id,
      element_parent_id = index$elements$parent_id,
      element_path_id = index$native_plan$element_path_id,
      entity_path_id = entity_path_ids,
      maximum_node_id = maximum_node_id
    )
    owner_entity <- entity_map$owner_by_node
    is_entity_node <- entity_map$is_entity_node
    entity_elements <- index$elements[
      entity_map$entity_element_pos,
      ,
      drop = FALSE
    ]
    parent_entity_node_id <- as.integer(entity_map$parent_entity_node_id)
    occurrence <- as.integer(entity_map$occurrence)
  } else {
    owner_entity <- rep.int(NA_integer_, maximum_node_id)
    is_entity_node <- rep.int(FALSE, maximum_node_id)
    is_entity_node[index$elements$node_id] <-
      index$elements$path_key %in% entity_paths$path_key

    for (row in seq_len(nrow(index$elements))) {
      node_id <- index$elements$node_id[[row]]
      parent_id <- index$elements$parent_id[[row]]

      if (is_entity_node[[node_id]]) {
        owner_entity[[node_id]] <- node_id
      } else if (
        !is.na(parent_id) &&
          parent_id <= length(owner_entity)
      ) {
        owner_entity[[node_id]] <- owner_entity[[parent_id]]
      }
    }

    entity_elements <- index$elements[
      index$elements$node_id %in% which(is_entity_node),
      ,
      drop = FALSE
    ]
    entity_elements <- entity_elements[
      order(entity_elements$node_id),
      ,
      drop = FALSE
    ]

    parent_entity_node_id <- rep.int(NA_integer_, nrow(entity_elements))
    for (row in seq_len(nrow(entity_elements))) {
      parent_id <- entity_elements$parent_id[[row]]
      if (
        !is.na(parent_id) &&
          parent_id <= length(owner_entity)
      ) {
        parent_entity_node_id[[row]] <- owner_entity[[parent_id]]
      }
    }
  }

  entity_elements$entity <- unname(alias_by_path[entity_elements$path_key])

  entity_alias_by_node <- stats::setNames(
    entity_elements$entity,
    as.character(entity_elements$node_id)
  )
  parent_entity <- ifelse(
    is.na(parent_entity_node_id),
    NA_character_,
    unname(entity_alias_by_node[as.character(parent_entity_node_id)])
  )

  if (!identical(analyst_engine, "native")) {
    occurrence <- integer(nrow(entity_elements))
    occurrence_groups <- split(
      seq_len(nrow(entity_elements)),
      entity_elements$entity,
      drop = TRUE
    )

    for (group in occurrence_groups) {
      occurrence[group] <- seq_along(group)
    }
  }

  entity_rows <- data.frame(
    xml_document_id = entity_elements$document_id,
    xml_entity = entity_elements$entity,
    xml_entity_id = sprintf("e%09d", entity_elements$node_id),
    xml_parent_entity = parent_entity,
    xml_parent_entity_id = ifelse(
      is.na(parent_entity_node_id),
      NA_character_,
      sprintf("e%09d", parent_entity_node_id)
    ),
    xml_occurrence = as.integer(occurrence),
    xml_node_id = as.integer(entity_elements$node_id),
    xml_parent_node_id = as.integer(entity_elements$parent_id),
    xml_depth = as.integer(entity_elements$depth),
    xml_source_path = entity_elements$display_path,
    xml_namespace_uri = entity_elements$namespace_uri,
    xml_namespaces = rep.int(
      namespace_info$description,
      nrow(entity_elements)
    ),
    stringsAsFactors = FALSE
  )

  row_by_node_id <- rep.int(NA_integer_, maximum_node_id)
  row_by_node_id[nodes$node_id] <- seq_len(nrow(nodes))
  element_display_path_by_id <- rep.int(NA_character_, maximum_node_id)
  element_display_path_by_id[index$elements$node_id] <- index$elements$display_path
  # Parent-child lookups sit on the hottest extraction path. A named list
  # returned by split() requires repeated character-name lookup for every
  # element. Convert each grouping once to a dense node-id-indexed list so
  # subsequent lookups are direct integer indexing. This is generic for the
  # canonical tree and does not depend on XML vocabulary or document shape.
  dense_groups_by_parent <- function(values, parents) {
    out <- vector("list", maximum_node_id)
    keep <- !is.na(parents) & parents >= 1L & parents <= maximum_node_id

    if (any(keep)) {
      groups <- split(values[keep], parents[keep], drop = TRUE)
      parent_ids <- as.integer(names(groups))
      out[parent_ids] <- unname(groups)
    }

    out
  }

  text_rows <- which(nodes$node_type %in% c("text", "cdata"))
  attribute_rows <- which(nodes$node_type == "attribute")

  if (identical(analyst_engine, "native")) {
    # The native structural plan already computed exact subtree boundaries in
    # the same preorder scan that assigned path ids. Recomputing them in R was
    # a redundant O(nodes) stack pass and the largest remaining P2 hotspot.
    subtree_end_rows <- index$subtree_end_rows
    text_by_parent <- dense_groups_by_parent(
      text_rows,
      nodes$parent_id[text_rows]
    )
    element_children <- NULL
    attributes_by_parent <- NULL
  } else {
    subtree_end_rows <- .xml_analyst_subtree_end_rows(nodes)
    text_by_parent <- dense_groups_by_parent(
      text_rows,
      nodes$parent_id[text_rows]
    )
    # These dense child/attribute lists are used only by the frozen R fallback.
    # Avoid allocating and splitting them on the native path.
    element_children <- dense_groups_by_parent(
      index$elements$node_id,
      index$elements$parent_id
    )
    attributes_by_parent <- dense_groups_by_parent(
      attribute_rows,
      nodes$parent_id[attribute_rows]
    )
  }

  # A canonical attribute contributes at most one analyst field and an element
  # contributes at most one value/text_content/presence field. Preallocate an
  # exact safe upper bound instead of repeatedly extending a nested R list.
  # This is purely an implementation optimization: field order and values are
  # populated in exactly the same extraction loops as the frozen reference.
  field_capacity <- length(attribute_rows) + nrow(index$elements)
  field_count <- 0L
  field_owner_id <- integer(field_capacity)
  field_entity_path_key <- character(field_capacity)
  field_source_signature <- character(field_capacity)
  # P5 keeps the semantic field kind explicitly instead of reparsing it later
  # from source_signature with a regex over every field occurrence.
  field_kind_buffer <- character(field_capacity)
  field_base_buffer <- character(field_capacity)
  field_value_buffer <- vector("list", field_capacity)
  field_storage_type <- character(field_capacity)
  field_order <- integer(field_capacity)

  projected_attribute_count <- 0L
  projected_text_node_count <- 0L
  projected_empty_element_count <- 0L

  add_field <- function(
    owner_id,
    source_signature,
    field_base,
    value,
    storage_type,
    order
  ) {
    field_count <<- field_count + 1L

    if (field_count > field_capacity) {
      stop(
        "Internal analyst field buffer capacity was exceeded.",
        call. = FALSE
      )
    }

    field_owner_id[[field_count]] <<- as.integer(owner_id)
    field_entity_path_key[[field_count]] <<- element_path_by_id[[owner_id]]
    field_source_signature[[field_count]] <<- source_signature
    field_kind_buffer[[field_count]] <<- sub("\u001e.*$", "", source_signature)
    field_base_buffer[[field_count]] <<- field_base
    field_value_buffer[[field_count]] <<- value
    field_storage_type[[field_count]] <<- storage_type
    field_order[[field_count]] <<- as.integer(order)
    invisible(NULL)
  }

  # Every attribute belongs to the nearest entity. Attribute markers are kept
  # explicitly in the analytical column name so `<x id="1">` and `<x><id>1`
  # cannot silently collapse into the same field.
  if (identical(analyst_engine, "native") && length(attribute_rows) > 0L) {
    # Attribute metadata is structural and highly repetitive. Large documents
    # may contain tens of thousands of attributes but only a small number of
    # (owner-path, parent-path, attribute-name) combinations. Compute relative
    # path prefixes once per distinct structural pair, then emit the field
    # vectors in one batch. Values and canonical order remain occurrence-level.
    attribute_parent_id <- nodes$parent_id[attribute_rows]
    valid_parent <- !is.na(attribute_parent_id) &
      attribute_parent_id <= length(owner_entity)
    owner_id <- rep.int(NA_integer_, length(attribute_rows))
    owner_id[valid_parent] <- owner_entity[attribute_parent_id[valid_parent]]
    keep <- valid_parent & !is.na(owner_id)

    if (any(keep)) {
      rows <- attribute_rows[keep]
      parent_id <- attribute_parent_id[keep]
      owner_id <- owner_id[keep]
      parent_path_id <- index$path_id_by_node[parent_id]
      owner_path_id <- index$path_id_by_node[owner_id]

      # Path ids are dense positive integers. Encode the structural pair as an
      # exact double rather than allocating tens of thousands of concatenated
      # character keys. The product is far below 2^53 for any R-addressable
      # canonical table, so equality is exact.
      path_stride <- as.double(length(index$path_key_by_id) + 1L)
      pair_key <- as.double(owner_path_id) +
        as.double(parent_path_id) * path_stride
      pair_first <- !duplicated(pair_key)
      first_index <- which(pair_first)
      pair_prefix_unique <- vapply(
        first_index,
        function(i) {
          relative <- .xml_analyst_relative_tokens(
            token_paths,
            parent_id[[i]],
            owner_id[[i]]
          )
          paste(relative, collapse = "__")
        },
        character(1)
      )
      pair_prefix <- pair_prefix_unique[
        match(pair_key, pair_key[pair_first])
      ]

      attribute_node_id <- nodes$node_id[rows]
      attribute_token <- node_token_by_id[attribute_node_id]
      attribute_field <- paste0("attr_", attribute_token)
      field_base <- ifelse(
        nzchar(pair_prefix),
        paste0(pair_prefix, "__", attribute_field),
        attribute_field
      )
      attribute_name <- index$expanded_name_by_id[attribute_node_id]
      source_signature <- paste(
        "attribute",
        index$path_key_by_id[parent_path_id],
        attribute_name,
        sep = "\u001e"
      )

      count <- length(rows)
      target <- seq.int(field_count + 1L, field_count + count)
      if (tail(target, 1L) > field_capacity) {
        stop("Internal analyst field buffer capacity was exceeded.", call. = FALSE)
      }
      field_owner_id[target] <- as.integer(owner_id)
      field_entity_path_key[target] <- element_path_by_id[owner_id]
      field_source_signature[target] <- source_signature
      field_kind_buffer[target] <- "attribute"
      field_base_buffer[target] <- field_base
      field_value_buffer[target] <- as.list(nodes$value[rows])
      field_storage_type[target] <- "character"
      field_order[target] <- as.integer(nodes$node_order[rows])
      field_count <- field_count + count
      projected_attribute_count <- projected_attribute_count + count
    }
  } else {
    for (row in attribute_rows) {
      parent_id <- nodes$parent_id[[row]]

      if (is.na(parent_id) || parent_id > length(owner_entity)) {
        next
      }

      owner_id <- owner_entity[[parent_id]]

      if (is.na(owner_id)) {
        next
      }

      relative <- .xml_analyst_relative_tokens(
        token_paths,
        parent_id,
        owner_id
      )
      attribute_token <- node_token_by_id[[nodes$node_id[[row]]]]
      field_parts <- c(relative, paste0("attr_", attribute_token))
      field_base <- paste(field_parts, collapse = "__")
      attribute_name <- index$expanded_name_by_id[[nodes$node_id[[row]]]]
      source_signature <- paste(
        "attribute",
        .xml_path_key(index$expanded_paths[[parent_id]]),
        attribute_name,
        sep = "\u001e"
      )

      add_field(
        owner_id = owner_id,
        source_signature = source_signature,
        field_base = field_base,
        value = nodes$value[[row]],
        storage_type = "character",
        order = nodes$node_order[[row]]
      )
      projected_attribute_count <- projected_attribute_count + 1L
    }
  }

  # Text/presence fields are occurrence-level values, but their structural
  # metadata depends only on the pair (owner path, element path).  The native
  # analyst engine therefore computes field names/signatures once per distinct
  # structural pair and broadcasts them to all occurrences.  This replaces a
  # full character-path reconstruction for every element while preserving the
  # frozen field order and values exactly.
  if (identical(analyst_engine, "native")) {
    element_node_id <- index$elements$node_id
    element_owner_id <- owner_entity[element_node_id]
    valid_owner <- !is.na(element_owner_id)

    text_parent_count <- tabulate(
      nodes$parent_id[text_rows],
      nbins = maximum_node_id
    )
    attribute_parent_count <- tabulate(
      nodes$parent_id[attribute_rows],
      nbins = maximum_node_id
    )
    direct_text_count <- text_parent_count[element_node_id]
    attribute_count <- attribute_parent_count[element_node_id]
    child_count <- as.integer(index$elements$has_element_children)

    element_kind <- rep.int("", length(element_node_id))
    has_text <- valid_owner & direct_text_count > 0L
    element_kind[has_text & child_count > 0L] <- "text_content"
    element_kind[has_text & child_count == 0L] <- "value"
    element_kind[
      valid_owner & direct_text_count == 0L &
        child_count == 0L & attribute_count == 0L
    ] <- "presence"

    emit_element <- which(nzchar(element_kind))

    if (length(emit_element) > 0L) {
      emit_node_id <- element_node_id[emit_element]
      emit_owner_id <- element_owner_id[emit_element]
      emit_path_id <- index$path_id_by_node[emit_node_id]
      emit_owner_path_id <- index$path_id_by_node[emit_owner_id]
      path_stride <- as.double(length(index$path_key_by_id) + 1L)
      pair_key <- as.double(emit_owner_path_id) +
        as.double(emit_path_id) * path_stride
      pair_first <- !duplicated(pair_key)
      pair_first_index <- which(pair_first)

      pair_relative_token <- vapply(
        pair_first_index,
        function(i) {
          relative <- .xml_analyst_relative_tokens(
            token_paths,
            emit_node_id[[i]],
            emit_owner_id[[i]]
          )
          paste(relative, collapse = "__")
        },
        character(1)
      )

      pair_relative_source <- vapply(
        pair_first_index,
        function(i) {
          relative_expanded <- .xml_relative_parts(
            index$path_expanded_by_id[[emit_path_id[[i]]]],
            index$path_expanded_by_id[[emit_owner_path_id[[i]]]]
          )
          .xml_path_key(relative_expanded)
        },
        character(1)
      )

      pair_match <- match(pair_key, pair_key[pair_first])
      relative_token <- pair_relative_token[pair_match]
      relative_source <- pair_relative_source[pair_match]
      kind <- element_kind[emit_element]

      field_base <- relative_token
      value_rows <- kind == "value"
      field_base[value_rows & !nzchar(relative_token)] <- "value"
      text_content_rows <- kind == "text_content"
      field_base[text_content_rows] <- ifelse(
        nzchar(relative_token[text_content_rows]),
        paste0(relative_token[text_content_rows], "__text_content"),
        "text_content"
      )
      presence_rows <- kind == "presence"
      field_base[presence_rows] <- ifelse(
        nzchar(relative_token[presence_rows]),
        paste0(relative_token[presence_rows], "__present"),
        "present"
      )

      source_signature <- paste(kind, relative_source, sep = "\u001e")
      storage_type <- ifelse(kind == "presence", "logical", "character")
      values <- vector("list", length(emit_element))

      for (i in seq_along(emit_element)) {
        if (kind[[i]] == "presence") {
          values[[i]] <- TRUE
          next
        }

        node_id <- emit_node_id[[i]]
        direct_text <- text_by_parent[[node_id]]
        if (is.null(direct_text)) {
          direct_text <- integer()
        }

        if (kind[[i]] == "text_content") {
          canonical_row <- row_by_node_id[[node_id]]
          values[[i]] <- .xml_analyst_subtree_text(
            nodes,
            canonical_row,
            subtree_end_rows = subtree_end_rows,
            text_rows = text_rows
          )
        } else if (length(direct_text) == 1L) {
          values[[i]] <- nodes$value[[direct_text]]
        } else {
          values[[i]] <- paste0(nodes$value[direct_text], collapse = "")
        }
      }

      count <- length(emit_element)
      target <- seq.int(field_count + 1L, field_count + count)
      if (tail(target, 1L) > field_capacity) {
        stop("Internal analyst field buffer capacity was exceeded.", call. = FALSE)
      }
      field_owner_id[target] <- as.integer(emit_owner_id)
      field_entity_path_key[target] <- element_path_by_id[emit_owner_id]
      field_source_signature[target] <- source_signature
      field_kind_buffer[target] <- kind
      field_base_buffer[target] <- field_base
      field_value_buffer[target] <- values
      field_storage_type[target] <- storage_type
      field_order[target] <- as.integer(
        nodes$node_order[row_by_node_id[emit_node_id]]
      )
      field_count <- field_count + count

      projected_text_node_count <- as.integer(
        sum(direct_text_count[emit_element[kind != "presence"]])
      )
      projected_empty_element_count <- as.integer(sum(kind == "presence"))
    }
  } else {
    # Frozen R reference implementation.
    for (element_row in seq_len(nrow(index$elements))) {
      node_id <- index$elements$node_id[[element_row]]
      owner_id <- owner_entity[[node_id]]

      if (is.na(owner_id)) {
        next
      }

      canonical_row <- row_by_node_id[[node_id]]
      direct_text <- text_by_parent[[node_id]]

      if (is.null(direct_text)) {
        direct_text <- integer()
      }

      child_elements <- element_children[[node_id]]

      if (is.null(child_elements)) {
        child_elements <- integer()
      }

      attributes <- attributes_by_parent[[node_id]]

      if (is.null(attributes)) {
        attributes <- integer()
      }

      relative <- .xml_analyst_relative_tokens(
        token_paths,
        node_id,
        owner_id
      )
      relative_expanded <- .xml_relative_parts(
        index$expanded_paths[[node_id]],
        index$expanded_paths[[owner_id]]
      )

      if (length(direct_text) > 0L) {
        if (length(child_elements) > 0L) {
          value <- .xml_analyst_subtree_text(
            nodes,
            canonical_row,
            subtree_end_rows = subtree_end_rows,
            text_rows = text_rows
          )
          field_parts <- c(relative, "text_content")
          kind <- "text_content"
        } else {
          value <- paste0(nodes$value[direct_text], collapse = "")
          field_parts <- if (length(relative) == 0L) {
            "value"
          } else {
            relative
          }
          kind <- "value"
        }

        field_base <- paste(field_parts, collapse = "__")
        source_signature <- paste(
          kind,
          .xml_path_key(relative_expanded),
          sep = "\u001e"
        )

        add_field(
          owner_id = owner_id,
          source_signature = source_signature,
          field_base = field_base,
          value = value,
          storage_type = "character",
          order = nodes$node_order[[canonical_row]]
        )
        projected_text_node_count <-
          projected_text_node_count + length(direct_text)
      } else if (
        length(child_elements) == 0L &&
          length(attributes) == 0L
      ) {
        field_parts <- c(relative, "present")
        field_base <- paste(field_parts, collapse = "__")
        source_signature <- paste(
          "presence",
          .xml_path_key(relative_expanded),
          sep = "\u001e"
        )

        add_field(
          owner_id = owner_id,
          source_signature = source_signature,
          field_base = field_base,
          value = TRUE,
          storage_type = "logical",
          order = nodes$node_order[[canonical_row]]
        )
        projected_empty_element_count <-
          projected_empty_element_count + 1L
      }
    }
  }

  if (field_count == 0L) {
    fields <- data.frame(
      owner_id = integer(),
      entity_path_key = character(),
      source_signature = character(),
      field_base = character(),
      value = character(),
      storage_type = character(),
      order = integer(),
      stringsAsFactors = FALSE
    )
  } else {
    used_fields <- seq_len(field_count)
    fields <- data.frame(
      owner_id = field_owner_id[used_fields],
      entity_path_key = field_entity_path_key[used_fields],
      source_signature = field_source_signature[used_fields],
      field_base = field_base_buffer[used_fields],
      storage_type = field_storage_type[used_fields],
      order = field_order[used_fields],
      stringsAsFactors = FALSE
    )
    fields$value <- field_value_buffer[used_fields]
  }
  field_kind <- if (field_count == 0L) {
    character()
  } else {
    field_kind_buffer[seq_len(field_count)]
  }

  field_column_id <- NULL
  column_propagate <- NULL

  if (nrow(fields) > 0L) {
    fields$entity_alias <- unname(alias_by_path[fields$entity_path_key])

    if (identical(analyst_engine, "native")) {
      # P5: catalogue identity and repeated-value layout are structural integer
      # problems. The native kernel replaces occurrence_key string creation,
      # order()+rle(), tapply(max), a second order(), and string match() while
      # preserving the frozen source-order and suffix semantics exactly.
      field_entity_path_id <- as.integer(index$path_id_by_node[fields$owner_id])
      field_layout <- .xml_native_field_layout(
        owner_id = fields$owner_id,
        entity_path_id = field_entity_path_id,
        source_signature = fields$source_signature,
        field_order = fields$order
      )

      catalog <- fields[field_layout$catalog_first_field, , drop = FALSE]
      catalog$column_base <- paste0(
        catalog$entity_alias,
        "__",
        catalog$field_base
      )
      catalog$column_name <- make.unique(catalog$column_base, sep = "__field")

      fields$column_base <- catalog$column_name[field_layout$catalog_id]
      fields$value_occurrence <- as.integer(field_layout$value_occurrence)
      fields$column_name <- fields$column_base
      repeated_value <-
        field_layout$catalog_max_occurrence[field_layout$catalog_id] > 1L
      fields$column_name[repeated_value] <- paste0(
        fields$column_base[repeated_value],
        "__",
        fields$value_occurrence[repeated_value]
      )

      slot_order <- as.integer(field_layout$data_slot_order)
      slot_first_field <- as.integer(field_layout$slot_first_field)
      slot_column_name <- fields$column_name[slot_first_field]
      ordered_slot_name <- slot_column_name[slot_order]

      text_content_slot <- logical(length(slot_order))
      text_fields <- which(field_kind == "text_content")
      if (length(text_fields) > 0L) {
        text_content_slot[unique(field_layout$slot_id[text_fields])] <- TRUE
      }

      if (!anyDuplicated(ordered_slot_name)) {
        # Normal case: the pre-suffix make.unique() policy also leaves final
        # occurrence-suffixed names unique, so column ids are pure integers.
        data_columns <- ordered_slot_name
        column_id_by_slot <- integer(length(slot_order))
        column_id_by_slot[slot_order] <- seq_along(slot_order)
        field_column_id <- column_id_by_slot[field_layout$slot_id]
        column_propagate <- !text_content_slot[slot_order]
      } else {
        # Preserve the frozen edge case where appending __1/__2 can collide
        # with another already-valid catalog base. The old code merged such
        # equal final names via unique()+match(); do the same only across the
        # small slot dictionary rather than all field occurrences.
        data_columns <- unique(ordered_slot_name)
        column_id_by_slot <- match(slot_column_name, data_columns)
        field_column_id <- column_id_by_slot[field_layout$slot_id]
        text_column <- tabulate(
          column_id_by_slot[text_content_slot],
          nbins = length(data_columns)
        ) > 0L
        column_propagate <- !text_column
      }
      text_content_columns <- data_columns[!column_propagate]
    } else {
      fields$catalog_key <- paste(
        fields$entity_path_key,
        fields$source_signature,
        sep = "\u001f"
      )
      first_catalog <- which(!duplicated(fields$catalog_key))
      catalog <- fields[first_catalog, , drop = FALSE]
      catalog$column_base <- paste0(
        catalog$entity_alias,
        "__",
        catalog$field_base
      )
      catalog$column_name <- make.unique(catalog$column_base, sep = "__field")
      column_by_catalog <- stats::setNames(
        catalog$column_name,
        catalog$catalog_key
      )
      fields$column_base <- unname(column_by_catalog[fields$catalog_key])

      occurrence_key <- paste(
        fields$owner_id,
        fields$catalog_key,
        sep = "\u001f"
      )
      occurrence_order <- order(
        occurrence_key,
        fields$order,
        seq_len(nrow(fields))
      )
      occurrence_runs <- rle(occurrence_key[occurrence_order])$lengths
      value_occurrence <- integer(nrow(fields))
      value_occurrence[occurrence_order] <- sequence(occurrence_runs)
      fields$value_occurrence <- value_occurrence

      max_per_catalog <- tapply(
        fields$value_occurrence,
        fields$catalog_key,
        max
      )
      fields$column_name <- fields$column_base
      repeated_value <- max_per_catalog[fields$catalog_key] > 1L
      fields$column_name[repeated_value] <- paste0(
        fields$column_base[repeated_value],
        "__",
        fields$value_occurrence[repeated_value]
      )

      data_columns <- unique(fields$column_name[order(fields$order)])
      text_content_columns <- unique(fields$column_name[
        startsWith(fields$source_signature, paste0("text_content", "\u001e"))
      ])
    }
  } else {
    catalog <- fields
    fields$column_name <- character()
    data_columns <- character()
    text_content_columns <- character()
  }

  entity_row_by_node <- rep.int(NA_integer_, maximum_node_id)
  entity_row_by_node[entity_elements$node_id] <- seq_len(nrow(entity_elements))
  row_by_entity_node <- stats::setNames(
    seq_len(nrow(entity_elements)),
    as.character(entity_elements$node_id)
  )

  if (identical(analyst_engine, "native") && length(data_columns) > 0L) {
    column_total <- tabulate(field_column_id, nbins = length(data_columns))
    column_logical_count <- tabulate(
      field_column_id[fields$storage_type == "logical"],
      nbins = length(data_columns)
    )
    column_logical <- column_total > 0L & column_total == column_logical_count
    # `column_propagate` is supplied directly by the native field layout.
    native_projection <- .xml_native_project_fields(
      entity_node_id = entity_elements$node_id,
      parent_entity_node_id = parent_entity_node_id,
      entity_depth = entity_elements$depth,
      field_column_id = field_column_id,
      field_owner_id = fields$owner_id,
      field_values = fields$value,
      column_logical = column_logical,
      column_propagate = column_propagate
    )

    projection_columns <- stats::setNames(
      native_projection$columns,
      data_columns
    )
    amplification_owner_rows <- stats::setNames(
      as.integer(native_projection$owner_rows),
      data_columns
    )
    amplification_owner_bytes <- stats::setNames(
      as.numeric(native_projection$owner_bytes),
      data_columns
    )
    amplification_emitted_rows <- stats::setNames(
      as.integer(native_projection$emitted_rows),
      data_columns
    )
    amplification_emitted_bytes <- stats::setNames(
      as.numeric(native_projection$emitted_bytes),
      data_columns
    )
    amplification_max_depth <- stats::setNames(
      as.integer(native_projection$max_depth),
      data_columns
    )

    kind_groups <- split(field_kind, field_column_id, drop = TRUE)
    amplification_field_kind <- stats::setNames(
      vapply(
        seq_along(data_columns),
        function(column_id) {
          kinds <- kind_groups[[as.character(column_id)]]
          if (is.null(kinds)) NA_character_ else paste(unique(kinds), collapse = "|")
        },
        character(1)
      ),
      data_columns
    )
  } else {
    child_rows_by_parent <- dense_groups_by_parent(
      seq_len(nrow(entity_elements)),
      parent_entity_node_id
    )

    field_rows_by_column <- if (nrow(fields) == 0L) {
      list()
    } else {
      split(seq_len(nrow(fields)), fields$column_name, drop = TRUE)
    }

    analyst_value_bytes_vector <- function(value) {
      if (length(value) == 0L) {
        return(numeric())
      }

      present <- !is.na(value)
      bytes <- numeric(length(value))

      if (any(present)) {
        bytes[present] <- nchar(
          enc2utf8(as.character(value[present])),
          type = "bytes"
        )
      }

      as.numeric(bytes)
    }

    projection_columns <- stats::setNames(
      vector("list", length(data_columns)),
      data_columns
    )

    amplification_owner_rows <- stats::setNames(
      integer(length(data_columns)),
      data_columns
    )
    amplification_owner_bytes <- stats::setNames(
      numeric(length(data_columns)),
      data_columns
    )
    amplification_emitted_rows <- stats::setNames(
      integer(length(data_columns)),
      data_columns
    )
    amplification_emitted_bytes <- stats::setNames(
      numeric(length(data_columns)),
      data_columns
    )
    amplification_max_depth <- stats::setNames(
      integer(length(data_columns)),
      data_columns
    )
    amplification_field_kind <- stats::setNames(
      rep.int(NA_character_, length(data_columns)),
      data_columns
    )

    for (column in data_columns) {
      rows <- field_rows_by_column[[column]]
      logical_column <- all(fields$storage_type[rows] == "logical")

      output <- if (logical_column) {
        rep.int(NA, nrow(entity_elements))
      } else {
        rep.int(NA_character_, nrow(entity_elements))
      }

      values <- if (logical_column) {
        vapply(
          fields$value[rows],
          function(value) as.logical(value[[1L]]),
          logical(1)
        )
      } else {
        vapply(
          fields$value[rows],
          function(value) as.character(value[[1L]]),
          character(1)
        )
      }

      owner_ids <- fields$owner_id[rows]

      if (!column %in% text_content_columns) {
        for (index in seq_along(rows)) {
          child_rows <- child_rows_by_parent[[owner_ids[[index]]]]

          if (!is.null(child_rows) && length(child_rows) > 0L) {
            output[child_rows] <- values[[index]]
          }
        }
      }

      owner_rows <- entity_row_by_node[owner_ids]
      output[owner_rows] <- values
      projection_columns[[column]] <- output

      amplification_owner_rows[[column]] <- length(unique(owner_ids))
      amplification_owner_bytes[[column]] <- sum(
        analyst_value_bytes_vector(values)
      )
      emitted <- !is.na(output)
      amplification_emitted_rows[[column]] <- sum(emitted)
      amplification_emitted_bytes[[column]] <- sum(
        analyst_value_bytes_vector(output[emitted])
      )

      owner_depths <- entity_elements$depth[
        entity_row_by_node[owner_ids]
      ]
      owner_depths <- owner_depths[!is.na(owner_depths)]
      owner_depth <- if (length(owner_depths) > 0L) min(owner_depths) else NA_integer_

      if (any(emitted) && !is.na(owner_depth)) {
        amplification_max_depth[[column]] <- max(
          0L,
          as.integer(max(entity_elements$depth[emitted]) - owner_depth)
        )
      }

      kinds <- unique(sub("\u001e.*$", "", fields$source_signature[rows]))
      amplification_field_kind[[column]] <- paste(kinds, collapse = "|")
    }
  }

  result <- entity_rows

  if (length(projection_columns) > 0L) {
    projected_data <- as.data.frame(
      projection_columns,
      check.names = FALSE,
      stringsAsFactors = FALSE,
      optional = TRUE
    )
    result <- cbind(result, projected_data)
  }

  amplification <- data.frame(
    column = data_columns,
    field_kind = unname(amplification_field_kind[data_columns]),
    owner_rows = as.integer(amplification_owner_rows[data_columns]),
    emitted_rows = as.integer(amplification_emitted_rows[data_columns]),
    context_rows = as.integer(
      pmax(
        0L,
        amplification_emitted_rows[data_columns] -
          amplification_owner_rows[data_columns]
      )
    ),
    owner_bytes = as.numeric(amplification_owner_bytes[data_columns]),
    emitted_bytes = as.numeric(amplification_emitted_bytes[data_columns]),
    context_bytes = as.numeric(
      pmax(
        0,
        amplification_emitted_bytes[data_columns] -
          amplification_owner_bytes[data_columns]
      )
    ),
    row_amplification = ifelse(
      amplification_owner_rows[data_columns] > 0L,
      amplification_emitted_rows[data_columns] /
        amplification_owner_rows[data_columns],
      NA_real_
    ),
    byte_amplification = ifelse(
      amplification_owner_bytes[data_columns] > 0,
      amplification_emitted_bytes[data_columns] /
        amplification_owner_bytes[data_columns],
      NA_real_
    ),
    max_propagation_depth = as.integer(amplification_max_depth[data_columns]),
    stringsAsFactors = FALSE
  )

  finite_row_amplification <- amplification$row_amplification[
    is.finite(amplification$row_amplification)
  ]
  finite_byte_amplification <- amplification$byte_amplification[
    is.finite(amplification$byte_amplification)
  ]
  total_owner_bytes <- sum(amplification$owner_bytes)
  total_emitted_bytes <- sum(amplification$emitted_bytes)

  amplification_summary <- list(
    columns = as.integer(nrow(amplification)),
    owner_rows = as.numeric(sum(amplification$owner_rows)),
    emitted_rows = as.numeric(sum(amplification$emitted_rows)),
    context_rows = as.numeric(sum(amplification$context_rows)),
    owner_bytes = as.numeric(total_owner_bytes),
    emitted_bytes = as.numeric(total_emitted_bytes),
    context_bytes = as.numeric(sum(amplification$context_bytes)),
    byte_amplification = if (total_owner_bytes > 0) {
      as.numeric(total_emitted_bytes / total_owner_bytes)
    } else {
      NA_real_
    },
    max_field_row_amplification = if (length(finite_row_amplification) > 0L) {
      as.numeric(max(finite_row_amplification))
    } else {
      NA_real_
    },
    max_field_byte_amplification = if (length(finite_byte_amplification) > 0L) {
      as.numeric(max(finite_byte_amplification))
    } else {
      NA_real_
    },
    max_propagation_depth = if (nrow(amplification) > 0L) {
      as.integer(max(amplification$max_propagation_depth))
    } else {
      0L
    }
  )

  # Only misc/provenance rows need an explicit owner-context map. Avoid
  # constructing thousands of per-entity named lists when the document has no
  # retained misc nodes.
  misc_rows <- if (isTRUE(include_misc)) {
    which(
      !nodes$node_type %in% c(
        "document", "element", "attribute", "text", "cdata"
      )
    )
  } else {
    integer()
  }

  context_maps <- NULL

  if (length(misc_rows) > 0L) {
    context_maps <- stats::setNames(
      vector("list", nrow(entity_elements)),
      as.character(entity_elements$node_id)
    )

    if (nrow(fields) > 0L) {
      field_rows_by_owner <- split(
        seq_len(nrow(fields)),
        fields$owner_id,
        drop = TRUE
      )

      for (owner in names(field_rows_by_owner)) {
        rows <- field_rows_by_owner[[owner]]
        rows <- rows[
          !fields$column_name[rows] %in% text_content_columns
        ]

        if (length(rows) == 0L) {
          next
        }

        rows <- rows[order(fields$order[rows], fields$value_occurrence[rows])]
        values <- vector("list", length(rows))
        names(values) <- fields$column_name[rows]

        for (index in seq_along(rows)) {
          values[[index]] <- fields$value[[rows[[index]]]]
        }

        context_maps[[owner]] <- values
      }
    }
  }

  # Comments, processing instructions, and any retained non-data node kinds are
  # optional rows in the same table. They preserve audit-relevant XML material
  # without forcing analysts back to the source document.
  if (isTRUE(include_misc)) {
    if (length(misc_rows) > 0L) {
      misc <- result[rep.int(NA_integer_, length(misc_rows)), , drop = FALSE]
      misc$xml_document_id <- nodes$document_id[misc_rows]
      misc$xml_entity <- "xml_misc"
      misc$xml_entity_id <- sprintf("m%09d", nodes$node_id[misc_rows])
      misc$xml_occurrence <- seq_along(misc_rows)
      misc$xml_node_id <- nodes$node_id[misc_rows]
      misc$xml_parent_node_id <- nodes$parent_id[misc_rows]
      misc$xml_depth <- nodes$depth[misc_rows]
      misc$xml_source_path <- NA_character_
      misc$xml_namespace_uri <- nodes$namespace_uri[misc_rows]
      misc$xml_namespaces <- namespace_info$description

      if (!"xml_misc__type" %in% names(misc)) {
        result$xml_misc__type <- NA_character_
        result$xml_misc__name <- NA_character_
        result$xml_misc__value <- NA_character_
        misc$xml_misc__type <- NA_character_
        misc$xml_misc__name <- NA_character_
        misc$xml_misc__value <- NA_character_
        data_columns <- c(
          data_columns,
          "xml_misc__type",
          "xml_misc__name",
          "xml_misc__value"
        )
      }

      for (index in seq_along(misc_rows)) {
        source_row <- misc_rows[[index]]
        node_id <- nodes$node_id[[source_row]]
        parent_id <- nodes$parent_id[[source_row]]
        owner_id <- if (
          !is.na(parent_id) &&
            parent_id <= length(owner_entity)
        ) {
          owner_entity[[parent_id]]
        } else {
          NA_integer_
        }

        if (!is.na(owner_id)) {
          owner_row <- row_by_entity_node[[as.character(owner_id)]]
          context <- context_maps[[as.character(owner_id)]]
          misc$xml_parent_entity[[index]] <- entity_elements$entity[[owner_row]]
          misc$xml_parent_entity_id[[index]] <- sprintf("e%09d", owner_id)

          for (name in names(context)) {
            misc[[name]][[index]] <- context[[name]]
          }
        }

        parent_path <- if (
          !is.na(parent_id) &&
            parent_id <= length(element_display_path_by_id)
        ) {
          element_display_path_by_id[[parent_id]]
        } else {
          NA_character_
        }
        misc$xml_source_path[[index]] <- if (
          is.na(parent_path) || !nzchar(parent_path)
        ) {
          paste0("#", nodes$node_type[[source_row]])
        } else {
          paste0(parent_path, "/#", nodes$node_type[[source_row]])
        }
        misc$xml_misc__type[[index]] <- nodes$node_type[[source_row]]
        misc$xml_misc__name[[index]] <- nodes$qualified_name[[source_row]]
        misc$xml_misc__value[[index]] <- nodes$value[[source_row]]
      }

      result <- rbind(result, misc)
      result <- result[order(result$xml_node_id), , drop = FALSE]
      rownames(result) <- NULL
    }
  }

  result <- .xml_analyst_apply_types(
    result,
    data_columns = data_columns,
    infer_types = infer_types,
    analyst_engine = analyst_engine
  )
  result <- .xml_analyst_key_candidates(result, data_columns)

  metadata_columns <- c(
    "xml_document_id",
    "xml_entity",
    "xml_entity_id",
    "xml_parent_entity",
    "xml_parent_entity_id",
    "xml_occurrence",
    "xml_node_id",
    "xml_parent_node_id",
    "xml_depth",
    "xml_source_path",
    "xml_namespace_uri",
    "xml_key_column",
    "xml_key_value",
    "xml_namespaces"
  )
  data_columns <- setdiff(names(result), metadata_columns)
  result <- result[, c(metadata_columns, data_columns), drop = FALSE]
  result <- tibble::as_tibble(result)

  attr(result, "xml_analyst_metadata") <- list(
    entity_paths = entity_paths,
    aliases = alias_by_path,
    namespaces = namespace_info$description,
    column_sources = if (nrow(fields) == 0L) {
      data.frame()
    } else if (identical(analyst_engine, "native")) {
      # The native slot dictionary already contains one representative field
      # per final catalogue/occurrence column. De-duplicate this small table to
      # preserve even the rare final-name collision semantics without running
      # unique.data.frame() over every field occurrence.
      unique(
        fields[
          as.integer(field_layout$slot_first_field),
          c(
            "entity_path_key",
            "source_signature",
            "column_name",
            "storage_type"
          ),
          drop = FALSE
        ]
      )
    } else {
      unique(
        fields[
          ,
          c(
            "entity_path_key",
            "source_signature",
            "column_name",
            "storage_type"
          ),
          drop = FALSE
        ]
      )
    },
    amplification = amplification,
    amplification_summary = amplification_summary,
    audit = list(
      canonical_nodes = as.integer(nrow(nodes)),
      expected_entity_rows = as.integer(sum(entity_paths$occurrences)),
      emitted_entity_rows = as.integer(nrow(entity_elements)),
      canonical_attributes = as.integer(length(attribute_rows)),
      projected_attributes = as.integer(projected_attribute_count),
      canonical_text_nodes = as.integer(
        sum(!is.na(owner_entity[nodes$parent_id[text_rows]]))
      ),
      projected_text_nodes = as.integer(projected_text_node_count),
      empty_elements_projected = as.integer(projected_empty_element_count),
      misc_nodes = as.integer(
        sum(
          !nodes$node_type %in% c(
            "document", "element", "attribute", "text", "cdata"
          )
        )
      )
    )
  )

  result
}


#' Expand ancestor context on demand inside an analyst table
#'
#' The stored analyst table carries only immediate-parent context. This helper
#' materialises more distant ancestor fields when a particular analysis needs
#' them, without reopening the XML and without making every stored row fully
#' denormalised by default.
#'
#' @param x A table returned by `xml_analyst_table()` or
#'   `rectangle_xml_analyst()`.
#' @param entity Optional entity name or vector of entity names to retain.
#'   `NULL` keeps all rows.
#' @param levels Maximum number of ancestor entity hops to inspect. `Inf`
#'   expands the complete ancestor chain.
#' @return A tibble with the same columns as `x`; missing analytical cells are
#'   filled from the owning fields of requested ancestors.
xml_analyst_expand_context <- function(x, entity = NULL, levels = Inf) {
  required <- c(
    "xml_entity",
    "xml_entity_id",
    "xml_parent_entity_id"
  )
  missing <- setdiff(required, names(x))
  if (length(missing) > 0L) {
    stop(
      paste0(
        "`x` is not an analyst table; missing column(s): ",
        paste(missing, collapse = ", "),
        "."
      ),
      call. = FALSE
    )
  }

  if (
    length(levels) != 1L ||
      is.na(levels) ||
      (!is.infinite(levels) && (levels < 0 || levels != as.integer(levels)))
  ) {
    stop("`levels` must be a non-negative integer or `Inf`.", call. = FALSE)
  }

  if (anyDuplicated(x$xml_entity_id)) {
    stop("`xml_entity_id` must be unique before context expansion.", call. = FALSE)
  }

  rows <- if (is.null(entity)) {
    seq_len(nrow(x))
  } else {
    which(x$xml_entity %in% entity)
  }

  result <- x[rows, , drop = FALSE]
  if (nrow(result) == 0L || identical(levels, 0L)) {
    return(tibble::as_tibble(result))
  }

  data_columns <- names(x)[!startsWith(names(x), "xml_")]
  row_by_id <- stats::setNames(seq_len(nrow(x)), x$xml_entity_id)

  for (out_row in seq_along(rows)) {
    source_row <- rows[[out_row]]
    parent_id <- x$xml_parent_entity_id[[source_row]]
    hop <- 0L

    while (
      !is.na(parent_id) && nzchar(parent_id) &&
        (is.infinite(levels) || hop < levels)
    ) {
      parent_row <- row_by_id[[parent_id]]
      if (is.null(parent_row) || is.na(parent_row)) {
        stop(
          paste0("Unknown `xml_parent_entity_id`: ", parent_id, "."),
          call. = FALSE
        )
      }

      parent_entity <- x$xml_entity[[parent_row]]
      own_columns <- data_columns[
        startsWith(data_columns, paste0(parent_entity, "__"))
      ]

      for (column in own_columns) {
        if (
          is.na(result[[column]][[out_row]]) &&
            !is.na(x[[column]][[parent_row]])
        ) {
          result[[column]][[out_row]] <- x[[column]][[parent_row]]
        }
      }

      parent_id <- x$xml_parent_entity_id[[parent_row]]
      hop <- hop + 1L
    }
  }

  tibble::as_tibble(result)
}


#' Read one XML file and return its self-contained analyst table
rectangle_xml_analyst <- function(
  file,
  whitespace = c("drop_blank", "preserve"),
  infer_types = TRUE,
  include_misc = TRUE
) {
  file <- .validate_one_string(file, "file")
  whitespace <- match.arg(whitespace)

  # P4 direct native path: the canonical tibble is a public/audit API, not a
  # necessary intermediate representation for XML -> analyst conversion.  When
  # both native engines are requested, consume the canonical column bundle as
  # a plain internal data frame and avoid two redundant validation/tibble
  # layers.  Public `xml_to_nodes_memory()` is unchanged and remains fully
  # validated and byte/attribute compatible with the frozen canonical contract.
  if (
    identical(.xml_requested_canonical_engine(), "native") &&
      identical(.xml_requested_analyst_engine(), "native")
  ) {
    if (!file.exists(file)) {
      stop(sprintf("XML file does not exist: %s", file), call. = FALSE)
    }
    normalized_file <- normalizePath(file, winslash = "/", mustWork = TRUE)
    document_id <- basename(normalized_file)
    nodes <- .xml_to_nodes_memory_native_raw(
      file = normalized_file,
      document_id = document_id,
      whitespace = whitespace
    )
    return(
      xml_analyst_table(
        nodes,
        infer_types = infer_types,
        include_misc = include_misc,
        .validate_nodes = FALSE
      )
    )
  }

  nodes <- xml_to_nodes_memory(file, whitespace = whitespace)
  xml_analyst_table(
    nodes,
    infer_types = infer_types,
    include_misc = include_misc
  )
}


#' Write the analyst table transactionally as one CSV file
rectangle_xml_analyst_csv <- function(
  file,
  output,
  whitespace = c("drop_blank", "preserve"),
  infer_types = TRUE,
  include_misc = TRUE,
  na = "\\N",
  overwrite = FALSE
) {
  file <- .validate_one_string(file, "file")
  output <- .validate_one_string(output, "output")
  whitespace <- match.arg(whitespace)
  na <- .validate_one_string(na, "na", allow_empty = TRUE)

  if (file.exists(output) && !isTRUE(overwrite)) {
    stop(
      "The analyst CSV already exists; use `overwrite = TRUE` explicitly.",
      call. = FALSE
    )
  }

  directory <- dirname(output)

  if (!dir.exists(directory)) {
    dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  }

  temporary <- tempfile(
    pattern = paste0(".", basename(output), "-"),
    tmpdir = directory,
    fileext = ".part"
  )
  on.exit(if (file.exists(temporary)) unlink(temporary), add = TRUE)

  result <- rectangle_xml_analyst(
    file,
    whitespace = whitespace,
    infer_types = infer_types,
    include_misc = include_misc
  )

  character_columns <- vapply(result, is.character, logical(1))
  sentinel_collision <- any(
    vapply(
      result[character_columns],
      function(column) any(!is.na(column) & column == na),
      logical(1)
    )
  )

  if (sentinel_collision) {
    stop(
      paste0(
        "The CSV missing-value sentinel `",
        na,
        "` occurs as genuine source data. Supply a different `na` value " ,
        "so missing values remain distinguishable from source strings."
      ),
      call. = FALSE
    )
  }

  utils::write.table(
    result,
    file = temporary,
    sep = ",",
    row.names = FALSE,
    col.names = TRUE,
    quote = TRUE,
    na = na,
    qmethod = "double",
    fileEncoding = "UTF-8"
  )

  if (file.exists(output) && isTRUE(overwrite)) {
    unlink(output)
  }

  if (!file.rename(temporary, output)) {
    stop("Could not publish the completed analyst CSV.", call. = FALSE)
  }

  invisible(result)
}


#' Write the analyst table transactionally as one Parquet file
rectangle_xml_analyst_parquet <- function(
  file,
  output,
  whitespace = c("drop_blank", "preserve"),
  infer_types = TRUE,
  include_misc = TRUE,
  overwrite = FALSE,
  compression = "snappy"
) {
  .require_xml_rectangle_package("arrow")
  file <- .validate_one_string(file, "file")
  output <- .validate_one_string(output, "output")
  whitespace <- match.arg(whitespace)

  if (file.exists(output) && !isTRUE(overwrite)) {
    stop(
      "The analyst Parquet file already exists; use `overwrite = TRUE` explicitly.",
      call. = FALSE
    )
  }

  directory <- dirname(output)

  if (!dir.exists(directory)) {
    dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  }

  temporary <- tempfile(
    pattern = paste0(".", basename(output), "-"),
    tmpdir = directory,
    fileext = ".parquet"
  )
  on.exit(if (file.exists(temporary)) unlink(temporary), add = TRUE)

  result <- rectangle_xml_analyst(
    file,
    whitespace = whitespace,
    infer_types = infer_types,
    include_misc = include_misc
  )

  arrow::write_parquet(
    result,
    sink = temporary,
    compression = compression
  )

  if (file.exists(output) && isTRUE(overwrite)) {
    unlink(output)
  }

  if (!file.rename(temporary, output)) {
    stop("Could not publish the completed analyst Parquet file.", call. = FALSE)
  }

  invisible(result)
}
