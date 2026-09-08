#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>

#include <libxml/parser.h>
#include <libxml/tree.h>

#include <limits.h>
#include <math.h>
#include <errno.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/*
 * Native engine for the xmlrectr R package.
 *
 * This is the validated standalone native implementation adapted only to the
 * package DLL registration name. Design goals remain unchanged:
 *   - preserve the canonical node-table contract exactly;
 *   - parse once with libxml2 and traverse the tree directly in C;
 *   - avoid XPath and per-node R <-> C calls;
 *   - retain the R implementation as the semantic reference/fallback engine.
 *
 * Analyst semantics remain in R. Native code accelerates structural indexing,
 * occurrence/layout work, type inference, and field projection without
 * changing entity choice, naming, typing, or source-key policy.
 */

typedef struct {
  R_xlen_t count;
  int drop_blank;
} count_state;

typedef struct {
  SEXP document_id;
  SEXP node_id;
  SEXP parent_id;
  SEXP node_order;
  SEXP sibling_order;
  SEXP depth;
  SEXP node_type;
  SEXP qualified_name;
  SEXP local_name;
  SEXP prefix;
  SEXP namespace_uri;
  SEXP value;

  xmlDocPtr doc;
  R_xlen_t row;
  int drop_blank;
} fill_state;

static int is_blank_xml_text(const xmlChar *value) {
  if (value == NULL) {
    return 1;
  }

  const unsigned char *p = (const unsigned char *) value;
  while (*p != '\0') {
    switch (*p) {
      case ' ':
      case '\t':
      case '\r':
      case '\n':
      case '\f':
      case '\v':
        ++p;
        break;
      default:
        return 0;
    }
  }
  return 1;
}

static int should_retain_node(xmlNodePtr node, int drop_blank) {
  if (node == NULL) {
    return 0;
  }

  /* Keep the native engine semantically identical to the frozen xml2/XPath
   * canonical reader: namespace declarations and the document DTD/DOCTYPE
   * declaration itself are structural parser metadata, not canonical rows.
   * DTD-based documents otherwise acquire one extra top-level xml_misc row and
   * all subsequent generated node ids shift by one. */
  if (node->type == XML_NAMESPACE_DECL ||
      node->type == XML_DTD_NODE ||
      node->type == XML_DOCUMENT_TYPE_NODE) {
    return 0;
  }

  if (drop_blank && node->type == XML_TEXT_NODE) {
    return !is_blank_xml_text(node->content);
  }

  return 1;
}

static const char *canonical_node_type(xmlElementType type) {
  switch (type) {
    case XML_ELEMENT_NODE:       return "element";
    case XML_ATTRIBUTE_NODE:     return "attribute";
    case XML_TEXT_NODE:          return "text";
    case XML_CDATA_SECTION_NODE: return "cdata";
    case XML_ENTITY_REF_NODE:    return "entity_ref";
    case XML_ENTITY_NODE:        return "entity";
    case XML_PI_NODE:            return "pi";
    case XML_COMMENT_NODE:       return "comment";
    case XML_DOCUMENT_NODE:      return "document";
    case XML_DOCUMENT_TYPE_NODE: return "dtd";
    case XML_DOCUMENT_FRAG_NODE: return "document_fragment";
    case XML_NOTATION_NODE:      return "notation";
    case XML_HTML_DOCUMENT_NODE: return "html_document";
    case XML_DTD_NODE:           return "dtd";
    case XML_ELEMENT_DECL:       return "element_decl";
    case XML_ATTRIBUTE_DECL:     return "attribute_decl";
    case XML_ENTITY_DECL:        return "entity_decl";
#ifdef XML_XINCLUDE_START
    case XML_XINCLUDE_START:     return "xinclude_start";
#endif
#ifdef XML_XINCLUDE_END
    case XML_XINCLUDE_END:       return "xinclude_end";
#endif
    default:                      return "unknown";
  }
}

static int node_has_canonical_name(xmlElementType type) {
  return type == XML_ELEMENT_NODE ||
         type == XML_ATTRIBUTE_NODE ||
         type == XML_PI_NODE;
}

static void count_one_node(xmlNodePtr node, count_state *state);

static void count_children(xmlNodePtr first, count_state *state) {
  for (xmlNodePtr node = first; node != NULL; node = node->next) {
    count_one_node(node, state);
  }
}

static void count_one_node(xmlNodePtr node, count_state *state) {
  if (!should_retain_node(node, state->drop_blank)) {
    return;
  }

  if (state->count >= INT_MAX - 1) {
    Rf_error("Native canonical reader cannot represent more than INT_MAX nodes.");
  }

  state->count += 1;

  if (node->type == XML_ELEMENT_NODE) {
    for (xmlAttrPtr attr = node->properties; attr != NULL; attr = attr->next) {
      state->count += 1;
      if (state->count >= INT_MAX - 1) {
        Rf_error("Native canonical reader cannot represent more than INT_MAX nodes.");
      }
    }
  }

  if (node->type == XML_ELEMENT_NODE && node->children != NULL) {
    count_children(node->children, state);
  }
}

static SEXP utf8_scalar_or_na(const xmlChar *value) {
  if (value == NULL) {
    return NA_STRING;
  }
  return Rf_mkCharCE((const char *) value, CE_UTF8);
}

static SEXP make_qualified_name(const xmlChar *local, const xmlChar *prefix) {
  if (local == NULL) {
    return NA_STRING;
  }

  if (prefix == NULL || prefix[0] == '\0') {
    return Rf_mkCharCE((const char *) local, CE_UTF8);
  }

  size_t prefix_len = strlen((const char *) prefix);
  size_t local_len = strlen((const char *) local);
  size_t total = prefix_len + 1u + local_len;
  char *buffer = (char *) R_alloc(total + 1u, sizeof(char));
  memcpy(buffer, prefix, prefix_len);
  buffer[prefix_len] = ':';
  memcpy(buffer + prefix_len + 1u, local, local_len);
  buffer[total] = '\0';
  return Rf_mkCharCE(buffer, CE_UTF8);
}

static void set_named_metadata(
  fill_state *state,
  R_xlen_t row,
  xmlNodePtr node
) {
  if (!node_has_canonical_name(node->type)) {
    SET_STRING_ELT(state->qualified_name, row, NA_STRING);
    SET_STRING_ELT(state->local_name, row, NA_STRING);
    SET_STRING_ELT(state->prefix, row, NA_STRING);
    SET_STRING_ELT(state->namespace_uri, row, NA_STRING);
    return;
  }

  const xmlChar *local = node->name;
  const xmlChar *prefix = NULL;
  const xmlChar *uri = NULL;

  if (node->type == XML_PI_NODE) {
    /*
     * XPath name(.) is lexical for processing instructions.  Mirror the
     * frozen R implementation's colon split even though PIs do not carry an
     * XML namespace node in libxml2.
     */
    const char *qname = (const char *) node->name;
    const char *colon = qname == NULL ? NULL : strchr(qname, ':');

    SET_STRING_ELT(state->qualified_name, row, utf8_scalar_or_na(node->name));
    SET_STRING_ELT(state->namespace_uri, row, Rf_mkChar(""));

    if (colon == NULL) {
      SET_STRING_ELT(state->local_name, row, utf8_scalar_or_na(node->name));
      SET_STRING_ELT(state->prefix, row, Rf_mkChar(""));
    } else {
      size_t prefix_len = (size_t) (colon - qname);
      char *prefix_buffer = (char *) R_alloc(prefix_len + 1u, sizeof(char));
      memcpy(prefix_buffer, qname, prefix_len);
      prefix_buffer[prefix_len] = '\0';

      SET_STRING_ELT(
        state->prefix,
        row,
        Rf_mkCharCE(prefix_buffer, CE_UTF8)
      );
      SET_STRING_ELT(
        state->local_name,
        row,
        Rf_mkCharCE(colon + 1, CE_UTF8)
      );
    }
    return;
  }

  if (node->ns != NULL) {
    prefix = node->ns->prefix;
    uri = node->ns->href;
  }

  SET_STRING_ELT(
    state->qualified_name,
    row,
    make_qualified_name(local, prefix)
  );
  SET_STRING_ELT(state->local_name, row, utf8_scalar_or_na(local));

  if (prefix == NULL) {
    SET_STRING_ELT(state->prefix, row, Rf_mkChar(""));
  } else {
    SET_STRING_ELT(state->prefix, row, utf8_scalar_or_na(prefix));
  }

  if (uri == NULL) {
    SET_STRING_ELT(state->namespace_uri, row, Rf_mkChar(""));
  } else {
    SET_STRING_ELT(state->namespace_uri, row, utf8_scalar_or_na(uri));
  }
}

static SEXP node_value(xmlDocPtr doc, xmlNodePtr node) {
  if (node->type == XML_DOCUMENT_NODE || node->type == XML_ELEMENT_NODE) {
    return NA_STRING;
  }

  xmlChar *content = NULL;

  if (node->type == XML_ATTRIBUTE_NODE) {
    xmlAttrPtr attr = (xmlAttrPtr) node;
    content = xmlNodeListGetString(doc, attr->children, 1);
  } else {
    content = xmlNodeGetContent(node);
  }

  if (content == NULL) {
    return NA_STRING;
  }

  SEXP ans = PROTECT(Rf_mkCharCE((const char *) content, CE_UTF8));
  xmlFree(content);
  UNPROTECT(1);
  return ans;
}

