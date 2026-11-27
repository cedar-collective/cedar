---
title: Low Enrollment
parent: User Guide
nav_order: 10.5
---

# Low Enrollment
{: .fs-9 }

**Sections running under the enrollment expected for their level**
{: .fs-6 .fw-300 }

---

**Courses > Low Enrollment** lists the sections that are at or near a review threshold, for the terms and departments you choose. Pick a term, narrow to a college or a department if you like, and click **Find Low Enrollment**. The list is split into four tabs by level (Lower, Upper, Split, Graduate), each with its own threshold, and each tab's title says how many rows it holds.

It is a list to look into, not a verdict. A small class can be a required course, a capstone or a section added on purpose, and none of that shows here.

---

## Two lists, chosen by the term

**A term with registrations** gets a list of sections: each active section's class against the threshold for its level.

**A term nobody has registered for yet** gets a *schedule check*: there are no students to count, so each scheduled course is compared with how it filled in the same season before. Once registration opens, the page lists sections instead and says when the counts were pulled.

The scope bar says which list ran, and for which campuses, departments and terms: it describes the list on screen, whatever the filters above it now say. Terms of both kinds cannot be listed together, because the two lists do not share columns: the page says which term gets which and asks for one kind.

A note above the list says so when the counts were pulled before registration settled. Those sections can still gain or lose students.

---

## Thresholds

Each level has its own threshold. The standard values (12 / 12 / 10 / 5 for lower / upper / split / graduate) reflect typical minimum viability targets, not institutional policy. Open **Adjust thresholds** under the filters to change one; the closed line says whether the standard values are in force.

**The thresholds are part of a run**, like the term: change one and click **Find Low Enrollment** again. The scope bar states the thresholds the list on screen was run with, and a shared link carries them.

**Smallest section listed** is 1 by default, which leaves out active sections nobody is in: these are usually schedule artifacts. Set it to 0 to see them. A schedule check does not use it.

---

## How sections are listed

A section is listed when its class is at or under its threshold, or within a quarter above it. Only active home sections are read, so a crosslisted course appears once.

**A crosslisted section is judged by its combined class**, the students who meet together across its partner sections, not by its own share of them. That number is the **XL Total** column, and it is the one coloured.

| Column | What it is |
|---|---|
| **Enrolled** | The section's own students |
| **XL Total** | The class that is judged: for a crosslisted section, the combined class across its partners; otherwise the same as Enrolled |
| **Sects** | Active home sections of the course in that term and campus |
| **Course Total** | Those sections' combined classes |
| **Prior History** | The course's enrollment in its last 4 earlier terms |

The cards count the listed sections by band, then the listed sections' own students.

| Colour | Band |
|---|---|
| **Red** | Under 50% of the threshold |
| **Yellow** | 50% to 75% |
| **Blue** | 75% up to and at the threshold |
| **Green** | Over the threshold, within a quarter of it |

A run that lists more than 500 sections leaves Prior History out, and the page says so. Choose a college or a department to see it.

---

## Excluded courses

Independent studies, thesis credits, dissertation credits, honors credits, and similar special-enrollment courses are always excluded. These courses are expected to have very low or individually-arranged enrollment and would otherwise dominate the results. The excluded list is the institution's `institution/<id>/excluded_courses.csv`.

---

## Course levels

| Level | Course numbers |
|---|---|
| **Lower division** | Below 300 (and 1000+) |
| **Upper division** | 300–499 |
| **Graduate** | 500–699 |
| **Split-level** | A crosslisted group spanning the undergraduate/graduate boundary (at least one section ≤499 and at least one ≥500). Its sections appear in the Split tab alone, with their own threshold, and **Split Partners** names every course in the group. |

Lab sections (course numbers ending in L, e.g., EDUC 331L) are classified by their numeric base (331 → upper division).

---

## The schedule check

A course appears when its historical average is under its threshold or within five students of it, or when it has no same-season history at all.

### Historical averages

1. CEDAR identifies all prior terms of the same type (e.g., all past falls for a Fall 2026 schedule).
2. For each course on the future schedule, it sums the combined classes of its home sections in each prior term, then averages the **last 4 available terms**.
3. Courses are matched by course and campus: history for HIST 1105 at ABQ is computed separately from HIST 1105 at Valencia. A reworded title is the same course. A topics course (any section titled `T:`) is matched by title too, so each topic keeps its own history.
4. Only active terms (at least one active section) contribute to the average. Cancelled terms appear in the history column as "C" but do not affect the average.

History columns show counts first, followed by the matching terms in parentheses: `12, C, 10 (Fa22, Sp23, Fa23)`.

A course with no same-season history on its campus shows a dash for its average and lists its latest offerings that ran anywhere else (another season, another campus, another topic) with each campus named: `None in spring on EA; other offerings: 465, 81 (ABQ Fa26, GA Fa26)`. Those offerings are not comparable demand, so they never set the average.

**Excluded from history:** Shell/placeholder sections (active status with zero enrollment and no instructor assigned) are excluded.

### Trend

A linear regression slope is computed across enrollment values from active historical terms. A slope greater than +1 student/term is labeled **↑ up**; less than −1 is **↓ down**; between −1 and +1 is **↔ stable**. If fewer than 2 active terms are available, trend shows **—** (insufficient data).

### Colours

| Colour | Meaning |
|---|---|
| **Red** | Historical average below 50% of threshold |
| **Yellow** | Historical average 50–75% of threshold |
| **Blue** | Historical average 75% up to the threshold |
| **Green** | Historical average meets or exceeds the threshold, by up to 5 students |
| **Gray** | No same-season history on this campus: see the other offerings it lists |

### Limitations

- The check reads total enrollment per course, not individual section enrollment.
- Courses with no same-season history on their campus always appear regardless of threshold.
- It does not account for changes in the number of sections, delivery method or curriculum.

---

## Download and links

**Download CSV** holds every listed row across the four tabs, with the threshold and band each was judged under. **Copy link** carries the filters and the thresholds; `?tab=low-enrollment` links made when this was a sub-tab of Enrollment open this page.

The Dept Dashboard's **Low Enrollment Review** uses the same bands for one department's selected term.
