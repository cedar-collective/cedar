---
title: Audits
parent: Developer Guide
nav_order: 40
has_children: true
---

# Audits

Point-in-time checks of CEDAR against its own data, each dated. They are the
evidence behind rules that now live in `AGENTS.md` and the policy pages, and
behind entries in `ISSUES.md`; read those for what holds today.

- [Mapping Audit (2026-07)](mapping-audit-2026-07.html): whether the code
  vocabularies and join keys hold (`scripts/audit-mappings.R` re-runs it).
- [Campus-Grain Audit (2026-08)](campus-grain-audit-2026-08.html): which course
  metrics grouped by campus; the source of [Campus Policy](../campus-policy.html).
- [Platform vs Institution Audit (2026-09)](institution-boundary-audit.html):
  what is CEDAR and what is UNM; the source of ADR-002 and the
  `institution/<id>/` files.
