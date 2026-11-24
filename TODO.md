# TODO

Work planned for `localize_translate`; shipped changes are in the [CHANGELOG](CHANGELOG.md).

## Open

* [ ] **Literal query locales skip validation and parent walking** — `translated(Article, a.title, :"es-419")` looks up `"es-419"` as written, where a runtime locale is validated and walks to `:es`. Expand literal chains at compile time as runtime ones are expanded.

* [ ] **The runtime query path guesses the table alias from the binding name** — `from b in Book` emits `b0`, but Ecto names the alias after the table (`a0` for `articles`), so the `translate_field` call fails with an undefined column.

* [ ] **A `nil` value inside a translation differs between memory and SQL** — `translate/3` ends the chain at the base value, the `translate_field` function and literal queries move on to the next locale. Decide one rule and apply it to all three.

## In progress

* [ ] **Ash integration** — an Ash extension with a validated translations type, data-layer calculations for filtering and sorting, and runtime per-tenant locales, in a separate package, `localize_translate_ash`; proposal in [plans/ash-integration.md](plans/ash-integration.md). The spike and the three core fixes are done; the new package is next.

## Done

* [x] **A caller-supplied per-locale schema** — `translations/3` takes `fields_module:` in place of the generated `Fields`, checked when the parent compiles; closes localize_translate#1. 2026-11-23, v0.3.0.
