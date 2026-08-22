# Course-neighbor visualization helpers.
#
# The authoritative course-flow calculations live in R/branches/course-flows.R.
# This cone renders already summarized destination/feeders outputs.

#' Plot courses taken alongside a selected course
#'
#' @param concurrent_courses Output from `summarize_concurrent_courses()`.
#' @param opt Named list. `max_courses` limits displayed campus-course rows.
#' @return A Plotly treemap, or `NULL` when no concurrent courses are present.
plot_concurrent_course_treemap <- function(concurrent_courses, opt = list()) {
  if (is.null(concurrent_courses) || nrow(concurrent_courses) == 0L) {
    return(NULL)
  }

  max_courses <- as.integer(opt[["max_courses"]] %||% 20L)
  if (is.na(max_courses) || max_courses < 1L) max_courses <- 20L

  plotted <- concurrent_courses %>%
    dplyr::arrange(
      dplyr::desc(pct_selected_student_terms), campus, subject_course
    ) %>%
    dplyr::slice_head(n = max_courses)

  campuses <- unique(plotted$campus)
  campus_colors <- stats::setNames(
    rep(CEDAR_PALETTE, length.out = length(campuses)),
    campuses
  )

  campus_nodes <- plotted %>%
    dplyr::group_by(campus) %>%
    dplyr::summarise(value = sum(coenrolled_student_terms), .groups = "drop") %>%
    dplyr::transmute(
      id = paste0("campus::", campus),
      label = campus,
      parent = "",
      value,
      color = unname(campus_colors[campus]),
      hover = paste0(
        "Campus: ", campus,
        "<br>Top-course student-term enrollments: ",
        format(value, big.mark = ",", trim = TRUE)
      )
    )

  course_nodes <- plotted %>%
    dplyr::transmute(
      id = paste(campus, subject_course, sep = "::"),
      label = subject_course,
      parent = paste0("campus::", campus),
      value = coenrolled_student_terms,
      color = unname(campus_colors[campus]),
      hover = paste0(
        subject_course,
        "<br>Campus: ", campus,
        "<br>Co-enrolled student-terms: ",
        format(coenrolled_student_terms, big.mark = ",", trim = TRUE),
        "<br>Share of selected-course student-terms: ",
        format(round(pct_selected_student_terms, 1), nsmall = 1), "%",
        "<br>Average per selected-course term: ",
        format(round(avg_students_per_target_term, 1), nsmall = 1)
      )
    )

  nodes <- dplyr::bind_rows(campus_nodes, course_nodes)

  plotly::plot_ly(
    type = "treemap",
    ids = nodes$id,
    labels = nodes$label,
    parents = nodes$parent,
    values = nodes$value,
    branchvalues = "total",
    text = nodes$hover,
    hoverinfo = "text",
    textinfo = "label+value",
    marker = list(
      colors = nodes$color,
      line = list(color = "#ffffff", width = 2)
    )
  ) %>%
    plotly::layout(
      margin = list(t = 8, r = 8, b = 8, l = 8),
      paper_bgcolor = "rgba(0,0,0,0)"
    )
}

