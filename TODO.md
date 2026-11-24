# TODO

Work planned for `localize_translate`; shipped changes are in the [CHANGELOG](CHANGELOG.md).

## Open

* [ ] **A `nil` value inside a translation differs between memory and SQL** — `translate/3` ends the chain at the base value, where queries move on to the next locale. Decided 2026-11-24: a `nil` field moves on, so `translate/3` changes to match.

## In progress

* [ ] **Ash integration** — an Ash extension with a validated translations type, data-layer calculations for filtering and sorting, and runtime per-tenant locales, in a separate package, `localize_translate_ash`; proposal in [plans/ash-integration.md](plans/ash-integration.md). The spike and the three core fixes are done; the new package is next.

## Done

* [x] **One function-free SQL shape for queries** — literal and runtime locales are expanded and validated the same way, and walked by a subquery that reads columns through Ecto; fixes the table-alias guess and literal locales skipping parent walking. 2026-11-24, unreleased (0.4.0).

* [x] **A caller-supplied per-locale schema** — `translations/3` takes `fields_module:` in place of the generated `Fields`, checked when the parent compiles; closes localize_translate#1. 2026-11-23, v0.3.0.
