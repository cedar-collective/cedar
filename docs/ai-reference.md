---
title: Using AI with CEDAR
nav_order: 4
---

# Using AI with CEDAR
{: .fs-9 }

**How AI assistants can help you understand what CEDAR is actually doing**
{: .fs-6 .fw-300 }

---

One of CEDAR's core commitments is transparency: every analysis is produced from source code you can read. AI assistants like GitHub Copilot, Claude, and ChatGPT make that transparency practical — you don't need to be an R programmer to ask the code questions.

This page describes how to use AI tools to inspect CEDAR analyses, understand methodology, and build confidence in what the dashboard is showing you.

---

## Reading the code behind a result

Every CEDAR analysis lives in `R/cones/`. If you want to understand exactly how a number is calculated — what's included, what's excluded, what counts as a DFW — you can open the relevant file and ask an AI to explain it.

**Example prompts:**

> "I'm looking at `R/cones/enrl.R`. Can you explain in plain language what `get_low_enrollment_courses()` does and how it decides which sections to flag?"

> "What does `get_stopout()` measure? Specifically: what counts as a stop-out, and what's the 'gap' it's calculating?"

> "In `R/branches/filter.R`, what does `filter_DESRs()` filter out by default? I want to know what sections are excluded before any analysis runs."

You don't need to understand R to get useful answers from these questions. AI assistants are good at translating code into plain English — and when the methodology is in the code, asking about the code is asking about the methodology.

---

## Checking a specific calculation

If a number in the dashboard surprises you, tracing it back to the code is often the fastest way to understand why.

**Example prompts:**

> "In CEDAR's credit hour calculation, it says only enrollments with passing grades count. Which grades count as passing? Show me where in the code that's defined."

> "The drop rate table shows 'early' and 'late' drops. What makes a drop 'early' vs. 'late' in CEDAR's calculation? Is it based on census date?"

> "I see a DFW rate that seems high. How does CEDAR define DFW? Does it include D- grades? What about incompletes?"

---

## Understanding data and terminology

CEDAR uses terminology drawn from Banner and institutional research conventions. When something isn't clear, AI can explain concepts in context.

**Example prompts:**

> "What's the difference between a 'home' section and an 'away' section in CEDAR's crosslist handling?"

> "CEDAR shows 'split-level' courses separately. What makes a section split-level, and why does CEDAR treat it differently?"

> "What does `term_type` mean in the CEDAR data model? How is it different from `term`?"

> "What's a 'cone' in CEDAR? How is it different from a regular R function?"

---

## Exploring what analyses exist

CEDAR's analyses are organized into files by topic. AI can help you navigate the codebase to find what's relevant to your question.

**Example prompts:**

> "I want to understand how CEDAR identifies courses that are trending toward cancellation. Which file or function handles that, and how does it work?"

> "Is there a CEDAR analysis that compares enrollment patterns for transfer students vs. first-time freshmen? Where would I find it?"

> "What analyses does CEDAR have for understanding course sequences — the order students take courses in?"

If you're working directly in the repository, point the AI to the relevant files. If you're using a tool like GitHub Copilot in VS Code, it can search the codebase for you.

---

## For developers writing new cones

If you're contributing to CEDAR or extending it for your institution, the developer AI reference (for writing cones) lives at `AI-REFERENCE.md` in the repository root. It contains the full data model, the cone pattern, and common code patterns — designed to be pasted directly into an AI chat when building something new.

[Developer documentation →](developers/){: .btn }
