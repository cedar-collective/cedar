---
title: Why CEDAR
nav_order: 2
---

# Why CEDAR
{: .fs-9 }

**The case for a different kind of analytics**
{: .fs-6 .fw-300 }

---

## The gap in the middle

A department chair making scheduling decisions typically has access to more data than they can use and less data than they need. Most universities have significant analytics infrastructure — enterprise systems managing operational data, IR offices producing reports for accreditors and senior leadership, specialized platforms promising insight into student success.

And yet chairs routinely make decisions about curriculum, courses, and scheduling without data that speaks to their actual questions.

This isn't an accident. Analytics platforms are configured to answer institutional-level questions. The people who run and monitor academic programs — chairs, graduate directors, associate deans — are a different audience, with more granular questions that don't often surface in high-level reports.

CEDAR aims to serve that audience. It's not trying to replace anything — it provides an analytical layer between raw institutional data and the program-level decisions that higher-level offices rarely have bandwidth to address at scale.

---

## What vs. why

The analytics most institutions already have are good at answering *what*. How many students enrolled? What's the headcount by major? How many sections ran last fall?

The questions that actually drive curriculum decisions can be different and much more particular to a degree program or curricular dynamics. They ask *why* and *what does it mean*:

- Do students who take Calculus before Physics perform differently than those who take them simultaneously?
- What characteristics distinguish students who succeed in the second course of a sequence from those who struggle?
- How do DFW rates shift when a course moves from a tenure-track instructor to contingent faculty?

These questions exist at every institution. They come up in curriculum committees, program reviews, conversations between deans and chairs. They almost never get answered — not because the data doesn't exist, but because the infrastructure for asking them doesn't.

CEDAR tries to help with this by surfacing the data and suggesting new questions.

---

## The same data, different questions

The same institution-wide enrollment data can yield very different information depending on where you sit. Here's an example using one dataset at three elevations.

A university has five years of course section records and student enrollment histories. From that:

**chair level**: Which courses on this fall's schedule are trending toward low enrollment before the drop deadline? Which sections have early drop rates significantly above their historical average? The same chair wants forward-looking analysis: which courses that ran two falls ago aren't on this year's schedule, and what does that mean for students mid-degree?

**dean level**: How has credit hour production shifted across the college's departments over five years? Which programs are growing in declared majors and which are shrinking? Where are there waitlist signals that suggest students can't get into courses they need?

**provost level**: What are the retention patterns for students who encounter a high-DFW gateway course in their first year? Do those patterns differ by cohort entry type? And — critically — are the headcount numbers the dean presented using the same definition IR is using in the accreditation report?

CEDAR answers all of these questions from the same underlying data, with the same documented methods. The unit chair's scheduling analysis and the provost's retention report aren't produced by different systems with different assumptions and potentially different ways of counting. They're produced by the same codebase running at different scopes.

---

## Reproducible by design

When a data question moves through several hands — from department to IR to leadership — what typically travels is the number, not the methodology. How the metric was defined, what was included or excluded, and what assumptions shaped the result can be hard to recover after the fact. 

This matters because **there are a lot of ways to count things**. Numbers without traceable methods are difficult to defend, replicate, or build on. When a chair presents enrollment data to a curriculum committee, or when a dean makes a case to the provost, the methodology is part of the answer — not a footnote to it.

CEDAR produces analyses from documented, inspectable code. When you run an analysis, you have the result, the code that produced it, and the ability to reproduce it exactly for a different term, department, or course. That's standard in research. There's no good reason it shouldn't be standard in institutional analytics too.

---

## The work that disappears

Every institution has a version of this story. A program director asks whether students who take a gateway course in their first year have different graduation rates than those who delay it. The question is specific, the answer matters for advising, and producing it requires non-trivial work: defining the cohort, handling transfer students, deciding what counts as "first year," accounting for curriculum changes. IR produces the answer. It shapes a recommendation in the program review. And then — because the question was one-off and the methodology lives in someone's local files — it cannot be replicated when the follow-up comes two years later, by someone who may not know the question was already answered.

The problem isn't that institutions aren't doing analysis. It's that the analysis doesn't accumulate. Each answered question is also an answered question that will have to be answered again, from scratch, by whoever next inherits the role.

CEDAR addresses this directly. When an analysis is built — whether for a recurring dashboard report or an ad-hoc question — it exists as documented, runnable code. The question doesn't have to be reconstructed when it comes back around. The methodology doesn't have to be trusted on faith. The answer doesn't depend on whether the person who originally produced it is still in the office. Analytical work, done once in this form, becomes part of what the institution knows rather than what one person knew.

---

## What enterprise systems don't do

CEDAR is not a replacement for institutional data infrastructure. Banner, PeopleSoft, Workday, and similar enterprise platforms manage the operational data institutions run on — registration, financial aid, student records, HR. Institutional Research offices produce the high-level reporting those systems make possible: enrollment snapshots, headcount tables, retention dashboards built to institutional and federal specifications.

CEDAR sits at a different layer. It addresses the questions that enterprise reporting wasn't configured to answer and that IR doesn't have bandwidth to field routinely: custom cohort definitions, analyses that join enrollment histories with grade outcomes, program-specific questions that don't map onto a standard report template. It does this from the same data exports those systems already produce, with documented methods that can be compared to IR's outputs and audited when they diverge.

The relationship is complementary rather than competitive. CEDAR requires no direct database access and no custom integration — it works from the standardized exports institutions already generate. When a chair's numbers differ from what IR reports, the shared methodology makes the disagreement resolvable: here is what CEDAR counted, here is what was included, here is where the definitions diverge. That conversation is more productive than the usual one, which tends to be about whose number is right rather than what the difference actually means.

---

## The collective model

The same questions come up everywhere. A graduate director at a research university wondering why some students succeed in a gateway course and others don't is asking the same question as a graduate director at a liberal arts college, a regional university, a community college. The data is different. The question is the same. And so, more than is usually recognized, is the data's underlying structure.

Higher education produces enrollment and curricular data in recognizable forms across institutions: census-date enrollment snapshots, grade distributions with withdrawal codes that carry different implications depending on when they were recorded, crosslisted sections whose proper unit of analysis depends on what you're trying to count, standardized exports with field conventions that each institution's analysts have had to decode separately. These are shared problems. The analytical decisions they require — how to handle crosslisting in a headcount, when a withdrawal should count as a DFW, how to define a cohort across transfer populations — are decisions that have been made, documented, and encoded into CEDAR's data model. They don't have to be made again from scratch at each institution.

CEDAR's analyses are built as **cones** — modular, documented, shareable units that answer specific questions from this shared data structure. A cone developed to understand course sequence outcomes at one institution can be adapted and used at another. Solutions accumulate. The work compounds across institutions rather than being repeated inside each one.

This is what "collective" means. Not just open source — though CEDAR is that. Not just free — though CEDAR is that too. It means that answering a question well, once, in a form others can use and inspect, creates value beyond the institution where the work was done.

---

[Explore what CEDAR can do →](users/){: .btn .btn-primary }
[Contribute to the project →](developers/){: .btn }
[Get in touch](mailto:fwgibbs@unm.edu){: .btn }