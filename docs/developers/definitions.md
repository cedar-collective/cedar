---
title: Shared Definition Records
parent: Developer Guide
nav_order: 15
---

# Shared definition records

`docs/_data/definitions.yml` is the single authored source for the migrated
metric explanations. Jekyll reads it as site data. `load_funcs()` reads and
validates the same local file once, using the already-installed `yaml` package,
and exposes `CEDAR_DEFINITIONS` to the app and standalone R analyses. No network
request, generated copy, or second registry is needed.

The records describe calculations; they do not implement them. Keep formulas
and grade/status policy in the existing branches, cones, and constants. Test
those calculations against fixtures. A prose registry cannot prove that the
implementation satisfies its claims.

## Using a record

- `cedar_definition("dfw")` returns the current record shipped with this checkout.
- `cedar_definition("dfw", "1.0.0")` selects an exact version; unknown IDs and
  versions fail explicitly rather than falling back.
- `cedar_definition_summary("course-timing")` supplies a page description.
- `cedar_definition_note("dfw")` renders the short explanation, exclusions,
  limitations, and links inside an existing blue box.
- `cedar_definition_panel(c("registered", "census-enrollment"))` creates a
  standard collapsed blue box. Avoid repeating it if the same explanation is
  already on the visible page.

In a user guide, use the same record:

{% raw %}
```liquid
{% include definition-summary.html id="dfw" %}
```
{% endraw %}

Detailed records and all retained versions render automatically on
[Definition Records](../users/definitions). Keep local guides focused on
controls, examples, and interpretation. Keep dynamic scope, observation edges,
missing data, and actual exclusion counts beside the app's results. Do not
reintroduce static Methodology tabs or copy a record into a code comment.
Comments should explain implementation choices and may name the definition ID.

## Versioning and release discipline

1. Give each concept a stable kebab-case ID. Every version must have all the
   required fields and at least one implementation reference and limitation.
2. Once published, preserve the old record verbatim. Append a new version and
   advance `current_version`. Use a major version for a changed population,
   grain, formula, or interpretation; a minor version for added explanatory
   scope; a patch version for a wording correction. Do not reuse a version.
3. Update calculation tests and the record in the same change when behavior
   changes. If behavior still contradicts intended policy, document the actual
   discrepancy under limitations instead of implying that it is resolved.
4. Run the R suite and build the docs. Definition tests check schema, historical
   lookup, current implementation references, guide/include targets, and rendered app
   links. Analytical tests remain responsible for numerical agreement.
5. Publish the docs before deploying an app that links to a new version. The
   normal docs workflow already watches `docs/**`, including the registry and
   templates. The app workflow explicitly includes the registry despite ignoring
   other docs changes. Deployments are separate; committing a record does not
   publish it.

`schema_version` governs the YAML shape. Definition versions govern the meaning
and explanation of a metric. Projection `model_version` and `schema_version`
remain separate and are preserved inside saved bundles.

The first migration covers enrollment, DFW, program counts, Pathways population
and timing, credit positions, Roadblocks, course retention/sequence comparisons,
waitlists, Regstats, projections, and credit hours. Other local explanations
remain candidates for migration as their calculations are reconciled.
