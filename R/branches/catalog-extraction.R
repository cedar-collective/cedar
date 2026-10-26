# Pure transformations of captured public catalog records. Extracted != reviewed.

catalog_scalar <- function(record, field) {
  value <- record[[field]]
  if (is.null(value)) return("") # An absent source field is recorded as absent, never as no requirement.
  if (is.list(value) || length(value) != 1L || is.na(value)) {
    stop("[catalog-extraction.R] Expected scalar source field: ", field)
  }
  as.character(value)
}

catalog_named_value <- function(record, field) {
  value <- record[[field]]
  if (is.null(value)) return("")
  if (!is.list(value)) stop("[catalog-extraction.R] Expected named source value: ", field)
  catalog_scalar(value, "name")
}

validate_catalog_index <- function(index) {
  if (!is.list(index) || !length(index) || !is.null(names(index))) {
    stop("[catalog-extraction.R] Program index must be a nonempty JSON array")
  }
  ids <- vapply(index, catalog_scalar, character(1), field = "pid")
  if (any(!grepl("^[A-Za-z0-9_-]+$", ids)) || anyDuplicated(ids) ||
      any(!nzchar(vapply(index, catalog_scalar, character(1), field = "title")))) {
    stop("[catalog-extraction.R] Invalid or duplicate program index identifiers")
  }
  invisible(index)
}

catalog_program_scope <- function(index, credentials) {
  validate_catalog_index(index)
  if (!all(c("degree_type", "scope") %in% names(credentials)) || !nrow(credentials) ||
      anyNA(credentials) || any(!nzchar(credentials$degree_type)) || anyDuplicated(credentials$degree_type) ||
      any(!credentials$scope %in% c("undergraduate_degree", "excluded"))) {
    stop("[catalog-extraction.R] Invalid credential classification file")
  }
  types <- vapply(index, catalog_named_value, character(1), field = "degreeType")
  unknown <- setdiff(types[nzchar(types)], credentials$degree_type)
  if (length(unknown)) stop("[catalog-extraction.R] Unclassified degree types: ", paste(unknown, collapse = ", "))
  scope <- credentials$scope[match(types, credentials$degree_type)]
  scope[!nzchar(types)] <- "unclassified"
  data.frame(program_id = vapply(index, catalog_scalar, character(1), field = "pid"),
    title = vapply(index, catalog_scalar, character(1), field = "title"),
    degree_type = types, scope = scope, stringsAsFactors = FALSE)
}

catalog_html_document <- function(html) {
  xml2::read_html(paste0('<div id="cedar-source">', html, "</div>"),
    options = c("RECOVER", "NOERROR", "NOWARNING", "NONET"))
}

catalog_node_text <- function(node) {
  text <- paste(xml2::xml_text(xml2::xml_find_all(node,
    ".//text()[not(ancestor::script) and not(ancestor::style)]")), collapse = " ")
  trimws(gsub("[[:space:]\u00a0]+", " ", text))
}

catalog_html_text <- function(html) catalog_node_text(catalog_html_document(html))

# Course links are references, not prerequisite edges. Uninterpreted prose keeps
# its links without claiming that every mentioned course is required.
catalog_source_links <- function(html) {
  anchors <- xml2::xml_find_all(catalog_html_document(html), "//a[@href]")
  links <- xml2::xml_attr(anchors, "href")
  lapply(seq_along(links), function(i) list(label = trimws(xml2::xml_text(anchors[[i]])), href = links[i]))
}

catalog_entity_references <- function(html, kind) {
  if (!kind %in% c("courses", "programs")) stop("[catalog-extraction.R] Unknown reference kind")
  all <- catalog_source_links(html)
  links <- vapply(all, function(x) x$href, character(1))
  prefix <- paste0("^#/", kind, "/")
  keep <- grepl(paste0(prefix, "(view/)?[A-Za-z0-9_-]+(?:[?].*)?$"), links, perl = TRUE)
  all <- all[keep]; links <- links[keep]
  lapply(seq_along(links), function(i) list(
    key = sub("[?].*$", "", sub(prefix, "", links[i])),
    code = all[[i]]$label, href = links[i]))
}

catalog_course_references <- function(html) catalog_entity_references(html, "courses")
catalog_program_references <- function(html) catalog_entity_references(html, "programs")

