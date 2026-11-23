# Shared UI helper functions available to all Shiny modules.
# Sourced by load-funcs.R before any module files.

# Sentinel value for the "all follow-on courses in this department" option in
# the Sequence Effect / Downstream Success course pickers. A reserved string
# rather than a real course code so it can never collide with one.
CR_ROLLUP_SENTINEL <- "__cedar_dept_rollup__"


# Format the group summaries shown beside a standardized mean difference.
# Continuous means need their decimals: rounding them like counts can make two
# visibly identical values appear to produce a large SMD. Binary summaries are
# percentages and stay at one decimal place.
cedar_format_balance_value <- function(value, type) {
  if (length(value) == 0L) return(character())
  type <- rep_len(type, length(value))
  out <- rep("—", length(value))
  usable <- !is.na(value)
  continuous <- usable & !is.na(type) & type == "continuous"
  other <- usable & !continuous
  out[continuous] <- formatC(value[continuous], format = "f", digits = 2)
  out[other] <- formatC(value[other], format = "f", digits = 1)
  out
}


# Collapsible info panel for column guides, methodology notes, and detail tables.
# Usage: info_panel("Title", p("..."), tags$ul(tags$li(...)))
info_panel <- function(title, ..., description = NULL, class = NULL) {
  classes <- paste(c("cedar-info-panel", class), collapse = " ")
  tags$details(
    class = classes,
    tags$summary(
      tags$span(
        class = "cedar-info-summary-copy",
        tags$span(class = "cedar-info-summary-title", title),
        if (!is.null(description)) {
          tags$span(class = "cedar-info-summary-description", description)
        }
      )
    ),
    tags$div(class = "panel-body", ...)
  )
}

CEDAR_DOCS_BASE_URL <- "https://cedarplatform.org"

cedar_docs_url <- function(path) {
  if (is.null(path)) path <- ""
  path <- sub("^/+", "", path)
  paste0(CEDAR_DOCS_BASE_URL, "/", path)
}

cedar_docs_link <- function(path, label = "Full methodology \u2192") {
  htmltools::tags$a(label, href = cedar_docs_url(path), target = "_blank", rel = "noopener")
}

# The short explanation and the full docs record share one source. Scope and
# run-specific diagnostics still belong beside the result, outside this helper.
cedar_definition_note <- function(id, version = NULL) {
  record <- cedar_definition(id, version)
  htmltools::tags$div(
    class = "cedar-definition-note",
    `data-definition-id` = record$id,
    `data-definition-version` = record$version,
    htmltools::tags$p(htmltools::tags$strong(paste0(record$title, ". ")), record$summary),
    htmltools::tags$p(htmltools::tags$strong("Exclusions. "), record$exclusions),
    htmltools::tags$ul(lapply(record$limitations, htmltools::tags$li)),
    cedar_definition_links(id, version, attributes = FALSE)
  )
}

# The definition's version and user-guide links alone, for a page that
# explains the metric in its own words and leaves the full record to the docs.
cedar_definition_links <- function(id, version = NULL, attributes = TRUE) {
  record <- cedar_definition(id, version)
  htmltools::tags$p(
    class = "cedar-definition-links",
    `data-definition-id` = if (attributes) record$id,
    `data-definition-version` = if (attributes) record$version,
    cedar_docs_link(paste0("users/definitions#", record$anchor),
                    paste0("Definition v", record$version, " \u2192")),
    " · ", cedar_docs_link(record$guide, "User guide \u2192")
  )
}

cedar_definition_panel <- function(ids, title = "What this view counts") {
  info_panel(title, lapply(ids, cedar_definition_note))
}

# The method slot of a section: scope, exclusions, thresholds, the edge used
# and the definition links. A section's visible sentence says what it answers
# in a reader's words; how it is counted goes here (ISSUES M43;
# docs/developers/shiny-modules.md#explaining-a-section).
#
# It shows as a small link after the section's sentence and opens as a dialog
# (www/cedar-custom.css, www/cedar-method-dialog.js). The content stays in the
# page as a <details>, so an output inside it is filled as before.
# concept   a key of docs/_data/concepts.yml: the section's plain paragraph,
#           shown first, with the view's own counts under "In this view".
# NULL method and no concept renders nothing.
cedar_method_panel <- function(method, title = "How this is counted", concept = NULL) {
  idea <- if (!is.null(concept)) cedar_section_concept(concept)
  if (is.null(method) && is.null(idea)) return(NULL)
  tags$details(
    class = "cedar-info-panel cedar-method-panel",
    tags$summary(tags$span(class = "cedar-info-summary-copy",
                           tags$span(class = "cedar-info-summary-title", title))),
    tags$div(
      class = "panel-body", role = "dialog", `aria-label` = title, tabindex = "-1",
      tags$div(class = "cedar-method-head",
               tags$span(class = "cedar-method-title", title),
               tags$button(type = "button", class = "cedar-method-close", "Close")),
      if (!is.null(idea)) tags$p(class = "cedar-method-idea", idea),
      if (!is.null(idea) && !is.null(method)) tags$p(class = "cedar-method-label", "In this view"),
      method)
  )
}

# A section's sentence with its method link after it, on one line of text.
cedar_section_lede <- function(description_tag, method_panel, class = NULL) {
  if (is.null(description_tag) && is.null(method_panel)) return(NULL)
  div(class = paste(c("cedar-section-lede", class), collapse = " "), description_tag, method_panel)
}

# Shared compact metric card. Keep the card itself column-agnostic so callers
# can place it in fluid rows, grids, or repeated campus summaries.
cedar_stat_card <- function(value, label, note = NULL, class = NULL) {
  div(
    class = paste(c("stat-card", class), collapse = " "),
    p(value, class = "stat-num"),
    p(label, class = "stat-lbl"),
    if (!is.null(note)) p(note, class = "stat-compare")
  )
}

# ── Finding figures ──────────────────────────────────────────────────────────
# A finding a page used to state as a sentence of counts, drawn instead: a
# card with the one count to act on, a thin bar splitting the whole into its
# parts, and the parts listed beneath with a swatch each. Pure (htmltools
# only). Every number arrives computed from a feature; these only lay it out.

# The card: a title with its scope beside it, the headline count with its
# caption, then the figures. `warn` marks a finding that asks for action.
cedar_finding_card <- function(title, ..., scope = NULL, headline = NULL,
                               caption = NULL, warn = FALSE, class = NULL) {
  div(
    class = paste(c("stat-card", "stat-card--left", "finding-card",
                    if (isTRUE(warn)) "finding-card--warn", class), collapse = " "),
    div(
      class = "finding-card-title",
      span(title),
      if (!is.null(scope) && !is.na(scope)) span(class = "text-note", scope)
    ),
    if (!is.null(headline)) {
      p(class = "finding-card-headline",
        span(class = "stat-num", headline), " ", span(class = "stat-lbl", caption))
    },
    ...
  )
}

# One whole split into parts: a thin segmented bar, and the parts listed under
# it. `parts` has `n` (the part's size), `tone` (critical, warning, success,
# info, neutral or muted: the swatch and segment fill), `label` and `detail`
# (NA for none). A part of zero is listed and draws nothing. `description` is
# the bar's accessible text, the sentence the figure replaces.
cedar_segment_figure <- function(parts, description = NULL) {
  required <- c("n", "tone", "label", "detail")
  if (!all(required %in% names(parts))) {
    stop("cedar_segment_figure(): parts needs ", paste(required, collapse = ", "), ".",
         call. = FALSE)
  }
  total <- sum(parts$n)
  drawn <- parts[parts$n > 0, , drop = FALSE]
  share <- 100 * drawn$n / total
  start <- cumsum(c(0, share))[seq_along(share)]
  pct <- function(x) paste0(round(x, 3), "%")
  tagList(
    if (total > 0) {
      tags$svg(
        class = "segment-bar", role = "img", `aria-label` = description,
        lapply(seq_len(nrow(drawn)), function(i) {
          tags$rect(
            class = paste0("segment-bar-part segment--", drawn$tone[[i]]),
            x = pct(start[[i]]), width = pct(share[[i]]), height = "100%",
            tags$title(paste(drawn$n[[i]], drawn$label[[i]]))
          )
        }),
        # The gap between touching parts, in the card's own colour.
        lapply(start[-1], function(at) {
          tags$rect(class = "segment-bar-gap", x = pct(at), width = 2, height = "100%",
                    transform = "translate(-1 0)")
        })
      )
    },
    tags$ul(
      class = "segment-legend",
      lapply(seq_len(nrow(parts)), function(i) {
        tags$li(
          span(class = paste0("segment-swatch segment--", parts$tone[[i]])),
          span(class = "segment-legend-count", format(parts$n[[i]], big.mark = ",")),
          span(
            span(class = "segment-legend-label", parts$label[[i]]),
            if (!is.na(parts$detail[[i]])) span(class = "text-note", parts$detail[[i]])
          )
        )
      })
    )
  )
}

