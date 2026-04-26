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

Most universities have significant analytics infrastructure. They have enterprise systems — Banner, PeopleSoft, Workday, whatever — that manage operational data. They have institutional research offices that produce reports for accreditors and senior leadership. They may have specialized analytics platforms that promise insight into student success.

And yet department chairs routinely make decisions about curriculum, courses, and scheduling without data that speaks to their actual questions.

This isn't an accident. Analytics platforms are purchased at the institutional level and configured to answer institutional-level questions. The people who run and monitor academic programs — chairs, graduate directors, associate deans — are a different audience with different questions, and they are largely underserved.

CEDAR aims to fill that gap. It's not trying to replace anything, but provide an analytical layer between raw institutional data and the program-level decisions that higher-level offices rarely have time to address at that scale.

---

## What vs. why

The analytics most institutions already have are good at answering *what*. How many students enrolled? What's the headcount by major? How many sections ran last fall?

The questions that actually drive curriculum decisions are different. They ask *why* and *what does it mean*:

- Which sections consistently fill slowly, and is there a pattern to when they cancel?
- Do students who take Calculus before Physics perform differently than those who take them simultaneously?
- What characteristics distinguish students who succeed in the second course of a sequence from those who struggle?
- How do DFW rates shift when a course moves from a tenure-track instructor to contingent faculty?

These questions exist at every institution. They come up in every curriculum committee, every program review, every conversation between a dean and a department chair. They almost never get answered — not because the data doesn't exist, but because the infrastructure for asking them doesn't.

CEDAR tries to help with this by surfacing the data and suggesting new questions.

---

## The same data, different questions

The same institution-wide enrollment data can yield very different information depending on where you sit. Here's an example using one dataset at three elevations.

A university has five years of course section records and student enrollment histories. From that:

**A department chair** wants to know: Which courses on this fall's schedule are trending toward low enrollment before the drop deadline? Which sections have early drop rates significantly above their historical average? The same chair wants forward-looking analysis: which courses that ran two falls ago aren't on this year's schedule, and what does that mean for students mid-degree?

**A dean** wants to know: How has credit hour production shifted across her college's departments over five years? Which programs are growing in declared majors and which are shrinking? Where are there waitlist signals that suggest students can't get into courses they need?

**A vice provost** wants to know: What are the retention patterns for students who encounter a high-DFW gateway course in their first year? Do those patterns differ by cohort entry type? And — critically — are the headcount numbers the dean presented using the same definition IR is using in the accreditation report?

CEDAR answers all of these questions from the same underlying data, with the same documented methods, at each level. The unit chair's scheduling analysis and the provost's retention report aren't produced by different systems with different assumptions. They're produced by the same codebase running at different scopes.

---

## Reproducible by design

When a central analytics office answers a data question, you typically receive a number. Sometimes a chart. Rarely an explanation of how the number was derived, what was included or excluded, and what assumptions shaped the result.

This matters more than it might seem. Numbers without methodology are hard to defend, impossible to replicate, and difficult to build on. When a chair presents enrollment data to a curriculum committee, or when a dean makes a case to the provost, or when an institution documents student success outcomes for an accreditor, the methodology is part of the answer.

CEDAR produces analyses from documented, inspectable code. When you run an analysis, you have:

- The result
- The code that produced it
- The ability to reproduce it exactly, for a different term or department or course
- The ability to share the analysis — not just the output — with a colleague at another institution

This is what reproducibility means in practice. It's standard in research. It's almost entirely absent from institutional analytics.

---

## The collective model

The same questions come up everywhere. A graduate director at a research university wondering why some students succeed in a gateway course and others don't is asking the same question as a graduate director at a liberal arts college, a regional university, a community college. The data is different. The question is the same.

Most institutions solve this problem independently, poorly, or not at all. Each IR office reinvents the analysis. Each department chair waits for a report that may or may not address what they actually asked. Each institution pays for software that doesn't answer the question.

CEDAR's approach is different. Analyses are built as **cones** — modular, documented, shareable units that answer specific questions. A cone developed to understand course sequence outcomes at one institution can be adapted and used at another. Solutions accumulate. The work compounds.

This is what "collective" means. Not just open source — though CEDAR is that. Not just free — though CEDAR is that too. It means that solving a problem well, once, in a form others can use, is worth more than solving it adequately, repeatedly, in isolation.

---

[Explore what CEDAR can do →](users/){: .btn .btn-primary }
[Contribute to the project →](developers/){: .btn }
[Get in touch](mailto:fwgibbs@unm.edu){: .btn }