#' Preserve list nesting, explicit choice counts and AND bundles; retain prose
#' as a condition requiring review. No attempt to infer eligibility is made.
extract_catalog_rule_tree <- function(html) {
  document <- catalog_html_document(html)
  # Published Kuali groups can wrap an option in div/span headings rather than
  # putting li directly under ul. Match the nearest list, so nested options
  # remain children of their own rule instead of being dropped or flattened.
  parse_list <- function(node) {
    unlist(lapply(xml2::xml_contents(node), function(child) {
      if (xml2::xml_type(child) %in% c("comment", "pi")) return(list())
      if (xml2::xml_type(child) == "text") {
        label <- trimws(gsub("[[:space:]\u00a0]+", " ", xml2::xml_text(child)))
        if (!nzchar(label)) return(list())
        return(list(list(operator = "condition", minimum = NULL, text = label,
          locator = xml2::xml_path(child), source_anchor = "", course_references = list(),
          children = list(), requires_review = TRUE)))
      }
      if (xml2::xml_name(child) == "li") return(list(parse_item(child)))
      candidates <- xml2::xml_find_all(child, ".//li")
      candidates <- candidates[vapply(candidates, function(x)
        identical(xml2::xml_path(xml2::xml_find_first(x, "ancestor::*[self::ul or self::ol][1]")),
          xml2::xml_path(node)), logical(1))]
      children <- lapply(candidates, parse_item)
      copy <- catalog_html_document(as.character(child))
      xml2::xml_remove(xml2::xml_find_all(copy, "//ul | //ol | //li"))
      label <- catalog_node_text(copy)
      if (!nzchar(label) && length(children)) return(children)
      if (!nzchar(label)) {
        # An orphan list is not an option with a known scope. Retain the whole
        # fragment for interpretation rather than dropping its course links.
        label <- catalog_node_text(child)
        if (!nzchar(label)) return(list())
        copy <- catalog_html_document(as.character(child))
      }
      headings <- xml2::xml_find_all(copy, "//span[starts-with(@class, 'rules_groupHeader_')]")
      is_heading <- length(headings) == 1L && length(children) == 1L &&
        identical(catalog_node_text(headings[[1]]), label)
      list(list(operator = if (is_heading) "group" else "condition", minimum = NULL,
        text = label, locator = xml2::xml_path(child), source_anchor = "",
        course_references = catalog_course_references(as.character(copy)), children = children,
        requires_review = !is_heading || any(vapply(children, function(x) isTRUE(x$requires_review), logical(1)))))
    }), recursive = FALSE)
  }
  parse_item <- function(node) {
    copy <- catalog_html_document(as.character(node))
    own <- xml2::xml_find_first(copy, "//li")
    xml2::xml_remove(xml2::xml_find_all(own, ".//ul | .//ol"))
    label <- catalog_node_text(own)
    lists <- xml2::xml_find_all(node, ".//ul | .//ol")
    lists <- lists[vapply(lists, function(x)
      identical(xml2::xml_path(xml2::xml_find_first(x, "ancestor::li[1]")), xml2::xml_path(node)), logical(1))]
    children <- unlist(lapply(lists, parse_list), recursive = FALSE)
    references <- catalog_course_references(as.character(own))
    program_references <- catalog_program_references(as.character(own))
    operator <- "condition"; minimum <- NULL; minimum_grade <- NULL; milestone <- NULL
    if (grepl("^Complete (all of the following|the following):?$", label, ignore.case = TRUE)) operator <- "all"
    choice <- regexec("^Complete (?:at least )?([0-9]+) of the following:?$", label, ignore.case = TRUE, perl = TRUE)
    count <- regmatches(label, choice)[[1]]
    if (length(count)) { operator <- "choose_n"; minimum <- as.integer(count[2]) }
    credit <- regexec("^Earn at least ([0-9]+(?:[.][0-9]+)?) credits from the following:?$", label, ignore.case = TRUE, perl = TRUE)
    count <- regmatches(label, credit)[[1]]
    if (length(count)) { operator <- "credits"; minimum <- as.numeric(count[2]) }
    # A grade is a constraint on this group, not an ignorable heading. Retain
    # its literal threshold (C != C-); no CEDAR outcome/pass policy is applied.
    grade <- regexec("^Earned a minimum grade of ([A-F][+-]?) in (each|at least ([0-9]+)) of the following:?$",
      label, ignore.case = TRUE, perl = TRUE)
    count <- regmatches(label, grade)[[1]]
    if (length(count)) {
      minimum_grade <- toupper(count[2])
      operator <- if (tolower(count[3]) == "each") "all" else "choose_n"
      if (operator == "choose_n") minimum <- as.integer(count[4])
    }
    if (!length(children) && length(references) == 1L &&
        grepl("^[A-Z]+[[:space:]]*[0-9]+[A-Z]*[[:space:]]*[-–].*\\([0-9]+([[:space:]]*[-–][[:space:]]*[0-9]+)?\\)$", label)) operator <- "course"
    if (!length(children) && !length(references) && !length(program_references)) {
      standing <- regmatches(label, regexec(
        "^Must (not )?have a class standing of ([[:alpha:]][[:alnum:]_-]*)$", label, ignore.case = TRUE))[[1]]
      if (length(standing)) {
        relation <- if (nzchar(standing[2])) "is_not" else "is"
        milestone <- list(type = "class_standing", relation = relation, value = standing[3],
          id = paste("class_standing", relation, standing[3], sep = ":"),
          label = paste0("Class standing: ", if (relation == "is_not") "not " else "", standing[3]))
        operator <- "milestone"
      }
    }
    if (!length(children) && !length(references) && length(program_references) == 1L &&
        identical(label, paste0("Admitted to ", program_references[[1]]$code))) {
      # Resolve the link against the captured program registry after all records
      # have been read. A matching label alone never identifies a program.
      milestone <- list(type = "program_admission", relation = "is", value = program_references[[1]]$key,
        label = paste0("Admission to ", program_references[[1]]$code))
      operator <- "milestone"
    }
    if ((operator %in% c("all", "credits") && !length(children)) ||
        (operator == "choose_n" && (minimum <= 0L || minimum > length(children) || !length(children)))) operator <- "condition"
    anchor <- xml2::xml_attr(node, "data-test")
    if (is.na(anchor)) anchor <- ""
    list(operator = operator, minimum = minimum, minimum_grade = minimum_grade, milestone = milestone, text = label,
      locator = xml2::xml_path(node), source_anchor = anchor,
      course_references = references, program_references = program_references, children = children,
      requires_review = operator == "condition" ||
        (!is.null(milestone) && milestone$type == "program_admission" && is.null(milestone$id)) ||
        any(vapply(children, function(x) isTRUE(x$requires_review), logical(1))))
  }
  roots <- xml2::xml_find_all(document, "//ul[not(ancestor::ul or ancestor::ol)] | //ol[not(ancestor::ul or ancestor::ol)]")
  children <- unlist(lapply(roots, parse_list), recursive = FALSE)
  outside <- xml2::xml_find_all(document,
    "//div[@id='cedar-source']//text()[not(ancestor::ul or ancestor::ol) and not(ancestor::script or ancestor::style)]")
  prose <- trimws(gsub("[[:space:]\u00a0]+", " ", paste(xml2::xml_text(outside), collapse = " ")))
  if (nzchar(prose)) children <- c(children, list(list(operator = "condition", minimum = NULL,
    text = prose, locator = "outside-lists", source_anchor = "", course_references = list(),
    children = list(), requires_review = TRUE)))
  list(operator = "document", children = children,
    requires_review = any(vapply(children, function(x) isTRUE(x$requires_review), logical(1))))
}