# Amounts set against the amount each is for, one per row with the bars
# aligned: `meters` has `label`, `share` (the amount over what it is for) and
# `text` (both amounts in words). A bar past its mark runs to the end, and the
# mark, the amount it is for, moves in from it.
cedar_meter_list <- function(meters) {
  required <- c("label", "share", "text")
  if (!all(required %in% names(meters))) {
    stop("cedar_meter_list(): meters needs ", paste(required, collapse = ", "), ".",
         call. = FALSE)
  }
  pct <- function(x) paste0(round(100 * x, 3), "%")
  tags$dl(
    class = "meter-list",
    lapply(seq_len(nrow(meters)), function(i) {
      share <- meters$share[[i]]
      scale <- max(1, share)
      tagList(
        tags$dt(meters$label[[i]]),
        tags$dd(
          tags$svg(
            class = "meter-bar", role = "img",
            `aria-label` = paste0(meters$label[[i]], ": ", meters$text[[i]]),
            tags$rect(class = "meter-bar-track", width = "100%", height = "100%"),
            tags$rect(class = "meter-bar-fill", width = pct(share / scale), height = "100%"),
            if (share > 1) {
              tags$rect(class = "meter-bar-mark", x = pct(1 / scale), width = 2, height = "100%")
            }
          ),
          span(
            class = "meter-list-figure",
            tags$strong(scales::percent(share, accuracy = 0.1)), " ",
            span(class = "text-note", meters$text[[i]])
          )
        )
      )
    })
  )
}

# Two or more values set side by side as bars on one scale, one per row:
# `bars` has `label`, `share` (the value over the scale's end, 0-1), `text`
# (the value in words) and `reference` (TRUE draws the comparison's grey).
# For a finding card that sets a group beside what was expected of it.
cedar_compare_bars <- function(bars) {
  required <- c("label", "share", "text", "reference")
  if (!all(required %in% names(bars))) {
    stop("cedar_compare_bars(): bars needs ", paste(required, collapse = ", "), ".", call. = FALSE)
  }
  pct <- function(x) paste0(round(100 * min(max(x, 0), 1), 3), "%")
  tags$dl(
    class = "meter-list compare-bars",
    lapply(seq_len(nrow(bars)), function(i) {
      tagList(
        tags$dt(bars$label[[i]]),
        tags$dd(
          tags$svg(
            class = "meter-bar", role = "img", `aria-label` = paste0(bars$label[[i]], ": ", bars$text[[i]]),
            tags$rect(class = "meter-bar-track", width = "100%", height = "100%"),
            tags$rect(class = paste(c("meter-bar-fill", if (isTRUE(bars$reference[[i]])) "meter-bar-fill--reference"),
                                    collapse = " "),
                      width = pct(bars$share[[i]]), height = "100%")
          ),
          span(class = "meter-list-figure", tags$strong(bars$text[[i]]))
        )
      )
    })
  )
}

# Compact current-term snapshot: grouped measure rows, the current term as the
# anchor column, and earlier comparison terms beside it. The current column may
# split into sub-columns (e.g. All plus each crosslisted code); a row whose
# measure does not split leaves those sub-columns as one empty cell. Values
# arrive formatted from a prepare_* adapter; this only lays them out.
#   spec$caption        table title, e.g. "MATH 375 · ABQ"
#   spec$current_label  header for the current term
#   spec$sub_labels     NULL, or sub-column headers under current_label
#   spec$prior_labels   headers for the comparison terms
#   spec$rows           list of list(group, label, current, span_listings,
#                       prior, prior_titles). `current` holds one value, or
#                       one per sub-column; one value under sub-columns needs
#                       span_listings = TRUE. `prior` matches prior_labels.
#                       `prior_titles` (hover text) is optional; when given it
#                       matches `prior`, with NA for a cell without one.
#   spec$footnote       NULL or a sentence shown as a full-width table footer
cedar_snapshot_table <- function(spec) {
  n_sub <- max(1L, length(spec$sub_labels))
  n_cols <- 1L + n_sub + length(spec$prior_labels)
  split <- n_sub > 1L

  # A short row would shift every later cell into the wrong column, so a
  # malformed row stops here, by name, rather than rendering misaligned.
  for (row in spec$rows) {
    where <- paste0("cedar_snapshot_table(): row '", row$label, "' ")
    fills_current <- length(row$current) == n_sub ||
      (split && length(row$current) == 1L && isTRUE(row$span_listings))
    if (!fills_current) {
      stop(where, "has ", length(row$current), " current value(s) for ", n_sub,
           " column(s) and does not span them")
    }
    if (length(row$prior) != length(spec$prior_labels)) {
      stop(where, "has ", length(row$prior), " earlier value(s) for ",
           length(spec$prior_labels), " earlier term(s)")
    }
    if (!is.null(row$prior_titles) && length(row$prior_titles) != length(row$prior)) {
      stop(where, "has ", length(row$prior_titles), " hover title(s) for ",
           length(row$prior), " earlier value(s)")
    }
  }

  header <- if (split) {
    tagList(
      tags$tr(
        tags$th(rowspan = 2, scope = "col", class = "snap-corner"),
        tags$th(colspan = n_sub, scope = "colgroup", class = "snap-current", spec$current_label),
        lapply(spec$prior_labels, function(lbl) tags$th(rowspan = 2, scope = "col", class = "snap-prior", lbl))
      ),
      tags$tr(lapply(seq_len(n_sub), function(i) {
        tags$th(scope = "col",
                class = if (i == 1L) "snap-current" else "snap-current snap-listing",
                spec$sub_labels[[i]])
      }))
    )
  } else {
    tags$tr(
      tags$th(scope = "col", class = "snap-corner"),
      tags$th(scope = "col", class = "snap-current", spec$current_label),
      lapply(spec$prior_labels, function(lbl) tags$th(scope = "col", class = "snap-prior", lbl))
    )
  }

  body <- list()
  last_group <- NULL
  for (row in spec$rows) {
    if (!identical(row$group, last_group)) {
      body[[length(body) + 1]] <- tags$tr(
        class = "snap-group",
        tags$th(colspan = n_cols, scope = "colgroup", row$group)
      )
      last_group <- row$group
    }
    current_cells <- lapply(seq_along(row$current), function(i) {
      tags$td(class = if (i == 1L) "snap-current" else "snap-current snap-listing",
              row$current[[i]])
    })
    if (split && isTRUE(row$span_listings)) {
      current_cells <- c(current_cells, list(
        tags$td(colspan = n_sub - 1L, class = "snap-current snap-listing snap-span")
      ))
    }
    prior_cells <- lapply(seq_along(row$prior), function(i) {
      title <- if (is.null(row$prior_titles)) NA_character_ else row$prior_titles[[i]]
      tags$td(class = "snap-prior",
              title = if (!is.na(title)) title,
              row$prior[[i]])
    })
    body[[length(body) + 1]] <- tags$tr(
      tags$th(scope = "row", class = "snap-label", row$label),
      current_cells,
      prior_cells
    )
  }

  # The footnote is a table row spanning every column, so it is always exactly
  # as wide as the table, including when the table scrolls on a narrow screen.
  footer <- if (!is.null(spec$footnote)) {
    tags$tfoot(tags$tr(
      tags$td(colspan = n_cols, class = "cedar-snapshot-note", spec$footnote)
    ))
  }

  div(
    class = "cedar-snapshot",
    tags$table(
      class = "cedar-snapshot-table",
      tags$caption(spec$caption),
      tags$thead(header),
      tags$tbody(body),
      footer
    )
  )
}

# Standard informational modal. Use for explanations, warnings, and read-only
# detail views that can be dismissed without taking an app action.
# scrollable = TRUE keeps a long dialog inside the screen and scrolls its body.
cedar_info_modal <- function(title, ..., size = "m", close_label = "Close",
                             easyClose = TRUE, scrollable = FALSE, footer = NULL) {
  modal <- modalDialog(
    title = title,
    ...,
    size = size,
    easyClose = easyClose,
    footer = if (is.null(footer)) modalButton(close_label) else footer
  )
  if (!scrollable) return(modal)
  htmltools::tagQuery(modal)$find(".modal-dialog")$addClass("modal-dialog-scrollable")$allTags()
}

# Standard confirmation modal. Use for destructive or expensive actions where
# clicking outside the modal should not be treated as an intentional choice.
cedar_confirm_modal <- function(title, ..., confirm_button,
                                cancel_label = "Cancel", easyClose = FALSE) {
  modalDialog(
    title = title,
    ...,
    easyClose = easyClose,
    footer = tagList(
      modalButton(cancel_label),
      confirm_button
    )
  )
}

# Standard empty-state prompt shown before a user action (button click, selection).
# msg: instruction text shown to the user.
empty_state <- function(msg = "Set filters and click the button to load data.") {
  div(
    class = "empty-state",
    tags$p(msg)
  )
}

# Standard in-flow section heading for tab bodies. Replaces the ad-hoc
# h5(..., class = "text-secondary mb-1") pattern so spacing/size are uniform.
# level = "h6" renders the smaller subsection variant.
# Usage: section_heading("DFW Rates by Course")  /  section_heading("Changes by Term", level = "h6")
section_heading <- function(title, ..., level = "h5", class = NULL) {
  tag <- match.fun(level)
  base <- if (identical(level, "h6")) "cedar-section-heading--sub" else "cedar-section-heading"
  tag(class = paste(c(base, class), collapse = " "), title, ...)
}

# Shared heading + explanatory copy + body block.
# Use this when a section has a heading followed by a short description so the
# heading/paragraph/table spacing is consistent across modules.
section_block <- function(title, description = NULL, ..., level = "h5", class = NULL) {
  classes <- paste(c("cedar-section-block", class), collapse = " ")
  description_tag <- NULL
  if (!is.null(description)) {
    description_tag <- if (inherits(description, "shiny.tag") ||
                           inherits(description, "shiny.tag.list")) {
      description
    } else {
      tags$p(class = "text-hint", description)
    }
  }

  div(
    class = classes,
    section_heading(title, level = level),
    description_tag,
    ...
  )
}

