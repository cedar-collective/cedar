parse <- function(new_courses) {

  # Rename raw column names to avoid special-character headaches downstream
  message("[parse-DESR.R] Renaming columns...")
  new_courses <- rename(new_courses, "CRSE"    = "CRSE#")
  new_courses <- rename(new_courses, "SECT"    = "SECT#")
  new_courses <- rename(new_courses, "XL_CRSE" = "XL_CRSE#")
  new_courses <- rename(new_courses, "XL_ENRL" = "XL_TOTAL_ENROLLMENT")

  # Normalize key types
  message("[parse-DESR.R] Normalizing types...")
  new_courses$XL_ENRL[is.na(new_courses$XL_ENRL)] <- 0
  new_courses$XL_ENRL  <- as.integer(new_courses$XL_ENRL)
  new_courses$ENROLLED <- as.integer(new_courses$ENROLLED)

  new_courses <- distinct(new_courses)

  message("[parse-DESR.R] Done. Returning ", nrow(new_courses), " rows.")
  return(new_courses)
}
