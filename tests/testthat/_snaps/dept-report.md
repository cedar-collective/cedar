# compute_dept_course_units_tab reads the majors' teaching units and pools small rows

    Code
      cat(dept_course_units_headline(result), sep = "\n")
    Output
      In Spring 2021, 1 History major held 1 registration in courses taught on ABQ; 100.0% were in the unit's own courses.

---

    Code
      cat(dept_course_units_headline(later), sep = "\n")
    Output
      No enrolled History major holds a registration after Spring 2021; the data runs to Fall 2021, so that is the latest term read here.
      In Spring 2021, 1 History major held 1 registration in courses taught on ABQ; 100.0% were in the unit's own courses.

---

    Code
      cat(dept_course_units_headline(one), sep = "\n")
    Output
      In Spring 2021, 1 History major held 2 registrations in courses taught on ABQ; 50.0% were in the unit's own courses, and English (50.0%) taught the most outside it.

