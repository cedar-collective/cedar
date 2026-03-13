parse <- function(new_students) {

  # Discard PII fields
  new_students <- new_students %>% select(-c(
    `Primary Instructor Email`, `Primary Instructor Preferred First Name`,
    `Primary Instructor NetID`, `Student Name`, `Student First Name`,
    `Student Last Name`, `Confidentiality Indicator`, `Student Email Address`,
    `Student Preferred First Name`, `Student NetID`, `Street Line 1`,
    `Street Line 2`, `City`, `County`, `Zip Code`, `Nation`, `Phone Number`,
    `Visa Type`, `Registration User ID`
  ))

  new_students <- new_students %>% distinct()

  message("done processing class list Excel file.")
  return(new_students)
}