#' Extract configured public fields using the captured schema's labels/types
extract_catalog_record <- function(record, kind, receipt, edition, schemas, fields) {
  pid <- catalog_scalar(record, "pid")
  if (!nzchar(pid) || !nzchar(catalog_scalar(record, "title"))) stop("[catalog-extraction.R] Record lacks identity")
  schema <- schemas[[kind]]
  if (is.null(schema)) stop("[catalog-extraction.R] Missing captured schema: ", kind)
  sections <- list()
  candidate_fields <- union(fields$field, names(schema)[vapply(schema,
    function(x) is.list(x) && identical(x$type, "OmegaRules"), logical(1))])
  for (field in intersect(candidate_fields, names(record))) {
    html <- record[[field]]
    if (is.null(html) || identical(html, "")) next
    structured_value <- !is.character(html) || length(html) != 1L
    if (structured_value) html <- as.character(jsonlite::toJSON(html, auto_unbox = TRUE, null = "null", digits = NA))
    phase <- fields$phase[match(field, fields$field)]
    if (is.na(phase)) phase <- "unclassified"
    field_schema <- schema[[field]]
    label <- if (is.null(field_schema)) field else catalog_scalar(field_schema, "label")
    tree <- if (structured_value) list(operator = "document", children = list(list(
      operator = "condition", text = html, locator = "structured-source-value", minimum = NULL,
      course_references = list(), children = list(), requires_review = TRUE)), requires_review = TRUE)
      else extract_catalog_rule_tree(html)
    if (phase == "info") {
      tree <- list(operator = "document", children = list(list(operator = "text", text = catalog_html_text(html),
        minimum = NULL, locator = "informational-field", course_references = list(), children = list(),
        requires_review = FALSE)), requires_review = FALSE)
    }
    prefix <- if (is.null(receipt$json_pointer)) "" else receipt$json_pointer
    sections[[length(sections) + 1L]] <- list(field = field, label = label, phase = phase,
      text = catalog_html_text(html), html_sha256 = source_sha256(charToRaw(enc2utf8(html))),
      source_pointer = paste0(prefix, "/", field), tree = tree,
      source_links = catalog_source_links(html),
      course_references = catalog_course_references(html),
      requires_review = isTRUE(tree$requires_review) || phase == "unclassified")
  }
  metadata <- record[setdiff(names(record), c("pid", "id", "_score", "specializations",
    vapply(sections, function(x) x$field, character(1))))]
  metadata$specialization_ids <- sort(vapply(record$specializations, catalog_scalar, character(1), field = "pid"))
  list(kind = kind, pid = pid, revision_id = catalog_scalar(record, "id"), metadata = metadata,
    title = catalog_scalar(record, "title"), code = catalog_scalar(record, "code"),
    course_code = catalog_scalar(record, "__catalogCourseId"),
    degree_type = catalog_named_value(record, "degreeType"),
    degree_hours = catalog_scalar(record, "degreeHours"),
    department = catalog_named_value(record, "groupFilter1"),
    college = catalog_named_value(record, "groupFilter2"),
    catalog_id = edition$`_id`, catalog_title = edition$title,
    source = receipt, sections = sections, review_status = "unreviewed")
}

