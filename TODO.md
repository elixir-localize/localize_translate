# TODO

Work planned for `localize_translate`; shipped changes are in the [CHANGELOG](CHANGELOG.md).

## In progress

* [ ] **Ash integration** — an Ash extension with a validated translations type, data-layer calculations for filtering and sorting, and runtime per-tenant locales, in a separate package, `ash_localize_translate`; proposal in [plans/ash-integration.md](plans/ash-integration.md). The package is built and tested; its review findings and first release remain, after `localize_translate` 0.4.0.

## Blocked

* [ ] **Call `Localize.Locale.fallback_chain/2` from `locale_chain/2`** — the parent walk in `Localize.Translate.Locale.expand_valid/2` moved into Localize, with the same chains; delete the copy here and keep the list inputs and `:default_locale`. Blocked on localize ~> 1.10.

## Done

* [x] **A function default locale and Ecto writes** — `validate_translations/1` keeps the default locale out of the container, for map containers and generated embeds, checking only when the container or the default changes. 2026-11-24, unreleased (0.4.0).

* [x] **Bring the Ash records up to date** — the plan's status, tasks and this list describe the built package; the README and guide point Ash users to `ash_localize_translate`. 2026-11-24.

* [x] **Own the `__trans__/1` reflection** — `reflection/1` generates every clause with defaults and checks its options at compile time; `use Localize.Translate` calls it. 2026-11-24, unreleased (0.4.0).

* [x] **A public locale id** — `locale_id/1`, so `ash_localize_translate` validates locales through the core rather than calling `Localize.validate_locale/1` itself; a language that resolves to `und` is refused and left out of chains. 2026-11-24, unreleased (0.4.0).

* [x] **Dialyzer on the 0.4.0 changes** — `Total errors: 0` on Elixir 1.20.5 / OTP 29.1.2. 2026-11-24.

* [x] **The `translate_field` generator task is deprecated** — it warns when run and its docs carry the deprecation; removal is for a later release. 2026-11-24, unreleased (0.4.0).

* [x] **House style** — 40 keyword-form functions in block form, 13 one-line pipelines split (doc examples and tests included), and `options` for `opts` in `using/1` and `__using__/1`. 2026-11-24, unreleased (0.4.0).

* [x] **Public docs follow the template** — `translations/3,4` gained `### Returns` (and `/4` its `### Options` and `### Examples`), `translate/1` a doctest, and `QueryBuilder.translated_as/4` examples. 2026-11-24, unreleased (0.4.0).

* [x] **`translate/1,2,3` never raise on bad input** — a field that is not translatable is its base value, a value that is not a struct passes through, and `translate!/3` raises an `ArgumentError`; `translate!/3` also loads sibling-store translations now. 2026-11-24, unreleased (0.4.0).

* [x] **The sibling-resource store validates instead of rescuing** — options and the subject's key are checked up front as tagged errors; only the repo call is rescued. 2026-11-24, unreleased (0.4.0).

* [x] **`translatable?/2` creates no atoms and never raises** — a string field is compared as a string, and a module that does not use `Localize.Translate` is `false`. 2026-11-24, unreleased (0.4.0).

* [x] **One rule for a `nil` translation** — it counts as missing in memory and in SQL, so a chain moves on to its next locale. 2026-11-24, unreleased (0.4.0).

* [x] **One function-free SQL shape for queries** — literal and runtime locales are expanded and validated the same way, and walked by a subquery that reads columns through Ecto; fixes the table-alias guess and literal locales skipping parent walking. 2026-11-24, unreleased (0.4.0).

* [x] **A caller-supplied per-locale schema** — `translations/3` takes `fields_module:` in place of the generated `Fields`, checked when the parent compiles; closes localize_translate#1. 2026-11-23, v0.3.0.
