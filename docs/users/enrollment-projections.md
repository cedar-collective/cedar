---
title: Enrollment Projections
parent: User Guide
nav_order: 4.5
---

# Enrollment Projections
{: .fs-9 }

**Saved course-demand projections with visible historical evidence**
{: .fs-6 .fw-300 }

---

Open **Registration > Projections** to inspect the latest validated Spring
demand artifact for the pooled ABQ and EA course market. The page
includes courses in the Gen Ed monitoring scope that passed the pressure screen
plus the always-monitored FYEX and gateway list. Branch campuses are not
included.

The page opens to **Always monitored**. Use **Course group**, **Department**,
**Course**, and **Confidence** to narrow the saved rows. The table expands to
show every matching row and scrolls with the page. These controls do not fit or
rerun a model. The download button exports the current filtered table. Expand
**How projections work and how to read the table** for an in-page methodology
and column guide.

Below the summary table, expand **Projection methods** for the complete method
map. The nine candidate labels are six underlying ideas organized into three
families:

- **Observed enrollment baselines:** prior same-season, seasonal median, and
  seasonal trend. These use only the course's own same-season history and are
  eligible for selection.
- **Upstream indicators:** broad population growth, major/classification cohort
  flow, and feeder transitions. These raw estimates show why demand might move,
  but they are diagnostic and are never selected directly.
- **Anchored upstream candidates:** one 50/50 blend of prior same-season
  enrollment with each upstream indicator. These can be selected only after
  minimum aftcast, source-coverage, and error requirements are met.

Thus the three anchored labels are managed variants of the three upstream
signals, not three additional sources of evidence. CEDAR first finds the best
historical baseline and the best eligible anchored candidate, then compares
those two for the published course projection.

| Column | Meaning |
|---|---|
| **Projection** | First-day / ever-registered proxy: unique non-waitlisted students found in the class-list extract, including students who later dropped. This is the aftcast target, but it is not a frozen first-day roster. |
| **Expected census** | Projection multiplied by the course's historical class-list-to-census retention |
| **Method** | The historical baseline or eligible anchored method selected from leakage-safe aftcasts for this course |
| **Aftcast accuracy** | Number of shared comparable historical predictions and their raw WAPE when methods compete; otherwise the selected method's usable history |
| **Confidence** | High, Medium, Low, or None based primarily on comparable aftcast count, WAPE, and consistency across terms |
| **Why confidence** | A brief evidence-volume/stability summary plus the most important qualification, such as capacity limits or method disagreement |
| **Recent same-season terms** | Four compact columns showing first-day / ever-registered enrollment followed by scheduled sections. `479 / 4` means 479 students across 4 sections. |
| **Planning sects** | Projected demand divided by the target schedule's average section size when available, otherwise the recent historical median, rounded up. This is a planning conversion, not a forecast of the sections that will actually be scheduled. |

Select a row to compare every forecasting method against historical first-day /
ever-registered, census, and final/last-day enrollment. The plot is restricted
to the selected target's term type: Spring is compared only with prior Spring
terms, Fall only with Fall, and Summer only with Summer. Method selection, WAPE,
and confidence are judged against the first-day / ever-registered proxy;
census and final enrollment provide lifecycle context rather than alternative
accuracy targets.

The detail also shows the last four same-season enrollments, sections,
capacity, selected-method aftcast, signed error, capacity-bounded status, and
potential explanation. Its full **Why confidence** text separates historical
fit from structural caveats: a method can fit observed enrollment consistently
while a seat ceiling still prevents that fit from proving unconstrained demand.
The detail summary also retains the full planning recommendation, bias-correction
status, and population-fit evidence removed from the compact summary table.
The candidate-method table beneath it shows every
observed and structural estimate, including methods that were not selected.
Use **Back to projection table** above the evidence to return to the main list.

Expand **Enrollment movement diagnostic** in the course detail to compare each
same-season enrollment movement with scheduled capacity and three possible
upstream indicators from the preceding term: enrolled-student population, pooled
ABQ/EA market population, and first-semester freshman population. These are
distinct enrolled students in the class-list data, not official institutional
headcount measures. The diagnostic
also reports the course's canonical DFW count/rate in that preceding term and,
after the fact, how many of those students enrolled in the same course in the
following term. A DFW source term beyond the graded data edge is shown as
unavailable rather than calculated from partial grades.

These comparisons are clues, not attribution. Capacity may have followed
anticipated demand; university growth may affect courses unevenly; and the
next-term repeater count is known only after that next term begins. The signals
remain diagnostic because leakage-safe testing did not justify adding separate
incoming-freshman or DFW forecasting methods.

The context stripe states the target, historical data window, pooled campus
scope, and model version. Hover the information icon beside the model version
to see its Git state. The saved artifact carries hashes and the exact normalized
model source for analyst audit and future comparisons.

`Capacity-bounded` means registration reached the scheduled seat ceiling, so an
estimate above the observed first-day / ever-registered proxy cannot be fully
judged as an error. It
does not mean zero error. `Potential explanation` identifies measured changes
that coincide with a miss; it is not a causal claim.

The page is a planning aid rather than an automatic scheduling decision. Review
confidence, capacity status, and recent evidence before acting on a section
recommendation.