static void fill_one_node(
  xmlNodePtr node,
  int parent_id,
  int sibling_order,
  int depth,
  fill_state *state
);

static void fill_children(
  xmlNodePtr first,
  int parent_id,
  int depth,
  fill_state *state
) {
  int retained_position = 0;

  for (xmlNodePtr node = first; node != NULL; node = node->next) {
    if (!should_retain_node(node, state->drop_blank)) {
      continue;
    }

    retained_position += 1;
    fill_one_node(node, parent_id, retained_position, depth, state);
  }
}

static void fill_attribute(
  xmlAttrPtr attr,
  int parent_id,
  int depth,
  fill_state *state
) {
  R_xlen_t row = state->row;
  state->row += 1;

  INTEGER(state->node_id)[row] = (int) row + 1;
  INTEGER(state->parent_id)[row] = parent_id;
  INTEGER(state->node_order)[row] = (int) row + 1;
  INTEGER(state->sibling_order)[row] = NA_INTEGER;
  INTEGER(state->depth)[row] = depth;
  SET_STRING_ELT(state->node_type, row, Rf_mkChar("attribute"));

  set_named_metadata(state, row, (xmlNodePtr) attr);
  SET_STRING_ELT(state->value, row, node_value(state->doc, (xmlNodePtr) attr));
}

static void fill_one_node(
  xmlNodePtr node,
  int parent_id,
  int sibling_order,
  int depth,
  fill_state *state
) {
  R_xlen_t row = state->row;
  state->row += 1;

  int current_id = (int) row + 1;

  INTEGER(state->node_id)[row] = current_id;
  INTEGER(state->parent_id)[row] = parent_id;
  INTEGER(state->node_order)[row] = current_id;
  INTEGER(state->sibling_order)[row] = sibling_order;
  INTEGER(state->depth)[row] = depth;
  SET_STRING_ELT(
    state->node_type,
    row,
    Rf_mkChar(canonical_node_type(node->type))
  );

  set_named_metadata(state, row, node);
  SET_STRING_ELT(state->value, row, node_value(state->doc, node));

  if (node->type == XML_ELEMENT_NODE) {
    for (xmlAttrPtr attr = node->properties; attr != NULL; attr = attr->next) {
      fill_attribute(attr, current_id, depth + 1, state);
    }
  }

  if (node->type == XML_ELEMENT_NODE && node->children != NULL) {
    fill_children(node->children, current_id, depth + 1, state);
  }
}


SEXP C_xmlrect_native_read(
  SEXP file_sexp,
  SEXP document_id_sexp,
  SEXP drop_blank_sexp
) {
  if (TYPEOF(file_sexp) != STRSXP || XLENGTH(file_sexp) != 1 ||
      STRING_ELT(file_sexp, 0) == NA_STRING) {
    Rf_error("`file` must be one non-missing string.");
  }

  if (TYPEOF(document_id_sexp) != STRSXP || XLENGTH(document_id_sexp) != 1 ||
      STRING_ELT(document_id_sexp, 0) == NA_STRING) {
    Rf_error("`document_id` must be one non-missing string.");
  }

  int drop_blank = Rf_asLogical(drop_blank_sexp);
  if (drop_blank == NA_LOGICAL) {
    Rf_error("`drop_blank` must be TRUE or FALSE.");
  }

  const char *file = CHAR(STRING_ELT(file_sexp, 0));

  xmlResetLastError();
  xmlDocPtr doc = xmlReadFile(file, NULL, XML_PARSE_NONET);
  if (doc == NULL) {
    const xmlError *err = xmlGetLastError();
    if (err != NULL && err->message != NULL) {
      Rf_error("%s", err->message);
    }
    Rf_error("libxml2 could not parse the XML document.");
  }

  count_state counter;
  counter.count = 1; /* synthetic document row */
  counter.drop_blank = drop_blank;
  count_children(doc->children, &counter);

  R_xlen_t n = counter.count;

  int protect_count = 0;

  SEXP document_id = PROTECT(Rf_allocVector(STRSXP, n)); protect_count++;
  SEXP node_id = PROTECT(Rf_allocVector(INTSXP, n)); protect_count++;
  SEXP parent_id = PROTECT(Rf_allocVector(INTSXP, n)); protect_count++;
  SEXP node_order = PROTECT(Rf_allocVector(INTSXP, n)); protect_count++;
  SEXP sibling_order = PROTECT(Rf_allocVector(INTSXP, n)); protect_count++;
  SEXP depth = PROTECT(Rf_allocVector(INTSXP, n)); protect_count++;
  SEXP node_type = PROTECT(Rf_allocVector(STRSXP, n)); protect_count++;
  SEXP qualified_name = PROTECT(Rf_allocVector(STRSXP, n)); protect_count++;
  SEXP local_name = PROTECT(Rf_allocVector(STRSXP, n)); protect_count++;
  SEXP prefix = PROTECT(Rf_allocVector(STRSXP, n)); protect_count++;
  SEXP namespace_uri = PROTECT(Rf_allocVector(STRSXP, n)); protect_count++;
  SEXP value = PROTECT(Rf_allocVector(STRSXP, n)); protect_count++;

  SEXP doc_id_chr = STRING_ELT(document_id_sexp, 0);
  for (R_xlen_t i = 0; i < n; ++i) {
    SET_STRING_ELT(document_id, i, doc_id_chr);
    INTEGER(parent_id)[i] = NA_INTEGER;
    INTEGER(sibling_order)[i] = NA_INTEGER;
    INTEGER(depth)[i] = NA_INTEGER;
    SET_STRING_ELT(node_type, i, NA_STRING);
    SET_STRING_ELT(qualified_name, i, NA_STRING);
    SET_STRING_ELT(local_name, i, NA_STRING);
    SET_STRING_ELT(prefix, i, NA_STRING);
    SET_STRING_ELT(namespace_uri, i, NA_STRING);
    SET_STRING_ELT(value, i, NA_STRING);
  }

  /* Synthetic document row. */
  INTEGER(node_id)[0] = 1;
  INTEGER(parent_id)[0] = NA_INTEGER;
  INTEGER(node_order)[0] = 1;
  INTEGER(sibling_order)[0] = NA_INTEGER;
  INTEGER(depth)[0] = 0;
  SET_STRING_ELT(node_type, 0, Rf_mkChar("document"));

  fill_state state;
  state.document_id = document_id;
  state.node_id = node_id;
  state.parent_id = parent_id;
  state.node_order = node_order;
  state.sibling_order = sibling_order;
  state.depth = depth;
  state.node_type = node_type;
  state.qualified_name = qualified_name;
  state.local_name = local_name;
  state.prefix = prefix;
  state.namespace_uri = namespace_uri;
  state.value = value;
  state.doc = doc;
  state.row = 1;
  state.drop_blank = drop_blank;

  fill_children(doc->children, 1, 1, &state);

  if (state.row != n) {
    xmlFreeDoc(doc);
    UNPROTECT(protect_count);
    Rf_error("Native canonical reader internal node-count mismatch.");
  }

  xmlFreeDoc(doc);

  SEXP result = PROTECT(Rf_allocVector(VECSXP, 12)); protect_count++;
  SET_VECTOR_ELT(result, 0, document_id);
  SET_VECTOR_ELT(result, 1, node_id);
  SET_VECTOR_ELT(result, 2, parent_id);
  SET_VECTOR_ELT(result, 3, node_order);
  SET_VECTOR_ELT(result, 4, sibling_order);
  SET_VECTOR_ELT(result, 5, depth);
  SET_VECTOR_ELT(result, 6, node_type);
  SET_VECTOR_ELT(result, 7, qualified_name);
  SET_VECTOR_ELT(result, 8, local_name);
  SET_VECTOR_ELT(result, 9, prefix);
  SET_VECTOR_ELT(result, 10, namespace_uri);
  SET_VECTOR_ELT(result, 11, value);

  SEXP names = PROTECT(Rf_allocVector(STRSXP, 12)); protect_count++;
  const char *column_names[12] = {
    "document_id", "node_id", "parent_id", "node_order",
    "sibling_order", "depth", "node_type", "qualified_name",
    "local_name", "prefix", "namespace_uri", "value"
  };
  for (int i = 0; i < 12; ++i) {
    SET_STRING_ELT(names, i, Rf_mkChar(column_names[i]));
  }
  Rf_setAttrib(result, R_NamesSymbol, names);

  UNPROTECT(protect_count);
  return result;
}



/* -------------------------------------------------------------------------
 * Native analyst structural plan
 * -------------------------------------------------------------------------
 *
 * The public analyst table remains an R object and its semantic rules remain
 * in R.  This helper only replaces repeated tree-index bookkeeping with dense
 * integer arrays.  Paths are dictionary-coded by the structural tuple
 * (parent_path_id, local_name, namespace_uri), so a path is represented once
 * regardless of how many times it occurs in the document.
 */

static unsigned long long hash_bytes(const char *s) {
  unsigned long long h = 1469598103934665603ULL;
  if (s == NULL) return h;
  while (*s) {
    h ^= (unsigned char) *s++;
    h *= 1099511628211ULL;
  }
  return h;
}