# Title for a SUBTAB (a nav_panel/tabPanel inside a tab), plus one line saying
# what the subtab shows. Sits above any dashboard_section()s.
#
# This is a distinct level from dashboard_section_header(): a subtab title is
# near-black plain type, larger but visually lighter than the filled green
# section bars beneath it, so hierarchy reads as size-then-fill. Before this
# existed, every subtab opened with a section bar, which made the subtab's own
# title indistinguishable from a divider inside it.
#
# Usage: subtab_header("Rollcall", "Who takes this course, by classification and major.")
subtab_header <- function(title, description = NULL, ..., method = NULL, class = NULL) {
  description_parts <- Filter(Negate(is.null), c(list(description), list(...)))
  description_tag <- NULL
  if (length(description_parts) > 0) {
    description <- if (length(description_parts) == 1) {
      description_parts[[1]]
    } else if (all(vapply(description_parts, is.character, logical(1)))) {
      paste0(unlist(description_parts), collapse = "")
    } else {
      do.call(tagList, description_parts)
    }
    description_tag <- if (inherits(description, "shiny.tag") ||
                           inherits(description, "shiny.tag.list")) {
      tags$div(class = "cedar-subtab-description", description)
    } else {
      tags$p(class = "cedar-subtab-description", description)
    }
  }

  div(
    class = paste(c("cedar-subtab-header", class), collapse = " "),
    tags$h2(class = "cedar-subtab-title", title),
    cedar_section_lede(description_tag, cedar_method_panel(method, title = "What this view counts"))
  )
}

# Dashboard sections need a stronger hierarchy than regular tab sections:
# a broad group heading, optional short copy, then one or more compact panels.
dashboard_section_header <- function(title, description = NULL, ..., class = NULL, method_panel = NULL) {
  description_parts <- Filter(Negate(is.null), c(list(description), list(...)))
  description_tag <- NULL
  if (length(description_parts) > 0) {
    description <- if (length(description_parts) == 1) {
      description_parts[[1]]
    } else if (all(vapply(description_parts, is.character, logical(1)))) {
      paste0(unlist(description_parts), collapse = "")
    } else {
      do.call(tagList, description_parts)
    }

    description_tag <- if (inherits(description, "shiny.tag") ||
                           inherits(description, "shiny.tag.list")) {
      tags$div(class = "cedar-dashboard-section-description", description)
    } else {
      tags$p(class = "cedar-dashboard-section-description", description)
    }
  }

  div(
    class = paste(c("cedar-dashboard-section-header", class), collapse = " "),
    tags$h2(class = "cedar-dashboard-section-title", title),
    cedar_section_lede(description_tag, method_panel, class = "cedar-dashboard-section-lede")
  )
}

# An action button's click count as a plain integer, for a run key. A button
# that has not rendered yet reads NULL (0 here) and a rendered one Shiny's 0,
# which carries a class: identical() calls them different, so a key holding
# the raw value changes when a subtab's settings first render, and a view
# that already ran on its defaults runs again (ISSUES I66).
cedar_click_count <- function(value) as.integer(value %||% 0L)

# concept   a key of docs/_data/concepts.yml (see cedar_method_panel()).
dashboard_section <- function(title, description = NULL, ..., method = NULL, class = NULL, concept = NULL) {
  div(
    class = paste(c("cedar-dashboard-section", class), collapse = " "),
    dashboard_section_header(title, description, method_panel = cedar_method_panel(method, concept = concept)),
    div(class = "cedar-dashboard-section-body", ...)
  )
}

dashboard_subsection <- function(title, description = NULL, ..., method = NULL,
                                 class = NULL, tone = NULL) {
  description_tag <- NULL
  if (!is.null(description)) {
    description_tag <- if (inherits(description, "shiny.tag") ||
                           inherits(description, "shiny.tag.list")) {
      description
    } else {
      tags$p(class = "cedar-dashboard-subsection-description", description)
    }
  }

  div(
    class = paste(c("cedar-dashboard-subsection", class), collapse = " "),
    tags$h3(class = paste(c("cedar-dashboard-subsection-title", tone), collapse = " "), title),
    cedar_section_lede(description_tag, cedar_method_panel(method)),
    ...
  )
}

# Primary explanatory paragraph ("what this tab/section does"). rem-based so it
# escapes the global body 0.9em shrink. Use for the lead copy under a heading.
lead_text <- function(...) tags$p(class = "cedar-lead", ...)

# Standard top filter band used by Cedar tabs and modules.
filter_bar <- function(title, subtitle = NULL, ..., class = NULL) {
  classes <- paste(c("filters-compact", class), collapse = " ")
  div(
    class = classes,
    h1(title),
    if (!is.null(subtitle)) tags$p(subtitle, class = "filter-subtitle"),
    ...
  )
}

# Aligns run/download/copy buttons with compact filter inputs.
# A run button that waits for what it needs: disabled, with `hint` as its
# tooltip, until its inputs hold a value (www/cedar-navigation.js keeps it in
# step as they change). The one way CEDAR disables a run button for a missing
# input; the server's own check stays as the last guard. A button that waits
# on server state (a defined population) is set by the server with
# updateActionButton(disabled =).
#   button  the actionButton() tag.
#   inputs  full input ids (ns() applied) that must all hold a value; with
#           `when`, a named list from each value of the `when` input to the
#           ids that case needs (an empty case needs nothing).
#   any     TRUE: one of the ids is enough.
#   when    the id of an input (a radio group or select) that decides which
#           case applies.
cedar_requires <- function(button, inputs, hint, any = FALSE, when = NULL) {
  spec <- if (is.null(when)) {
    list(inputs = as.list(as.character(inputs)))
  } else {
    if (is.null(names(inputs)) || any(!nzchar(names(inputs)))) {
      stop("cedar_requires(): with `when`, inputs is a list named by its values.")
    }
    list(when = when, cases = lapply(inputs, function(ids) as.list(as.character(ids))))
  }
  spec$any <- isTRUE(any)
  htmltools::tagAppendAttributes(
    button, disabled = NA, `aria-disabled` = "true",
    `data-cedar-requires` = as.character(jsonlite::toJSON(spec, auto_unbox = TRUE)),
    `data-cedar-requires-hint` = hint
  )
}

# A page's link button: a small menu with "Copy link" and "Make this my start
# page". `id` is the copy input's full id (ns("x_copy_url") in a module): "Copy
# link" keeps it, so cedar_copy_url_observer() is unchanged; the start-page
# item is `<id>_home`, and the visible toggle `<id>_menu`, which the
# observer flashes. The start page lives in this browser (www/cedar-navigation.js).
cedar_link_menu <- function(id) {
  div(
    class = "dropdown cedar-link-menu",
    tags$button(
      id = paste0(id, "_menu"), type = "button",
      class = "btn btn-outline-secondary btn-sm dropdown-toggle",
      `data-bs-toggle` = "dropdown", `aria-expanded` = "false",
      title = "Copy a link to this view, or make it your start page",
      `aria-label` = "Link options",
      icon("link")
    ),
    tags$ul(
      class = "dropdown-menu dropdown-menu-end",
      tags$li(actionLink(id, "Copy link", icon = icon("copy"), class = "dropdown-item")),
      tags$li(actionLink(paste0(id, "_home"), "Make this my start page", icon = icon("house"),
                         class = "dropdown-item"))
    )
  )
}

filter_actions <- function(..., class = NULL) {
  classes <- paste(c("filter-actions", class), collapse = " ")
  div(class = classes, ...)
}

# Light green scope strip shown at the bottom of a filter bar.
filter_scope_stripe <- function(...) {
  div(class = "filter-scope-strip", ...)
}

# One labelled chip in a scope bar. Empty values render nothing, so a bar can
# list every part and show only those that apply.
scope_chip <- function(key, val, class = NULL) {
  if (is.null(val) || length(val) == 0 || !any(nzchar(as.character(val)))) return(NULL)
  span(class = paste(c("scope-chip", class), collapse = " "),
       span(class = "scope-chip-key", key),
       span(class = "scope-chip-val", paste(val, collapse = ", ")))
}

# A stacked scope bar saying what a headcount counted, one chip per part of
# describe_headcount_scope(). Shared by the Headcount tab and the Dept
# Dashboard so the two read as the same count.
headcount_scope_bar <- function(described, ...) {
  div(class = "scope-bar scope-bar--stacked", ...,
      lapply(names(described), function(k) scope_chip(k, described[[k]])))
}