plot_course_sankey_by_term_with_flow_counts <- function(to_courses, from_courses, opt) {

  message("[course-neighbors.R] === SANKEY VISUALIZATION ===")
  message("[course-neighbors.R] Creating term-specific sankey for course: ", opt[["course"]])

  source_course <- opt[["course"]]
  min_contrib <- opt[["min_contrib"]] %||% 2
  max_courses <- opt[["max_courses"]] %||% 8

  message("[course-neighbors.R] Using visualization parameters:")
  message("[course-neighbors.R]   min_contrib: ", min_contrib)
  message("[course-neighbors.R]   max_courses: ", max_courses)

  term_types_to <- unique(to_courses$source_term_type)
  term_types_from <- unique(from_courses$target_term_type)
  target_term_types <- unique(c(term_types_to, term_types_from))
  target_term_types <- target_term_types[!is.na(target_term_types)]

  message("[course-neighbors.R] Creating plots for term types: ", paste(target_term_types, collapse = ", "))

  sankey_plots <- list()

  for (current_target_type in target_term_types) {
    message("[course-neighbors.R] --- Processing ", toupper(current_target_type), " term ---")

    to_term <- to_courses %>%
      dplyr::filter(source_term_type == !!current_target_type) %>%
      dplyr::filter(avg_contrib >= min_contrib) %>%
      dplyr::arrange(dplyr::desc(avg_contrib)) %>%
      head(max_courses)

    message("[course-neighbors.R] Outgoing flows (", nrow(to_term), " courses):")
    if (nrow(to_term) > 0) {
      for (i in 1:min(5, nrow(to_term))) {
        message("[course-neighbors.R]   ", to_term$subject_course[i], ": ",
                round(to_term$avg_contrib[i], 1), " students")
      }
    }

    from_term_all <- from_courses %>%
      dplyr::filter(target_term_type == !!current_target_type) %>%
      dplyr::filter(avg_contrib >= min_contrib)

    from_term <- from_term_all %>%
      dplyr::group_by(campus, subject_course) %>%
      dplyr::summarize(
        avg_contrib = sum(avg_contrib),
        source_term_type = paste(unique(source_term_type), collapse = ","),
        .groups = "drop"
      ) %>%
      dplyr::arrange(dplyr::desc(avg_contrib)) %>%
      head(max_courses)

    message("[course-neighbors.R] Incoming flows (", nrow(from_term), " courses):")
    if (nrow(from_term) > 0) {
      for (i in 1:min(5, nrow(from_term))) {
        message("[course-neighbors.R]   ", from_term$subject_course[i], " (",
                from_term$source_term_type[i], "): ",
                round(from_term$avg_contrib[i], 1), " students")
      }
    }

    if (nrow(to_term) == 0 && nrow(from_term) == 0) {
      message("[course-neighbors.R] No sufficient flows for ", current_target_type, " - skipping")
      next
    }

    campuses_in_plot <- sort(unique(c(to_term$campus, from_term$campus)))
    show_campus <- length(campuses_in_plot) > 1
    make_node_id <- function(course, campus) {
      if (show_campus) paste(course, campus, sep = "__CAMPUS__") else course
    }

    to_links <- to_term %>%
      dplyr::mutate(
        source = source_course,
        target = make_node_id(subject_course, campus),
        value = avg_contrib
      ) %>%
      dplyr::filter(subject_course != source_course) %>%
      dplyr::select(source, target, value)

    from_links <- from_term %>%
      dplyr::mutate(
        source = make_node_id(subject_course, campus),
        target = source_course,
        value = avg_contrib
      ) %>%
      dplyr::filter(subject_course != source_course) %>%
      dplyr::select(source, target, value)

    courses_in_both <- intersect(to_links$target, from_links$source)

    if (length(courses_in_both) > 0) {
      message("[course-neighbors.R] Found ", length(courses_in_both),
              " courses appearing in both directions: ",
              paste(courses_in_both, collapse = ", "))

      to_links <- to_links %>%
        dplyr::mutate(target = ifelse(
          target %in% courses_in_both, paste0(target, "_RIGHT"), target
        ))

      from_links <- from_links %>%
        dplyr::mutate(source = ifelse(
          source %in% courses_in_both, paste0(source, "_LEFT"), source
        ))
    }

    all_links <- rbind(to_links, from_links)

    if (nrow(all_links) == 0) {
      message("[course-neighbors.R] No valid links for ", current_target_type, " - skipping")
      next
    }

    message("[course-neighbors.R] Created ", nrow(all_links), " visualization links")

    total_to_flow <- if (nrow(to_term) > 0) sum(to_term$avg_contrib) else 0
    total_from_flow <- if (nrow(from_term) > 0) sum(from_term$avg_contrib) else 0

    message("[course-neighbors.R] Flow totals: OUT=", round(total_to_flow, 1),
            ", IN=", round(total_from_flow, 1))

    all_nodes <- unique(c(all_links$source, all_links$target))

    to_meta <- to_term %>%
      dplyr::mutate(
        node_id = make_node_id(subject_course, campus),
        direction = "to",
        term_text = "",
        contrib = avg_contrib
      ) %>%
      dplyr::select(node_id, subject_course, campus, direction, term_text, contrib)

    from_meta <- from_term %>%
      dplyr::mutate(
        node_id = make_node_id(subject_course, campus),
        direction = "from",
        term_text = source_term_type,
        contrib = avg_contrib
      ) %>%
      dplyr::select(node_id, subject_course, campus, direction, term_text, contrib)

    node_meta <- dplyr::bind_rows(to_meta, from_meta) %>%
      dplyr::distinct(node_id, .keep_all = TRUE)

    display_labels <- vapply(all_nodes, function(node) {
      base_node <- gsub("_(LEFT|RIGHT)$", "", node)
      meta <- node_meta %>%
        dplyr::filter(node_id == base_node) %>%
        dplyr::slice_head(n = 1)

      if (node == source_course) {
        campus_label <- if (show_campus) paste0("<br>", paste(campuses_in_plot, collapse = ", ")) else ""
        paste0(node, campus_label, "<br>(", current_target_type, ")<br>",
               "OUT: ", round(total_to_flow, 1), " | IN: ", round(total_from_flow, 1))
      } else if (nrow(meta) > 0) {
        campus_label <- if (show_campus) paste0("<br>", meta$campus) else ""
        if (grepl("_LEFT$", node) || meta$direction == "from") {
          paste0(meta$subject_course, campus_label, "<br>(",
                 meta$term_text, ": ~", round(meta$contrib, 1), ")")
        } else {
          paste0(meta$subject_course, campus_label, "<br>(~", round(meta$contrib, 1), ")")
        }
      } else {
        node
      }
    }, FUN.VALUE = character(1))

    node_colors <- vapply(all_nodes, function(node) {
      if (node == source_course) {
        "#1f77b4"
      } else if (grepl("_LEFT$", node) || node %in% from_links$source) {
        "#ff7f0e"
      } else {
        "#2ca02c"
      }
    }, FUN.VALUE = character(1))

    nodes_df <- data.frame(
      name = all_nodes,
      display_label = display_labels,
      color = node_colors,
      stringsAsFactors = FALSE
    )

    message("[course-neighbors.R] Created ", nrow(nodes_df), " nodes")

    all_links$source_id <- match(all_links$source, nodes_df$name) - 1
    all_links$target_id <- match(all_links$target, nodes_df$name) - 1

    sankey_plot <- plot_ly(
      type = "sankey",
      orientation = "h",
      node = list(
        label = nodes_df$display_label,
        color = nodes_df$color,
        pad = 15,
        thickness = 30
      ),
      link = list(
        source = all_links$source_id,
        target = all_links$target_id,
        value = all_links$value,
        color = ifelse(
          all_links$target == source_course,
          "rgba(255, 127, 14, 0.4)",
          "rgba(44, 160, 44, 0.4)"
        )
      )
    ) %>%
      layout(
        title = paste(toupper(current_target_type), "Flow:", source_course),
        font = list(size = 11),
        margin = list(t = 60)
      )

    sankey_plots[[current_target_type]] <- sankey_plot
    message("[course-neighbors.R] Created ", current_target_type, " sankey plot")
  }

  message("[course-neighbors.R] === SANKEY COMPLETE: Returning ", length(sankey_plots), " plots ===")
  sankey_plots
}