#' Flatten one extracted tree for CSV review; every node retains its source
catalog_rule_rows <- function(record, section) {
  rows <- list()
  visit <- function(node, parent = "", ordinal = "0") {
    id <- paste(record$kind, record$pid, section$field, ordinal, sep = ":")
    refs <- node$course_references
    rows[[length(rows) + 1L]] <<- data.frame(entity = paste(record$kind, record$pid, sep = ":"),
      title = record$title, field = section$field, phase = section$phase, node_id = id, parent_id = parent,
      operator = node$operator, minimum = if (is.null(node$minimum)) "" else as.character(node$minimum),
      minimum_grade = if (is.null(node$minimum_grade)) "" else node$minimum_grade,
      milestone_id = if (is.null(node$milestone$id)) "" else node$milestone$id,
      milestone_type = if (is.null(node$milestone)) "" else node$milestone$type,
      milestone_relation = if (is.null(node$milestone)) "" else node$milestone$relation,
      milestone_value = if (is.null(node$milestone)) "" else node$milestone$value,
      milestone_label = if (is.null(node$milestone)) "" else node$milestone$label,
      course_codes = paste(vapply(refs, function(x) x$code, character(1)), collapse = " | "),
      text = if (is.null(node$text)) "" else node$text,
      locator = if (is.null(node$locator)) "" else node$locator,
      source_pointer = section$source_pointer,
      source_sha256 = record$source$sha256, source_url = record$source$url,
      requires_review = isTRUE(node$requires_review), review_status = "unreviewed", stringsAsFactors = FALSE)
    for (i in seq_along(node$children)) visit(node$children[[i]], id, paste0(ordinal, ".", i))
  }
  visit(section$tree)
  do.call(rbind, rows)
}

#' Surface provider flags and coverage gaps without repairing or discarding data
catalog_source_issue_rows <- function(records, inventory, receipts, sections) {
  rows <- list()
  add <- function(issue, entity, title, pointer, receipt, detail, course_code = "") {
    if (is.null(receipt)) stop("[catalog-extraction.R] Source issue lacks a capture receipt")
    rows[[length(rows) + 1L]] <<- data.frame(issue = issue, entity = entity, title = title, course_code = course_code,
      source_pointer = pointer, source_url = receipt$url, source_sha256 = receipt$sha256,
      detail = detail, review_status = "unreviewed", stringsAsFactors = FALSE)
  }
  for (record in records) {
    entity <- paste(record$kind, record$pid, sep = ":")
    prefix <- if (is.null(record$source$json_pointer)) "" else record$source$json_pointer
    if (identical(record$metadata$`__passedCatalogQuery`, FALSE)) {
      add("source_query_flag_false", entity, record$title, paste0(prefix, "/__passedCatalogQuery"), record$source,
        "The source returned __passedCatalogQuery=false. Review this record's inclusion in the selected catalog; the flag alone does not explain why.", record$course_code)
    }
    if (record$kind == "programs" && !any(sections$entity == entity & sections$phase == "degree")) {
      add("no_degree_section", entity, record$title, prefix, record$source,
        "No degree-phase section was extracted. Missing coverage is not evidence of no degree requirements.")
    }
  }
  for (i in which(inventory$scope %in% c("unclassified", "undergraduate_candidate"))) {
    id <- inventory$program_id[i]
    add("credential_needs_review", paste0("programs:", id), inventory$title[i], "/degreeType",
      receipts[[paste0("program:", id)]], "The published credential could not be classified as a declared undergraduate degree or an exclusion.")
  }
  if (length(rows)) return(unique(do.call(rbind, rows)))
  as.data.frame(stats::setNames(rep(list(character()), 9), c("issue", "entity", "title", "course_code",
    "source_pointer", "source_url", "source_sha256", "detail", "review_status")))
}