# The codes a department's figures are built from, each with its name: course
# subjects, programs (accelerated online X-prefix codes apart) and pre-majors,
# one block per unit, from unit_mapping_rows(). Shared by Dept Trends, the Dept
# Dashboard and Headcount, so every scope bar names the same codes the mapping
# files assign. Rows wrap (filter-context-row), since names make them long.
#
# The visible line is facts only: the unit, its code counts and, given
# `time_facts` (cedar_scope_time_facts()), one chip per time fact. Explanation
# (`time_meaning`, cedar_in_progress_meaning()) opens with the codes.
unit_codes_scope <- function(rows, time_facts = NULL, time_meaning = NULL) {
  only <- function(college, level) {
    parts <- c(if (!is.na(college)) paste(college, "only"),
               if (!is.na(level)) paste(level, "only"))
    if (length(parts)) paste0(" (", paste(parts, collapse = ", "), ")") else NULL
  }
  item <- function(code, label = NULL) {
    tags$span(tags$code(class = "filter-context-code", code),
              tags$span(class = "filter-context-name", label))
  }
  row_item <- function(label, items) {
    if (length(items) == 0) return(NULL)
    tags$div(class = "filter-context-row",
             tags$span(label, class = "filter-context-label"), items)
  }
  # The unit and its college stay in view; the codes behind them open on a
  # click (ISSUES M43). The text is in the page either way, so a search or a
  # browser check still finds every code.
  unit_titles <- vapply(seq_len(nrow(rows$units)), function(i) {
    u <- rows$units[i, ]
    college <- if (is.na(u$college_code)) "no home college" else
      if (is.na(u$college_name)) u$college_code else u$college_name
    paste0(u$unit_name, " (", u$unit_code, "), ", college)
  }, character(1))
  n_codes <- function(n, one, many) if (n > 0) paste(n, if (n == 1) one else many)
  code_counts <- paste(c(
    n_codes(nrow(rows$subjects), "course subject", "course subjects"),
    n_codes(sum(!rows$programs$is_pre_major), "program", "programs"),
    n_codes(sum(rows$programs$is_pre_major), "pre-major", "pre-majors")
  ), collapse = " · ")
  blocks <- lapply(seq_len(nrow(rows$units)), function(i) {
    u  <- rows$units[i, ]
    sj <- rows$subjects[rows$subjects$unit_code == u$unit_code, ]
    pr <- rows$programs[rows$programs$unit_code == u$unit_code, ]
    online <- grepl("^X", pr$program_code)
    program_items <- function(p) lapply(seq_len(nrow(p)), function(j) {
      item(p$program_code[j], paste0(
        p$program_name[j],
        if (p$is_pre_major[j] && !is.na(p$leads_to[j])) paste0(" → ", p$leads_to[j]),
        only(p$in_college[j], NA)))
    })
    tagList(
      # One unit is named in the summary already; several are told apart here.
      if (nrow(rows$units) > 1) div(class = "filter-context-title", unit_titles[[i]]),
      row_item("Course subject codes:",
               lapply(seq_len(nrow(sj)), function(j)
                 item(sj$subject_code[j], only(sj$in_college[j], sj$in_level[j])))),
      row_item("Program codes:", program_items(pr[!pr$is_pre_major & !online, ])),
      row_item("Accelerated online codes (X-prefix):", program_items(pr[!pr$is_pre_major & online, ])),
      row_item("Pre-major codes:", program_items(pr[pr$is_pre_major, ]))
    )
  })
  tags$details(
    class = "scope-bar scope-bar--stacked cedar-scope-details",
    tags$summary(
      tags$span(class = "filter-context-title",
                paste0("Data scope for ", paste(unit_titles, collapse = "; "))),
      lapply(names(time_facts), function(k) scope_chip(k, paste(time_facts[[k]], collapse = "; "))),
      tags$span(class = "cedar-scope-details-hint",
                paste0(code_counts, if (nzchar(code_counts)) " — " else "",
                       if (is.null(time_meaning)) "show the codes" else "show the codes and term notes"))
    ),
    if (!is.null(time_meaning)) tags$div(class = "filter-context-row",
      tags$span(class = "filter-context-label", time_meaning)),
    blocks,
    tags$div(class = "filter-context-row",
             tags$span(class = "filter-context-label",
                       paste("Concentrations count with the student's primary major.",
                             "Every code is a row in the institution mapping files;",
                             "see Admin > Data & Usage > Mappings.")))
  )
}

# Shared campus + single-department selector formulation for department tabs.
dept_selector_bar <- function(title, subtitle, campus_input, dept_input,
                              term_input = NULL, actions = NULL, scope_output = NULL) {
  # When a term picker is present the dept column narrows to make room for it,
  # so campus/term/dept/actions still fit one row. Callers without a term input
  # (e.g. Dept Trends) keep the original two-column widths unchanged.
  dept_width <- if (is.null(term_input)) 4 else 3
  actions_width <- if (is.null(term_input)) 3 else 2
  filter_bar(
    title,
    subtitle,
    fluidRow(
      column(3, campus_input),
      if (!is.null(term_input)) column(2, term_input),
      column(dept_width, dept_input),
      if (!is.null(actions)) column(actions_width, actions)
    ),
    scope_output
  )
}

# Shared reactable theme — used by all cedar tables for consistent styling.
cedar_tbl_theme <- reactable::reactableTheme(
  # Colours are CSS tokens (www/cedar-custom.css), so a table follows the
  # page between light and dark mode without re-rendering.
  color           = "var(--table-text)",
  backgroundColor = "var(--table-bg)",
  borderColor     = "var(--table-border)",
  stripedColor    = "var(--table-stripe)",
  highlightColor  = "var(--table-highlight)",
  cellPadding     = "5px 10px",
  style           = list(fontSize = "0.87rem"),
  headerStyle     = list(
    background    = "var(--table-header-bg)",
    color         = "var(--table-header-text)",
    fontWeight    = "600",
    fontSize      = "0.73rem",
    textTransform = "uppercase",
    letterSpacing = "0.05em",
    borderBottom  = "2px solid var(--table-header-rule)"
  ),
  inputStyle      = list(backgroundColor = "var(--input-bg)", color = "var(--table-text)"),
  pageButtonStyle = list(color = "var(--table-text)"),
  paginationStyle = list(fontSize = "0.82rem")
)

# Standardized "Part of Term" (PoT) column for cedar tables. Reuse this everywhere a
# ── Sparkline / trend cell renderers ─────────────────────────────────────────
# Inline SVG history sparkline and the trend-cell HTML that wraps it. Shared by
# the regstats bumps/dips/drops/saturation tables and the waitlists course
# overview so a course's current value reads against its own history the same way
# everywhere. Pure (htmltools + base R only), so they render outside a Shiny
# reactive as well.

# Inline sparkline of `values` (a numeric history, ordered oldest→newest). The
# term being viewed can be marked with a dot via current_idx. Returns an empty
# span when there is too little variation to plot.
make_sparkline <- function(values, current_idx = NULL, width = 80, height = 20,
                           col = "#8BAF99", cur_col = "#3F5E4B") {
  vals <- suppressWarnings(as.numeric(values))
  vals <- vals[!is.na(vals)]
  if (length(vals) < 2) return(htmltools::span())
  n    <- length(vals)
  vmin <- min(vals); vmax <- max(vals)
  if (vmax == vmin) return(htmltools::span())
  pad <- 2
  xs  <- round((seq_len(n) - 1) / (n - 1) * (width - pad * 2) + pad, 1)
  ys  <- round((1 - (vals - vmin) / (vmax - vmin)) * (height - pad * 2) + pad, 1)
  pts <- paste(xs, ys, sep = ",", collapse = " ")
  dot <- if (!is.null(current_idx) && current_idx >= 1 && current_idx <= n)
    paste0('<circle cx="', xs[current_idx], '" cy="', ys[current_idx],
           '" r="2.5" fill="', cur_col, '"/>')
  else ""
  htmltools::HTML(paste0(
    '<svg width="', width, '" height="', height,
    '" style="display:inline-block;vertical-align:middle;margin-left:4px;">',
    '<polyline points="', pts, '" fill="none" stroke="', col,
    '" stroke-width="1.5" stroke-linejoin="round" stroke-linecap="round"/>',
    dot, '</svg>'
  ))
}

# Linear (scaled) units-per-term slope; NA when fewer than 3 points.
# Wraps the canonical compute_trend() (R/trunk/utils.R) with this cell's display
# conventions: a scale factor (points vs. rate metrics), a 3-point minimum, and
# rounding to one decimal.
trend_slope <- function(v, scale = 1) {
  round(unname(compute_trend(v * scale, min_n = 3)$slope), 1)
}
fmt_slope <- function(s, unit) if (is.na(s)) "n/a" else
  paste0(if (s >= 0) "+" else "", formatC(s, format = "f", digits = 1), unit)

# Renders a metric's same-term-type history as a sparkline with the viewed term dotted,
# a ▲/▼ chip for the trend *heading into* that term, and a tooltip carrying the full-arc
# trend and comparison average. pct = TRUE for rate metrics (fill rate 0–1, shown as
# points/term); FALSE for counts (enrollment, drops — shown as units/term).
trend_cell_html <- function(series, terms, cur_term, pct = FALSE,
                            baseline_mean = NULL, baseline_n = NULL) {
  if (is.null(series) || length(series) < 2) return("")
  cur   <- match(cur_term, terms)
  scale <- if (pct) 100 else 1
  unit  <- if (pct) " pts/term" else "/term"
  todot <- if (!is.na(cur)) trend_slope(series[seq_len(cur)], scale) else NA_real_
  arc   <- trend_slope(series, scale)
  prior_baseline <- !is.null(baseline_mean)
  avg_v <- if (prior_baseline) baseline_mean else if (!is.na(cur)) mean(series[-cur], na.rm = TRUE) else mean(series, na.rm = TRUE)
  avg_t <- if (pct) paste0(round(avg_v * 100), "%") else formatC(avg_v, format = "f", digits = 1)
  spark <- as.character(make_sparkline(series, cur, width = 66, height = 18, cur_col = "#A15D4E"))
  tip   <- paste0("Trend into ", cur_term, ": ", fmt_slope(todot, unit),
                  " · full-arc: ", fmt_slope(arc, unit),
                  if (prior_baseline) " · prior avg " else " · reference avg ", avg_t,
                  " over ", if (prior_baseline) baseline_n else length(series) - as.integer(!is.na(cur)),
                  if (prior_baseline) " earlier terms" else " reference terms")
  chip  <- if (!is.na(todot) && abs(todot) >= 1) {
    up <- todot > 0
    sprintf('<span style="font-size:0.72rem;font-weight:600;margin-left:3px;color:%s">%s%s</span>',
            if (up) "#A15D4E" else "#6F8B78", if (up) "▲" else "▼",
            formatC(abs(todot), format = "f", digits = 1))
  } else ""
  sprintf('<div title="%s" style="display:flex;align-items:center;gap:2px">%s%s</div>',
          htmltools::htmlEscape(tip, attribute = TRUE), spark, chip)
}

