# TODO

Work planned for `localize_translate`; shipped changes are in the [CHANGELOG](CHANGELOG.md).

## Open

* [ ] **`translatable?/2` turns a string field into an atom** — it calls `String.to_atom/1` on a field name, which may come from a request (non-negotiable rule 1). It also raises a `RuntimeError` for a module that does not use `Localize.Translate`, naming it `Elixir.Date` because it interpolates the module with `to_string`.

* [ ] **The sibling-resource store uses `rescue` as control flow** — `load_translations/2` raises on a missing option and on an unknown primary key field, then rescues everything into `{:error, exception}`. Return tagged tuples, and keep a rescue only around the repo call.

* [ ] **`translate/3` and `translate!/3` raise a bare `RuntimeError` for a field that is not translatable** — a programming error rather than request input, but a generic `RuntimeError` is hard to match. Needs a decision: an `ArgumentError`, or the base value.

* [ ] **Public docs miss template sections** — `translations/1,2` lack `### Returns` (and one clause `### Examples`), `translate/1` and `QueryBuilder.translated_as/4` lack `### Examples`.

* [ ] **House style** — 39 keyword-form `def` clauses (including `mix.exs` and the generated `__trans__/1`), and `opts` for `options` in `using/1` and `__using__/1`.

* [ ] **The `translate_field` generator task** — nothing calls the function since the `QueryBuilder` rewrite. Needs a decision: deprecate it in 0.4.0, or remove it.

* [ ] **Dialyzer has not run** on the 0.4.0 changes; to run before the release, on request.

## In progress

* [ ] **Ash integration** — an Ash extension with a validated translations type, data-layer calculations for filtering and sorting, and runtime per-tenant locales, in a separate package, `ash_localize_translate`; proposal in [plans/ash-integration.md](plans/ash-integration.md). The spike and the three core fixes are done; the new package is next.

## Done

* [x] **One rule for a `nil` translation** — it counts as missing in memory and in SQL, so a chain moves on to its next locale. 2026-11-24, unreleased (0.4.0).

* [x] **One function-free SQL shape for queries** — literal and runtime locales are expanded and validated the same way, and walked by a subquery that reads columns through Ecto; fixes the table-alias guess and literal locales skipping parent walking. 2026-11-24, unreleased (0.4.0).

* [x] **A caller-supplied per-locale schema** — `translations/3` takes `fields_module:` in place of the generated `Fields`, checked when the parent compiles; closes localize_translate#1. 2026-11-23, v0.3.0.
