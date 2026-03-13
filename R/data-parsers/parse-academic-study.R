parse <- function(new_students) {

  # Remove noise rows (blank Academic Year = header/footer artifacts in xlsx)
  new_students <- new_students %>% drop_na(`Academic Year`)

  # Discard PII fields
  new_students <- new_students %>% select(-c(
    `Student First Name`, `Student Last Name`, `Confidentiality Indicator`,
    `Email Address`, `Preferred First Name`, `NetID`, `Street Line 1`,
    `Street Line 2`, `City`, `County`, `County Code`, `Zip Code`,
    `State/Province`, `Phone Number`
  ))

  message("done processing academic study Excel file.")
  return(new_students)
}
