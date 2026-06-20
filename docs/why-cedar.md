---
title: Why CEDAR
nav_order: 2
---

# Why CEDAR
{: .fs-9 }

**A case for more transparent, collaborative analytics**
{: .fs-6 .fw-300 }

---

## What vs. why

The analytics most institutions already have are good at answering *what*. How many students enrolled? What's the headcount by major? How many sections ran last fall?

The questions that come up in curriculum and program conversations can be more particular to a degree program or curricular pattern. They often ask *what might be happening here?* or *what context do we need before deciding what this means?*

- Do students who take Calculus before Physics perform differently than those who take them simultaneously?
- What characteristics distinguish students who do well in the second course of a sequence from those who struggle?
- How do DFW rates shift when a course moves from a tenure-track instructor to a graduate student?

These questions come up in curriculum committees, program reviews, and conversations between deans and chairs. They can be hard to answer at the unit level — not because the data does not exist, but because the data is often spread across systems and the methods for joining it are rarely visible to the people discussing the results.

CEDAR is an attempt to make those unit-level views easier to produce, inspect, and reproduce.

---

## The work that disappears

There are a lot of ways to count enrollment — and most institutions produce enrollment numbers from several different systems, for different purposes, using definitions that were set independently of each other. Census date or end of term? Crosslisted sections deduplicated or separate? What grade counts as passing? 

When a department and a college office produce different numbers from "the same" data, it's usually not an error — it's different choices, often made without recognizing a choice was involved. Numbers without traceable methods are difficult to defend, replicate, or build on.

Every institution also has a version of this story. A program director asks whether students who take a gateway course in their first year have different graduation rates than those who delay it. Producing the answer requires non-trivial work: defining the cohort, handling transfer students, deciding what counts as "first year," accounting for curriculum changes. A researcher produces it. It shapes a recommendation in the program review. The question comes up again two years later, but the methodology isn't reproducible. A few years after that, the researcher has moved on and the cycle starts from scratch.

The problem is not that institutions are not doing analysis. It is that analysis often does not accumulate — and when it does surface, the methodology does not always travel with it.

CEDAR is built to help with both. Analyses are produced from documented, inspectable code. When you run an analysis, you have the result, the code that produced it, and the ability to reproduce it for a different term, department, or course. The question does not have to be reconstructed from scratch when it comes back around. Analytical work, done in this form, can become part of shared institutional knowledge rather than remaining a private file.

---

## CEDAR as complement to ERM

CEDAR is not a replacement for institutional data infrastructure. Banner, PeopleSoft, Workday, and similar enterprise platforms manage the operational data institutions run on — registration, financial aid, student records, HR. Institutional Research offices produce the high-level reporting those systems make possible: enrollment snapshots, headcount tables, retention dashboards built to institutional and federal specifications.

CEDAR works alongside those systems. It focuses on questions that often fall outside standard institutional reporting: custom population definitions, analyses that join enrollment histories with grade outcomes, program-specific questions that do not map neatly onto a standard report template. It does this from the same data exports those systems already produce, with documented methods so the data pipeline is clear and auditable.

---

## The collective model

Higher education produces enrollment and curricular data in recognizable forms across institutions: census-date enrollment snapshots, grade distributions with withdrawal codes that carry different implications depending on when they were recorded, crosslisted sections whose proper unit of analysis depends on what you're trying to count, standardized exports with field conventions that each institution's analysts have had to decode separately. 

These are shared problems. The analytical decisions they require — how to handle crosslisting in a headcount, when a withdrawal should count as a DFW, how to define a population across transfer and native students — are exactly the kinds of decisions that benefit from being documented, debated, and encoded in a reusable data model. The hope is not that every institution should use the same answer, but that none of us should have to start from a blank page.


CEDAR's analyses are organized as **cones** — focused modules built on a foundation of shared functions. Adding a new analysis means assembling a cone from pieces that already exist; the underlying infrastructure does not have to change. That structure makes extension more manageable and makes work done at one institution easier to adapt elsewhere. More architecture detail can be found in the [developer documentation](developers/).

**The result is a platform where work can accumulate rather than reset.** When an institution builds a new cone, refines a branch function, or works out a better way of handling a particular edge case in higher education data, that work can be shared with others building on the same foundation. Local solutions do not have to disappear into private files when someone changes roles; they can become shared infrastructure.

The CEDAR collective is built on a simple premise: when a question is answered carefully — in inspectable, reusable code — that work can help others facing a similar question. Open source and freely available are part of that. But the more meaningful part is collaborative: good analytical work can be reviewed, adapted, improved, and reused rather than reinvented in isolation.

---

[Explore what CEDAR can do →](users/){: .btn .btn-primary }
[Contribute to the project →](developers/){: .btn }
[Get in touch](mailto:fwgibbs@unm.edu){: .btn }