# table shows part_term so the label and cell treatment stay identical across tabs.
#   - Full-term ("1") is the common case, dimmed to "Full".
#   - Missing/blank shows an em dash.
#   - Half-term / nonstandard variants (1H, 2H, INT, …) stand out in semibold, because
#     they are analyzed as distinct offerings rather than folded into the course.
# The header opts out of the theme's uppercase transform so it reads "PoT" (lowercase
# o), not "POT".
#' A course code cell that names the codes the course used to carry
#'
#' The code in the table's usual weight, with the course's former codes and
#' their terms beneath it in the sub-text style, so a reader of a table keyed
#' on course_id (ADR-001 step 4) can see which history is behind the row.
#'
#' @param code The course's code (its `course_id`).
#' @param former_codes The row's `former_codes` text, or NA when the course
#'   has carried one code.
#' @param onclick Optional JavaScript run when the code is clicked (a drill);
#'   the code is then a link and the former codes stay plain text beneath it.
course_code_cell <- function(code, former_codes = NA_character_, onclick = NULL) {
  label <- htmltools::span(class = "fw-semibold", code)
  if (!is.null(onclick)) {
    label <- htmltools::tags$a(href = "javascript:void(0)", onclick = onclick, label)
  }
  if (length(former_codes) != 1L || is.na(former_codes) || !nzchar(former_codes)) {
    return(label)
  }
  htmltools::tagList(
    label,
    htmltools::div(class = "text-sub", paste0("also ", former_codes))
  )
}

cedar_pot_coldef <- function(name = "PoT", maxWidth = 52, align = "center") {
  reactable::colDef(
    name        = name,
    maxWidth    = maxWidth,
    align       = align,
    headerStyle = list(textTransform = "none"),
    cell = function(v) {
      if (is.na(v) || v == "" || v == "1")
        htmltools::span(class = "text-sub", if (is.na(v) || v == "") "—" else "Full")
      else htmltools::span(class = "fw-semibold", v)
    }
  )
}

# Count and rate columns for reactable tables (AGENTS.md, Numeric precision):
# whole counts with thousands separators, rates as percentages at one decimal,
# and an em dash where the value is unknown, never 0. Values stay numeric, so
# the columns sort and filter on the number.
cedar_count_coldef <- function(name, ...) {
  reactable::colDef(name = name, align = "right", na = "\u2014",
                    format = reactable::colFormat(separators = TRUE), ...)
}

# The courses a group of students took most (summer_course_list()'s `courses`):
# code, title, the campus that taught it, students, and their share of the group.
# titles   describe_courses() output for the listed courses.
cedar_course_share_table <- function(courses, titles, share_label) {
  if (NROW(courses) == 0L) return(reactable::reactable(
    data.frame(Message = "No course was taken by enough of these students to list."),
    theme = cedar_tbl_theme, compact = TRUE))
  shown <- data.frame(course = courses$subject_course,
                      title = titles$title[match(courses$subject_course, titles$subject_course)],
                      campus = courses$campus, n = courses$n_students, share = courses$share_pct / 100,
                      stringsAsFactors = FALSE)
  reactable::reactable(shown, theme = cedar_tbl_theme, compact = TRUE, striped = TRUE, defaultPageSize = 15,
    columns = list(course = reactable::colDef(name = "Course", minWidth = 110),
                   title = reactable::colDef(name = "Title", minWidth = 220, na = "\u2014"),
                   campus = reactable::colDef(name = "Campus"),
                   n = cedar_count_coldef("Students"), share = cedar_percent_coldef(share_label)))
}

cedar_percent_coldef <- function(name, ...) {
  reactable::colDef(name = name, align = "right", na = "\u2014",
                    format = reactable::colFormat(percent = TRUE, digits = 1), ...)
}

# A difference between two rates, in percentage points, signed at one decimal.
cedar_points_coldef <- function(name, ...) {
  reactable::colDef(name = name, align = "right", na = "\u2014",
                    cell = function(v) if (is.na(v)) "\u2014" else sprintf("%+.1f", v), ...)
}

# A rate (0-100, unrounded) shown with the count beside it: "76.0% (45)", or
# with `of = TRUE` its denominator, "76.0% of 45". `counts` is that count's
# column of the same table, in the table's row order; reactable passes the
# row's index to the cell, so the pairing survives sorting. A rate withheld by
# a small-cell guard shows an em dash, with the count in its hover text.
cedar_pct_count_coldef <- function(name, counts, of = FALSE, ...) {
  force(counts)
  reactable::colDef(
    name = name,
    align = "right",
    minWidth = 110,
    cell = function(value, index) {
      count <- counts[[index]]
      n <- if (is.na(count)) "\u2014" else
        format(as.integer(count), big.mark = ",", scientific = FALSE, trim = TRUE)
      if (is.na(value)) {
        return(htmltools::tags$span(
          title = if (!is.na(count)) paste0(n, " students; too few for a rate"), "\u2014"))
      }
      rate <- paste0(formatC(value, format = "f", digits = 1), "%")
      htmltools::tags$span(class = "text-nowrap",
                           if (of) paste0(rate, " of ", n) else paste0(rate, " (", n, ")"))
    },
    ...
  )
}

# ── How alike two groups were (build_comparison() / compute_balance()) ──────
# Every observational comparison on Course Dynamics > Downstream reads its
# balance through these: Against Non-Takers (course-cohort.R), Prepared for It
# (server.R) and the instructor check in Next Courses (later-course.R). One
# table, a row per measured characteristic with each group's value, the
# standardized difference and its band; a characteristic measured after the
# outcome (the registrar's current GPA) joins it as a described row with no
# difference, so a reader never has two tables of the same people to reconcile.
# Nothing here infers comparability from the absence of a substantial
# difference.

CEDAR_BALANCE_READING <- c(
  small = "Small difference",
  review = "Review",
  substantial = "Substantial difference",
  unavailable = "Unavailable"
)

CEDAR_BALANCE_CATEGORY_LABELS <- c(
  ipeds_race = "Race and ethnicity", gender = "Gender", time_status = "Full- or part-time",
  residency = "Residency", admissions_population = "Admissions population",
  student_population = "Student population", student_classification = "Classification"
)

# A covariate's name for a reader: the course report's label where it has one.
cedar_balance_measure_label <- function(covariate) {
  label <- unname(CEDAR_COVARIATE_LABELS[covariate])
  label[is.na(label)] <- gsub("_", " ", covariate[is.na(label)])
  paste0(toupper(substr(label, 1, 1)), substr(label, 2, nchar(label)))
}

# The verdict over the whole table, in one sentence.
cedar_balance_verdict <- function(balance) {
  switch(
    balance$overall_balance %||% "unavailable",
    substantial = paste0(
      "At least one measured characteristic differs substantially between the groups (a standardized difference above 0.25), ",
      "so a gap between them partly reflects who entered each group."),
    review = paste0(
      "At least one measured characteristic differs by 0.10 to 0.25 standard deviations and none by more: ",
      "close, but not close enough to call the groups alike."),
    small = paste0(
      "Every measured characteristic differs by less than 0.10 standard deviations. ",
      "That says nothing about what was not measured."),
    "No measured characteristic could be compared between the groups."
  )
}

#' The balance table for display
#'
#' @param balance `compute_balance()` output.
#' @param group_labels The two groups' names, treatment first.
#' @param described NULL, or rows shown for description only: `measure`,
#'   `value_treatment`, `value_control` (already formatted) and `note`.
#' @return One row per characteristic: Measure, each group's value, how many
#'   in each group have one, the difference with its band marked, and the
#'   reading.
cedar_balance_rows <- function(balance, group_labels, described = NULL) {
  smd <- balance$smd_table
  required <- c("covariate", "type", "n_treatment", "n_control", "value_treatment",
                "value_control", "smd", "balance_band")
  missing <- setdiff(required, names(smd))
  if (length(missing) > 0) stop("cedar_balance_rows(): smd_table lacks ", paste(missing, collapse = ", "), call. = FALSE)
  value <- function(v, type) {
    out <- cedar_format_balance_value(v, type)
    ifelse(type == "binary" & out != "—", paste0(out, "%"), out)
  }
  rows <- tibble::tibble(
    Measure = cedar_balance_measure_label(smd$covariate),
    a = value(smd$value_treatment, smd$type),
    b = value(smd$value_control, smd$type),
    `With a value` = paste0(format(smd$n_treatment, big.mark = ",", trim = TRUE), " / ",
                            format(smd$n_control, big.mark = ",", trim = TRUE)),
    Difference = dplyr::case_when(
      is.na(smd$smd) ~ "—",
      smd$balance_band == "substantial" ~ paste0(sprintf("%.3f", smd$smd), " ⚠"),
      smd$balance_band == "review" ~ paste0(sprintf("%.3f", smd$smd), " △"),
      TRUE ~ sprintf("%.3f", smd$smd)
    ),
    Reading = unname(CEDAR_BALANCE_READING[smd$balance_band])
  )
  if (!is.null(described) && nrow(described) > 0) {
    rows <- dplyr::bind_rows(rows, tibble::tibble(
      Measure = described$measure, a = described$value_treatment, b = described$value_control,
      `With a value` = "—", Difference = "—", Reading = described$note))
  }
  names(rows)[2:3] <- group_labels
  rows
}