#' Parse a single credit figure or explicit range ("120" or "123-130")
catalog_parse_credit_range <- function(text) {
  m <- regmatches(text, regexec("(\\d{2,3})(?:\\s*[-–]\\s*(\\d{2,3}))?", text, perl = TRUE))[[1]]
  if (!length(m) || !nzchar(m[1])) return(NULL)
  low <- as.numeric(m[2]); high <- if (nzchar(m[3])) as.numeric(m[3]) else low
  list(min = min(low, high), max = max(low, high))
}

#' Every "<label>: <number or range>" total-credit mention inside one section's text
catalog_credit_mentions_in_text <- function(text) {
  labels <- c("Grand Total Credits", "Total Credits", "Degree Hours", "Total Program Credits")
  label_alt <- paste(labels, collapse = "|")
  pattern <- paste0("(", label_alt, ")\\s*:?\\s*\\d{2,3}(?:\\s*[-–]\\s*\\d{2,3})?")
  whole <- regmatches(text, gregexpr(pattern, text, perl = TRUE))[[1]]
  if (!length(whole)) return(list())
  lapply(whole, function(one) {
    label <- regmatches(one, regexec(paste0("^(", label_alt, ")"), one, perl = TRUE))[[1]][2]
    range <- catalog_parse_credit_range(one)
    list(label = label, min = range$min, max = range$max)
  })
}

#' Flag total-credit mentions that conflict on one program's own captured page (e.g. a
#' structured Degree Hours field disagreeing with a "Grand Total Credits" figure printed
#' elsewhere on that same page). Scoped deliberately to the program record itself: a
#' concentration's own total almost always describes a smaller, different quantity (its
#' share of the major, not the whole degree), so comparing it against the parent's Degree
#' Hours produces false conflicts far more often than real ones (observed: 38 of ~115
#' programs in the 2026-2027 undergraduate scan). A later authored degree plan still needs
#' a human decision on which number is correct; this only stops a same-page conflict from
#' going unnoticed before the decision is made.
catalog_credit_conflict_rows <- function(records) {
  rows <- list()
  programs <- Filter(function(x) x$kind == "programs", records)
  for (program in programs) {
    mentions <- list()
    if (nzchar(program$degree_hours)) {
      range <- catalog_parse_credit_range(program$degree_hours)
      if (!is.null(range)) mentions[[length(mentions) + 1L]] <- list(
        label = "Degree Hours (structured field)", min = range$min, max = range$max, pointer = "/degreeHours")
    }
    for (section in program$sections) for (found in catalog_credit_mentions_in_text(section$text)) {
      mentions[[length(mentions) + 1L]] <- c(found, list(pointer = section$source_pointer))
    }
    if (length(mentions) < 2L) next
    conflict <- FALSE
    for (a in seq_along(mentions)) for (b in seq_along(mentions)) {
      if (b <= a) next
      if (mentions[[a]]$max < mentions[[b]]$min || mentions[[b]]$max < mentions[[a]]$min) conflict <- TRUE
    }
    if (!conflict) next
    describe <- function(m) sprintf("%s: %s (%s)", m$label,
      if (m$min == m$max) as.character(m$min) else paste0(m$min, "-", m$max), m$pointer)
    rows[[length(rows) + 1L]] <- data.frame(issue = "total_credit_conflict",
      entity = paste(program$kind, program$pid, sep = ":"), title = program$title, course_code = "",
      source_pointer = "/degreeHours", source_url = program$source$url, source_sha256 = program$source$sha256,
      detail = paste0("Conflicting total-credit mentions on this program's own captured page — ",
        paste(vapply(mentions, describe, character(1)), collapse = "; "),
        ". This flag does not say which number is correct, and does not compare against concentration-level totals."),
      review_status = "unreviewed", stringsAsFactors = FALSE)
  }
  if (length(rows)) return(do.call(rbind, rows))
  as.data.frame(stats::setNames(rep(list(character()), 9), c("issue", "entity", "title", "course_code",
    "source_pointer", "source_url", "source_sha256", "detail", "review_status")))
}
