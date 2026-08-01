# Changelog

## [v0.2.0] — 2026-08-01

The store behaviour is new public API and its first consumer — the Ash integration — has not yet written an adapter against it. The package stays on a 0.x line until that shape is agreed, so it can change without a major bump.

### Added

* `Localize.Translate.Store` — a behaviour for translation storage, so translations need not live on the subject. It is subject-and-field shaped: a store receives the whole subject rather than an extracted key, so a CLDR fallback chain resolves in one pass.

* `Localize.Translate.Store.Embedded` — the default store, implementing the container-map storage this library has always used. Existing schemas keep working unchanged.

* `Localize.Translate.Store.SiblingResource` — a store keeping translations in a sibling table, one row per `(subject, locale)`. For per-translation workflow state, per-locale permissions, row-level translation history, or concurrent editing across locales.

* A schema selects its store with `use Localize.Translate, store: MyStore` or `store: {MyStore, options}`.

### Changed

* Requires `localize ~> 1.0`. The previous requirement of `~> 0.32` excluded it.

* Test database connection settings read the standard `PG*` environment variables, so the same configuration works on CI and on a developer machine.

### Fixed

* `Mix.Tasks.Localize.Translate.Gen.TranslateFunction.format_string!/1` returns a binary rather than iodata, and no longer carries a `@dialyzer {:no_return, ...}` annotation that claimed it never returns.

## [v0.1.0] — 2026-05-13

Initial release. Provides embedded translations for `Ecto.Schema` modules — `use Localize.Translate` declares translatable fields, locales, and default locale; `Localize.Translate.translate/2,3` reads translations at runtime, and `Localize.Translate.QueryBuilder.translated/3` builds matching `Ecto.Query` fragments.

Built on [`:localize`](https://hex.pm/packages/localize) — atoms, strings, and `%Localize.LanguageTag{}` are accepted as locales in `:locales`, in `translate/N`, and in `QueryBuilder.translated/3`, all validated and normalised via `Localize.validate_locale/1`; fallback chains walk CLDR parent locales (filtered to the schema's supported locales for query building) and `translate/1,2` default to `Localize.get_locale/0`.
