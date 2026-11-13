# compute_dept_course_units_tab reads the majors' teaching units and pools small rows

    Code
      for (case in names(pooled_units)) {
        print(as.data.frame(pooled_units[[case]]$tables$latest_units[c(
          "college_label", "unit_label")]))
        print(as.data.frame(pooled_units[[case]]$tables$top_units[c("college_label",
          "unit_label")]))
      }
    Output
        college_label                           unit_label
      1          ARTS                              History
      2          ARTS 2 other units, each under 2 students
        college_label            unit_label
      1          ARTS History (own courses)
      2          ARTS   ARTS: 2 other units
        college_label                     unit_label
      1          ARTS                        History
      2          ENGR 2 units, each under 2 students
        college_label            unit_label
      1          ARTS History (own courses)
      2          ENGR         ENGR: 2 units
                                 college_label                     unit_label
      1                                   ARTS                        History
      2 Other colleges (each under 3 students) 2 units, each under 3 students
                                 college_label
      1                                   ARTS
      2 Other colleges (each under 3 students)
                                             unit_label
      1                           History (own courses)
      2 Other colleges (each under 3 students): 2 units
                                    college_label
      1 Other colleges (each under 1000 students)
      2 Other colleges (each under 1000 students)
                                     unit_label
      1                                 History
      2 2 other units, each under 1000 students
      [1] college_label unit_label   
      <0 rows> (or 0-length row.names)

---

    Code
      cat(dept_course_units_note(later), sep = "\n")
    Output
      No enrolled History major holds a registration after Spring 2021; the data runs to Fall 2021, so that is the latest term read here.

---

    Code
      cat(dept_course_units_note(nobody), sep = "\n")
    Output
      No enrolled Philosophy major holds a registration to Spring 2021.

