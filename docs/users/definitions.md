---
title: Definition Records
parent: User Guide
nav_order: 18
---

# Definition Records

These versioned records supply the short explanations in CEDAR and the user
guides. Each record states the population, counting unit, numerator, denominator,
campus scope, time window, exclusions, limitations, and implementation references.

The app reads the records shipped with its checkout, not the live website. Its
**Definition v…** links point to that exact version here. Older versions remain
available when definitions change. A definition version is not a data snapshot,
model version, or certification that every implementation issue has been fixed.
Known discrepancies are stated explicitly. Local scope notes still describe
the actual filters, data edges, and exclusions for a particular run.

{% for definition in site.data.definitions.definitions %}
- [{{ definition.versions.last.title }}](#{{ definition.id }})
{% endfor %}

{% for definition in site.data.definitions.definitions %}
<h2 id="{{ definition.id }}">{{ definition.versions.last.title | escape }}</h2>
{% for record in definition.versions reversed %}
{% assign version_anchor = record.version | replace: '.', '-' %}
<h3 id="{{ definition.id }}-v{{ version_anchor }}">Version {{ record.version }}{% if record.version == definition.current_version %} (current){% endif %}</h3>
<p>{{ record.summary | escape }}</p>
<dl>
{% assign fields = 'population,unit,numerator,denominator,campus,time_window,exclusions' | split: ',' %}
{% for field in fields %}
  <dt>{{ field | replace: '_', ' ' | capitalize }}</dt>
  <dd>{{ record[field] | escape }}</dd>
{% endfor %}
</dl>
<p><strong>Limitations and implementation caveats</strong></p>
<ul>{% for limitation in record.limitations %}<li>{{ limitation | escape }}</li>{% endfor %}</ul>
<p><strong>Implementation references</strong> (paths relative to the CEDAR repository)</p>
<ul>{% for source in record.implementation %}
  <li><code>{{ source.file | escape }}</code>: {% for function in source.functions %}<code>{{ function | escape }}()</code>{% unless forloop.last %}, {% endunless %}{% endfor %}</li>
{% endfor %}</ul>
<p><a href="{{ record.guide | prepend: '/' | relative_url }}">Related user guide →</a></p>
{% endfor %}
{% endfor %}
