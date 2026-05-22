---
title: Why CEDAR
nav_order: 2
---

# Why CEDAR
{: .fs-9 }

**The case for a different kind of analytics**
{: .fs-6 .fw-300 }

---

## What vs. why

The analytics most institutions already have are good at answering *what*. How many students enrolled? What's the headcount by major? How many sections ran last fall?

The questions that drive curriculum decisions can be different and much more particular to a degree program or curricular dynamics. They ask *why* and *what does it mean*:

- Do students who take Calculus before Physics perform differently than those who take them simultaneously?
- What characteristics distinguish students who succeed in the second course of a sequence from those who struggle?
- How do DFW rates shift when a course moves from a tenure-track instructor to a graduate student?

These questions come up in curriculum committees, program reviews, conversations between deans and chairs. They often go unanswered — not because the data doesn't exist, but because the infrastructure for answering them doesn't.

CEDAR is an attempt to make these questions answerable as a matter of course, not exception.

---

## The work that disappears

There are a lot of ways to count enrollment — and most institutions produce enrollment numbers from several different systems, for different purposes, using definitions that were set independently of each other. Census date or end of term? Crosslisted sections deduplicated or separate? What grade counts as passing? 

When a department and a college office produce different numbers from "the same" data, it's usually not an error — it's different choices, often made without recognizing a choice was involved. Numbers without traceable methods are difficult to defend, replicate, or build on.

Every institution also has a version of this story. A program director asks whether students who take a gateway course in their first year have different graduation rates than those who delay it. Producing the answer requires non-trivial work: defining the cohort, handling transfer students, deciding what counts as "first year," accounting for curriculum changes. A researcher produces it. It shapes a recommendation in the program review. The question comes up again two years later, but the methodology isn't reproducible. A few years after that, the researcher has moved on and the cycle starts from scratch.

The problem isn't that institutions aren't doing analysis. It's that the analysis doesn't accumulate — and when it does surface, the methodology rarely travels with it.

CEDAR is built to address both. Analyses are produced from documented, inspectable code. When you run an analysis, you have the result, the code that produced it, and the ability to reproduce it exactly for a different term, department, or course. The question doesn't have to be reconstructed when it comes back around. The answer doesn't depend on whether the person who originally produced it is still in the office. Analytical work, done once in this form, becomes part of what the institution knows rather than what one person knew.

---

## CEDAR as complement to ERM

CEDAR is not a replacement for institutional data infrastructure. Banner, PeopleSoft, Workday, and similar enterprise platforms manage the operational data institutions run on — registration, financial aid, student records, HR. Institutional Research offices produce the high-level reporting those systems make possible: enrollment snapshots, headcount tables, retention dashboards built to institutional and federal specifications.

CEDAR works alongside those systems. It addresses the questions that fall outside what standard institutional reporting is designed for: custom cohort definitions, analyses that join enrollment histories with grade outcomes, program-specific questions that don't map onto a standard report template. It does this from the same data exports those systems already produce, with documented methods so the data pipeline is clear and auditable.

---

## The collective model

Higher education produces enrollment and curricular data in recognizable forms across institutions: census-date enrollment snapshots, grade distributions with withdrawal codes that carry different implications depending on when they were recorded, crosslisted sections whose proper unit of analysis depends on what you're trying to count, standardized exports with field conventions that each institution's analysts have had to decode separately. 

These are shared problems. The analytical decisions they require — how to handle crosslisting in a headcount, when a withdrawal should count as a DFW, how to define a cohort across transfer populations — are decisions that have been made, documented, and encoded into CEDAR's data model. The hope is that they don't have to be made again from scratch at each institution.


CEDAR's analyses are organized as **cones** — focused modules built on a foundation of shared functions. Adding a new analysis means assembling a cone from pieces that already exist; the underlying infrastructure doesn't change. That's what makes it straightforward and safe to extend, and what makes work done at one institution transferable to another. More architecture detail can be found in the [developer documentation](developers/).

**The result is a platform that compounds rather than resets.** When an institution builds a new cone, refines a branch function, or works out a better way of handling a particular edge case in higher education data, that work is available to others building on the same foundation. Solutions don't disappear into local files when someone changes roles — they accumulate as shared infrastructure. 

The CEDAR collective is built on a simple premise: when a question gets answered well — in inspectable, reusable code — that work belongs to everyone who faces the same question. Open source and freely available are part of that. But the more meaningful part is that good analytical work, done once and shared, doesn't have to be reinvented at every institution that comes next.

---

[Explore what CEDAR can do →](users/){: .btn .btn-primary }
[Contribute to the project →](developers/){: .btn }
[Get in touch](mailto:fwgibbs@unm.edu){: .btn }