# The categorical characteristics: each group's share in every category.
.cedar_balance_categories <- function(categorical, group_labels) {
  if (is.null(categorical) || length(categorical) == 0L) return(NULL)
  info_panel(
    "Characteristics with categories",
    description = "Each group's share in every category, read directly rather than as one difference.",
    div(class = "cedar-balance-categories", lapply(names(categorical), function(varname) {
      d <- categorical[[varname]] %>%
        tidyr::pivot_wider(id_cols = "value", names_from = "group", values_from = "pct", values_fill = 0)
      for (g in c("treatment", "control")) if (!g %in% names(d)) d[[g]] <- 0
      d <- d %>%
        dplyr::transmute(Value = as.character(value), a = treatment, b = control) %>%
        dplyr::arrange(dplyr::desc(a))
      names(d)[2:3] <- paste0(group_labels, ", %")
      div(
        section_heading(if (varname %in% names(CEDAR_BALANCE_CATEGORY_LABELS)) CEDAR_BALANCE_CATEGORY_LABELS[[varname]]
                        else tools::toTitleCase(gsub("_", " ", varname)), level = "h6"),
        reactable::reactable(d, theme = cedar_tbl_theme, compact = TRUE, striped = TRUE,
                             pagination = FALSE, defaultColDef = reactable::colDef(minWidth = 90))
      )
    }))
  )
}

#' How alike two groups were, as one block of the trust section
#'
#' @param balance `compute_balance()` output, or NULL when none was built.
#' @param group_labels The two groups' names, treatment first.
#' @param question One sentence: which two groups, measured when.
#' @param described See [cedar_balance_rows()].
#' @param method Extra method text for this comparison, beside the bands.
#' @param title The block's heading.
cedar_alike_block <- function(balance, group_labels, question, described = NULL, method = NULL,
                              title = "How Alike the Groups Were") {
  smd <- balance$smd_table
  div(
    class = "cedar-alike-block",
    section_heading(title, level = "h6"),
    tags$p(class = "text-hint", question),
    cedar_method_panel(tagList(
      tags$p("Each characteristic's difference is standardized: the gap between the two groups' values in units of their pooled standard deviation, so it reads the same for a GPA, a credit count or a share. Under 0.10 is a small difference, 0.10 to 0.25 one to review (\u25b3), above 0.25 a substantial one (\u26a0). For a yes-or-no characteristic the value is each group's share with it; for the rest, the group's average."),
      tags$p("The bands describe what was measured. They adjust nothing, and a small difference on every row does not show the groups were alike in what was not measured."),
      method
    )),
    if (is.null(balance) || is.null(smd) || nrow(smd) == 0L) {
      tags$p(class = "text-note", "No characteristic could be measured for both groups.")
    } else tagList(
      tags$p(class = "cedar-balance-verdict", cedar_balance_verdict(balance)),
      reactable::reactable(
        cedar_balance_rows(balance, group_labels, described),
        theme = cedar_tbl_theme, compact = TRUE, striped = TRUE, pagination = FALSE,
        columns = list(Measure = reactable::colDef(minWidth = 170),
                       Reading = reactable::colDef(minWidth = 150))
      ),
      .cedar_balance_categories(balance$categorical, group_labels)
    )
  )
}

# ── Downstream's last section ────────────────────────────────────────────────
# Every view on Course Dynamics > Downstream ends the same way: one section
# named "How Far to Trust It" holding who was counted (collapsed), how alike
# the compared groups were, and anything else that bounds the reading. Its
# sentence says what limits this comparison; `method` holds what it cannot
# show.
downstream_trust_section <- function(description, who_counted = NULL, ..., method = NULL) {
  dashboard_subsection(
    "How Far to Trust It", description, method = method,
    if (!is.null(who_counted)) info_panel(
      "Who is counted", who_counted,
      description = "The groups, their sizes, the data window and who was left out."),
    ...
  )
}

# ── Shared loading overlay ───────────────────────────────────────────────────
# Data-heavy tabs show the standard dash-loader spinner box while a report runs.
# cedar_loading_overlay() renders that box plus the JS that shows it the instant
# the run button is pressed and hides it when the server calls
# signal_load_complete(). Both sides share one contract: the message channel is
# paste0(id, "_load_complete") and the DOM ids are prefixed with `id`, so the UI
# `id` MUST equal the module id the server runs under.
#
#   id           module id — also the overlay id prefix and the message channel.
#   run_button   run button's id relative to the module (e.g. "cn_button"); the
#                overlay shows on a capture-phase click of "#<id>-<run_button>".
#                Deep-link autorun uses the overlay's early URL bootstrap instead.
#   trigger_input  alternative to run_button for non-module tabs (dashboard,
#                  enrollment): a Shiny input name watched via shiny:inputchanged.
#                  The overlay shows when that input changes — use it when the run
#                  signal is a select or actionButton whose DOM id is not
#                  namespaced as "<id>-<run_button>". Supply at most one of
#                  run_button / trigger_input. With neither, only the server
#                  opens the overlay: cedar_with_loading() around the work, for
#                  a page that reads on open or whenever a filter changes.
#   hide_on_empty  with trigger_input, also hide the overlay when the watched
#                  input clears to empty (e.g. deselecting a dashboard department).
#   ...            the tab body placed under the overlay (typically a uiOutput()).
#   emoji          glyph shown over the spinner (defaults to the cedar tree).
#   report_type    optional timing-log key; when given, fresh/cached estimates are
#                  looked up (see report_time_estimates) and shown in the label.
#   fresh_default  fallback fresh estimate (seconds) until the log has fresh runs.
#   cached_default fallback cache-hit estimate; leave NULL for tabs that never
#                  cache so the label stays a single "(est. Ns)".
#   loading_label  action-specific text shown beside the spinner.
#   loading_detail optional explanation of what the blocking load prepares.
#   show_at_start  TRUE renders the overlay visible, for a tab whose content
#                  loads as soon as it is opened with no run button: the page
#                  otherwise looks finished while its outputs are still seconds
#                  away. The server must then always send a completion (or an
#                  error) for the first load, or the overlay never leaves.
#
# Labels use the recent median-to-90th-percentile end-to-end range. With both a
# fresh and cached estimate the label names both paths; with neither, it stays
# plain "Loading…". On completion the server
# passes `cached` (see signal_load_complete) so the timing line names which path
# ran: "Loaded from cache in Ns" / "Generated in Ns" / "Loaded in Ns".
.cedar_format_loading_script <- function(template, ...) {
  values <- list(...)
  for (value in values) {
    template <- sub("%s", as.character(value), template, fixed = TRUE)
  }
  if (grepl("%s", template, fixed = TRUE)) {
    stop("cedar_loading_overlay(): unmatched script placeholder.")
  }
  template
}

