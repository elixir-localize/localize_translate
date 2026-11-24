# TODO

Work planned for `localize_translate`; shipped changes are in the [CHANGELOG](CHANGELOG.md).

## Open

* [ ] **Ash integration** — an Ash extension with a validated translations type, data-layer calculations for filtering and sorting, and runtime per-tenant locales; three core fixes it needs (related records, a runtime default locale, no raising on an invalid locale). A separate package, `localize_translate_ash`; proposal in [plans/ash-integration.md](plans/ash-integration.md), open questions first.

## Done

* [x] **A caller-supplied per-locale schema** — `translations/3` takes `fields_module:` in place of the generated `Fields`, checked when the parent compiles; closes localize_translate#1. 2026-11-23, v0.3.0.
