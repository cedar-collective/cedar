# ============================================================================
# UI Definition for Cedar Analytics Application
# ============================================================================
#
# DEPENDENCIES (loaded via global.R):
#   - data_objects[["cedar_sections"]]  - Course sections (DESRs)
#   - data_objects[["cedar_students"]]  - Student enrollments (class lists)
#   - data_objects[["cedar_programs"]]  - Student programs (academic studies)
#   - data_objects[["cedar_degrees"]]   - Degree completions
#   - data_objects[["cedar_faculty"]]   - Faculty information
#
# DATA MODEL: CEDAR (lowercase column names, no backticks)
#   - All data uses CEDAR naming conventions (e.g., campus, department, term)
#   - No legacy column names (e.g., CAMP, DEPT, TERM)
#
# ============================================================================

# Convenience variables for UI (all from data_objects loaded in global.R)
cedar_sections <- data_objects[["cedar_sections"]]
cedar_students <- data_objects[["cedar_students"]]
cedar_programs <- data_objects[["cedar_programs"]]
cedar_degrees <- data_objects[["cedar_degrees"]]
cedar_faculty <- data_objects[["cedar_faculty"]]

# Helper: named vector of dept choices (dept_name → dept_code) for selectizeInput dropdowns.
# Source: cedar_lookups$dept_name_lookup, derived from subj_dept_map in transform-to-cedar.R.
# Falls back to raw dept_codes if lookups not available.
.dept_choices <- local({
  # Restrict to departments with sections at main academic campuses (ABQ + EA).
  # This excludes branch-campus-only vocational/continuing-ed units (e.g., ADOB/Adobe)
  # that clutter the list for main-campus users. Branch campus departments are still
  # accessible on the dashboard when a branch campus is explicitly selected.
  main_campus_codes <- c("ABQ", "EA")
  main_campus_depts <- unique(cedar_sections$department[
    !is.na(cedar_sections$department) &
    cedar_sections$department != "" &
    cedar_sections$campus %in% main_campus_codes
  ])
  lkp <- data_objects[["cedar_lookups"]][["dept_name_lookup"]]
  if (!is.null(lkp) && nrow(lkp) > 0) {
    lkp <- lkp[lkp$dept_code %in% main_campus_depts, ]
    lkp <- lkp[order(lkp$dept_name), ]
    setNames(lkp$dept_code, lkp$dept_name)
  } else {
    sort(main_campus_depts)
  }
})

cedar_home_card <- function(title, text, href, icon_name, meta = NULL) {
  tags$a(
    class = "cedar-home-card",
    href = href,
    div(class = "cedar-home-card-icon", icon(icon_name)),
    div(
      class = "cedar-home-card-copy",
      tags$h3(title),
      tags$p(text),
      if (!is.null(meta)) tags$span(class = "cedar-home-card-meta", meta)
    ),
    div(class = "cedar-home-card-arrow", icon("arrow-right"))
  )
}

# Evergreen "Feature Spotlight" bar. Unlike What's New, this is not release
# history; it rotates useful corners of the app that users may not notice.
cedar_home_feature_spotlight <- function(spotlights) {
  if (is.null(spotlights) || length(spotlights) == 0) return(NULL)
  spotlight_items <- if (!is.null(spotlights$title)) list(spotlights) else spotlights

  links <- lapply(seq_along(spotlight_items), function(i) {
    spotlight <- spotlight_items[[i]]
    href <- if (!is.null(spotlight$tab)) paste0("?tab=", spotlight$tab) else "?tab=changelog"
    cta <- spotlight$cta %||% "Open feature"
    link_class <- paste(c("cedar-spotlight-link", if (i > 1) "is-hidden"), collapse = " ")

    tags$a(
      class = link_class,
      href = href,
      div(class = "cedar-spotlight-icon", icon(spotlight$icon %||% "star")),
      div(class = "cedar-spotlight-copy",
        tags$span(class = "cedar-home-kicker", "Feature Spotlight"),
        tags$h2(spotlight$title %||% "Try this feature"),
        tags$p(spotlight$text %||% "")
      ),
      div(class = "cedar-spotlight-cta", cta, icon("arrow-right"))
    )
  })

  tags$section(class = "cedar-home-spotlight", links)
}

