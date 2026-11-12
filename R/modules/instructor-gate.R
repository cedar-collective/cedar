# Shiny Module: the instructor-name gate
#
# Every table or chart that names an instructor beside student outcomes sits
# behind one password (CEDAR_DFW_PASSWORD), and one shared flag: unlocking
# it anywhere unlocks it for the session. A page mounts instructorGateUI()
# where the named content would be and renders that content only when the
# shared `access()` is TRUE. With no password configured the content is
# unavailable, never open.
#
# Exported functions:
#   instructorGateUI(id)
#   instructorGateServer(id, access, password, what)

instructorGateUI <- function(id) {
  uiOutput(NS(id)("gate"))
}

#' @param access The session's shared `reactiveVal(FALSE)`; set TRUE on the
#'   right password.
#' @param password The configured password ("" when none is).
#' @param what What is behind the gate, for the prompt ("Outcomes by
#'   instructor").
instructorGateServer <- function(id, access, password, what = "Results that name an instructor") {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    configured <- is.character(password) && length(password) == 1L && nzchar(password)

    output$gate <- renderUI({
      if (isTRUE(access())) return(NULL)
      if (!configured) {
        return(div(
          class = "alert alert-warning",
          h5(icon("lock"), " Access Unavailable"),
          p(what, " are disabled because CEDAR_DFW_PASSWORD is not configured. Everything that names no instructor remains available.")
        ))
      }
      div(
        class = "alert alert-warning",
        h5(icon("lock"), " Access Restricted"),
        p(what, " require the instructor-data password. Everything that names no instructor remains visible; unlocking here unlocks every instructor table for this session."),
        div(
          class = "d-flex gap-2 align-items-start",
          passwordInput(ns("password"), NULL, placeholder = "Enter password"),
          actionButton(ns("submit"), "Access", class = "btn-primary")
        )
      )
    })

    observeEvent(input$submit, {
      if (!configured) {
        showNotification("Instructor results are disabled until CEDAR_DFW_PASSWORD is configured.",
                         type = "error", duration = 5)
      } else if (identical(input$password, password)) {
        access(TRUE)
        showNotification("Access granted", type = "message", duration = 3)
      } else {
        showNotification("Incorrect password. Please try again.", type = "error", duration = 3)
      }
    }, ignoreInit = TRUE)
  })
}
