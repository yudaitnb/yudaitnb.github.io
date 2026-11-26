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
<style>
  .publication-filters {
    margin-top: 0.5rem;
    font-size: 0.8rem;
    line-height: 1.9;
  }
  .publication-filters .filter-row {
    display: flex;
    align-items: baseline;
  }
  .publication-filters .filter-group {
    flex: 0 0 4.5rem;
    font-weight: bold;
  }
  .publication-filters .filter-area-cell {
    flex: 0 0 2.8rem;
  }
  .publication-filters .filter-values {
    flex: 1;
  }
  .publication-filters a {
    margin-right: 0.3rem;
    padding: 0 0.4rem;
    border: 1px solid var(--global-divider-color);
    border-radius: 0.25rem;
    color: var(--global-text-color);
    text-decoration: none;
    white-space: nowrap;
  }
  .publication-filters a:hover {
    border-color: var(--global-theme-color);
    color: var(--global-theme-color);
  }
  .publication-filters a.filter-area {
    font-weight: bold;
  }
</style>
<div class="publication-filters">
  {% for group in site.data.publication_filters %}
    {% if group.areas %}
      {% for area in group.areas %}
        <div class="filter-row">
          <span class="filter-group">{% if forloop.first %}{{ group.title }}{% endif %}</span>
          <span class="filter-area-cell"><a class="filter-area" href="#{{ area.name | slugify | prepend: 'area-' }}">{{ area.name }}</a></span>
          <span class="filter-values">
            {%- for value in area.values -%}
              <a href="#{{ value | slugify | prepend: '-' | prepend: group.prefix }}">{{ value }}</a>
            {% endfor -%}
          </span>
        </div>
      {% endfor %}
    {% else %}
      <div class="filter-row">
        <span class="filter-group">{{ group.title }}</span>
        <span class="filter-values">
          {%- for value in group.values -%}
            <a href="#{{ value | slugify | prepend: '-' | prepend: group.prefix }}">{{ value }}</a>
          {% endfor -%}
        </span>
      </div>
    {% endif %}
  {% endfor %}
  <div class="filter-row">
    <span class="filter-group"></span>
    <span class="filter-values"><a href="#">Show all</a></span>
  </div>
</div>

<div class="publications">

{% bibliography %}

</div>