static unsigned long long mix_u64(unsigned long long h, unsigned long long x) {
  h ^= x + 0x9e3779b97f4a7c15ULL + (h << 6) + (h >> 2);
  return h;
}

static int same_string(SEXP a, SEXP b) {
  if (a == b) return 1;
  if (a == NA_STRING || b == NA_STRING) return 0;
  return strcmp(CHAR(a), CHAR(b)) == 0;
}

static unsigned long long hash_path_key(int parent_path, SEXP local, SEXP ns) {
  unsigned long long h = 1469598103934665603ULL;
  h = mix_u64(h, (unsigned long long) (unsigned int) parent_path);
  h = mix_u64(h, hash_bytes(local == NA_STRING ? "<NA>" : CHAR(local)));
  h = mix_u64(h, hash_bytes(ns == NA_STRING ? "<NA>" : CHAR(ns)));
  return h;
}

static unsigned long long hash_sibling_key(int parent_node, SEXP local, SEXP ns) {
  unsigned long long h = 1099511628211ULL;
  h = mix_u64(h, (unsigned long long) (unsigned int) parent_node);
  h = mix_u64(h, hash_bytes(local == NA_STRING ? "<NA>" : CHAR(local)));
  h = mix_u64(h, hash_bytes(ns == NA_STRING ? "<NA>" : CHAR(ns)));
  return h;
}

static R_xlen_t next_pow2(R_xlen_t x) {
  R_xlen_t p = 1;
  while (p < x) {
    if (p > R_XLEN_T_MAX / 2) Rf_error("Native analyst hash table is too large.");
    p <<= 1;
  }
  return p;
}

SEXP C_xmlrect_native_analyst_plan(
  SEXP node_id_sexp,
  SEXP parent_id_sexp,
  SEXP depth_sexp,
  SEXP node_type_sexp,
  SEXP local_name_sexp,
  SEXP namespace_uri_sexp
) {
  if (TYPEOF(node_id_sexp) != INTSXP ||
      TYPEOF(parent_id_sexp) != INTSXP ||
      TYPEOF(depth_sexp) != INTSXP ||
      TYPEOF(node_type_sexp) != STRSXP ||
      TYPEOF(local_name_sexp) != STRSXP ||
      TYPEOF(namespace_uri_sexp) != STRSXP) {
    Rf_error("Native analyst plan received unexpected canonical column types.");
  }

  R_xlen_t n = XLENGTH(node_id_sexp);
  if (XLENGTH(parent_id_sexp) != n || XLENGTH(depth_sexp) != n ||
      XLENGTH(node_type_sexp) != n || XLENGTH(local_name_sexp) != n ||
      XLENGTH(namespace_uri_sexp) != n) {
    Rf_error("Native analyst plan received canonical columns of unequal length.");
  }

  R_xlen_t ne = 0;
  int max_node_id = 0;
  for (R_xlen_t i = 0; i < n; ++i) {
    int nid = INTEGER(node_id_sexp)[i];
    if (nid == NA_INTEGER || nid < 1) Rf_error("Canonical node_id must be positive.");
    if (nid > max_node_id) max_node_id = nid;
    SEXP type = STRING_ELT(node_type_sexp, i);
    if (type != NA_STRING && strcmp(CHAR(type), "element") == 0) ne++;
  }
  if (ne == 0) Rf_error("Canonical table contains no elements.");

  int *element_pos_by_node = (int *) R_Calloc((size_t) max_node_id + 1u, int);
  int *element_path_id_c = (int *) R_Calloc((size_t) ne, int);
  int *element_group_id_c = (int *) R_Calloc((size_t) ne, int);
  int *element_child_count_c = (int *) R_Calloc((size_t) ne, int);

  R_xlen_t hash_size = next_pow2(ne * 4 + 16);
  int *path_slots = (int *) R_Calloc((size_t) hash_size, int);
  int *sib_slots = (int *) R_Calloc((size_t) hash_size, int);

  int *path_parent_c = (int *) R_Calloc((size_t) ne, int);
  int *path_first_pos_c = (int *) R_Calloc((size_t) ne, int);
  int *path_occ_c = (int *) R_Calloc((size_t) ne, int);
  int *path_max_sib_c = (int *) R_Calloc((size_t) ne, int);
  int *path_complex_c = (int *) R_Calloc((size_t) ne, int);
  SEXP *path_local_c = (SEXP *) R_Calloc((size_t) ne, SEXP);
  SEXP *path_ns_c = (SEXP *) R_Calloc((size_t) ne, SEXP);

  int *sib_parent_c = (int *) R_Calloc((size_t) ne, int);
  int *sib_count_c = (int *) R_Calloc((size_t) ne, int);
  SEXP *sib_local_c = (SEXP *) R_Calloc((size_t) ne, SEXP);
  SEXP *sib_ns_c = (SEXP *) R_Calloc((size_t) ne, SEXP);

  int protect_count = 0;
  SEXP element_rows = PROTECT(Rf_allocVector(INTSXP, ne)); protect_count++;
  SEXP element_node_id = PROTECT(Rf_allocVector(INTSXP, ne)); protect_count++;
  SEXP element_path_id = PROTECT(Rf_allocVector(INTSXP, ne)); protect_count++;
  SEXP sibling_occurrence = PROTECT(Rf_allocVector(INTSXP, ne)); protect_count++;
  SEXP sibling_count = PROTECT(Rf_allocVector(INTSXP, ne)); protect_count++;
  SEXP has_element_children = PROTECT(Rf_allocVector(LGLSXP, ne)); protect_count++;
  SEXP subtree_end_rows = PROTECT(Rf_allocVector(INTSXP, n)); protect_count++;

  R_xlen_t e = 0;
  int np = 0;
  int ng = 0;

  for (R_xlen_t i = 0; i < n; ++i) {
    SEXP type = STRING_ELT(node_type_sexp, i);
    if (type == NA_STRING || strcmp(CHAR(type), "element") != 0) continue;

    int nid = INTEGER(node_id_sexp)[i];
    int pid = INTEGER(parent_id_sexp)[i];
    int parent_element_pos = 0;
    int parent_element_node = 0;
    int parent_path = 0;
    if (pid != NA_INTEGER && pid >= 1 && pid <= max_node_id) {
      parent_element_pos = element_pos_by_node[pid];
      if (parent_element_pos > 0) {
        parent_element_node = pid;
        parent_path = element_path_id_c[parent_element_pos - 1];
        element_child_count_c[parent_element_pos - 1]++;
      }
    }

    SEXP local = STRING_ELT(local_name_sexp, i);
    SEXP ns = STRING_ELT(namespace_uri_sexp, i);

    unsigned long long ph = hash_path_key(parent_path, local, ns);
    R_xlen_t slot = (R_xlen_t) (ph & (unsigned long long) (hash_size - 1));
    int path_id = 0;
    for (;;) {
      int stored = path_slots[slot];
      if (stored == 0) {
        path_id = ++np;
        path_slots[slot] = path_id;
        path_parent_c[path_id - 1] = parent_path;
        path_first_pos_c[path_id - 1] = (int) e + 1;
        path_local_c[path_id - 1] = local;
        path_ns_c[path_id - 1] = ns;
        break;
      }
      int j = stored - 1;
      if (path_parent_c[j] == parent_path &&
          same_string(path_local_c[j], local) && same_string(path_ns_c[j], ns)) {
        path_id = stored;
        break;
      }
      slot = (slot + 1) & (hash_size - 1);
    }
    path_occ_c[path_id - 1]++;

    unsigned long long sh = hash_sibling_key(parent_element_node, local, ns);
    slot = (R_xlen_t) (sh & (unsigned long long) (hash_size - 1));
    int group_id = 0;
    for (;;) {
      int stored = sib_slots[slot];
      if (stored == 0) {
        group_id = ++ng;
        sib_slots[slot] = group_id;
        sib_parent_c[group_id - 1] = parent_element_node;
        sib_local_c[group_id - 1] = local;
        sib_ns_c[group_id - 1] = ns;
        break;
      }
      int j = stored - 1;
      if (sib_parent_c[j] == parent_element_node &&
          same_string(sib_local_c[j], local) && same_string(sib_ns_c[j], ns)) {
        group_id = stored;
        break;
      }
      slot = (slot + 1) & (hash_size - 1);
    }
    sib_count_c[group_id - 1]++;

    INTEGER(element_rows)[e] = (int) i + 1;
    INTEGER(element_node_id)[e] = nid;
    INTEGER(element_path_id)[e] = path_id;
    INTEGER(sibling_occurrence)[e] = sib_count_c[group_id - 1];
    element_path_id_c[e] = path_id;
    element_group_id_c[e] = group_id;
    element_pos_by_node[nid] = (int) e + 1;
    e++;
  }

  for (R_xlen_t j = 0; j < ne; ++j) {
    int group_id = element_group_id_c[j];
    int sc = sib_count_c[group_id - 1];
    INTEGER(sibling_count)[j] = sc;
    LOGICAL(has_element_children)[j] = element_child_count_c[j] > 0;
    int path_id = element_path_id_c[j];
    if (sc > path_max_sib_c[path_id - 1]) path_max_sib_c[path_id - 1] = sc;
    if (element_child_count_c[j] > 0) path_complex_c[path_id - 1] = 1;
  }

  /* Exact equivalent of .xml_analyst_subtree_end_rows(). */
  int *stack = (int *) R_Calloc((size_t) ne, int);
  R_xlen_t top = 0;
  for (R_xlen_t i = 0; i < n; ++i) INTEGER(subtree_end_rows)[i] = (int) n;
  for (R_xlen_t i = 0; i < n; ++i) {
    int d = INTEGER(depth_sexp)[i];
    while (top > 0) {
      int prior_row = stack[top - 1]; /* one-based */
      int prior_depth = INTEGER(depth_sexp)[prior_row - 1];
      if (prior_depth < d) break;
      INTEGER(subtree_end_rows)[prior_row - 1] = (int) i;
      top--;
    }
    SEXP type = STRING_ELT(node_type_sexp, i);
    if (type != NA_STRING && strcmp(CHAR(type), "element") == 0) {
      stack[top++] = (int) i + 1;
    }
  }
  R_Free(stack);

  SEXP path_parent_id = PROTECT(Rf_allocVector(INTSXP, np)); protect_count++;
  SEXP path_first_element_pos = PROTECT(Rf_allocVector(INTSXP, np)); protect_count++;
  SEXP path_occurrences = PROTECT(Rf_allocVector(INTSXP, np)); protect_count++;
  SEXP path_max_per_parent = PROTECT(Rf_allocVector(INTSXP, np)); protect_count++;
  SEXP path_repeated = PROTECT(Rf_allocVector(LGLSXP, np)); protect_count++;
  SEXP path_complex = PROTECT(Rf_allocVector(LGLSXP, np)); protect_count++;

  for (int j = 0; j < np; ++j) {
    INTEGER(path_parent_id)[j] = path_parent_c[j] == 0 ? NA_INTEGER : path_parent_c[j];
    INTEGER(path_first_element_pos)[j] = path_first_pos_c[j];
    INTEGER(path_occurrences)[j] = path_occ_c[j];
    INTEGER(path_max_per_parent)[j] = path_max_sib_c[j];
    LOGICAL(path_repeated)[j] = path_max_sib_c[j] > 1;
    LOGICAL(path_complex)[j] = path_complex_c[j] != 0;
  }

  SEXP result = PROTECT(Rf_allocVector(VECSXP, 13)); protect_count++;
  SET_VECTOR_ELT(result, 0, element_rows);
  SET_VECTOR_ELT(result, 1, element_node_id);
  SET_VECTOR_ELT(result, 2, element_path_id);
  SET_VECTOR_ELT(result, 3, sibling_occurrence);
  SET_VECTOR_ELT(result, 4, sibling_count);
  SET_VECTOR_ELT(result, 5, has_element_children);
  SET_VECTOR_ELT(result, 6, subtree_end_rows);
  SET_VECTOR_ELT(result, 7, path_parent_id);
  SET_VECTOR_ELT(result, 8, path_first_element_pos);
  SET_VECTOR_ELT(result, 9, path_occurrences);
  SET_VECTOR_ELT(result, 10, path_max_per_parent);
  SET_VECTOR_ELT(result, 11, path_repeated);
  SET_VECTOR_ELT(result, 12, path_complex);

  SEXP names = PROTECT(Rf_allocVector(STRSXP, 13)); protect_count++;
  const char *names_c[13] = {
    "element_rows", "element_node_id", "element_path_id",
    "sibling_occurrence", "sibling_count", "has_element_children",
    "subtree_end_rows", "path_parent_id", "path_first_element_pos",
    "path_occurrences", "path_max_per_parent", "path_repeated", "path_complex"
  };
  for (int j = 0; j < 13; ++j) SET_STRING_ELT(names, j, Rf_mkChar(names_c[j]));
  Rf_setAttrib(result, R_NamesSymbol, names);

  R_Free(element_pos_by_node);
  R_Free(element_path_id_c);
  R_Free(element_group_id_c);
  R_Free(element_child_count_c);
  R_Free(path_slots);
  R_Free(sib_slots);
  R_Free(path_parent_c);
  R_Free(path_first_pos_c);
  R_Free(path_occ_c);
  R_Free(path_max_sib_c);
  R_Free(path_complex_c);
  R_Free(path_local_c);
  R_Free(path_ns_c);
  R_Free(sib_parent_c);
  R_Free(sib_count_c);
  R_Free(sib_local_c);
  R_Free(sib_ns_c);

  UNPROTECT(protect_count);
  return result;
}



