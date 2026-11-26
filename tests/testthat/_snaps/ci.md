# after a failed browser stage the runner says what the app's container shows

    Code
      writeLines(c("== The R process was killed for memory and another has started",
        killed$said, "", "== The R process is gone and none has started yet", dead$
          said, "", "== The container restarted", restarted$said, "",
        "== Nothing happened to the container", nothing$said, "",
        "== The container stopped", gone$said, "",
        "== The disk is nearly full and the app answers 500", full$said))
    Output
      == The R process was killed for memory and another has started
      What the app's container says (cedar-test-app):
        - The app's R process is not the one the suites began with (pid 275 then, 3120 now).
          Every session open when it went was dropped, so the step that failed is probably not the cause.
        - Docker reports a process in it killed for memory (OOMKilled: true).
          Usually a second CEDAR container is up, or courses are built ahead (CEDAR_PRELOAD_COURSES):
          docs/developers/e2e-testing.md, the browser stages are memory-bound.
        memory now: cedar-test-app  3.41GiB / 3.83GiB
      
      == The R process is gone and none has started yet
      What the app's container says (cedar-test-app):
        - The app's R process is not the one the suites began with (pid 275 then, none running now).
          Every session open when it went was dropped, so the step that failed is probably not the cause.
        memory now: cedar-test-app  3.41GiB / 3.83GiB
      
      == The container restarted
      What the app's container says (cedar-test-app):
        - The container itself restarted during the suites.
        memory now: cedar-test-app  3.41GiB / 3.83GiB
      
      == Nothing happened to the container
      What the app's container says (cedar-test-app):
        - Nothing here explains the failure: the R process is the one the suites began with, no process was killed for memory,
          the disk has 10.0 GiB free and the app answers. Read the suite's own output above.
        memory now: cedar-test-app  3.41GiB / 3.83GiB
      
      == The container stopped
      What the app's container says: no running container publishes port 3838.
        - cedar-test-app was running before the suites and has stopped: docker logs cedar-test-app
      
      == The disk is nearly full and the app answers 500
      What the app's container says (cedar-test-app):
        - The disk has 0.2 GiB free. Docker stops, or answers with input/output errors, as it fills.
        - The app answers 500: it stopped as it started. docker logs cedar-test-app 2>&1 | grep -B 5 'Execution halted'
        memory now: cedar-test-app  3.41GiB / 3.83GiB

