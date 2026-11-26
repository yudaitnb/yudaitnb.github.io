# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## This repository is a site, not the starter

This is the personal site published at https://yudaitnb.github.io/, created from the al-folio v1 starter and kept in sync with it by merging the `upstream` remote (`git fetch upstream && git merge upstream/main`). The starter notes below and in `AGENTS.md` still describe how the gems work. These points differ here:

- `baseurl` is empty. Build and serve with plain `bundle exec jekyll build` / `bundle exec jekyll serve` (http://localhost:4000/); never pass `--baseurl /al-folio`.
- Local `_layouts/` and `_includes/` are allowed (see [local overrides](docs/ARCHITECTURE.md#local-overrides-your-site-vs-this-repo)). `_layouts/bib.liquid` overrides `al_folio_core` and is tracked in `.al-folio-overrides.yml`; `_layouts/cv_sections.liquid`, `_includes/cv_sections/`, `_includes/publication_badges.liquid` (the badge row and filter tokens above each publication title, see `_data/publication_filters.yml`) and `_includes/hook/bib.liquid` belong to this site.
- `_data/cv.yml`, `_data/activities.yml` and `_data/grants.yml` use the classic al-folio CV format, rendered by the `cv_sections` layout. `cv/generate_cv.rb` builds `assets/pdf/CV.pdf` from them and from `_pages/about.md`, `_pages/teaching.md` and `_bibliography/papers.bib`, so keep those formats, including the `<a class="font-weight-bold">` course lines in `teaching.md`.
- When an upstream merge conflicts on demo content this site deleted (posts, projects, demo pages and assets), keep it deleted.
- `_data/citations.yml` holds this site's Google Scholar counts, refreshed by `update-citations.yml`; `.gitattributes` keeps our copy on upstream merges once `git config merge.ours.driver true` is set in the clone.

@AGENTS.md

`AGENTS.md` (imported above) is the **authoritative** agent entry point: change routing, the stop sign for gem-owned paths, the three silent failure modes, and the validated command set. Keep it short and ecosystem-neutral. Cross-repo architecture — the wrapper/tag/gem delegation table, feature gating, the v1 config contract, local overrides — lives in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md); area-to-gem ownership lives in [`docs/BOUNDARIES.md`](docs/BOUNDARIES.md).

**Read those three before editing anything.** Everything below is Claude-specific or longer-form operational detail that does not belong in the short entry point. Do not restate facts from those files here — link to them.

## Daily dev loop

```bash
bundle install                                # ruby gems
bundle exec jekyll serve                      # dev server → http://localhost:4000/al-folio/  (NOTE baseurl)
bundle exec jekyll build --baseurl /al-folio  # production-style build to _site/
bash test/integration_distill.sh              # run ONE integration test (any of the seven in test/)
npm run test:visual:update                    # refresh playwright snapshots after intentional UI change
bundle exec al-folio upgrade apply --safe     # deterministic codemods (font-weight-* → font-*, remote→local URLs)
bundle exec al-folio upgrade overrides diff <path>    # then `overrides accept <path>` to acknowledge an override
```

## Optional toolchains

- **Jupyter posts.** `bin/setup-python-deps` installs _only_ `jupyter` and `nbconvert` (via `pip --user --break-system-packages`) for `jekyll-jupyter-notebook`. It does **not** read `requirements.txt`. Missing `jupyter-nbconvert` is warn-and-continue; notebook rendering is skipped.
- **Everything else Python.** [`requirements.txt`](requirements.txt) is the fuller list and must be installed separately (`python3 -m pip install -r requirements.txt`): `rendercv[full]` for CV rendering, `scholarly` for `bin/update_scholar_citations.py`, plus `nbconvert` and `pyyaml`.
- **Responsive images.** `imagemagick.enabled: true` needs ImageMagick `convert` on `PATH`.
- **Manual deploy.** `bin/deploy` is the manual `gh-pages` build + purgecss + force-push path; CI normally deploys. `purgecss` is not a devDependency — install it with `npm install -g purgecss`.

## Docker serving model (v1-specific)

`docker compose up -d` bind-mounts the repo to `/srv/jekyll` and runs `bin/entry_point.sh`, which serves with `--force_polling --destination /tmp/_site`. The build output deliberately goes to **container-local `/tmp/_site`, not the bind-mounted `_site`** — writing `_site` back across the host bind mount caused write deadlocks. The container also `inotifywait`s `_config.yml` and restarts Jekyll on change (config edits aren't hot-reloaded by `--watch`). Verify with the `/al-folio` baseurl: `curl -fsS http://127.0.0.1:8080/al-folio/`. `docker-compose-slim.yml` pulls a prebuilt `:slim` image instead of building locally.

## CI gates and the style contract

`npm run lint:style-contract` (`test/style_contract.js`) is the automated enforcement of the thin-starter boundary and will fail CI if you cross it. Beyond the forbidden paths listed in `AGENTS.md`, it also asserts that `_config.yml` keeps `theme: al_folio_core` and the required plugins, that the `third_party_libraries` SRI pins are present, and that the `al_math` Gemfile pin stays on a released version rather than a git branch.

Other gates:

- `unit-tests.yml` — style contract plus all seven `test/integration_*.sh` scripts (`comments`, `plugin_toggles`, `distill`, `bootstrap_compat`, `upgrade_cli`, `css_minify`, `new_plugins`).
- `visual-regression.yml` — Playwright on chromium + webkit, diffing the candidate build against a `v0.16.3` baseline worktree served on `:4100` via `BASELINE_URL`.
- `upgrade-check.yml` — `bundle exec al-folio upgrade audit`.
- `prettier.yml` — Prettier with `@shopify/prettier-plugin-liquid` and `printWidth: 150`. Run `npm run lint:prettier` before pushing; `npx prettier . --write` fixes.
- `update-tocs.yml` — regenerates `<!--ts-->…<!--te-->` blocks in changed root and `docs/` Markdown files. If you add or rename a heading, expect a follow-up auto-commit on `main`.

## Gem version pins

`Gemfile` pins every `al-*` gem to an exact released version in `group :al_folio_plugins`, and `_config.yml` lists the same gems under `plugins:`. Read the current pins from the `Gemfile` rather than trusting any version quoted in prose — including here. To test a gem fix against this site, repoint the `Gemfile` at a sibling checkout (`path:`, `git:`, or `branch:`) and `bundle install`; see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md#working-on-a-gem-alongside-the-starter). Revert the pin before committing.