/* -------------------------------------------------------------------------
 * Native entity ownership map
 * -------------------------------------------------------------------------
 *
 * Entity selection and aliases remain R semantics.  Once R has selected the
 * structural path ids that constitute entities, ownership is a pure preorder
 * tree scan: an entity owns itself and every non-entity descendant inherits
 * its parent's nearest entity owner.  Doing this in C avoids two occurrence-
 * scale R loops plus a redundant sort/which pass on large documents.
 */
SEXP C_xmlrect_native_entity_map(
  SEXP element_node_id_sexp,
  SEXP element_parent_id_sexp,
  SEXP element_path_id_sexp,
  SEXP entity_path_id_sexp,
  SEXP max_node_id_sexp
) {
  if (TYPEOF(element_node_id_sexp) != INTSXP ||
      TYPEOF(element_parent_id_sexp) != INTSXP ||
      TYPEOF(element_path_id_sexp) != INTSXP ||
      TYPEOF(entity_path_id_sexp) != INTSXP) {
    Rf_error("Native entity map received unexpected integer column types.");
  }

  R_xlen_t ne = XLENGTH(element_node_id_sexp);
  if (XLENGTH(element_parent_id_sexp) != ne ||
      XLENGTH(element_path_id_sexp) != ne) {
    Rf_error("Native entity map received element columns of unequal length.");
  }

  int max_node_id = Rf_asInteger(max_node_id_sexp);
  if (max_node_id == NA_INTEGER || max_node_id < 1) {
    Rf_error("Native entity map requires a positive maximum node id.");
  }

  int max_path_id = 0;
  for (R_xlen_t i = 0; i < ne; ++i) {
    int path_id = INTEGER(element_path_id_sexp)[i];
    if (path_id == NA_INTEGER || path_id < 1) {
      Rf_error("Native entity map requires positive element path ids.");
    }
    if (path_id > max_path_id) max_path_id = path_id;
  }

  unsigned char *entity_path = (unsigned char *) R_Calloc(
    (size_t) max_path_id + 1u, unsigned char
  );
  R_xlen_t n_entity_paths = XLENGTH(entity_path_id_sexp);
  for (R_xlen_t i = 0; i < n_entity_paths; ++i) {
    int path_id = INTEGER(entity_path_id_sexp)[i];
    if (path_id == NA_INTEGER || path_id < 1 || path_id > max_path_id) {
      R_Free(entity_path);
      Rf_error("Native entity map received an out-of-range entity path id.");
    }
    entity_path[path_id] = 1u;
  }

  int protect_count = 0;
  SEXP owner_by_node = PROTECT(Rf_allocVector(INTSXP, max_node_id)); protect_count++;
  SEXP is_entity_node = PROTECT(Rf_allocVector(LGLSXP, max_node_id)); protect_count++;
  for (int i = 0; i < max_node_id; ++i) {
    INTEGER(owner_by_node)[i] = NA_INTEGER;
    LOGICAL(is_entity_node)[i] = FALSE;
  }

  R_xlen_t nr = 0;
  for (R_xlen_t i = 0; i < ne; ++i) {
    int nid = INTEGER(element_node_id_sexp)[i];
    int pid = INTEGER(element_parent_id_sexp)[i];
    int path_id = INTEGER(element_path_id_sexp)[i];
    if (nid == NA_INTEGER || nid < 1 || nid > max_node_id) {
      R_Free(entity_path);
      UNPROTECT(protect_count);
      Rf_error("Native entity map received an out-of-range element node id.");
    }

    if (entity_path[path_id]) {
      INTEGER(owner_by_node)[nid - 1] = nid;
      LOGICAL(is_entity_node)[nid - 1] = TRUE;
      nr++;
    } else if (pid != NA_INTEGER && pid >= 1 && pid <= max_node_id) {
      INTEGER(owner_by_node)[nid - 1] = INTEGER(owner_by_node)[pid - 1];
    }
  }

  SEXP entity_element_pos = PROTECT(Rf_allocVector(INTSXP, nr)); protect_count++;
  SEXP parent_entity_node_id = PROTECT(Rf_allocVector(INTSXP, nr)); protect_count++;
  SEXP occurrence = PROTECT(Rf_allocVector(INTSXP, nr)); protect_count++;

  int *path_occurrence = (int *) R_Calloc((size_t) max_path_id + 1u, int);
  R_xlen_t out = 0;
  for (R_xlen_t i = 0; i < ne; ++i) {
    int nid = INTEGER(element_node_id_sexp)[i];
    if (!LOGICAL(is_entity_node)[nid - 1]) continue;

    int pid = INTEGER(element_parent_id_sexp)[i];
    int path_id = INTEGER(element_path_id_sexp)[i];
    INTEGER(entity_element_pos)[out] = (int) i + 1;
    INTEGER(parent_entity_node_id)[out] =
      (pid != NA_INTEGER && pid >= 1 && pid <= max_node_id)
        ? INTEGER(owner_by_node)[pid - 1]
        : NA_INTEGER;
    INTEGER(occurrence)[out] = ++path_occurrence[path_id];
    out++;
  }

  R_Free(path_occurrence);
  R_Free(entity_path);

  SEXP result = PROTECT(Rf_allocVector(VECSXP, 5)); protect_count++;
  SET_VECTOR_ELT(result, 0, owner_by_node);
  SET_VECTOR_ELT(result, 1, is_entity_node);
  SET_VECTOR_ELT(result, 2, entity_element_pos);
  SET_VECTOR_ELT(result, 3, parent_entity_node_id);
  SET_VECTOR_ELT(result, 4, occurrence);

  SEXP names = PROTECT(Rf_allocVector(STRSXP, 5)); protect_count++;
  const char *names_c[5] = {
    "owner_by_node", "is_entity_node", "entity_element_pos",
    "parent_entity_node_id", "occurrence"
  };
  for (int j = 0; j < 5; ++j) SET_STRING_ELT(names, j, Rf_mkChar(names_c[j]));
  Rf_setAttrib(result, R_NamesSymbol, names);

  UNPROTECT(protect_count);
  return result;
}


