# Helpers for preserving waitlist snapshots in raw class-list imports.

class_list_waitlist_key_cols <- function(old_data, new_data,
                                         term_col = "Academic Period",
                                         status_col = "Registration Status Code") {
  preferred <- c(
    term_col,
    "Academic Period Code",
    "Student ID",
    "Course Reference Number",
    "Sub-Academic Period Code",
    status_col
  )
  keys <- preferred[preferred %in% names(old_data) & preferred %in% names(new_data)]
  if (length(keys) == 0) {
    keys <- setdiff(intersect(names(old_data), names(new_data)), "as_of_date")
  }
  keys
}

normalize_class_list_waitlist_keys <- function(old_data, new_data, key_cols) {
  key_cols <- intersect(key_cols, intersect(names(old_data), names(new_data)))
  for (col in key_cols) {
    old_data[[col]] <- as.character(old_data[[col]])
    new_data[[col]] <- as.character(new_data[[col]])
  }
  list(old_data = old_data, new_data = new_data)
}

normalize_class_list_common_char_cols <- function(old_data, new_data) {
  common_cols <- intersect(names(old_data), names(new_data))
  for (col in common_cols) {
    if (is.character(old_data[[col]]) || is.character(new_data[[col]])) {
      old_data[[col]] <- as.character(old_data[[col]])
      new_data[[col]] <- as.character(new_data[[col]])
    }
  }
  list(old_data = old_data, new_data = new_data)
}


preserve_class_list_waitlists <- function(old_data, new_data,
                                          term_col = "Academic Period",
                                          status_col = "Registration Status Code",
                                          wl_code = "WL") {
  required <- c(term_col, status_col)
  missing_old <- setdiff(required, names(old_data))
  missing_new <- setdiff(required, names(new_data))
  if (length(missing_old) > 0 || length(missing_new) > 0) {
    stop("[class-list-waitlists.R] Cannot preserve waitlists; missing column(s). ",
         "old_data: ", paste(missing_old, collapse = ", "),
         "; new_data: ", paste(missing_new, collapse = ", "))
  }

  new_terms <- unique(stats::na.omit(new_data[[term_col]]))
  if (length(new_terms) == 0 || nrow(old_data) == 0 || nrow(new_data) == 0) {
    attr(new_data, "n_preserved_wl") <- 0L
    return(new_data)
  }

  old_wl <- old_data %>%
    dplyr::filter(.data[[term_col]] %in% new_terms,
                  .data[[status_col]] == wl_code)

  if (nrow(old_wl) == 0) {
    attr(new_data, "n_preserved_wl") <- 0L
    return(new_data)
  }

  new_wl <- new_data %>%
    dplyr::filter(.data[[term_col]] %in% new_terms,
                  .data[[status_col]] == wl_code)

  key_cols <- class_list_waitlist_key_cols(old_wl, new_data, term_col, status_col)
  preserved_wl <- if (nrow(new_wl) > 0 && length(key_cols) > 0) {
    normalized <- normalize_class_list_waitlist_keys(old_wl, new_wl, key_cols)
    old_wl <- normalized$old_data
    new_wl <- normalized$new_data
    old_wl %>% dplyr::anti_join(new_wl, by = key_cols)
  } else {
    old_wl
  }

  if (nrow(preserved_wl) == 0) {
    out <- dplyr::distinct(new_data)
    attr(out, "n_preserved_wl") <- 0L
    return(out)
  }

  normalized_out <- normalize_class_list_common_char_cols(new_data, preserved_wl)
  new_data <- normalized_out$old_data
  preserved_wl <- normalized_out$new_data

  out <- dplyr::bind_rows(new_data, preserved_wl) %>%
    dplyr::distinct()
  attr(out, "n_preserved_wl") <- nrow(preserved_wl)
  out
}