cedar_loading_overlay <- function(id, run_button = NULL, ..., emoji = "\U0001f332",
                                  trigger_input = NULL, hide_on_empty = FALSE,
                                  report_type = NULL, fresh_default = NULL,
                                  cached_default = NULL,
                                  loading_label = "Loading…",
                                  loading_detail = NULL,
                                  show_at_start = FALSE) {
  if (!is.null(run_button) && !is.null(trigger_input)) {
    stop("cedar_loading_overlay(): supply run_button or trigger_input, not both.")
  }
  # The page body goes in `...`: a tag passed second, unnamed, lands here and
  # would be written into the overlay's script.
  for (arg in list(run_button = run_button, trigger_input = trigger_input)) {
    if (!is.null(arg) && !(is.character(arg) && length(arg) == 1L)) {
      stop("cedar_loading_overlay(): run_button and trigger_input are input names; ",
           "pass the page body after them, or name run_button = NULL.")
    }
  }
  # Embed learned values on process startup so a busy single-threaded Shiny
  # worker does not leave the hard-coded default visible for the entire run.
  # The browser still requests current values whenever the overlay opens, so
  # history resets and later observations take effect without another restart.
  learned <- if (!is.null(report_type) && nzchar(report_type) &&
                 exists("report_time_estimates", mode = "function")) {
    tryCatch(
      report_time_estimates(report_type, fresh_default, cached_default),
      error = function(e) NULL
    )
  } else {
    NULL
  }
  fresh_sec <- if (!is.null(learned$fresh)) learned$fresh else fresh_default
  cached_sec <- if (!is.null(learned$cached)) learned$cached else cached_default
  fresh_range <- learned$fresh_range
  cached_range <- learned$cached_range
  if (is.null(fresh_range) && !is.null(fresh_sec)) {
    fresh_range <- list(lower = fresh_sec, upper = fresh_sec)
  }
  if (is.null(cached_range) && !is.null(cached_sec)) {
    cached_range <- list(lower = cached_sec, upper = cached_sec)
  }
  expected_js <- if (is.null(fresh_sec))  "null" else as.integer(fresh_sec)
  cached_js   <- if (is.null(cached_sec)) "null" else as.integer(cached_sec)
  expected_range_js <- if (is.null(fresh_range)) "null" else
    jsonlite::toJSON(fresh_range, auto_unbox = TRUE, null = "null")
  cached_range_js <- if (is.null(cached_range)) "null" else
    jsonlite::toJSON(cached_range, auto_unbox = TRUE, null = "null")
  report_js   <- if (is.null(report_type)) "" else report_type
  fresh_default_js <- if (is.null(fresh_default))  "null" else as.integer(fresh_default)
  cached_default_js <- if (is.null(cached_default)) "null" else as.integer(cached_default)
  runbtn_js   <- if (is.null(run_button))    "" else run_button
  trigger_js  <- if (is.null(trigger_input)) "" else trigger_input
  hide_js     <- if (isTRUE(hide_on_empty))  "true" else "false"
  loading_label <- as.character(loading_label %||% "Loading…")[[1]]
  loading_label_js <- jsonlite::toJSON(
    loading_label, auto_unbox = TRUE
  )
  div(
    class = "loader-anchor",
    div(
      id = paste0(id, "-loading-overlay"),
      class = "dash-loader-overlay",
      role = "dialog",
      `aria-modal` = "true",
      `aria-labelledby` = paste0(id, "-loading-label"),
      # The script adopts an already-visible overlay on DOMContentLoaded.
      style = if (isTRUE(show_at_start)) "display: flex;" else "display: none;",
      div(class = "dash-loader-backdrop"),
      div(class = "dash-loader-box",
        div(class = "dash-loader-icon",
          div(class = "dash-spinner"),
          tags$span(emoji, class = "dash-tree-icon")
        ),
        div(id = paste0(id, "-loading-label"), class = "dash-loader-msg", loading_label),
        if (!is.null(loading_detail)) {
          div(class = "dash-loader-detail", loading_detail)
        },
        div(id = paste0(id, "-timing-msg"),    class = "dash-timing-msg")
      )
    ),
    tags$script(HTML(.cedar_format_loading_script(
'(function() {
  var PREFIX = "%s", RUNBTN = "%s", TRIGGER = "%s", HIDE_EMPTY = %s;
  var LOADING_LABEL = %s;
  var REPORT_TYPE = "%s", FRESH_DEFAULT = %s, CACHED_DEFAULT = %s;
  var EXPECTED = %s, CACHED = %s;
  var EXPECTED_RANGE = %s;
  var CACHED_RANGE = %s;
  var hideTimer = null, finalizeTimer = null;
  var measurementActive = false, runStartedAt = null, completionReceivedAt = null, completionMsg = null;
  var payloadBytes = 0, outputNames = {};
  function el(suffix) { return document.getElementById(PREFIX + suffix); }

  function beginMeasurement() {
    if (measurementActive) return;
    measurementActive = true;
    runStartedAt = performance.now();
    completionReceivedAt = null;
    completionMsg = null;
    payloadBytes = 0;
    outputNames = {};
  }

  // An autorun URL can reveal the overlay from the early <head> script before
  // Shiny connects. Adopt that already-visible overlay once the DOM is ready so
  // its later completion message can always finalize and dismiss it.
  document.addEventListener("DOMContentLoaded", function() {
    var box = el("-loading-overlay");
    if (box && box.style.display !== "none") beginMeasurement();
  });

  // Track only output values belonging to this overlay. This approximates the
  // JSON payload Shiny delivers; it deliberately excludes query contents and
  // is not presented as an exact websocket byte count.
  $(document).on("shiny:value", function(e) {
    if (!measurementActive || !activeReport || !e.name) return;
    var output = document.getElementById(e.name);
    var box = el("-loading-overlay");
    var anchor = box && box.closest ? box.closest(".loader-anchor") : null;
    if (!output || !anchor || !anchor.contains(output)) return;
    try {
      var encoded = JSON.stringify(e.value);
      if (encoded !== undefined) {
        payloadBytes += window.TextEncoder
          ? new TextEncoder().encode(encoded).length
          : new Blob([encoded]).size;
      }
    } catch (ignore) {}
    outputNames[e.name] = true;
  });

  // Shiny idle means its output queue has been processed. Two paint frames and
  // a short settle period include the browser work that follows value delivery.
  $(document).on("shiny:idle", function() { scheduleFinalize(); });

  if (TRIGGER) {
    // Input-change trigger for non-module tabs whose run signal is a select or
    // actionButton input (no namespaced run button to click).
    $(document).on("shiny:inputchanged", function(e) {
      if (e.name !== TRIGGER) return;
      if (HIDE_EMPTY) {
        if (e.value !== null && e.value !== undefined && e.value !== "") showOverlay();
        else hideOverlay();
      } else {
        showOverlay();
      }
    });
  } else if (RUNBTN) {
    // Capture-phase click so the overlay opens before the manual run reaches
    // the Shiny input binding.
    document.addEventListener("click", function(e) {
      if (e.target && e.target.closest && e.target.closest("#" + PREFIX + "-" + RUNBTN)) showOverlay();
    }, true);
  }

  // The server opens it too (signal_load_start(), cedar_with_loading()), with
  // the label of the work it is starting when it names one.
  var customLabel = null;
  Shiny.addCustomMessageHandler(PREFIX + "_load_start", function(msg) {
    showOverlay(msg && msg.label, msg && msg.report_type, msg && msg.fresh_default);
  });
  Shiny.addCustomMessageHandler(PREFIX + "_load_complete", function(msg) { completeOverlay(msg || {}); });
  Shiny.addCustomMessageHandler(PREFIX + "_timing_estimates", function(msg) {
    EXPECTED = msg && msg.fresh !== null && msg.fresh !== undefined ? msg.fresh : activeFreshDefault;
    CACHED = msg && msg.cached !== null && msg.cached !== undefined ? msg.cached : activeCachedDefault;
    EXPECTED_RANGE = msg && msg.fresh_range ? msg.fresh_range
                   : (EXPECTED === null ? null : {lower: EXPECTED, upper: EXPECTED});
    CACHED_RANGE = msg && msg.cached_range ? msg.cached_range
                 : (CACHED === null ? null : {lower: CACHED, upper: CACHED});
    var box = el("-loading-overlay");
    if (box && box.style.display !== "none") el("-loading-label").textContent = loadingLabel();
  });

  function rangeText(range, fallback) {
    if (!range) return fallback ? "~" + fallback + "s" : "";
    var low = Number(range.lower), high = Number(range.upper);
    if (!isFinite(low)) low = Number(fallback);
    if (!isFinite(high)) high = low;
    if (!isFinite(low)) return "";
    return high > low + 1 ? "~" + low + "–" + high + "s" : "~" + low + "s";
  }

  function loadingLabel() {
    var label = customLabel || LOADING_LABEL;
    var freshText = rangeText(EXPECTED_RANGE, EXPECTED);
    var cachedText = rangeText(CACHED_RANGE, CACHED);
    if (freshText && cachedText) return label + " (cached " + cachedText + "; fresh " + freshText + ")";
    if (freshText) return label + " (usually " + freshText + ")";
    return label;
  }

  // The server may name a timing log for the work (the report_type of
  // cedar_with_loading()), so a subtab wait is estimated from its own runs,
  // never from the page. Without one the overlay keeps its built-in estimates.
  var ORIG = { expected: EXPECTED, cached: CACHED, expectedRange: EXPECTED_RANGE, cachedRange: CACHED_RANGE };
  var activeReport = REPORT_TYPE, activeFreshDefault = FRESH_DEFAULT, activeCachedDefault = CACHED_DEFAULT;
  var elapsedTimer = null;
  function showOverlay(label, reportType, freshDefault) {
    customLabel = (typeof label === "string" && label) ? label : null;
    clearTimeout(hideTimer);
    clearTimeout(finalizeTimer);
    beginMeasurement();
    if (typeof reportType === "string" && reportType && reportType !== REPORT_TYPE) {
      activeReport = reportType;
      activeFreshDefault = (freshDefault === undefined) ? null : freshDefault;
      activeCachedDefault = null;
      EXPECTED = activeFreshDefault; CACHED = null;
      EXPECTED_RANGE = null; CACHED_RANGE = null;
    } else {
      activeReport = REPORT_TYPE; activeFreshDefault = FRESH_DEFAULT; activeCachedDefault = CACHED_DEFAULT;
      EXPECTED = ORIG.expected; CACHED = ORIG.cached;
      EXPECTED_RANGE = ORIG.expectedRange; CACHED_RANGE = ORIG.cachedRange;
    }
    if (activeReport && window.Shiny && Shiny.setInputValue) {
      Shiny.setInputValue("cedar_timing_estimate_request", {
        prefix: PREFIX,
        report_type: activeReport,
        fresh_default: activeFreshDefault,
        cached_default: activeCachedDefault,
        nonce: Date.now()
      }, {priority: "event"});
    }
    var box = el("-loading-overlay");
    if (!box) return;
    el("-loading-label").textContent = loadingLabel();
    el("-timing-msg").textContent = "";
    // How long it has been working, so a wait is never a blank screen.
    clearInterval(elapsedTimer);
    elapsedTimer = setInterval(function() {
      if (runStartedAt === null) return;
      var s = Math.round((performance.now() - runStartedAt) / 1000);
      if (s >= 2) el("-timing-msg").textContent = "Working for " + s + "s";
    }, 1000);
    box.style.opacity = "0";
    box.style.display = "flex";
    box.style.transition = "opacity 0.2s ease";
    box.offsetWidth;
    box.style.opacity = "1";
  }

  function completeOverlay(msg) {
    var box = el("-loading-overlay");
    if (!box || box.style.display === "none") return;
    if (msg.error) {
      stopMeasurement();
      fadeOut(0);
      return;
    }
    // A completion message must never leave a visible overlay stranded, even if
    // the corresponding browser-side start event was missed during startup.
    if (!measurementActive) beginMeasurement();
    completionMsg = msg;
    completionReceivedAt = performance.now();
    // Start a paint-based settle immediately. If Shiny still has output work,
    // its subsequent idle event calls scheduleFinalize() again and extends the
    // measurement from that later boundary.
    scheduleFinalize();
    // Defensive fallback for a disconnected or older Shiny client that never
    // emits an idle event after the custom completion message.
    finalizeTimer = setTimeout(finalizeMeasurement, 5000);
  }

  function scheduleFinalize() {
    if (!measurementActive || !completionMsg) return;
    clearTimeout(finalizeTimer);
    requestAnimationFrame(function() {
      requestAnimationFrame(function() {
        finalizeTimer = setTimeout(finalizeMeasurement, 100);
      });
    });
  }

  function finalizeMeasurement() {
    if (!measurementActive || !completionMsg || runStartedAt === null) return;
    clearTimeout(finalizeTimer);
    var totalSec = Math.max((performance.now() - runStartedAt) / 1000, 0);
    var computeSec = Number(completionMsg.duration_sec);
    if (!isFinite(computeSec) || computeSec < 0) computeSec = null;
    var postComputeSec = computeSec === null ? null : Math.max(totalSec - computeSec, 0);
    var completionSec = completionReceivedAt === null ? totalSec
                      : Math.max((completionReceivedAt - runStartedAt) / 1000, 0);
    var queueDeliverySec = computeSec === null ? null : Math.max(completionSec - computeSec, 0);
    var browserSettleSec = Math.max(totalSec - completionSec, 0);

    if (window.Shiny && Shiny.setInputValue) {
      Shiny.setInputValue("cedar_client_render_timing", {
        report_type: activeReport,
        overlay_id: PREFIX,
        compute_sec: computeSec,
        total_sec: Math.round(totalSec * 1000) / 1000,
        post_compute_sec: postComputeSec === null ? null : Math.round(postComputeSec * 1000) / 1000,
        queue_delivery_sec: queueDeliverySec === null ? null : Math.round(queueDeliverySec * 1000) / 1000,
        browser_settle_sec: Math.round(browserSettleSec * 1000) / 1000,
        payload_bytes: payloadBytes,
        output_count: Object.keys(outputNames).length,
        cached: completionMsg.cached === true ? true : completionMsg.cached === false ? false : null,
        operation_id: completionMsg.operation_id || null,
        viewport_width: window.innerWidth,
        viewport_height: window.innerHeight,
        nonce: Date.now()
      }, {priority: "event"});
    }

    var verb = completionMsg.cached === true ? "Loaded from cache"
             : completionMsg.cached === false ? "Generated"
             : "Loaded";
    var txt = verb + " — ready in " + totalSec.toFixed(1) + "s";
    if (computeSec !== null) txt += " (" + computeSec + "s calculation)";
    el("-timing-msg").textContent = txt;
    stopMeasurement();
    fadeOut(800);
  }

  function stopMeasurement() {
    clearInterval(elapsedTimer);
    clearTimeout(finalizeTimer);
    measurementActive = false;
    runStartedAt = null;
    completionReceivedAt = null;
    completionMsg = null;
  }

  function hideOverlay() {
    clearTimeout(hideTimer);
    stopMeasurement();
    var box = el("-loading-overlay");
    if (!box) return;
    box.style.transition = "";
    box.style.opacity = "1";
    box.style.display = "none";
  }

  function fadeOut(delay) {
    var box = el("-loading-overlay");
    hideTimer = setTimeout(function() {
      box.style.transition = "opacity 0.4s ease";
      box.style.opacity = "0";
      setTimeout(function() {
        box.style.display = "none";
        box.style.transition = "";
        box.style.opacity = "1";
      }, 400);
    }, delay);
  }
})();',
      id, runbtn_js, trigger_js, hide_js, loading_label_js, report_js,
      fresh_default_js, cached_default_js, expected_js, cached_js,
      expected_range_js, cached_range_js
    ))),
    ...
  )
}

