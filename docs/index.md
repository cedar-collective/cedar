---
title: Home
layout: home
nav_order: 1
---

# CEDAR

## Curricular and Enrollment Data Analytics and Reporting

CEDAR is a dashboard and an open analytics platform.

**As a dashboard**, CEDAR tries to make unit-level curriculum and enrollment data easier to inspect. Which courses typically struggle with low enrollment? How do DFW rates vary across sections of the same course? Where do students appear to encounter difficulty in a required sequence? These questions come up in scheduling meetings and curriculum committees all the time, but the historical and current-term data needed to discuss them can be hard to assemble. CEDAR is an attempt to make that work more accessible and transparent.

**As a platform**, CEDAR is one way for analytical work to persist. Many useful one-off analyses live in a spreadsheet or script that made sense when it was written but is hard to find, rerun, or explain later. When a question is worth answering, the methodology is worth keeping. CEDAR keeps analysis in open, documented code — inspectable, rerunnable, and not dependent on any one person's memory or hard drive.

CEDAR is therefore not best understood as a turnkey app that an institution
deploys unchanged. The runnable Shiny dashboard is a reference interface over a
shared analytics codebase and normalized data model. Institutions that use CEDAR
still own their local hosting, access controls, privacy rules, and source-data
mapping. The common project is the code and definitions that make higher-ed
analytics easier to inspect, adapt, and improve together.

---

## What CEDAR is built around

**Access**

The dashboard is built for people working close to academic programs — chairs, graduate directors, associate deans, schedulers, and analysts. The questions it supports are often specific and local: which sections look unusual this term, how this year's enrollment compares to three years ago, where students appear to slow down in a sequence. These questions are not always the focus of standard institutional reports, which are usually built for broader reporting needs.

**Transparency**

Every CEDAR analysis is produced by source code in a public repository. The methodology is not only a separate explanation — it is also the calculation itself. When there is a question about how a number was derived, the code shows what was included, what was not, and what choices were made along the way. That traceability helps keep data from becoming a weapon: numbers are easier to discuss when their assumptions are visible.

**Trust**

There are a lot of ways to count enrollment, and the choices are not always obvious. Is a section's enrollment counted at census date or at the end of term? If two departments crosslist the same course, does it appear once or twice in a headcount? What grades are considered passing for different courses? When a department and a college office produce different numbers from "the same" data, it is often a definitions issue rather than a simple error. A shared platform can support shared definitions, or at least clearly named differences. When numbers do not reconcile, the question becomes easier to answer: here is the code, here is what is different.

**Collaboration**

The same analytical problems come up at many institutions, often from similar data structures. Crosslisted sections can be one course or two depending on the question. Grade records can mean different things depending on when a withdrawal was recorded. Data exports have conventions that analysts decode locally, again and again. CEDAR is built around these particulars. Analyses developed at one institution can become starting points for others — not as abstract templates, but as documented code written against the kinds of data higher education already produces.

---

[Why CEDAR](why-cedar){: .btn .btn-primary .fs-5 .mb-4 .mb-md-0 .mr-2 }
[The Analyses](users/){: .btn .fs-5 .mb-4 .mb-md-0 .mr-2 }
[The Questions](questions){: .btn .fs-5 .mb-4 .mb-md-0 .mr-2 }
[For Developers](developers/){: .btn .fs-5 .mb-4 .mb-md-0 }