cedar_home_rotation_script <- function() {
  tags$script(HTML("
    document.addEventListener('DOMContentLoaded', function() {
      function shuffleIndexes(count) {
        var indexes = Array.from({ length: count }, function(_, i) { return i; });
        for (var i = indexes.length - 1; i > 0; i--) {
          var j = Math.floor(Math.random() * (i + 1));
          var tmp = indexes[i];
          indexes[i] = indexes[j];
          indexes[j] = tmp;
        }
        return indexes;
      }

      function showRandomSubset(items, limit) {
        if (!items.length || items.length <= limit) return;
        var visible = shuffleIndexes(items.length).slice(0, limit);
        items.forEach(function(item, idx) {
          item.classList.toggle('is-hidden', visible.indexOf(idx) === -1);
        });
      }

      function rotateSpotlight(section) {
        var items = Array.prototype.slice.call(section.querySelectorAll('.cedar-spotlight-link'));
        if (items.length <= 1) return;
        var active = Math.floor(Math.random() * items.length);

        function show(index) {
          items.forEach(function(item, idx) {
            item.classList.toggle('is-hidden', idx !== index);
          });
        }

        show(active);
        window.setInterval(function() {
          active = (active + 1 + Math.floor(Math.random() * (items.length - 1))) % items.length;
          show(active);
        }, 16000);
      }

      document.querySelectorAll('.cedar-home-spotlight').forEach(rotateSpotlight);
      document.querySelectorAll('.cedar-home-whatsnew').forEach(function(section) {
        var highlightLimit = parseInt(section.getAttribute('data-highlight-limit') || '4', 10);
        var chipLimit = parseInt(section.getAttribute('data-chip-limit') || '6', 10);
        var cards = Array.prototype.slice.call(section.querySelectorAll('.cedar-whatsnew-card'));
        var chips = Array.prototype.slice.call(section.querySelectorAll('.cedar-whatsnew-chip'));

        showRandomSubset(cards, highlightLimit);
        showRandomSubset(chips, chipLimit);
        window.setInterval(function() { showRandomSubset(cards, highlightLimit); }, 22000);
        window.setInterval(function() { showRandomSubset(chips, chipLimit); }, 18000);
      });
    });
  "))
}

# Bottom-of-home "What's New" strip. Two tiers, pulled from config/changelog.yml:
#   - `highlights` render as big feature cards (icon + date + title + blurb)
#   - `improvements` render as a skinny row of title-only chips below them
# The hierarchy keeps "new feature" visually distinct from "steady improvement"
# while keeping both separate from the detailed entries on the Changelog tab.
cedar_home_whatsnew <- function(highlights, improvements = list(),
                                highlight_limit = 4, improvement_limit = 6) {
  if (length(highlights) == 0) return(NULL)

  cards <- lapply(seq_along(highlights), function(i) {
    h <- highlights[[i]]
    href <- if (!is.null(h$tab)) paste0("?tab=", h$tab) else "?tab=changelog"
    card_class <- paste(c("cedar-whatsnew-card", if (i > highlight_limit) "is-hidden"), collapse = " ")
    tags$a(
      class = card_class,
      href = href,
      div(class = "cedar-whatsnew-card-icon", icon(h$icon %||% "star")),
      div(
        class = "cedar-whatsnew-card-copy",
        tags$span(class = "cedar-whatsnew-card-date", format(as.Date(h$date), "%b %Y")),
        tags$h3(h$title),
        tags$p(h$text)
      )
    )
  })

  # Skinny "Also improved" row — title-only chips, linked to their tab when one
  # is set, otherwise a static pill (e.g. infrastructure work with no landing tab).
  more <- if (length(improvements) > 0) {
    chips <- lapply(seq_along(improvements), function(i) {
      imp <- improvements[[i]]
      chip_class <- paste(c("cedar-whatsnew-chip", if (i > improvement_limit) "is-hidden"), collapse = " ")
      if (!is.null(imp$tab)) {
        tags$a(class = chip_class, href = paste0("?tab=", imp$tab), imp$title)
      } else {
        tags$span(class = paste(chip_class, "cedar-whatsnew-chip--static"), imp$title)
      }
    })
    div(
      class = "cedar-whatsnew-more",
      tags$span(class = "cedar-whatsnew-more-label", "Also improved"),
      div(class = "cedar-whatsnew-chips", chips)
    )
  }

  tags$section(
    class = "cedar-home-whatsnew",
    `data-highlight-limit` = highlight_limit,
    `data-chip-limit` = improvement_limit,
    div(
      class = "cedar-whatsnew-head",
      div(
        tags$span(class = "cedar-home-kicker", "What's New"),
        tags$h2("Recent features worth a look")
      ),
      tags$a(class = "cedar-whatsnew-all", href = "?tab=changelog",
             "View all updates ", icon("arrow-right"))
    ),
    div(class = "cedar-whatsnew-grid", cards),
    more
  )
}

cedar_home_ui <- function() {
  div(
    class = "cedar-home",
    div(
      class = "cedar-home-intro",
      div(
        class = "cedar-home-intro-copy",
        tags$span(class = "cedar-home-kicker", "CEDAR Analytics"),
        tags$h1("A clearer view of courses, programs, and student pathways"),
        tags$p(
          "CEDAR brings enrollment, program, course, and outcome data into one workspace ",
          "so departments can move from a question to a defensible next step."
        )
      ),
      div(
        class = "cedar-home-values",
        tags$span("Core values"),
        div(class = "cedar-home-value", icon("eye"), "Transparency"),
        div(class = "cedar-home-value", icon("universal-access"), "Accessibility"),
        div(class = "cedar-home-value", icon("clipboard-check"), "Practicality")
      )
    ),

    tags$section(
      class = "cedar-home-section",
      tags$h2("Department Views"),
      div(
        class = "cedar-home-grid cedar-home-grid--dept",
        cedar_home_card(
          "Dept Dashboard",
          "A current snapshot of a department's enrollment, course activity, and student mix.",
          "?tab=dept-dashboard",
          "compass",
          "Start here for a quick departmental read."
        ),
        cedar_home_card(
          "Dept Trends",
          "Longer-term patterns for department headcount, credit hours, degrees, and course demand.",
          "?tab=dept-trends",
          "chart-area",
          "Use when the question is changing over time."
        )
      )
    ),

    tags$section(
      class = "cedar-home-section",
      tags$h2("Analysis Workspaces"),
      div(
        class = "cedar-home-grid cedar-home-grid--dept",
        cedar_home_card(
          "Pathways",
          "Build a student population and examine timing, sequences, roadblocks, major movement, and outcomes.",
          "?tab=pathways",
          "route",
          "Best for curriculum and student-progress questions."
        ),
        cedar_home_card(
          "Course Dynamics",
          "Enrollment trends, student flows, grade distributions, and outcomes for a single course.",
          "?tab=course-dynamics",
          "chart-line",
          "Best for course-level questions."
        )
      )
    ),

    tags$section(
      class = "cedar-home-section",
      tags$h2("Registration Tools"),
      div(
        class = "cedar-home-grid cedar-home-grid--top",
        cedar_home_card(
          "Regstats",
          "Registration signals for pressure points, drops, waitlists, and downstream course demand.",
          "?tab=registration",
          "traffic-light",
          "Useful during schedule planning and registration review."
        ),
        cedar_home_card(
          "Open Seats",
          "Find courses with available seats across selected terms and units.",
          "?tab=open-seats",
          "chair"
        ),
        cedar_home_card(
          "Waitlists",
          "Course waitlist demand by term, campus, level, department, and part of term.",
          "?tab=waitlists",
          "clipboard-list"
        )
      )
    ),

    tags$section(
      class = "cedar-home-section",
      tags$h2("Explore Tools"),
      div(
        class = "cedar-home-grid cedar-home-grid--explore",
        cedar_home_card(
          "Enrollment",
          "Section and course enrollment views with low-enrollment review.",
          "?tab=enrollment",
          "table",
          "Best for schedule review and section-level questions."
        ),
        cedar_home_card(
          "Headcount",
          "Program headcount views for majors, minors, certificates, and graduate programs.",
          "?tab=headcount",
          "users"
        ),
        cedar_home_card(
          "Gen Ed",
          "Inspect general-education offerings and fulfillment patterns.",
          "?tab=gen-ed",
          "graduation-cap"
        )
      )
    ),

    tags$section(
      class = "cedar-home-section",
      tags$h2("Admin Tools"),
      div(
        class = "cedar-home-grid cedar-home-grid--top",
        cedar_home_card(
          "Cancellations",
          "Review canceled courses by term, campus, department, and course level.",
          "?tab=cancellations",
          "ban"
        ),
        cedar_home_card(
          "Data & Usage",
          "Review data freshness, mappings, usage patterns, and cache tools.",
          "?tab=data-usage",
          "database",
          "Best for checking source transparency and app health."
        ),
        cedar_home_card(
          "Changelog",
          "See recent feature work, fixes, and release notes inside CEDAR.",
          "?tab=changelog",
          "history"
        )
      )
    ),

    cedar_home_feature_spotlight(load_feature_spotlights()),
    cedar_home_whatsnew(
      get_recent_highlights(max = 12),
      get_recent_improvements(max = 18),
      highlight_limit = 4,
      improvement_limit = 6
    ),
    cedar_home_rotation_script()
  )
}


# Define UI for application
ui <- page_navbar(
  id = "main_navbar",  # Add ID to enable tab switching

  tags$head(
    # Switch to the URL-requested tab immediately at DOM-ready, before the Shiny
    # WebSocket connects. This prevents the homepage from showing for 5-7 seconds
    # while Shiny initializes. The server observer still runs later to set filter
    # inputs and trigger autorun.
    tags$script(HTML("
      (function() {
        var tabMap = {
          'cedar':              'Home',
          'home':               'Home',
          'dept-dashboard':     'Dept Dashboard',
          'dashboard':          'Dept Dashboard',
          'enrollment':         'Enrollment',
          'low-enrollment':     'Enrollment',
          'headcount':          'Headcount',
          'waitlists':          'Waitlists',
          'open-seats':         'Open Seats',
          'cancellations':      'Cancellations',
          'course-dynamics':    'Course Dynamics',
          'gen-ed':             'Gen Ed',
          'department-profile': 'Dept Trends',
          'dept-trends':        'Dept Trends',
          'pathways':           'Pathways',
          'registration':       'Regstats',
          'healthcare':         'Healthcare',
          'data-usage':         'Data & Usage',
          'data':               'Data & Usage',
          'changelog':          'Changelog'
        };
        var params = new URLSearchParams(window.location.search);
        var tabSlug = (params.get('tab') || '').toLowerCase();
        var tabName = tabMap[tabSlug] || tabSlug;
        if (!tabName) return;
        document.addEventListener('DOMContentLoaded', function() {
          // Top-level panels use .nav-link; panels inside nav_menu() use .dropdown-item.
          // Scope to .navbar so we never accidentally match tab-content panel wrappers.
          var link = document.querySelector('.navbar [data-value=\"' + tabName + '\"]');
          if (link) link.click();

          // Show loading overlay immediately for autorun URLs so users don't
          // watch a blank screen for 4+ seconds while Shiny initializes.
          if (params.get('autorun') === 'true') {
            var overlayMap = {
              'open-seats':   'seatfinder-loading-overlay',
              'cancellations': 'cancellations-loading-overlay',
              'registration': 'regstats-loading-overlay',
              'headcount':    'headcount-loading-overlay',
              'enrollment':   'enrl-loading-overlay'
            };
            var oid = overlayMap[tabSlug];
            if (oid) {
              var el = document.getElementById(oid);
              if (el) { el.style.opacity = '1'; el.style.display = 'flex'; }
            }
          }
        });
      })();
    ")),

    # Scroll to top on load — prevents browser autofocus on first input from
    # jumping the page down past the navbar.
    tags$script("document.addEventListener('DOMContentLoaded', function() {
      window.scrollTo(0, 0);
      if (document.activeElement) document.activeElement.blur();
    });"),
    includeCSS("www/cedar-custom.css"),
    
    # Initialize tooltips and localStorage for changelog
    tags$script(HTML("
      $(document).ready(function(){
        $('[data-toggle=\"tooltip\"]').tooltip();
        
        // Re-initialize tooltips when new content is added
        $(document).on('shiny:value', function(event) {
          setTimeout(function() {
            $('[data-toggle=\"tooltip\"]').tooltip();
          }, 100);
        });
        
        // Close any open dropdowns when page loads with URL parameters
        if (window.location.search) {
          setTimeout(function() {
            $('.navbar-nav .dropdown').removeClass('show');
            $('.navbar-nav .dropdown-toggle').removeClass('show').attr('aria-expanded', 'false');
            $('.navbar-nav .dropdown-menu').removeClass('show');
          }, 100);
        }
      });
      
      // Check localStorage for changelog version AFTER Shiny is connected
      $(document).on('shiny:connected', function(event) {
        console.log('[CEDAR] Shiny connected, checking localStorage for version');
        var seenVersion = localStorage.getItem('cedar_changelog_version');
        console.log('[CEDAR] localStorage cedar_changelog_version:', seenVersion);
        
        // Always send the seen version to server for comparison
        // Server will decide if modal should show based on current version
        Shiny.setInputValue('cedar_last_seen_version', seenVersion || 'none', {priority: 'event'});
        console.log('[CEDAR] Sent last seen version to server:', seenVersion || 'none');
      });
      
      // Register custom message handler to update version when user sees modal
      $(document).ready(function() {
        Shiny.addCustomMessageHandler('cedar_mark_changelog_version', function(message) {
          console.log('[CEDAR] Received message to mark changelog version:', message.version);
          localStorage.setItem('cedar_changelog_version', message.version);
          console.log('[CEDAR] localStorage version set to:', message.version);
        });

        // Programmatically click an action button by ID
        Shiny.addCustomMessageHandler('click_button', function(id) {
          var btn = document.getElementById(id);
          if (btn) btn.click();
        });

        // Force one or more values into a server-side selectize input (which won't
        // display selected values whose options it hasn't loaded yet). Adds each
        // option and selects it via the selectize API. msg.value may be a scalar
        // (single/cross-tab nav) or an array (multi-select URL restore).
        // Shiny configures selectize with labelField:'label', so the option MUST
        // carry a 'label' -- without it the item template renders escape(undefined),
        // i.e. the literal text undefined. 'text' is kept for plain selectize.
        Shiny.addCustomMessageHandler('selectize_set_value', function(msg) {
          if (!msg || msg.value == null || msg.value === '') return;
          var el = document.getElementById(msg.id);
          if (el && el.selectize) {
            var vals = Array.isArray(msg.value) ? msg.value : [msg.value];
            vals.forEach(function(v) {
              el.selectize.addOption({value: v, label: String(v), text: String(v)});
            });
            el.selectize.setValue(msg.value, false);
          }
        });

        // Generic copy-URL handler: msg = { queryStr, buttonId }
        // Used by enrollment, regstats, seatfinder, and any future tab.
        Shiny.addCustomMessageHandler('copy_cedar_url', function(msg) {
          var url = window.location.origin + window.location.pathname + '?' + msg.queryStr;
          var btn = msg.buttonId ? document.getElementById(msg.buttonId) : null;
          function flash() {
            if (!btn) return;
            var icon = btn.querySelector('i');
            var savedClass = icon ? icon.className : '';
            btn.classList.add('btn-success');
            btn.classList.remove('btn-outline-secondary');
            if (icon) icon.className = 'fa fa-check';
            setTimeout(function() {
              btn.classList.remove('btn-success');
              btn.classList.add('btn-outline-secondary');
              if (icon) icon.className = savedClass;
            }, 1500);
          }
          if (navigator.clipboard && window.isSecureContext) {
            navigator.clipboard.writeText(url).then(flash);
          } else {
            var el = document.createElement('textarea');
            el.value = url;
            el.style.cssText = 'position:fixed;opacity:0';
            document.body.appendChild(el);
            el.select();
            try { document.execCommand('copy'); flash(); } catch(e) {}
            document.body.removeChild(el);
          }
        });

        // Update the address bar without a page load: msg = { queryStr, push }.
        // push=true adds a history entry (Back returns to the prior view); otherwise
        // it annotates the current entry via replaceState. Mirrors copy_cedar_url's
        // URL shape so back-button state and copied links stay in sync.
        Shiny.addCustomMessageHandler('cedar_set_url', function(msg) {
          var url = window.location.pathname + '?' + msg.queryStr + window.location.hash;
          if (msg.push) history.pushState({}, '', url);
          else          history.replaceState({}, '', url);
          // Remember the waitlist course/term now on screen so popstate can skip a
          // redundant re-run when Back/Forward lands on an already-rendered view.
          var q = new URLSearchParams(msg.queryStr);
          if ((q.get('tab') || '') === 'waitlists') {
            window.cedarWlRendered = {course: q.get('course') || '', term: q.get('term') || ''};
          }
        });

        // Waitlist course drill-down (called from the table links in waitlist.R).
        // Filters the Waitlists table by a course AND records the step in history so
        // Back returns to the full list instead of leaving CEDAR. Only pushes an entry
        // when already ON the Waitlists tab — cross-tab jumps (e.g. from Regstats) let
        // the tab-switch handler's push stand so Back returns to the originating tab.
        // The popstate handler below re-syncs the table when Back/Forward is used.
        window.cedarWaitlistDrill = function(course, term) {
          try {
            var active = document.querySelector('.navbar [data-value].active, .navbar [data-value][aria-selected=true]');
            if (active && active.getAttribute('data-value') === 'Waitlists') {
              var cur = new URLSearchParams(window.location.search);
              if ((cur.get('course') || '') !== course) {      // skip re-drilling the same course
                var qs = 'tab=waitlists' + (term ? '&term=' + encodeURIComponent(term) : '')
                       + '&course=' + encodeURIComponent(course);
                history.pushState({tab: 'waitlists'}, '',
                  window.location.pathname + '?' + qs + window.location.hash);
              }
            }
          } catch (e) {}
          window.cedarWlRendered = {course: course || '', term: term || ''};
          Shiny.setInputValue('waitlist-wl_navigate',
            {course: course || '', term: term || ''}, {priority: 'event'});
        };

        // After any tab activation (manual or programmatic), close open navbar dropdowns.
        // Runs on shown.bs.tab so it fires after Bootstrap finishes its own activation sequence.
        document.addEventListener('shown.bs.tab', function() {
          $('.navbar-nav .dropdown').removeClass('show');
          $('.navbar-nav .dropdown-toggle').removeClass('show').attr('aria-expanded', 'false');
          $('.navbar-nav .dropdown-menu').removeClass('show');
        });

        // ── Sync ?tab= with the active top-level nav tab, with history ───────
        // The DOMContentLoaded tabMap script (top of <head>) restores a tab on
        // load; this drives the address bar afterwards. Each tab change pushes a
        // history entry so the browser Back/Forward buttons move between tabs —
        // e.g. the waitlist link in Regstats lands on Waitlists, and Back returns
        // to Regstats (its state is intact since it is all one Shiny session).
        (function() {
          var slugByTab = {
            'Home': 'home', 'Dept Dashboard': 'dept-dashboard', 'Dept Trends': 'dept-trends',
            'Enrollment': 'enrollment', 'Regstats': 'registration', 'Pathways': 'pathways',
            'Open Seats': 'open-seats', 'Cancellations': 'cancellations', 'Waitlists': 'waitlists',
            'Gen Ed': 'gen-ed', 'Headcount': 'headcount', 'Course Dynamics': 'course-dynamics',
            'Healthcare': 'healthcare', 'Data & Usage': 'data-usage'
          };
          var tabBySlug = {};
          Object.keys(slugByTab).forEach(function(k) { tabBySlug[slugByTab[k]] = k; });

          var ready = false;       // true after Shiny connects
          var suppress = false;    // true while activating a tab from Back/Forward (don't re-push)

          function urlTab() { return new URLSearchParams(window.location.search).get('tab'); }
          function activeSlug() {
            var el = document.querySelector('.navbar [data-value].active, .navbar [data-value][aria-selected=true]');
            return el ? slugByTab[el.getAttribute('data-value')] : null;
          }

          // Hold off until Shiny connects so the server reads any deep-link params
          // (filters, autorun) from the original URL first. Then ensure the first
          // history entry carries a tab so Back always has somewhere to land.
          $(document).on('shiny:connected', function() {
            ready = true;
            if (!urlTab()) {
              var slug = activeSlug();
              if (slug) history.replaceState({tab: slug}, '',
                window.location.pathname + '?tab=' + slug + window.location.hash);
            }
          });

          // A top-level tab became active (manual click or programmatic, e.g. the
          // Regstats waitlist link) → push it onto history, unless this activation
          // was itself driven by a Back/Forward navigation.
          document.addEventListener('shown.bs.tab', function(e) {
            var link = e.target;
            if (!link || !link.closest || !link.closest('.navbar')) return;  // top-level only
            if (suppress) { suppress = false; return; }                      // came from popstate
            if (!ready) return;                                              // load-time switch
            var slug = slugByTab[link.getAttribute('data-value')];
            if (!slug || urlTab() === slug) return;
            history.pushState({tab: slug}, '',
              window.location.pathname + '?tab=' + slug + window.location.hash);
          });

          // Back/Forward changed the URL → activate the matching tab without pushing,
          // then (Waitlists only) re-sync the table to the URL's course/term so moving
          // between the full list and a course filter also works via Back/Forward.
          window.addEventListener('popstate', function() {
            var slug = (urlTab() || '').toLowerCase();
            var tabName = tabBySlug[slug];
            if (!tabName) return;
            var link = document.querySelector('.navbar [data-value=\"' + tabName + '\"]');
            if (!link) return;
            suppress = true;
            link.click();
            setTimeout(function() { suppress = false; }, 500);  // backstop if shown.bs.tab never fires
            if (slug === 'waitlists') {
              var p = new URLSearchParams(window.location.search);
              var course = p.get('course') || '', term = p.get('term') || '';
              var r = window.cedarWlRendered;
              var already = r && r.course === course && r.term === term;
              if ((course || term) && !already) {   // annotated entry, not already shown — rebuild it
                window.cedarWlRendered = {course: course, term: term};
                Shiny.setInputValue('waitlist-wl_navigate',
                  {course: course, term: term}, {priority: 'event'});
              }
            }
          });
        })();
      });
    "))
  ),
  
  title = "CEDAR",
  #fixed = FALSE,



############################
# EXPLORE YOUR UNIT PANEL
############################

nav_panel(
  title = "Home",
  value = "Home",
  icon = icon("home"),
  cedar_home_ui()
),

nav_panel(
  title = "Dept Dashboard",
  icon = icon("compass"),

  {
    # Use campus codes from cedar_sections — these match the campus column in
    # cedar_students and cedar_sections used by the dashboard filters.
    campus_vals <- sort(unique(cedar_sections$campus[
      !is.na(cedar_sections$campus) & cedar_sections$campus != ""]))
    # Default to ABQ (main campus) + EA (online).
    default_campus <- campus_vals[grepl("^ABQ$|^Main$|Albuquer|^EA$|^Online$", campus_vals,
                                        ignore.case = TRUE)]
    if (length(default_campus) == 0) default_campus <- ""

    # Term picker: concrete term codes only (no term_type aggregation — this is a
    # single-semester dashboard). Newest first; defaults to cedar_default_term.
    # Labels via term_code_to_str ("Fall 2025"); values are the integer term codes.
    dashboard_term_vals <- sort(unique(cedar_sections$term[
      !is.na(cedar_sections$term)]), decreasing = TRUE)
    dashboard_term_choices <- stats::setNames(
      dashboard_term_vals,
      vapply(dashboard_term_vals, term_code_to_str, character(1)))
    dashboard_default_term <- resolve_default_term_choice(
      dashboard_term_vals,
      default_term = if (exists("cedar_default_term")) cedar_default_term else NULL,
      fallback_term = if (exists("cedar_current_term")) cedar_current_term else NULL
    )

    dept_selector_bar(
      title = "Dept Dashboard",
      subtitle = "Headcount trends, enrollment patterns, and course activity for a single semester.",
      campus_input = selectizeInput(
        inputId   = "dashboard_campus",
        label     = "Campus",
        multiple  = TRUE,
        choices   = campus_vals,
        selected  = default_campus
      ),
      dept_input = selectizeInput(
        inputId  = "dashboard_dept",
        label    = "Department",
        multiple = FALSE,
        choices  = c("Select a department..." = "", .dept_choices),
        selected = ""
      ),
      term_input = selectInput(
        inputId  = "dashboard_term",
        label    = "Term",
        multiple = FALSE,
        choices  = dashboard_term_choices,
        selected = dashboard_default_term
      ),
      actions = filter_actions(
        actionButton("dashboard_button",
                     label = "Gather Data",
                     class = "btn-primary",
                     icon  = icon("sync-alt"))
      ),
      scope_output = uiOutput("dashboard_program_info")
    )
  },

  cedar_loading_overlay("dashboard", run_button = NULL,
    trigger_input = "dashboard_button",
    emoji = "\U0001f332", report_type = "dept_dashboard", fresh_default = 20,
    cached_default = 2,

    # Placeholder shown before a department is selected
    conditionalPanel(
      condition = "input.dashboard_dept == ''",
      div(
        style = "text-align: center; padding: 40px 0;",
        #tags$img(src = "cedar-sketch.png", style = "max-width: 100%; max-height: 80vh; opacity: 0.85;")          
      )
    ),

    # Dashboard content — shown only after Gather Data has loaded the current filters
    conditionalPanel(
      condition = "output.dashboard_has_loaded_data == 'true'",

    dashboard_section(
      "Students",
      "Selected-term headcount, recent movement, and credit-hour shifts worth noticing.",
      uiOutput("dashboard_headcount_cards"),
      plotOutput("dashboard_headcount_sparkline", height = "200px"),
      dashboard_subsection(
        "Credit Hour Shifts",
        "Course-level SCH this term compared with the recent same-season pattern.",
        uiOutput("dashboard_credit_hour_shifts")
      )
    ),

    dashboard_section(
      "Enrollment Signals",
      "Current-term enrollment signals for the selected department and campus. Above/below average compares to the recent same-term average: last 3 years, with at least 2 prior same-season offerings.",
      fluidRow(
        column(6,
          dashboard_subsection(
            "Above Average This Term",
            "Courses running higher than the recent average.",
            uiOutput("dashboard_above_avg_courses"),
            tone = "text-success"
          )
        ),
        column(6,
          dashboard_subsection(
            "Below Average This Term",
            "Courses running lower than the recent average.",
            uiOutput("dashboard_below_avg_courses"),
            tone = "text-amber"
          )
        )
      ),
      fluidRow(
        column(6,
          dashboard_subsection(
            "Early Drop Watch",
            "Courses with more pre-census drops than their own recent pattern.",
            uiOutput("dashboard_early_drop_watch"),
            tone = "text-amber"
          )
        ),
        column(6,
          dashboard_subsection(
            "Late Drop Watch",
            "Courses with more post-census drops than their own recent pattern.",
            uiOutput("dashboard_late_drop_watch"),
            tone = "text-amber"
          )
        )
      )
    ),

    dashboard_section(
      "Low Enrollment Review",
      "Selected-term sections under the low-enrollment thresholds for associate dean and chair review. Uses the same low-enrollment helper as the Enrollment tab and omits green buffer rows.",
      uiOutput("dashboard_low_enrollment_review_summary"),
      reactable::reactableOutput("dashboard_low_enrollment_review_table")
    ),

    dashboard_section(
      "High Waitlists",
      "Selected-term courses where waitlist demand is already visible.",
      reactable::reactableOutput("dashboard_high_waitlist_table")
    ),

    dashboard_section(
      "Course Activity",
      "Quick flags for new, missing, and recurring offerings in the selected term.",
      fluidRow(
        column(6,
          dashboard_subsection(
            "New This Term",
            "Courses whose course number and title have not appeared in the historical data. Topics courses count each distinct title separately.",
            uiOutput("dashboard_new_courses"),
            tone = "text-success"
          )
        ),
        column(6,
          dashboard_subsection(
            "Missing vs. Two Years Ago",
            "Courses that ran in this same term type two years ago but are not scheduled this term.",
            uiOutput("dashboard_dormant_courses"),
            tone = "text-amber"
          )
        )
      ),
      dashboard_subsection(
        "Recurring Topics This Term",
        "Topics courses running this term that have been offered at least twice before under the same course number and title.",
        uiOutput("dashboard_repeated_topics")
      )
    ),

    dashboard_section(
      "Audience Shifts",
      "Program overlap and course-audience shares that moved enough to notice this term.",
      uiOutput("dashboard_composition_shifts")
    )

    ) # end conditionalPanel (dept selected)
  ) # end position:relative wrapper
), # end Explore Your Unit nav_panel

############################
# DEPARTMENT TRENDS PANEL
############################

nav_panel(
  title = "Dept Trends",
  icon = icon("chart-line"),
  deptTrendsUI("dept_trends", cedar_sections, .dept_choices, cedar_current_term)
), # end department trends nav_panel

# Pathways tab — cohort-aware curriculum analytics
nav_panel(
  title = "Pathways",
  icon  = icon("route"),
  pathwaysUI(
    "pathways",
    campus_choices = sort(unique(cedar_programs$student_campus[
      !is.na(cedar_programs$student_campus) & nzchar(cedar_programs$student_campus)
    ])),
    program_choices = cedar_pathways_choices$program_choices,
    dept_choices = cedar_pathways_choices$dept_choices
  )
), # end Pathways nav_panel

# Course Dynamics tab — promoted from Explore
nav_panel(
  title = "Course Dynamics",
  icon = icon("file-lines"),

  filter_bar(
    "Course Dynamics",
    "Enrollment trends, student flows, grade distributions, and outcomes for a single course.",
    fluidRow(
      column(4,
        selectizeInput(
          inputId = "cr_campus",
          label = "Campus",
          multiple = TRUE,
          choices  = sort(unique(cedar_sections$campus)),
          selected = c("ABQ", "EA")
        )
      ),
      column(4,
        selectizeInput(
          inputId = "cr_course",
          label = "Select Course:",
          choices = NULL,
          options = list(
            placeholder = "Type to search courses...",
            maxOptions = 20
          )
        )
      ),
      column(3,
        filter_actions(
          actionButton(
            "cr_generate_button",
            "Analyze Course",
            icon = icon("chart-line"),
            class = "btn-primary"
          ),
          actionButton(
            "cr_copy_url",
            label = NULL,
            icon = icon("link"),
            title = "Copy shareable link for current view",
            class = "btn-outline-secondary btn-sm"
          )
        )
      )
    )
  ),

  conditionalPanel(
    condition = "input.cr_course === null || input.cr_course === ''",
    div(class = "empty-state",
      tags$p("Select a course to load its data."))
  ),

  conditionalPanel(
    condition = "input.cr_course !== null && input.cr_course !== ''",
    navset_tab(
      id = "cr_tabs",

      nav_panel(
        "Enrollment",
        icon = icon("users"),
        dashboard_section_header(
          "Classlist Enrollment Over Time",
          "Counts distinct students on the class list for this course by term. ",
          "Final enrollment is students still registered; census pressure adds back late drops, ",
          "who were present after census but left before the final class list."
        ),
        info_panel(
          "More On How This Is Counted",
          tags$ul(
            tags$li(tags$b("Final enrollment"), " counts distinct students with registered status codes RE, RS, or RR."),
            tags$li(tags$b("Census pressure"), " is final enrollment plus late drops (DG/DW), because late drops were enrolled past census."),
            tags$li(tags$b("Early drops"), " are DR/DD rows before grade consequence; they are shown separately and not included in census or final enrollment."),
            tags$li(tags$b("Late drops"), " are DG/DW rows after the drop deadline; they reduce final enrollment and are the gap between census pressure and final enrollment."),
            tags$li("Students are deduplicated within a course, campus, and term before status counts are summarized.")
          ),
          description = "Final enrollment, census pressure, and drop buckets."
        ),
        h5("Census Pressure vs Final Enrollment"),
        plotlyOutput("cr_enrollment_pressure_plot", height = "340px"),
        h5("Early and Late Drops"),
        plotlyOutput("cr_enrollment_drop_plot", height = "300px"),
        br(),
        h4("Classlist Enrollment History"),
        p(class = "cedar-body", "Reference table for the plotted class-list counts and same-term-type averages."),
        reactable::reactableOutput("cr_enrollment_table")
      ),

      nav_panel(
        "Course Flows",
        icon = icon("arrow-right-arrow-left"),
        dashboard_section_header(
          "Student Flow Patterns",
          "Shows what courses students commonly take immediately before, after, or alongside this course. ",
          "Links are average student counts per matching term, filtered to the selected campus scope."
        ),
        uiOutput("cr_flow_scope_note"),
        fluidRow(
          column(4,
            numericInput(
              "cr_flow_min_contrib",
              "Minimum students per term:",
              value = 2,
              min = 1,
              max = 50
            )
          ),
          column(4,
            numericInput(
              "cr_flow_max_courses",
              "Maximum courses to display:",
              value = 6,
              min = 3,
              max = 12
            )
          ),
          column(4,
            filter_actions(
              actionButton(
                "cr_update_flows",
                "Update Flow Diagrams",
                icon = icon("refresh")
              )
            )
          )
        ),
        br(),
        uiOutput("cr_flow_plots_ui")
      ),

      nav_panel(
        "Rollcall",
        icon = icon("user-check"),
        dashboard_section_header(
          "Who Takes This Course",
          "Shows the student mix in this course by classification and major, split by term type and trended over time. ",
          "Counts are based on distinct registered class-list students."
        ),

        h5("By Student Classification"),
        fluidRow(
          column(6, plotlyOutput("cr_rollcall_by_class_fall_plot", height = "400px")),
          column(6, plotlyOutput("cr_rollcall_by_class_spring_plot", height = "400px"))
        ),

        h5("By Major"),
        fluidRow(
          column(6, plotlyOutput("cr_rollcall_by_major_fall_plot", height = "400px")),
          column(6, plotlyOutput("cr_rollcall_by_major_spring_plot", height = "400px"))
        ),

        h5("Classification Trends Over Time"),
        fluidRow(
          column(12, plotlyOutput("cr_rollcall_by_class_time_plot", height = "400px"))
        ),

        h5("Major Trends Over Time"),
        fluidRow(
          column(12, plotlyOutput("cr_rollcall_by_major_time_plot", height = "400px"))
        ),

        h5("Data Tables"),
        fluidRow(
          column(12, reactable::reactableOutput("cr_rollcall_major_fall_table"))
        ),
        fluidRow(
          column(12, reactable::reactableOutput("cr_rollcall_class_fall_table"))
        )
      ),

      nav_panel(
        "DFW",
        icon = icon("chart-bar"),
        uiOutput("cr_dfw_tab_content")
      ),

      nav_panel(
        "Retention",
        icon = icon("person-walking-arrow-right"),
        uiOutput("cr_impact_retention_ui")
      ),

      nav_panel(
        "Sequence Effect",
        icon = icon("arrow-right-long"),
        uiOutput("cr_impact_sequence_ui")
      ),

      nav_panel(
        "Downstream Success",
        icon = icon("chalkboard-teacher"),
        uiOutput("cr_impact_instructor_ui")
      )

    ) # end navset_tab
  ) # end conditionalPanel
), # end course dynamics nav_panel

# Registration dropdown menu
nav_menu(
  title = "Registration",
  icon = icon("clipboard-list"),

  nav_panel(
    title = "Regstats",
    icon = icon("tachometer-alt"),
    regstatsUI("regstats", cedar_sections, cedar_regstats_thresholds, .dept_choices, cedar_default_reg_term)
  ), # end regstats nav_panel

  nav_panel(
    title = "Open Seats",
    icon = icon("door-open"),
    seatfinderUI("seatfinder", cedar_sections, cedar_default_reg_term, .dept_choices)
  ), # end open seats nav_panel

  nav_panel(
    title = "Waitlists",
    icon = icon("list-ol"),
    waitlistUI("waitlist", cedar_sections, cedar_default_reg_term, .dept_choices)
  ) # end waitlists nav_panel
), # end Registration nav_menu

# Explore dropdown menu
nav_menu(
  title = "Explore",
  icon = icon("search"),

######################
# ENROLLMENT NAV PANEL
########################

nav_panel(
  title = "Enrollment",
  icon = icon("chart-bar"),

    filter_bar(
      "Enrollment",
      "Section-level enrollment from the Department Enrollment Status Report, with crosslist deduplication and historical comparison.",
    fluidRow(
      column(2,
             selectizeInput(
               inputId = "enrl_campus",
               label = "Campus",
               multiple = TRUE,
               choices  = sort(unique(cedar_sections$campus)),
               selected = c("ABQ", "EA")),
      ),
      column(1,
             selectizeInput(
               inputId = "enrl_college",
               label = "College", 
               multiple = TRUE,
               choices = sort(unique(cedar_sections$college))),
      ),
      column(1,
             selectInput(
               inputId = "enrl_term",
               label = "Term",
               multiple = TRUE,
               choices = sort(unique(c(cedar_sections$term_type,cedar_sections$term)),decreasing = TRUE)),
      ),
      column(1,
             selectInput(
               inputId = "enrl_pt",
               label = "PoT",
               multiple = TRUE,
               choices = sort(unique(cedar_sections$part_term))),
      ),
      column(3,
             selectizeInput(
               inputId = "enrl_dept",
               label = "Department",
               multiple = TRUE,
               choices = .dept_choices),
      ),
      column(1,
             selectizeInput(
               inputId = "enrl_subj",
               label = "Subject",
               multiple = TRUE,
               choices = sort(unique(cedar_sections$subject))),
      ),

      column(2,
             selectizeInput(
               inputId = "enrl_course",
               label = "Course",
               multiple = TRUE,
               choices = NULL),
      ),

    ), # end fluidRow
    fluidRow(
      column(3,
             selectizeInput(
               inputId = "enrl_inst",
               label = "Instructor",
               multiple = TRUE,
               choices = NULL,
               options = list(placeholder = "Type to search instructors...")),
      ),
      # column(1,  # Method filter — hidden to save space; re-enable if needed
      #        selectInput(
      #          inputId = "enrl_im",
      #          label = "Method",
      #          multiple = TRUE,
      #          choices = sort(unique(cedar_sections$delivery_method))),
      # ),
      column(1,
             selectInput(
               inputId = "enrl_level",
               label = "Level",
               multiple = TRUE,
               choices = sort(unique(cedar_sections$level))),
      ),
      column(2,
             selectizeInput(
               inputId = "enrl_agg_by",
               label = "Group by",
               multiple = TRUE,
               choices = c("campus", "college", "subject_course", "course_title", "department", "term", "term_type", "part_term", "delivery_method", "instructor_name", "gen_ed_area")),
      ),
      # column(1,  # Gen Ed filter — hidden to save space; re-enable if needed
      #        selectInput(
      #          inputId = "enrl_gen_ed",
      #          label = "Gen Ed",
      #          multiple = TRUE,
      #          choices = sort(unique(cedar_sections$gen_ed_area))),
      # ),
      column(1,
        numericInput("enrl_min", "Min", value = 1, min = 0, step = 1)
      ),
      column(1,
        numericInput("enrl_max", "Max", value = NA, min = 0, step = 1)
      ),
      column(1,
        tags$div(
          tags$label("Exclude List", class = "control-label"),
          checkboxInput(inputId = "enrl_uel", label = "Use", value = TRUE)
        )
      ),
      column(2,
        filter_actions(
          actionButton("enrl_button",
                       label = "Gather Enrollments",
                       class = "btn-primary",
                       icon = icon("sync-alt")),
          uiOutput("enrl_download_button_ui"),
          actionButton("enrl_copy_url",
                       label = NULL,
                       icon = icon("link"),
                       title = "Copy shareable link for current view",
                       class = "btn-outline-secondary btn-sm")
        )
      )
    ), # end fluidRow

    filter_scope_stripe(uiOutput("enrl_filter_summary"))

    ), # end filters-compact div

    cedar_loading_overlay("enrl", run_button = NULL,
      trigger_input = "enrl_button",
      emoji = "\U0001f393", report_type = "enrollment", fresh_default = 10,

    # Tabbed output area (shares the filter controls above)
    navset_tab(
      id = "enrl_output_tabs",

      # DESR section-level data with crosslist sub-navigation
      nav_panel(
        title = "DESR",
        icon = icon("table"),
        # Crosslist view selector — tabs filter the DT below without re-querying
        navset_tab(
          id = "enrl_crosslist_tabs",
          selected = "home",
          nav_panel(
            title = "Home", value = "home",
            info_panel("Column guide — Home",
              tags$p("Your department's home/primary sections, plus all non-crosslisted courses. Each crosslisted course appears once, under its administrative home department."),
              tags$ul(
                tags$li(tags$strong("SectionEnrl"), " — registered students in this section."),
                tags$li(tags$strong("TotalEnrl"), " — for crosslisted sections, combined enrollment across all partner sections; equals SectionEnrl for non-crosslisted courses. Use this column for enrollment counts — it avoids double-counting."),
                tags$li(tags$strong("Partners"), " — other course codes sharing this section's enrollment pool (e.g., ANTH 350 paired with HIST 350).")
              ),
              tags$a("Full methodology →", href = "https://cedarplatform.org/users/enrollment-tab", target = "_blank")
            )
          ),
          nav_panel(
            title = "Split-level", value = "split",
            info_panel("Column guide — Split-level",
              tags$p("Sections crosslisted across the undergraduate/graduate divide — at least one section at or below 499 paired with one at 500 or above. Each group appears once (home section shown)."),
              tags$ul(
                tags$li(tags$strong("SectionEnrl"), " — registered students in this section."),
                tags$li(tags$strong("TotalEnrl"), " — combined enrollment across both the undergraduate and graduate sections in the split group."),
                tags$li(tags$strong("Partners"), " — the paired course code at the other level (e.g., HIST 402 shows HIST 502 here).")
              ),
              tags$a("Full methodology →", href = "https://cedarplatform.org/users/enrollment-tab", target = "_blank")
            )
          ),
          nav_panel(
            title = "Crosslisted", value = "xl-home",
            info_panel("Column guide — Crosslisted",
              tags$p("Your department's sections that also appear under another department's course number — your course is home, theirs is the partner."),
              tags$ul(
                tags$li(tags$strong("SectionEnrl"), " — registered students in your department's section."),
                tags$li(tags$strong("TotalEnrl"), " — combined enrollment across your section and all crosslist partner sections."),
                tags$li(tags$strong("Partners"), " — the other department's course code(s) this section is crosslisted with.")
              ),
              tags$a("Full methodology →", href = "https://cedarplatform.org/users/enrollment-tab", target = "_blank")
            )
          ),
          nav_panel(
            title = "Away", value = "away",
            info_panel("Column guide — Away",
              tags$p("Sections owned by another department but crosslisted under your department's course number. Your number is the partner; the other department is home."),
              tags$ul(
                tags$li(tags$strong("SectionEnrl"), " — registered students in the away (home-department) section."),
                tags$li(tags$strong("TotalEnrl"), " — combined enrollment across all sections in the crosslist group."),
                tags$li(tags$strong("Partners"), " — the home department's course code that owns this section.")
              ),
              tags$a("Full methodology →", href = "https://cedarplatform.org/users/enrollment-tab", target = "_blank")
            )
          ),
          nav_panel(
            title = "All", value = "all",
            info_panel("Column guide — All",
              tags$p("Every section including all crosslist partner rows. Crosslisted courses appear multiple times — once per subject code. Enrollment is not de-duplicated here."),
              tags$ul(
                tags$li(tags$strong("SectionEnrl"), " — registered students in this specific section."),
                tags$li(tags$strong("TotalEnrl"), " — combined enrollment across all sections sharing this crosslist group."),
                tags$li(tags$strong("Partners"), " — all other course codes in the same crosslist group.")
              ),
              tags$p(class = "cedar-body text-amber",
                icon("triangle-exclamation"), " Summing TotalEnrl across rows in this view will double-count crosslisted courses. Use the Home view for accurate totals."),
              tags$a("Full methodology →", href = "https://cedarplatform.org/users/enrollment-tab", target = "_blank")
            )
          )
        ),
        reactable::reactableOutput("enrl_summary")
      ),

      # Class list enrollment
      nav_panel(
        title = "Classlist",
        icon = icon("list"),
        reactable::reactableOutput("enrl_cl_summary")
      ),

      # Low enrollment — mode banner, summary cards, thresholds, then level sub-tabs
      nav_panel(
        title = "Low Enrollment",
        value = "low_enrl",
        icon = icon("exclamation-triangle"),

        # Mode banner — shown when a future term triggers concerns mode
        uiOutput("enrl_mode_banner"),

        # Summary stat cards — shown above sub-tabs once data is gathered
        uiOutput("low_enrl_summary"),

        # Threshold controls and calculate button
        div(style = "display: flex; align-items: flex-end; gap: 20px; padding: 4px 0 8px 0;",
          span("Thresholds:", style = "font-weight: 600; color: #555; padding-bottom: 6px; white-space: nowrap;"),
          div(style = "width: 100px;",
            numericInput("low_enrl_threshold_lower", "Lower div", value = 12, min = 1, max = 100, step = 1)
          ),
          div(style = "width: 100px;",
            numericInput("low_enrl_threshold_upper", "Upper div", value = 12, min = 1, max = 100, step = 1)
          ),
          div(style = "width: 100px;",
            numericInput("low_enrl_threshold_split", "Split-level", value = 10, min = 1, max = 100, step = 1)
          ),
          div(style = "width: 100px;",
            numericInput("low_enrl_threshold_grad", "Graduate", value = 5, min = 1, max = 100, step = 1)
          ),
          div(style = "width: 100px;",
            numericInput("low_enrl_min_enrl", "Min enrolled", value = 1, min = 0, max = 1000, step = 1)
          ),
          div(style = "padding-bottom: 6px;",
            uiOutput("low_enrl_download_ui"))
        ),

        info_panel("How to read this table",
          tags$p(tags$strong("Current / past terms (alerts mode):"), class = "mb-1"),
          tags$ul(
            tags$li(tags$strong("Sects"), " — number of active home sections of this course in the selected term."),
            tags$li(tags$strong("Enrolled"), " — this section's own registered student count."),
            tags$li(tags$strong("XL Total"), " — for crosslisted sections, the combined count across all partner sections; equals Enrolled for non-crosslisted courses."),
            tags$li(tags$strong("Course Total"), " — sum of XL Total across all home sections of this course. Color-coded against the threshold.")
          ),
          tags$p(tags$strong("Future terms (concerns mode):"), class = "mt-2 mb-1"),
          tags$ul(
            tags$li(tags$strong("Sects"), " — number of scheduled home sections."),
            tags$li(tags$strong("Sect Enrl"), " — current registration count for those sections."),
            tags$li(tags$strong("Hist Avg"), " — average combined enrollment over the last 4 same-type terms. Color-coded against the threshold."),
            tags$li(tags$strong("Trend"), " — ↑ up / ↓ down / ↔ stable based on linear regression slope across prior terms."),
            tags$li(tags$strong("# Terms"), " — how many prior terms contributed to the average.")
          ),
          tags$p(tags$strong("Color bands:"), " red = below 50% of threshold; yellow = 50–75%; blue = 75–100%; green = meets or exceeds threshold.", class = "mt-2"),
          tags$a("Full methodology →", href = "https://cedarplatform.org/users/enrollment-tab",
                 target = "_blank")
        ),

        navset_tab(
          id = "low_enrl_tabs",
          nav_panel(
            title = "Lower",
            icon = icon("exclamation-triangle"),
            br(),
            reactable::reactableOutput("low_enrl_table_lower")
          ),
          nav_panel(
            title = "Upper",
            icon = icon("exclamation-triangle"),
            br(),
            reactable::reactableOutput("low_enrl_table_upper")
          ),
          nav_panel(
            title = "Split",
            icon = icon("exclamation-triangle"),
            br(),
            p("Crosslisted courses that span the undergraduate/graduate boundary (at least one section ≤499 and one ≥500). The Sections column shows all partner courses in the group. Enrollment is the combined total.",
              class = "cedar-body"),
            reactable::reactableOutput("low_enrl_table_split")
          ),
          nav_panel(
            title = "Graduate",
            icon = icon("exclamation-triangle"),
            br(),
            reactable::reactableOutput("low_enrl_table_grad")
          )
        ) # end low_enrl navset_tab
      ),

      # Filter-driven course trend explorer — single dept only
      # Level overview + top growing/declining course charts
      nav_panel(
        title = "Trend Explorer",
        value = "trends",
        icon = icon("chart-line"),

        h5("Enrollment by Level", class = "cedar-section-heading"),
        p("Total enrollment broken out by course level across your selected filters and terms.",
          class = "cedar-body"),
        plotlyOutput("enrl_level_plot", height = "280px"),

        hr(class = "mt-4 mb-2"),

        p("A filter-driven workspace for exploring course enrollment trajectories. For curated chair-facing patterns, use Dept Trends > Enrollment. Based on
          linear regression across each course's last 6 offerings; courses with fewer than
          2 offerings are excluded.",
          class = "cedar-body"),
        uiOutput("enrl_trends_scope"),
        fluidRow(
          column(6,
            h5("↑ Top Growing Courses", class = "cedar-section-heading--sub text-success"),
            plotlyOutput("enrl_trends_growth_plot", height = "280px")
          ),
          column(6,
            h5("↓ Top Declining Courses", class = "cedar-section-heading--sub text-critical"),
            plotlyOutput("enrl_trends_decline_plot", height = "280px")
          )
        )
      ),


    ) # end navset_tab

    ) # end position:relative wrapper

), # end nav_panel for enrollment



    nav_panel(
      title = "Headcount",
      icon = icon("users"),
      headcountUI("headcount")
    ), # end headcount nav_panel

    nav_panel(
      title = "Gen Ed",
      icon = icon("layer-group"),
      genEdExploreUI("gen_ed", cedar_sections, .dept_choices, cedar_current_term, cedar_default_term)
    ) # end gen ed nav_panel

    # RETENTION (inside Explore) — hidden until cross-course comparison
    # is ready. Course-level retention trend lives in Course Dynamics tab.
    # nav_panel(
    #   title = "Retention",
    #   icon  = icon("user-check"),
    #   retentionUI("retention")
    # ), # end retention nav_panel

  ), # end Explore nav_menu

  # Admin dropdown menu
  nav_menu(
    title = "Admin",
    icon = icon("cog"),

  nav_panel(
    title = "Healthcare",
    icon  = icon("hospital"),
    healthWhatIfUI("health_whatif")
  ),

  nav_panel(
    title = "Cancellations",
    icon = icon("ban"),
    cancellationsUI("cancellations", cedar_sections, cedar_default_reg_term, .dept_choices)
  ),

  nav_item(tags$hr(class = "my-1")),

  nav_panel(
    title = "Data & Usage",
    icon  = icon("database"),

    div(class = "filters-compact",
      h1("Data Status & Usage Analytics")
    ),

    # Data Note (shown above tabs)
    div(
      class = "text-hint",
      "Data presented here is MyReports data — not official institutional data — and should not be used for required reporting purposes. ",
      "CEDAR tables are updated nightly for the current semester and +/- 1-2 terms."
    ),

    br(),

    # Tabbed interface for different sections
    navset_tab(
      id = "data_usage_tabs",

      # ── Tab 1: Data Summary (loads immediately) ────────────────────────
      nav_panel(
        title = "Data Summary",
        br(),
        div(
          p("Last updated information for all loaded datasets. This data is computed at startup.",
            class = "cedar-body"),
          uiOutput("cedar_version_summary"),
          reactable::reactableOutput("data_status_table")
        )
      ),

      # ── Tab 2: Mapping Transparency ───────────────────────────────────
      nav_panel(
        title = "Mappings",
        br(),
        div(
          p("Department, subject, and program mappings used by Cedar at startup. Mapping issues are surfaced here so unusual Banner codes can be reviewed without blocking the app.",
            class = "cedar-body"),
          uiOutput("mapping_issues_summary"),
          card(
            card_header("Mapping Issues"),
            p("Rows listed here are excluded from lookup vectors until they are mapped or explicitly reviewed. They may still appear in source data.",
              class = "text-hint"),
            reactable::reactableOutput("mapping_issues_table")
          ),
          navset_tab(
            nav_panel(
              title = "Program to Dept",
              br(),
              p("Validated major/program code to department-code lookup used for home-major classification and transform fallbacks.",
                class = "text-hint"),
              reactable::reactableOutput("program_dept_mapping_table")
            ),
            nav_panel(
              title = "Subject to Dept",
              br(),
              p("Course subject prefixes mapped to Cedar department codes. Use this when interpreting course ownership.",
                class = "text-hint"),
              reactable::reactableOutput("subject_dept_mapping_table")
            ),
            nav_panel(
              title = "Dept Names",
              br(),
              p("Department code display names derived from the subject/dept catalog.",
                class = "text-hint"),
              reactable::reactableOutput("dept_name_mapping_table")
            ),
            nav_panel(
              title = "Reviewed Exceptions",
              br(),
              p("Program codes intentionally allowed to remain unmapped at app startup. These should be treated as a review queue, not permanent truth.",
                class = "text-hint"),
              reactable::reactableOutput("allowed_unmapped_mapping_table")
            )
          )
        )
      ),

      # ── Tab 2: Usage Overview (lazy loaded) ────────────────────────────
      nav_panel(
        title = "Usage Overview",
        br(),

        # Date range selector
        fluidRow(
          column(4,
            dateInput("usage_start_date", "Start Date:", value = Sys.Date())
          ),
          column(4,
            dateInput("usage_end_date", "End Date:", value = Sys.Date())
          ),
          column(4,
            br(),
            actionButton("refresh_usage_overview", "Refresh", class = "btn-primary", icon = icon("sync"))
          )
        ),

        br(),

        card(
          card_header("Usage Summary"),
          p("High-level overview of CEDAR usage during the selected date range."),
          uiOutput("usage_overview_ui")
        ),

        card(
          card_header("Most Used Features"),
          reactable::reactableOutput("tab_usage_table")
        ),

        card(
          card_header("Department Trends"),
          reactable::reactableOutput("dept_reports_table")
        ),

        card(
          card_header("Course Dynamics"),
          reactable::reactableOutput("course_reports_table")
        )
      ),

      # ── Tab 3: Feature Details (lazy loaded) ───────────────────────────
      nav_panel(
        title = "Feature Details",
        br(),

        # Date range selector (shared reactive values from Usage Overview)
        fluidRow(
          column(4,
            dateInput("feature_start_date", "Start Date:", value = Sys.Date())
          ),
          column(4,
            dateInput("feature_end_date", "End Date:", value = Sys.Date())
          ),
          column(4,
            br(),
            actionButton("refresh_feature_details", "Refresh", class = "btn-primary", icon = icon("sync"))
          )
        ),

        br(),

        uiOutput("usage_stats_output"),

        card(
          card_header("Usage Event Log"),
          reactable::reactableOutput("feature_usage_table")
        )
      ),

      # ── Tab 4: Cache Management (lazy loaded) ──────────────────────
      nav_panel(
        title = "Cache",
        br(),
        cacheUI("cache")
      )
    ) # end navset_tab
  ), # end data & usage nav_panel
  
nav_panel(
    title = "Changelog",
    icon = icon("history"),
    div(class = "filters-compact",
      h1("CEDAR Changelog")
    ),
    changelogUI("changelog")
  )
) # end Admin nav_menu

) # end ui
