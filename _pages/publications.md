---
layout: page
permalink: /publications/
title: publications
description: publications by category in reverse chronological order.
nav: true
nav_order: 2
---

<!-- _pages/publications.md -->

This list is also maintained on my <a href="https://scholar.google.co.jp/citations?user=rFnRl1gAAAAJ">Google Scholar</a> and <a href="https://researchmap.jp/yudaitanabe?lang=en">researchmap</a> profiles.

<!-- Bibsearch Feature -->

{% include bib_search.liquid %}

<!-- Filter buttons: defined in _data/publication_filters.yml, applied by the search box above through the URL hash. -->
<div class="publication-filters" style="margin-top: 0.75rem; font-size: 0.85rem">
  {% for group in site.data.publication_filters %}
    <div style="margin-bottom: 0.25rem">
      <span style="display: inline-block; min-width: 4.5rem; font-weight: bold">{{ group.title }}</span>
      {% for value in group.values %}
        <a href="#{{ value | slugify | prepend: '-' | prepend: group.prefix }}" class="btn btn-sm z-depth-0" role="button">{{ value }}</a>
      {% endfor %}
    </div>
  {% endfor %}
  <a href="#" class="btn btn-sm z-depth-0" role="button">Show all</a>
</div>

<div class="publications">

{% bibliography %}

</div>
