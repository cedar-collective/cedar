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
**Course**, and **Confidence** to narrow the saved rows. Larger results show 25
rows per page by default. These controls do not fit or rerun a model. The
download button exports the current filtered table.

| Column | Meaning |
|---|---|
| **Projection** | First-day / ever-registered proxy: unique non-waitlisted students found in the class-list extract, including students who later dropped. This is the aftcast target, but it is not a frozen first-day roster. |
| **Expected census** | Projection multiplied by the course's historical class-list-to-census retention |
| **Method** | The observed-enrollment method selected from leakage-safe aftcasts for this course |
| **Aftcast accuracy** | Number of comparable historical predictions and their raw WAPE |
| **Confidence** | High, Medium, Low, or None based on comparable aftcast count, WAPE, and method coverage where applicable |
| **Why confidence** | The evidence behind that label and the next threshold the course did not clear |
| **Bias correction** | Whether a systematic error adjustment passed later rolling validation |
| **Population fit** | Whether broad Fall-population or major/classification growth has historically fit this course better |
| **Recommendation** | Planning comparison between projected demand, historical section size, and any available target schedule |

Select a row to compare every forecasting method against historical first-day /
ever-registered, census, and final/last-day enrollment. The plot is restricted
to the selected target's term type: Spring is compared only with prior Spring
terms, Fall only with Fall, and Summer only with Summer. Method selection, WAPE,
and confidence are judged against the first-day / ever-registered proxy;
census and final enrollment provide lifecycle context rather than alternative
accuracy targets.

The detail also shows the last three same-season enrollments, sections,
capacity, selected-method aftcast, signed error, capacity-bounded status, and
potential explanation. The candidate-method table beneath it shows every
observed and structural estimate, including methods that were not selected.
Use **Back to projection table** above the evidence to return to the main list.

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