# Server companion to cedar_loading_overlay(): hides the overlay for module `id`
# by sending the "<id>_load_complete" message its script listens for.
#   error  = TRUE dismisses with no timing readout.
#   cached = TRUE  → "Loaded from cache in Ns"; FALSE → "Generated in Ns";
#            NULL (default, non-caching tabs) → "Loaded in Ns".
# Rounding is handled here.
signal_load_start <- function(session, id, label = NULL, report_type = NULL, fresh_default = NULL) {
  session$sendCustomMessage(paste0(id, "_load_start"),
                            list(label = label, report_type = report_type, fresh_default = fresh_default))
}

# Run `expr` behind the loading overlay `id` (session$ns("load") in a module,
# cedar_loading_overlay(ns("load"), ...) in its UI): opens it with `label`,
# and always closes it, with the elapsed time when `expr` returns a value and
# with no timing when it fails or returns NULL (a caught error), so no page is
# left behind a stuck overlay (ISSUES I31). The page's one way of saying it is
# working, in place of withProgress().
# With `report_type`, the work is timed into its own log (start_report_timer()),
# and the overlay's "usually ~Ns" is read from those runs.
cedar_with_loading <- function(session, id, expr, label = NULL, report_type = NULL,
                               fresh_default = NULL) {
  signal_load_start(session, id, label, report_type, fresh_default)
  timer <- if (!is.null(report_type)) start_report_timer(report_type, session = session)
  started <- Sys.time()
  value <- NULL
  finished <- FALSE
  on.exit({
    ok <- finished && !is.null(value)
    duration <- if (!is.null(timer)) {
      if (ok) end_report_timer(timer, result = value) else end_report_timer(timer, success = FALSE, result = NULL)
    } else if (ok) {
      as.numeric(difftime(Sys.time(), started, units = "secs"))
    }
    signal_load_complete(session, id, duration_sec = if (ok) duration, error = !ok)
  }, add = TRUE)
  value <- expr
  finished <- TRUE
  value
}

# A result built once and shared by every session, for the life of the process.
# Called inside a reactive, after its req(): the reactive waits, this stores.
# Only a built result is stored. A build that returns NULL (a caught error) is
# not, so the next read tries again; and nothing here can store a failed req(),
# which bindCache() does and which left a page blank for every session (I75).
# `key` is every input that changes the result, with the result's name first.
cedar_shared_result <- function(key, build, cache = shiny::getShinyOption("cache")) {
  if (is.null(cache)) stop("[ui-helpers.R] cedar_shared_result() needs the app's cache.", call. = FALSE)
  hash <- cedar_content_hash(key)
  held <- cache$get(hash)
  # cachem is shiny's own cache package; its marker tells a miss from a stored value.
  if (!cachem::is.key_missing(held)) return(held)
  value <- build()
  if (!is.null(value)) cache$set(hash, value)
  value
}

# Build shared results ahead of their first reader, in the background once the
# app is running. `jobs` is a list of list(key, build), each as
# cedar_shared_result() takes them; a page's module makes its jobs with the
# same function its reactives call, so a result built ahead is the one the
# page asks for (graduation_preload_jobs() is the pattern).
#
# R answers one request at a time, so the jobs do not run in one piece: the
# first waits `start_after` seconds from the moment the event loop starts, so
# the request that started the process is answered first, and each later job
# waits `gap` seconds after the one before, so a click made meanwhile is
# answered between two jobs. A job whose result is already there builds
# nothing. A job that fails is written to the log and stores nothing: the page
# builds it when opened and shows the error there. The error is caught because
# one that escapes a scheduled callback stops the app.
# `schedule` and `cache` are arguments for the tests.
cedar_preload_shared_results <- function(jobs, start_after = 10, gap = 1, schedule = later::later,
                                         cache = function() shiny::getShinyOption("cache")) {
  is_job <- function(job) is.list(job) && is.list(job$key) && length(job$key) > 0L && is.function(job$build)
  if (!all(vapply(jobs, is_job, logical(1)))) {
    stop("[ui-helpers.R] cedar_preload_shared_results() takes jobs of list(key, build).", call. = FALSE)
  }
  if (length(jobs) == 0L) return(invisible(0L))
  run <- function(i) {
    job <- jobs[[i]]
    parts <- vapply(job$key, function(k) paste(k, collapse = "+"), character(1))
    label <- paste(parts[nzchar(parts)], collapse = ", ")
    started <- Sys.time()
    built <- FALSE
    outcome <- tryCatch({
      value <- cedar_shared_result(job$key, function() { built <<- TRUE; job$build() }, cache())
      if (is.null(value)) "the build returned nothing; not kept" else if (built) "built" else "already built"
    }, error = function(e) paste("failed:", conditionMessage(e)))
    message(sprintf("[preload] %s: %s (%.1fs)", label, outcome,
                    as.numeric(difftime(Sys.time(), started, units = "secs"))))
    if (i < length(jobs)) schedule(function() run(i + 1L), gap)
  }
  # A callback scheduled now runs when the event loop starts: the wait before
  # the first job is counted from there, not from this call during startup.
  schedule(function() schedule(function() run(1L), start_after), 0)
  invisible(length(jobs))
}

signal_load_complete <- function(session, id, duration_sec = NULL,
                                 cached = NULL, error = FALSE) {
  session$sendCustomMessage(paste0(id, "_load_complete"), list(
    duration_sec = if (!is.null(duration_sec)) round(duration_sec, 1) else NULL,
    operation_id = if (is.null(duration_sec)) NULL else attr(duration_sec, "operation_id"),
    cached       = if (is.null(cached)) NULL else isTRUE(cached),
    error        = isTRUE(error)
  ))
}