/* -------------------------------------------------------------------------
 * Native analyst field projection
 * -------------------------------------------------------------------------
 *
 * Once R has made the semantic decisions (entity set, analyst column names,
 * source-key policy, etc.), the remaining wide-table projection is a dense
 * integer-index problem.  This kernel performs immediate-parent propagation,
 * local-value override, and amplification accounting without repeated R list
 * lookups or per-cell vector replacement.  It deliberately does not decide
 * what an entity or field means.
 */

static double xmlrect_scalar_bytes(SEXP value, int logical_column) {
  if (value == R_NilValue || XLENGTH(value) < 1) return 0.0;

  if (logical_column) {
    int v = Rf_asLogical(value);
    if (v == NA_LOGICAL) return 0.0;
    return v ? 4.0 : 5.0; /* "TRUE" / "FALSE" */
  }

  SEXP ch = Rf_asChar(value);
  if (ch == NA_STRING) return 0.0;
  return (double) strlen(Rf_translateCharUTF8(ch));
}

SEXP C_xmlrect_native_project_fields(
  SEXP entity_node_id_sexp,
  SEXP parent_entity_node_id_sexp,
  SEXP entity_depth_sexp,
  SEXP field_column_id_sexp,
  SEXP field_owner_id_sexp,
  SEXP field_values_sexp,
  SEXP column_logical_sexp,
  SEXP column_propagate_sexp
) {
  if (TYPEOF(entity_node_id_sexp) != INTSXP ||
      TYPEOF(parent_entity_node_id_sexp) != INTSXP ||
      TYPEOF(entity_depth_sexp) != INTSXP ||
      TYPEOF(field_column_id_sexp) != INTSXP ||
      TYPEOF(field_owner_id_sexp) != INTSXP ||
      TYPEOF(field_values_sexp) != VECSXP ||
      TYPEOF(column_logical_sexp) != LGLSXP ||
      TYPEOF(column_propagate_sexp) != LGLSXP) {
    Rf_error("Native field projection received unexpected input types.");
  }

  R_xlen_t nr = XLENGTH(entity_node_id_sexp);
  R_xlen_t nf = XLENGTH(field_column_id_sexp);
  R_xlen_t nc = XLENGTH(column_logical_sexp);

  if (XLENGTH(parent_entity_node_id_sexp) != nr ||
      XLENGTH(entity_depth_sexp) != nr ||
      XLENGTH(field_owner_id_sexp) != nf ||
      XLENGTH(field_values_sexp) != nf ||
      XLENGTH(column_propagate_sexp) != nc) {
    Rf_error("Native field projection received vectors of unequal length.");
  }

  int max_node_id = 0;
  for (R_xlen_t r = 0; r < nr; ++r) {
    int node = INTEGER(entity_node_id_sexp)[r];
    if (node == NA_INTEGER || node < 1) {
      Rf_error("Entity node ids must be positive integers.");
    }
    if (node > max_node_id) max_node_id = node;
  }

  int *row_by_node = (int *) R_Calloc((size_t) max_node_id + 1u, int);
  int *first_child = (int *) R_Calloc((size_t) nr, int);
  int *next_child = (int *) R_Calloc((size_t) nr, int);
  int *owner_seen = (int *) R_Calloc((size_t) nr, int);

  for (R_xlen_t r = 0; r < nr; ++r) {
    int node = INTEGER(entity_node_id_sexp)[r];
    row_by_node[node] = (int) r + 1; /* one-based */
  }

  /* Build entity adjacency once.  Preserve entity-row order inside each
   * parent's child list by appending with a tail pointer. */
  int *last_child = (int *) R_Calloc((size_t) nr, int);
  for (R_xlen_t r = 0; r < nr; ++r) {
    int parent_node = INTEGER(parent_entity_node_id_sexp)[r];
    if (parent_node == NA_INTEGER || parent_node < 1 || parent_node > max_node_id) continue;
    int parent_row = row_by_node[parent_node];
    if (parent_row == 0) continue;
    int p = parent_row - 1;
    int child = (int) r + 1;
    if (first_child[p] == 0) {
      first_child[p] = child;
    } else {
      next_child[last_child[p] - 1] = child;
    }
    last_child[p] = child;
  }
  R_Free(last_child);

  int protect_count = 0;
  SEXP columns = PROTECT(Rf_allocVector(VECSXP, nc)); protect_count++;
  SEXP owner_rows = PROTECT(Rf_allocVector(INTSXP, nc)); protect_count++;
  SEXP emitted_rows = PROTECT(Rf_allocVector(INTSXP, nc)); protect_count++;
  SEXP owner_bytes = PROTECT(Rf_allocVector(REALSXP, nc)); protect_count++;
  SEXP emitted_bytes = PROTECT(Rf_allocVector(REALSXP, nc)); protect_count++;
  SEXP max_depth = PROTECT(Rf_allocVector(INTSXP, nc)); protect_count++;

  for (R_xlen_t c = 0; c < nc; ++c) {
    int logical_column = LOGICAL(column_logical_sexp)[c] == TRUE;
    int propagate = LOGICAL(column_propagate_sexp)[c] == TRUE;
    SEXP out = PROTECT(Rf_allocVector(logical_column ? LGLSXP : STRSXP, nr));

    if (logical_column) {
      for (R_xlen_t r = 0; r < nr; ++r) LOGICAL(out)[r] = NA_LOGICAL;
    } else {
      for (R_xlen_t r = 0; r < nr; ++r) SET_STRING_ELT(out, r, NA_STRING);
    }

    int owner_count = 0;
    double own_bytes = 0.0;
    int owner_min_depth = INT_MAX;
    int stamp = (int) c + 1;

    /* Context first.  Later fields retain the same overwrite order as the R
     * reference because field rows are visited in their original order. */
    if (propagate) {
      for (R_xlen_t f = 0; f < nf; ++f) {
        if (INTEGER(field_column_id_sexp)[f] != (int) c + 1) continue;
        int owner_node = INTEGER(field_owner_id_sexp)[f];
        if (owner_node < 1 || owner_node > max_node_id) continue;
        int owner_row = row_by_node[owner_node];
        if (owner_row == 0) continue;
        SEXP value = VECTOR_ELT(field_values_sexp, f);
        int child = first_child[owner_row - 1];
        while (child != 0) {
          int rr = child - 1;
          if (logical_column) {
            LOGICAL(out)[rr] = Rf_asLogical(value);
          } else {
            SET_STRING_ELT(out, rr, Rf_asChar(value));
          }
          child = next_child[rr];
        }
      }
    }

    /* Local values override inherited context.  Accumulate owner metrics in
     * the same pass. */
    for (R_xlen_t f = 0; f < nf; ++f) {
      if (INTEGER(field_column_id_sexp)[f] != (int) c + 1) continue;
      int owner_node = INTEGER(field_owner_id_sexp)[f];
      if (owner_node < 1 || owner_node > max_node_id) continue;
      int owner_row = row_by_node[owner_node];
      if (owner_row == 0) continue;
      int rr = owner_row - 1;
      SEXP value = VECTOR_ELT(field_values_sexp, f);

      if (logical_column) {
        LOGICAL(out)[rr] = Rf_asLogical(value);
      } else {
        SET_STRING_ELT(out, rr, Rf_asChar(value));
      }

      if (owner_seen[rr] != stamp) {
        owner_seen[rr] = stamp;
        owner_count++;
        int d = INTEGER(entity_depth_sexp)[rr];
        if (d != NA_INTEGER && d < owner_min_depth) owner_min_depth = d;
      }
      own_bytes += xmlrect_scalar_bytes(value, logical_column);
    }

    int emitted_count = 0;
    double emit_bytes = 0.0;
    int emitted_max_depth = INT_MIN;
    for (R_xlen_t r = 0; r < nr; ++r) {
      int present = 0;
      if (logical_column) {
        int v = LOGICAL(out)[r];
        if (v != NA_LOGICAL) {
          present = 1;
          emit_bytes += v ? 4.0 : 5.0;
        }
      } else {
        SEXP ch = STRING_ELT(out, r);
        if (ch != NA_STRING) {
          present = 1;
          emit_bytes += (double) strlen(Rf_translateCharUTF8(ch));
        }
      }
      if (present) {
        emitted_count++;
        int d = INTEGER(entity_depth_sexp)[r];
        if (d != NA_INTEGER && d > emitted_max_depth) emitted_max_depth = d;
      }
    }

    SET_VECTOR_ELT(columns, c, out);
    INTEGER(owner_rows)[c] = owner_count;
    INTEGER(emitted_rows)[c] = emitted_count;
    REAL(owner_bytes)[c] = own_bytes;
    REAL(emitted_bytes)[c] = emit_bytes;
    if (owner_min_depth == INT_MAX || emitted_max_depth == INT_MIN) {
      INTEGER(max_depth)[c] = 0;
    } else {
      int delta = emitted_max_depth - owner_min_depth;
      INTEGER(max_depth)[c] = delta > 0 ? delta : 0;
    }
    UNPROTECT(1);
  }

  SEXP result = PROTECT(Rf_allocVector(VECSXP, 6)); protect_count++;
  SET_VECTOR_ELT(result, 0, columns);
  SET_VECTOR_ELT(result, 1, owner_rows);
  SET_VECTOR_ELT(result, 2, emitted_rows);
  SET_VECTOR_ELT(result, 3, owner_bytes);
  SET_VECTOR_ELT(result, 4, emitted_bytes);
  SET_VECTOR_ELT(result, 5, max_depth);

  SEXP names = PROTECT(Rf_allocVector(STRSXP, 6)); protect_count++;
  const char *names_c[6] = {
    "columns", "owner_rows", "emitted_rows",
    "owner_bytes", "emitted_bytes", "max_depth"
  };
  for (int i = 0; i < 6; ++i) SET_STRING_ELT(names, i, Rf_mkChar(names_c[i]));
  Rf_setAttrib(result, R_NamesSymbol, names);

  R_Free(row_by_node);
  R_Free(first_child);
  R_Free(next_child);
  R_Free(owner_seen);

  UNPROTECT(protect_count);
  return result;
}



/* -------------------------------------------------------------------------
 * Native analyst field layout
 * -------------------------------------------------------------------------
 *
 * By P4, entity choice, field semantics and final value projection are already
 * outside the hot path.  The remaining R bottleneck was bookkeeping around the
 * field catalogue: building string concatenation keys, sorting occurrence
 * groups, run-length numbering, tapply(max), then sorting fields again merely
 * to discover final column order.
 *
 * This kernel keeps those operations structural.  R still supplies the exact
 * entity-path id and source signature that define one semantic catalogue
 * entry.  C assigns integer catalogue ids, computes within-owner occurrences,
 * expands repeated fields into final column slots, and returns the stable
 * source-order slot ordering.  No analyst naming/key/type policy lives here.
 */

typedef struct {
  int owner_id;
  int catalog_id;
  int field_order;
  R_xlen_t field_index;
} xmlrect_field_occurrence_entry;

typedef struct {
  int slot_id;
  int field_order;
  R_xlen_t field_index;
} xmlrect_slot_order_entry;

static int xmlrect_compare_field_occurrence(const void *a, const void *b) {
  const xmlrect_field_occurrence_entry *x =
    (const xmlrect_field_occurrence_entry *) a;
  const xmlrect_field_occurrence_entry *y =
    (const xmlrect_field_occurrence_entry *) b;

  if (x->owner_id < y->owner_id) return -1;
  if (x->owner_id > y->owner_id) return 1;
  if (x->catalog_id < y->catalog_id) return -1;
  if (x->catalog_id > y->catalog_id) return 1;
  if (x->field_order < y->field_order) return -1;
  if (x->field_order > y->field_order) return 1;
  if (x->field_index < y->field_index) return -1;
  if (x->field_index > y->field_index) return 1;
  return 0;
}

static int xmlrect_compare_slot_order(const void *a, const void *b) {
  const xmlrect_slot_order_entry *x =
    (const xmlrect_slot_order_entry *) a;
  const xmlrect_slot_order_entry *y =
    (const xmlrect_slot_order_entry *) b;

  if (x->field_order < y->field_order) return -1;
  if (x->field_order > y->field_order) return 1;
  if (x->field_index < y->field_index) return -1;
  if (x->field_index > y->field_index) return 1;
  if (x->slot_id < y->slot_id) return -1;
  if (x->slot_id > y->slot_id) return 1;
  return 0;
}

static unsigned long long xmlrect_hash_catalog_key(int path_id, const char *s) {
  /* 64-bit FNV-1a with the integer path id mixed first. */
  unsigned long long h = 1469598103934665603ULL;
  unsigned int u = (unsigned int) path_id;
  for (int k = 0; k < 4; ++k) {
    h ^= (unsigned char) (u & 0xffu);
    h *= 1099511628211ULL;
    u >>= 8;
  }
  const unsigned char *p = (const unsigned char *) s;
  while (*p != '\0') {
    h ^= (unsigned long long) *p++;
    h *= 1099511628211ULL;
  }
  return h;
}

static size_t xmlrect_hash_capacity(R_xlen_t n) {
  size_t target = (size_t) (n < 4 ? 8 : n * 2);
  size_t cap = 8u;
  while (cap < target) {
    if (cap > ((size_t) -1) / 2u) {
      Rf_error("Native field layout hash table is too large.");
    }
    cap <<= 1u;
  }
  return cap;
}

SEXP C_xmlrect_native_field_layout(
  SEXP owner_id_sexp,
  SEXP entity_path_id_sexp,
  SEXP source_signature_sexp,
  SEXP field_order_sexp
) {
  if (TYPEOF(owner_id_sexp) != INTSXP ||
      TYPEOF(entity_path_id_sexp) != INTSXP ||
      TYPEOF(source_signature_sexp) != STRSXP ||
      TYPEOF(field_order_sexp) != INTSXP) {
    Rf_error("Native field layout received unexpected input types.");
  }

  R_xlen_t nf = XLENGTH(owner_id_sexp);
  if (XLENGTH(entity_path_id_sexp) != nf ||
      XLENGTH(source_signature_sexp) != nf ||
      XLENGTH(field_order_sexp) != nf) {
    Rf_error("Native field layout received vectors of unequal length.");
  }

  int protect_count = 0;
  SEXP catalog_id = PROTECT(Rf_allocVector(INTSXP, nf)); protect_count++;
  SEXP value_occurrence = PROTECT(Rf_allocVector(INTSXP, nf)); protect_count++;
  SEXP slot_id = PROTECT(Rf_allocVector(INTSXP, nf)); protect_count++;

  if (nf == 0) {
    SEXP empty = PROTECT(Rf_allocVector(INTSXP, 0)); protect_count++;
    SEXP result = PROTECT(Rf_allocVector(VECSXP, 7)); protect_count++;
    SET_VECTOR_ELT(result, 0, catalog_id);
    SET_VECTOR_ELT(result, 1, empty);
    SET_VECTOR_ELT(result, 2, value_occurrence);
    SET_VECTOR_ELT(result, 3, empty);
    SET_VECTOR_ELT(result, 4, slot_id);
    SET_VECTOR_ELT(result, 5, empty);
    SET_VECTOR_ELT(result, 6, empty);
    SEXP names = PROTECT(Rf_allocVector(STRSXP, 7)); protect_count++;
    const char *names_c[7] = {
      "catalog_id", "catalog_first_field", "value_occurrence",
      "catalog_max_occurrence", "slot_id", "slot_first_field",
      "data_slot_order"
    };
    for (int i = 0; i < 7; ++i) SET_STRING_ELT(names, i, Rf_mkChar(names_c[i]));
    Rf_setAttrib(result, R_NamesSymbol, names);
    UNPROTECT(protect_count);
    return result;
  }

  size_t hash_cap = xmlrect_hash_capacity(nf);
  R_xlen_t *hash_field = (R_xlen_t *) R_Calloc(hash_cap, R_xlen_t);
  int *hash_catalog = (int *) R_Calloc(hash_cap, int);
  R_xlen_t *catalog_first_c = (R_xlen_t *) R_Calloc((size_t) nf, R_xlen_t);
  int catalog_count = 0;

  for (R_xlen_t i = 0; i < nf; ++i) {
    int path_id = INTEGER(entity_path_id_sexp)[i];
    int owner_id = INTEGER(owner_id_sexp)[i];
    int order = INTEGER(field_order_sexp)[i];
    SEXP sig_ch = STRING_ELT(source_signature_sexp, i);
    if (path_id == NA_INTEGER || path_id < 1 ||
        owner_id == NA_INTEGER || owner_id < 1 ||
        order == NA_INTEGER || sig_ch == NA_STRING) {
      R_Free(hash_field); R_Free(hash_catalog); R_Free(catalog_first_c);
      UNPROTECT(protect_count);
      Rf_error("Native field layout requires non-missing structural field metadata.");
    }

    const char *sig = CHAR(sig_ch);
    unsigned long long h = xmlrect_hash_catalog_key(path_id, sig);
    size_t pos = (size_t) h & (hash_cap - 1u);

    for (;;) {
      if (hash_catalog[pos] == 0) {
        catalog_count++;
        hash_catalog[pos] = catalog_count;
        hash_field[pos] = i + 1; /* zero means empty */
        catalog_first_c[catalog_count - 1] = i + 1;
        INTEGER(catalog_id)[i] = catalog_count;
        break;
      }

      R_xlen_t representative = hash_field[pos] - 1;
      if (INTEGER(entity_path_id_sexp)[representative] == path_id) {
        SEXP rep_ch = STRING_ELT(source_signature_sexp, representative);
        const char *rep_sig = CHAR(rep_ch);
        if (strcmp(rep_sig, sig) == 0) {
          INTEGER(catalog_id)[i] = hash_catalog[pos];
          break;
        }
      }

      pos = (pos + 1u) & (hash_cap - 1u);
    }
  }

  R_Free(hash_field);
  R_Free(hash_catalog);

  SEXP catalog_first_field = PROTECT(Rf_allocVector(INTSXP, catalog_count)); protect_count++;
  SEXP catalog_max_occurrence = PROTECT(Rf_allocVector(INTSXP, catalog_count)); protect_count++;
  for (int c = 0; c < catalog_count; ++c) {
    if (catalog_first_c[c] > INT_MAX) {
      R_Free(catalog_first_c);
      UNPROTECT(protect_count);
      Rf_error("Native field layout cannot represent a field index above INT_MAX.");
    }
    INTEGER(catalog_first_field)[c] = (int) catalog_first_c[c];
    INTEGER(catalog_max_occurrence)[c] = 0;
  }
  R_Free(catalog_first_c);

  xmlrect_field_occurrence_entry *occ_entries =
    (xmlrect_field_occurrence_entry *) R_Calloc((size_t) nf, xmlrect_field_occurrence_entry);
  for (R_xlen_t i = 0; i < nf; ++i) {
    occ_entries[i].owner_id = INTEGER(owner_id_sexp)[i];
    occ_entries[i].catalog_id = INTEGER(catalog_id)[i];
    occ_entries[i].field_order = INTEGER(field_order_sexp)[i];
    occ_entries[i].field_index = i;
  }
  qsort(
    occ_entries,
    (size_t) nf,
    sizeof(xmlrect_field_occurrence_entry),
    xmlrect_compare_field_occurrence
  );

  int previous_owner = INT_MIN;
  int previous_catalog = INT_MIN;
  int occurrence = 0;
  for (R_xlen_t j = 0; j < nf; ++j) {
    xmlrect_field_occurrence_entry *entry = &occ_entries[j];
    if (entry->owner_id != previous_owner || entry->catalog_id != previous_catalog) {
      previous_owner = entry->owner_id;
      previous_catalog = entry->catalog_id;
      occurrence = 1;
    } else {
      occurrence++;
    }
    INTEGER(value_occurrence)[entry->field_index] = occurrence;
    int c = entry->catalog_id - 1;
    if (occurrence > INTEGER(catalog_max_occurrence)[c]) {
      INTEGER(catalog_max_occurrence)[c] = occurrence;
    }
  }
  R_Free(occ_entries);

  int *catalog_offset = (int *) R_Calloc((size_t) catalog_count, int);
  long long slot_count_ll = 0;
  for (int c = 0; c < catalog_count; ++c) {
    catalog_offset[c] = (int) slot_count_ll;
    int width = INTEGER(catalog_max_occurrence)[c] > 1
      ? INTEGER(catalog_max_occurrence)[c]
      : 1;
    slot_count_ll += width;
    if (slot_count_ll > INT_MAX) {
      R_Free(catalog_offset);
      UNPROTECT(protect_count);
      Rf_error("Native field layout cannot represent more than INT_MAX analyst columns.");
    }
  }
  int slot_count = (int) slot_count_ll;

  SEXP slot_first_field = PROTECT(Rf_allocVector(INTSXP, slot_count)); protect_count++;
  SEXP data_slot_order = PROTECT(Rf_allocVector(INTSXP, slot_count)); protect_count++;
  int *slot_first_order = (int *) R_Calloc((size_t) slot_count, int);
  R_xlen_t *slot_first_index = (R_xlen_t *) R_Calloc((size_t) slot_count, R_xlen_t);
  for (int s = 0; s < slot_count; ++s) {
    INTEGER(slot_first_field)[s] = NA_INTEGER;
    slot_first_order[s] = INT_MAX;
    slot_first_index[s] = (R_xlen_t) -1;
  }

  for (R_xlen_t i = 0; i < nf; ++i) {
    int c = INTEGER(catalog_id)[i] - 1;
    int width = INTEGER(catalog_max_occurrence)[c];
    int within = width > 1 ? INTEGER(value_occurrence)[i] : 1;
    int sid = catalog_offset[c] + within; /* one-based */
    INTEGER(slot_id)[i] = sid;

    int order = INTEGER(field_order_sexp)[i];
    int s = sid - 1;
    if (order < slot_first_order[s] ||
        (order == slot_first_order[s] &&
         (slot_first_index[s] == (R_xlen_t) -1 || i < slot_first_index[s]))) {
      slot_first_order[s] = order;
      slot_first_index[s] = i;
      if (i >= INT_MAX) {
        R_Free(catalog_offset); R_Free(slot_first_order); R_Free(slot_first_index);
        UNPROTECT(protect_count);
        Rf_error("Native field layout cannot represent a field index above INT_MAX.");
      }
      INTEGER(slot_first_field)[s] = (int) i + 1;
    }
  }
  R_Free(catalog_offset);

  xmlrect_slot_order_entry *slot_entries =
    (xmlrect_slot_order_entry *) R_Calloc((size_t) slot_count, xmlrect_slot_order_entry);
  for (int s = 0; s < slot_count; ++s) {
    slot_entries[s].slot_id = s + 1;
    slot_entries[s].field_order = slot_first_order[s];
    slot_entries[s].field_index = slot_first_index[s];
  }
  qsort(
    slot_entries,
    (size_t) slot_count,
    sizeof(xmlrect_slot_order_entry),
    xmlrect_compare_slot_order
  );
  for (int s = 0; s < slot_count; ++s) {
    INTEGER(data_slot_order)[s] = slot_entries[s].slot_id;
  }
  R_Free(slot_entries);
  R_Free(slot_first_order);
  R_Free(slot_first_index);

  SEXP result = PROTECT(Rf_allocVector(VECSXP, 7)); protect_count++;
  SET_VECTOR_ELT(result, 0, catalog_id);
  SET_VECTOR_ELT(result, 1, catalog_first_field);
  SET_VECTOR_ELT(result, 2, value_occurrence);
  SET_VECTOR_ELT(result, 3, catalog_max_occurrence);
  SET_VECTOR_ELT(result, 4, slot_id);
  SET_VECTOR_ELT(result, 5, slot_first_field);
  SET_VECTOR_ELT(result, 6, data_slot_order);

  SEXP names = PROTECT(Rf_allocVector(STRSXP, 7)); protect_count++;
  const char *names_c[7] = {
    "catalog_id", "catalog_first_field", "value_occurrence",
    "catalog_max_occurrence", "slot_id", "slot_first_field",
    "data_slot_order"
  };
  for (int i = 0; i < 7; ++i) SET_STRING_ELT(names, i, Rf_mkChar(names_c[i]));
  Rf_setAttrib(result, R_NamesSymbol, names);

  UNPROTECT(protect_count);
  return result;
}



/* -------------------------------------------------------------------------
 * Native conservative analyst type inference/conversion
 * -------------------------------------------------------------------------
 *
 * This is deliberately narrower than a general-purpose parser.  It mirrors
 * the analyst layer's frozen lexical policy: ISO YYYY-MM-DD dates, XML
 * booleans, integer lexical forms, and finite decimal/exponent forms.  A
 * conversion is made only when at least two distinct observed lexical values
 * exist, matching the R reference's "high" confidence threshold.  Blank
 * strings, leading-zero numeric codes, and 0/1-only fields remain character.
 */

typedef struct {
  const char *begin;
  const char *end;
} xmlrect_span;

static xmlrect_span xmlrect_trim_span(const char *s) {
  xmlrect_span out;
  const char *b = s;
  const char *e = s + strlen(s);
  while (b < e && (*b == ' ' || *b == '\t' || *b == '\r' || *b == '\n')) b++;
  while (e > b && (e[-1] == ' ' || e[-1] == '\t' || e[-1] == '\r' || e[-1] == '\n')) e--;
  out.begin = b;
  out.end = e;
  return out;
}

static int xmlrect_span_equal(xmlrect_span a, xmlrect_span b) {
  ptrdiff_t na = a.end - a.begin;
  ptrdiff_t nb = b.end - b.begin;
  return na == nb && (na == 0 || memcmp(a.begin, b.begin, (size_t) na) == 0);
}

static int xmlrect_ascii_equal_ci(xmlrect_span x, const char *literal) {
  size_t n = strlen(literal);
  if ((size_t) (x.end - x.begin) != n) return 0;
  for (size_t i = 0; i < n; ++i) {
    unsigned char a = (unsigned char) x.begin[i];
    unsigned char b = (unsigned char) literal[i];
    if (a >= 'A' && a <= 'Z') a = (unsigned char) (a - 'A' + 'a');
    if (a != b) return 0;
  }
  return 1;
}

static int xmlrect_is_digit(char ch) {
  return ch >= '0' && ch <= '9';
}

static int xmlrect_date_parts(xmlrect_span x, int *year, int *month, int *day) {
  if (x.end - x.begin != 10) return 0;
  const char *p = x.begin;
  if (!xmlrect_is_digit(p[0]) || !xmlrect_is_digit(p[1]) ||
      !xmlrect_is_digit(p[2]) || !xmlrect_is_digit(p[3]) ||
      p[4] != '-' || !xmlrect_is_digit(p[5]) || !xmlrect_is_digit(p[6]) ||
      p[7] != '-' || !xmlrect_is_digit(p[8]) || !xmlrect_is_digit(p[9])) return 0;
  *year = (p[0]-'0')*1000 + (p[1]-'0')*100 + (p[2]-'0')*10 + (p[3]-'0');
  *month = (p[5]-'0')*10 + (p[6]-'0');
  *day = (p[8]-'0')*10 + (p[9]-'0');
  if (*month < 1 || *month > 12 || *day < 1) return 0;
  static const int mdays[12] = {31,28,31,30,31,30,31,31,30,31,30,31};
  int maxd = mdays[*month - 1];
  if (*month == 2) {
    int leap = ((*year % 4 == 0) && (*year % 100 != 0 || *year % 400 == 0));
    if (leap) maxd = 29;
  }
  return *day <= maxd;
}

static double xmlrect_days_from_civil(int y, unsigned m, unsigned d) {
  int mi = (int) m;
  y -= mi <= 2;
  const int era = (y >= 0 ? y : y - 399) / 400;
  const unsigned yoe = (unsigned) (y - era * 400);
  const unsigned doy = (unsigned) ((153 * (mi + (mi > 2 ? -3 : 9)) + 2) / 5) + d - 1;
  const unsigned doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
  return (double) (era * 146097 + (int) doe - 719468);
}

static int xmlrect_integer_shape(xmlrect_span x) {
  const char *p = x.begin;
  if (p < x.end && (*p == '+' || *p == '-')) p++;
  if (p == x.end) return 0;
  for (; p < x.end; ++p) if (!xmlrect_is_digit(*p)) return 0;
  return 1;
}

static int xmlrect_integer_fits_r(xmlrect_span x) {
  const char *p = x.begin;
  int negative = 0;
  if (p < x.end && (*p == '+' || *p == '-')) {
    negative = (*p == '-');
    p++;
  }
  unsigned long long value = 0;
  for (; p < x.end; ++p) {
    unsigned digit = (unsigned) (*p - '0');
    if (value > 2147483647ULL / 10ULL) return 0;
    value = value * 10ULL + digit;
    if (value > 2147483647ULL) return 0;
  }
  (void) negative;
  return 1;
}

static int xmlrect_numeric_shape(xmlrect_span x) {
  const char *p = x.begin;
  if (p < x.end && (*p == '+' || *p == '-')) p++;
  const char *digits_before = p;
  while (p < x.end && xmlrect_is_digit(*p)) p++;
  int before = (int) (p - digits_before);
  int after = 0;
  if (p < x.end && *p == '.') {
    p++;
    const char *digits_after = p;
    while (p < x.end && xmlrect_is_digit(*p)) p++;
    after = (int) (p - digits_after);
  }
  if (before == 0 && after == 0) return 0;
  if (p < x.end && (*p == 'e' || *p == 'E')) {
    p++;
    if (p < x.end && (*p == '+' || *p == '-')) p++;
    const char *exp_start = p;
    while (p < x.end && xmlrect_is_digit(*p)) p++;
    if (p == exp_start) return 0;
  }
  return p == x.end;
}

static int xmlrect_numeric_leading_zero(xmlrect_span x) {
  const char *p = x.begin;
  if (p < x.end && (*p == '+' || *p == '-')) p++;
  const char *start = p;
  while (p < x.end && xmlrect_is_digit(*p)) p++;
  ptrdiff_t n = p - start;
  return n > 1 && start[0] == '0';
}

static double xmlrect_span_to_double(xmlrect_span x) {
  errno = 0;
  char *endptr = NULL;
  double value = strtod(x.begin, &endptr);
  if (endptr == x.begin || endptr != x.end || errno == ERANGE || !isfinite(value)) return NA_REAL;
  return value;
}

static int xmlrect_span_to_int(xmlrect_span x) {
  int sign = 1;
  const char *p = x.begin;
  if (*p == '+' || *p == '-') {
    if (*p == '-') sign = -1;
    p++;
  }
  int value = 0;
  while (p < x.end) {
    value = value * 10 + (*p - '0');
    p++;
  }
  return sign * value;
}

static int xmlrect_logical_code(xmlrect_span x) {
  if (x.end - x.begin == 1 && x.begin[0] == '1') return 1;
  if (x.end - x.begin == 1 && x.begin[0] == '0') return 0;
  if (xmlrect_ascii_equal_ci(x, "true")) return 1;
  if (xmlrect_ascii_equal_ci(x, "false")) return 0;
  return -1;
}

SEXP C_xmlrect_native_infer_types(SEXP columns_sexp) {
  if (TYPEOF(columns_sexp) != VECSXP) {
    Rf_error("Native type inference expects a list of character columns.");
  }

  R_xlen_t nc = XLENGTH(columns_sexp);
  SEXP result = PROTECT(Rf_allocVector(INTSXP, nc));

  for (R_xlen_t c = 0; c < nc; ++c) {
    SEXP column = VECTOR_ELT(columns_sexp, c);
    if (TYPEOF(column) != STRSXP) {
      UNPROTECT(1);
      Rf_error("Native type inference received a non-character column.");
    }

    R_xlen_t n = XLENGTH(column);
    int saw_value = 0;
    int saw_blank = 0;
    int all_date = 1;
    int all_logical = 1;
    int all_integer = 1;
    int all_numeric = 1;
    int any_true_false = 0;
    int any_leading_zero = 0;
    int lexical_distinct = 0;
    int logical_distinct = 0;
    xmlrect_span first_lex = {NULL, NULL};
    int first_logical = -2;

    for (R_xlen_t i = 0; i < n; ++i) {
      SEXP ch = STRING_ELT(column, i);
      if (ch == NA_STRING) continue;
      xmlrect_span x = xmlrect_trim_span(Rf_translateCharUTF8(ch));
      saw_value = 1;
      if (x.begin == x.end) {
        saw_blank = 1;
        break;
      }

      if (first_lex.begin == NULL) {
        first_lex = x;
      } else if (!xmlrect_span_equal(first_lex, x)) {
        lexical_distinct = 1;
      }

      int y, m, d;
      if (!xmlrect_date_parts(x, &y, &m, &d)) all_date = 0;

      int lcode = xmlrect_logical_code(x);
      if (lcode < 0) {
        all_logical = 0;
      } else {
        if (xmlrect_ascii_equal_ci(x, "true") || xmlrect_ascii_equal_ci(x, "false")) {
          any_true_false = 1;
        }
        int form = lcode;
        if (xmlrect_ascii_equal_ci(x, "true")) form = 2;
        else if (xmlrect_ascii_equal_ci(x, "false")) form = 3;
        if (first_logical == -2) first_logical = form;
        else if (form != first_logical) logical_distinct = 1;
      }

      int ishape = xmlrect_integer_shape(x);
      if (!ishape || !xmlrect_integer_fits_r(x)) all_integer = 0;

      int nshape = xmlrect_numeric_shape(x);
      if (!nshape) {
        all_numeric = 0;
      } else {
        if (xmlrect_numeric_leading_zero(x)) any_leading_zero = 1;
        double parsed = xmlrect_span_to_double(x);
        if (!isfinite(parsed)) all_numeric = 0;
      }
    }

    /* Codes: 0 character, 1 date, 2 logical, 3 integer, 4 double.  A nonzero
     * code is returned only for the R reference's high-confidence cases. */
    int type = 0;
    if (!saw_value || saw_blank) {
      type = 0;
    } else if (all_date) {
      type = lexical_distinct ? 1 : 0;
    } else if (all_logical) {
      if (!any_true_false) type = 0;
      else type = logical_distinct ? 2 : 0;
    } else if (all_integer) {
      if (any_leading_zero) type = 0;
      else type = lexical_distinct ? 3 : 0;
    } else if (all_numeric) {
      if (any_leading_zero) type = 0;
      else type = lexical_distinct ? 4 : 0;
    }

    INTEGER(result)[c] = type;
  }

  UNPROTECT(1);
  return result;
}

static const R_CallMethodDef CallEntries[] = {
  {"C_xmlrect_native_read", (DL_FUNC) &C_xmlrect_native_read, 3},
  {"C_xmlrect_native_analyst_plan", (DL_FUNC) &C_xmlrect_native_analyst_plan, 6},
  {"C_xmlrect_native_entity_map", (DL_FUNC) &C_xmlrect_native_entity_map, 5},
  {"C_xmlrect_native_project_fields", (DL_FUNC) &C_xmlrect_native_project_fields, 8},
  {"C_xmlrect_native_field_layout", (DL_FUNC) &C_xmlrect_native_field_layout, 4},
  {"C_xmlrect_native_infer_types", (DL_FUNC) &C_xmlrect_native_infer_types, 1},
  {NULL, NULL, 0}
};

void R_init_xmlrectr(DllInfo *dll) {
  R_registerRoutines(dll, NULL, CallEntries, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
}
